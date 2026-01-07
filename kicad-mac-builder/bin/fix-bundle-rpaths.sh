#!/bin/bash
#
# Strips dangling LC_RPATH entries from all Mach-O binaries in an .app bundle.
#
# When com.apple.security.cs.disable-library-validation is set, macOS Gatekeeper
# inspects every LC_RPATH in the bundle. Absolute paths that point outside the
# bundle (build-machine paths, /opt/homebrew/lib, etc.) are treated as a
# dynamic-library impersonation risk and cause Gatekeeper to reject the app,
# even if notarization succeeded.
#
# Usage: fix-bundle-rpaths.sh /path/to/Foo.app

set -euo pipefail

APP_BUNDLE="${1:?Usage: fix-bundle-rpaths.sh /path/to/Foo.app}"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE is not a directory" >&2
    exit 1
fi

FIXED=0
ERRORS=0

while IFS= read -r -d '' binary; do
    rpaths=$(otool -l "$binary" 2>/dev/null \
        | grep -A 2 LC_RPATH \
        | grep 'path ' \
        | awk '{print $2}') || true

    for rpath in $rpaths; do
        case "$rpath" in
            @*)
                # @executable_path, @loader_path, @rpath — these are fine
                ;;
            *)
                echo "Removing dangling rpath from $(basename "$binary"): $rpath"
                if install_name_tool -delete_rpath "$rpath" "$binary" 2>/dev/null; then
                    FIXED=$((FIXED + 1))
                else
                    echo "  WARNING: failed to remove rpath $rpath from $binary" >&2
                    ERRORS=$((ERRORS + 1))
                fi
                ;;
        esac
    done
done < <(find "$APP_BUNDLE" -type f \( -perm +111 -o -name '*.dylib' -o -name '*.so' -o -name '*.kiface' -o -name '*.cm' -o -name '*.vpi' \) -print0 2>/dev/null)

echo "Fixed $FIXED dangling rpath(s), $ERRORS error(s)."

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

# Verify no dangling rpaths remain
REMAINING=$(find "$APP_BUNDLE" -type f \( -perm +111 -o -name '*.dylib' -o -name '*.so' -o -name '*.kiface' -o -name '*.cm' -o -name '*.vpi' \) -exec sh -c '
    otool -l "$1" 2>/dev/null | grep -A 2 LC_RPATH | grep "path " | awk "{print \$2}" | while read rp; do
        case "$rp" in @*) ;; *) echo "$1 -> $rp" ;; esac
    done
' _ {} \; 2>/dev/null)

if [ -n "$REMAINING" ]; then
    echo "Error: dangling rpaths still remain after fixing:" >&2
    echo "$REMAINING" >&2
    exit 1
fi

echo "Verification passed — no dangling rpaths in bundle."
