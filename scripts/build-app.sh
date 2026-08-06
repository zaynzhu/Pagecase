#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/页匣.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXTENSION_DIR="$RESOURCES_DIR/ChromeExtension"
ICON_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pagecase-icon.XXXXXX")

cleanup() {
  rm -rf "$ICON_TEMP_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$EXTENSION_DIR"

cp ".build/release/PagecaseApp" "$MACOS_DIR/PagecaseApp"
cp ".build/release/PagecaseBridge" "$MACOS_DIR/PagecaseBridge"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "extension/manifest.json" "$EXTENSION_DIR/manifest.json"
cp "extension/background.js" "$EXTENSION_DIR/background.js"
cp "extension/commands.js" "$EXTENSION_DIR/commands.js"
cp "extension/snapshot.js" "$EXTENSION_DIR/snapshot.js"
cp "extension/README.txt" "$EXTENSION_DIR/README.txt"

swift "Resources/generate-icon.swift" "$ICON_TEMP_DIR/master.png"
ICONSET_DIR="$ICON_TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  doubleSize=$((size * 2))
  sips -z "$size" "$size" "$ICON_TEMP_DIR/master.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$doubleSize" "$doubleSize" "$ICON_TEMP_DIR/master.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

print "已构建：$APP_DIR"
