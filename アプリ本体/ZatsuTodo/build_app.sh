#!/bin/zsh
set -euo pipefail

project_dir="/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ本体/ZatsuTodo"
app_dir="$project_dir/dist/ZatsuTodo.app"
module_cache="$project_dir/.build/module-cache"

cd "$project_dir"
mkdir -p "$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"
swift build -c release --disable-sandbox
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/.build/release/ZatsuTodo" "$app_dir/Contents/MacOS/ZatsuTodo"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Resources"
cp "$project_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --verify --deep --strict "$app_dir"
