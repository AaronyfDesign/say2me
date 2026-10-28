#!/bin/bash
# Build say2me.app (menu bar dictation, SenseVoice-Small via sherpa-onnx).
# Requires only Xcode Command Line Tools (swiftc). No code signing needed
# for local use; we ad-hoc sign so the Accessibility TCC entry is stable.
set -euo pipefail
cd "$(dirname "$0")"

APP=say2me
BUILD=build
mkdir -p "$BUILD"

swiftc \
  -O \
  -framework AppKit -framework AVFoundation -framework Carbon -framework ApplicationServices \
  -framework SwiftUI -framework Combine \
  Sources/*.swift \
  -o "$BUILD/$APP"

# Bundle it
BUNDLE="$BUILD/$APP.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mv "$BUILD/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"

# App icon: prebuild icns if missing, ship into Resources
if [ ! -f Assets/AppIcon.icns ] && [ -f Assets/AppIcon.png ]; then
  mkdir -p "/tmp/say2me.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s Assets/AppIcon.png --out "/tmp/say2me.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d Assets/AppIcon.png --out "/tmp/say2me.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns /tmp/say2me.iconset -o Assets/AppIcon.icns
fi
if [ -f Assets/AppIcon.icns ]; then
  mkdir -p "$BUNDLE/Contents/Resources"
  cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 内置 sherpa-onnx CLI + 动态库（二进制 rpath 为 @loader_path/../lib，保持 bin/lib 结构即可）
VENDOR_DIR=$(ls -d vendor/sherpa-onnx-*osx-arm64-shared 2>/dev/null | head -1)
if [ -n "$VENDOR_DIR" ]; then
  mkdir -p "$BUNDLE/Contents/Resources/sherpa-onnx/bin"
  cp "$VENDOR_DIR/bin/sherpa-onnx-offline" "$BUNDLE/Contents/Resources/sherpa-onnx/bin/"
  cp -R "$VENDOR_DIR/lib" "$BUNDLE/Contents/Resources/sherpa-onnx/"
fi

touch "$BUNDLE"

# Sign with a stable self-signed identity so the Accessibility grant
# survives rebuilds. Falls back to ad-hoc if the cert is missing.
IDENT="SenseDict Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT"; then
  codesign --force --deep --sign "$IDENT" "$BUNDLE"
else
  echo "NOTE: '$IDENT' certificate not found — creating one."
  security create-keypair -a DSA -f trustAsRoot -c "$IDENT" ~/Library/Keychains/login.keychain-db 2>/dev/null || true
  security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT" \
    && codesign --force --deep --options runtime --sign "$IDENT" "$BUNDLE" \
    || codesign --force --deep --sign - "$BUNDLE"
fi

echo "Built: $BUNDLE"
echo "Run:   open $BUNDLE"
