#!/bin/bash
# Fix library paths in KiCad.app after ninja install
# Run this after: ninja install

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="${SCRIPT_DIR}/build/kicad-dest/KiCad.app"
FRAMEWORKS="$APP_DIR/Contents/Frameworks"
PLUGINS="$APP_DIR/Contents/PlugIns"

echo "🔧 Fixing library paths in KiCad.app..."

# Function to fix a single binary
fix_binary() {
    local binary="$1"
    
    # Get all non-system library references
    otool -L "$binary" 2>/dev/null | grep '^\t' | awk '{print $1}' | while read lib; do
        # Skip system libraries
        if [[ "$lib" == /usr/* ]] || [[ "$lib" == /System/* ]] || [[ "$lib" == @* ]]; then
            continue
        fi
        
        # Get just the library name
        libname=$(basename "$lib")
        
        # Check if this library exists in our Frameworks
        if [[ -f "$FRAMEWORKS/$libname" ]]; then
            echo "  Fixing $libname in $(basename $binary)"
            install_name_tool -change "$lib" "@loader_path/../Frameworks/$libname" "$binary" 2>/dev/null || true
        fi
    done
}

# Copy required libraries to Frameworks if not present
echo "📦 Copying libraries to Frameworks..."

# wxWidgets
for lib in "${SCRIPT_DIR}/build/wxwidgets-dest/lib"/*.dylib; do
    if [[ -f "$lib" ]] && [[ ! -L "$lib" ]]; then
        libname=$(basename "$lib")
        if [[ ! -f "$FRAMEWORKS/$libname" ]]; then
            echo "  Copying $libname"
            cp "$lib" "$FRAMEWORKS/"
        fi
    fi
done

# ngspice
for lib in "${SCRIPT_DIR}/build/ngspice-dest/lib"/*.dylib; do
    if [[ -f "$lib" ]] && [[ ! -L "$lib" ]]; then
        libname=$(basename "$lib")
        if [[ ! -f "$FRAMEWORKS/$libname" ]]; then
            echo "  Copying $libname"
            cp "$lib" "$FRAMEWORKS/"
        fi
    fi
done

# Homebrew libraries
HOMEBREW_LIBS=(
    "/opt/homebrew/opt/glew/lib/libGLEW.2.3.dylib"
    "/opt/homebrew/opt/cairo/lib/libcairo.2.dylib"
    "/opt/homebrew/opt/pixman/lib/libpixman-1.0.dylib"
    "/opt/homebrew/opt/unixodbc/lib/libodbc.2.dylib"
    "/opt/homebrew/opt/nng/lib/libnng.1.dylib"
)

for lib in "${HOMEBREW_LIBS[@]}"; do
    if [[ -f "$lib" ]]; then
        libname=$(basename "$lib")
        if [[ ! -f "$FRAMEWORKS/$libname" ]]; then
            echo "  Copying $libname"
            cp "$lib" "$FRAMEWORKS/"
        fi
    fi
done

echo "🔗 Fixing library references..."

# Fix all kiface plugins
for kiface in "$PLUGINS"/*.kiface; do
    if [[ -f "$kiface" ]]; then
        fix_binary "$kiface"
    fi
done

# Fix main executable
fix_binary "$APP_DIR/Contents/MacOS/kicad"

# Fix all dylibs in Frameworks
for dylib in "$FRAMEWORKS"/*.dylib; do
    if [[ -f "$dylib" ]]; then
        fix_binary "$dylib"
    fi
done

echo "✅ Done! Library paths fixed."
echo ""
echo "Verify with:"
echo "  bash ${SCRIPT_DIR}/kicad-mac-builder/bin/verify-app.sh $APP_DIR 2>&1 | head -20"

