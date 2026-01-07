#!/bin/bash
#
# Lowers the LC_BUILD_VERSION minos field on any Mach-O in the bundle whose
# minimum-OS requirement exceeds the target deployment version.
#
# Homebrew builds libraries targeting the *host* macOS, so a build on Tahoe
# (26.x) produces dylibs with minos=26.0.  When those dylibs are bundled
# inside Trace.app and the app is opened on Sequoia (15.x), dyld refuses to
# load them: "this application is not supported on this Mac".
#
# This script uses Apple's vtool to rewrite minos to the deployment target
# while preserving each library's original SDK version.
#
# Usage: fix-bundle-minos.sh <target-minos> <app-bundle>
#   e.g. fix-bundle-minos.sh 12.0 /path/to/Trace.app

set -euo pipefail

TARGET_MINOS="${1:?Usage: fix-bundle-minos.sh <target-minos> <app-bundle>}"
APP_BUNDLE="${2:?Usage: fix-bundle-minos.sh <target-minos> <app-bundle>}"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE is not a directory" >&2
    exit 1
fi

if ! command -v vtool &>/dev/null; then
    echo "Error: vtool not found (requires Xcode command-line tools)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_MINOS_PY="$SCRIPT_DIR/patch-minos.py"

if [ ! -f "$PATCH_MINOS_PY" ]; then
    echo "Warning: patch-minos.py not found at $PATCH_MINOS_PY — vtool-only mode" >&2
fi

TARGET_MAJOR=$(echo "$TARGET_MINOS" | cut -d. -f1)
TARGET_MINOR=$(echo "$TARGET_MINOS" | cut -d. -f2)

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

minos_exceeds_target() {
    local minos="$1"
    local major minor
    major=$(echo "$minos" | cut -d. -f1)
    minor=$(echo "$minos" | cut -d. -f2)
    if [ "$major" -gt "$TARGET_MAJOR" ] 2>/dev/null; then
        return 0
    elif [ "$major" -eq "$TARGET_MAJOR" ] 2>/dev/null && [ "$minor" -gt "$TARGET_MINOR" ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# Rewrite a single binary's minos.  Tries vtool first (copy in /tmp to dodge
# filesystem quirks), then falls back to direct Mach-O binary patching via
# patch-minos.py if vtool segfaults.
rewrite_minos() {
    local binary="$1"
    local target_minos="$2"
    local sdk="$3"
    local basename_bin
    basename_bin=$(basename "$binary")

    local src_copy="$WORKDIR/${basename_bin}.src"
    local dst_copy="$WORKDIR/${basename_bin}.dst"

    cp -f "$binary" "$src_copy"
    codesign --remove-signature "$src_copy" 2>/dev/null || true

    # Attempt 1: vtool
    rm -f "$dst_copy"
    if vtool -set-build-version macos "$target_minos" "$sdk" -replace \
            -output "$dst_copy" "$src_copy" 2>/dev/null; then
        cp -f "$dst_copy" "$binary"
        rm -f "$src_copy" "$dst_copy"
        return 0
    fi

    # Attempt 2: direct binary patch (surgical 4-byte minos overwrite)
    if [ -f "$PATCH_MINOS_PY" ]; then
        echo "    vtool failed, falling back to binary patch for $basename_bin"
        codesign --remove-signature "$binary" 2>/dev/null || true
        if python3 "$PATCH_MINOS_PY" "$target_minos" "$binary"; then
            rm -f "$src_copy" "$dst_copy"
            return 0
        fi
    fi

    rm -f "$src_copy" "$dst_copy"
    return 1
}

FIXED=0
SKIPPED=0
ERRORS=0

while IFS= read -r -d '' binary; do
    build_info=$(vtool -show-build "$binary" 2>/dev/null) || continue

    echo "$build_info" | grep -q "platform MACOS" || continue

    # For universal (fat) binaries vtool prints multiple sections; take only
    # the first minos/sdk pair to avoid multi-line comparison failures.
    current_minos=$(echo "$build_info" | grep "minos" | head -1 | awk '{print $2}')
    current_sdk=$(echo "$build_info" | grep "sdk" | head -1 | awk '{print $2}')

    [ -z "$current_minos" ] && continue
    [ -z "$current_sdk" ] && continue

    if minos_exceeds_target "$current_minos"; then
        echo "  $(basename "$binary"): minos $current_minos -> $TARGET_MINOS (sdk $current_sdk)"

        if rewrite_minos "$binary" "$TARGET_MINOS" "$current_sdk"; then
            FIXED=$((FIXED + 1))
        else
            echo "    ERROR: all patching methods failed on $binary" >&2
            ERRORS=$((ERRORS + 1))
        fi
    else
        SKIPPED=$((SKIPPED + 1))
    fi
done < <(find "$APP_BUNDLE" -type f \( -perm +111 -o -name '*.dylib' -o -name '*.so' -o -name '*.kiface' -o -name '*.cm' -o -name '*.vpi' \) -print0 2>/dev/null)

echo "Done: $FIXED fixed, $SKIPPED already OK, $ERRORS errors."

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

# Verify nothing exceeds the target
FAIL=0
while IFS= read -r -d '' binary; do
    info=$(vtool -show-build "$binary" 2>/dev/null) || continue
    echo "$info" | grep -q "platform MACOS" || continue
    minos=$(echo "$info" | grep "minos" | head -1 | awk '{print $2}')
    [ -z "$minos" ] && continue
    if minos_exceeds_target "$minos"; then
        echo "  STILL TOO HIGH: $(basename "$binary") minos=$minos" >&2
        FAIL=1
    fi
done < <(find "$APP_BUNDLE" -type f \( -perm +111 -o -name '*.dylib' -o -name '*.so' -o -name '*.kiface' -o -name '*.cm' -o -name '*.vpi' \) -print0 2>/dev/null)

if [ "$FAIL" -eq 1 ]; then
    echo "Error: some binaries still exceed minos $TARGET_MINOS" >&2
    exit 1
fi

# Inject LSMinimumSystemVersion into Info.plist so Launch Services knows
# the app supports older macOS versions.
PLIST="$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    if ! defaults read "$PLIST" LSMinimumSystemVersion &>/dev/null; then
        echo "Setting LSMinimumSystemVersion=$TARGET_MINOS in Info.plist"
        defaults write "$PLIST" LSMinimumSystemVersion -string "$TARGET_MINOS"
        plutil -convert xml1 "$PLIST"
    fi
fi

echo "Verification passed — all binaries target minos <= $TARGET_MINOS."
