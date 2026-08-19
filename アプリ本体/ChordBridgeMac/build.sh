#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/Chord Bridge.app"
MODULE_CACHE="$BUILD_DIR/ModuleCache"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$MODULE_CACHE"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/ChordBridge.icns" "$APP_DIR/Contents/Resources/ChordBridge.icns"

swiftc \
  -swift-version 5 \
  -O \
  -module-cache-path "$MODULE_CACHE" \
  -framework AppKit \
  -framework ApplicationServices \
  "$SCRIPT_DIR/ChordBridge.swift" \
  -o "$APP_DIR/Contents/MacOS/ChordBridge"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
