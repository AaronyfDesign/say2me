#!/bin/bash
# Build SenseDict.app (menu bar dictation, SenseVoice-Small via sherpa-onnx).
# Requires only Xcode Command Line Tools (swiftc). No code signing needed
# for local use; we ad-hoc sign so the Accessibility TCC entry is stable.
set -euo pipefail
cd "$(dirname "$0")"

APP=SenseDict
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
