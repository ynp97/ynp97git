#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TODOインボックス"
EXECUTABLE="Ynp97TodoInbox"
BUNDLE_ID="com.yoshiakinagumo.ynp97-todo-inbox"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RESOURCES_DIR="$ROOT_DIR/Resources"
ICONSET_PATH="$RESOURCES_DIR/AppIcon.iconset"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"
BUILD_CONFIG="${BUILD_CONFIG:-debug}"

cd "$ROOT_DIR"

/usr/bin/pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true

swift "$ROOT_DIR/script/make_icon.swift" "$ICONSET_PATH" "$ICNS_PATH"

swift build --configuration "$BUILD_CONFIG"

BIN_PATH="$(swift build --configuration "$BUILD_CONFIG" --show-bin-path)/$EXECUTABLE"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ja</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCalendarsUsageDescription</key>
  <string>TODOの期限をカレンダーに追加するために使います。</string>
</dict>
</plist>
PLIST

if [[ "${1:-}" == "--verify" ]]; then
  /usr/bin/open -n "$APP_BUNDLE"
  sleep 1
  /usr/bin/pgrep -x "$EXECUTABLE" >/dev/null
  echo "Launched $APP_BUNDLE"
else
  /usr/bin/open -n "$APP_BUNDLE"
  echo "$APP_BUNDLE"
fi
