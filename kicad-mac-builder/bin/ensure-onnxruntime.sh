#!/bin/bash
set -euo pipefail

ORT_DIR="$1"
FRAMEWORKS_DIR="$2"
ORT_VERSION="$3"

if ls "$ORT_DIR/lib"/libonnxruntime*.dylib 1>/dev/null 2>&1; then
    echo "ONNX Runtime libs already present at $ORT_DIR/lib"
else
    ARCH=$(uname -m)
    echo "ONNX Runtime libs not found — downloading v${ORT_VERSION} for ${ARCH}..."
    URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-osx-${ARCH}-${ORT_VERSION}.tgz"

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    curl -fSL "$URL" | tar xz -C "$TMPDIR" --strip-components=1
    mkdir -p "$ORT_DIR/lib"
    cp -P "$TMPDIR"/lib/libonnxruntime*.dylib "$ORT_DIR/lib/"
    echo "Downloaded ONNX Runtime to $ORT_DIR/lib"
fi

mkdir -p "$FRAMEWORKS_DIR"
cp -P "$ORT_DIR/lib"/libonnxruntime*.dylib "$FRAMEWORKS_DIR"
install_name_tool -id "@rpath/libonnxruntime.${ORT_VERSION}.dylib" \
    "$FRAMEWORKS_DIR/libonnxruntime.${ORT_VERSION}.dylib" || true

echo "ONNX Runtime installed into $FRAMEWORKS_DIR"
