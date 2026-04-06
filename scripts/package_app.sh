#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
EXECUTABLE_NAME="NotesCurator"
APP_DISPLAY_NAME="Noter"
APP_BUNDLE_ID="com.yichenlin.Noter"
APP_NAME="${APP_DISPLAY_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
LEGACY_APP_DIR="$DIST_DIR/NotesCurator.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
SOURCE_ICON_PATH="/Users/yichenlin/Desktop/App/App_Icon.png"
BRAND_ARTWORK_PATH="$RESOURCES_DIR/BrandArtwork.png"

echo "Building $APP_DISPLAY_NAME ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" >/dev/null

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$LEGACY_APP_DIR" "$ICONSET_DIR"
rm -f "$DIST_DIR/.DS_Store"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if [[ -f "$SOURCE_ICON_PATH" ]]; then
  swift "$ROOT_DIR/scripts/generate_yc_icon.swift" "$ICONSET_DIR" "$SOURCE_ICON_PATH" >/dev/null
else
  swift "$ROOT_DIR/scripts/generate_yc_icon.swift" "$ICONSET_DIR" >/dev/null
fi

if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
  rm -rf "$ICONSET_DIR"
fi

if [[ -f "$SOURCE_ICON_PATH" ]]; then
  cp "$SOURCE_ICON_PATH" "$BRAND_ARTWORK_PATH"
fi

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Noter</string>
    <key>CFBundleExecutable</key>
    <string>NotesCurator</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.yichenlin.Noter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Noter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

touch "$RESOURCES_DIR/.keep"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Created app bundle:"
echo "$APP_DIR"
