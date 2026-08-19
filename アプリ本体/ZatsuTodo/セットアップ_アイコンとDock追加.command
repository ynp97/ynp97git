#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SRC="$DIR/AppIcon.icns"
APP="/Applications/ZatsuTodo.app"
RESOURCES="$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"

echo "=== 雑TODO アイコン反映 + Dock追加 ==="

if [ ! -d "$APP" ]; then
  echo "エラー: $APP が見つかりません。先に雑TODO本体をインストールしてください。"
  read -p "Enterキーで閉じます..."
  exit 1
fi

if [ ! -f "$ICON_SRC" ]; then
  echo "エラー: $ICON_SRC が見つかりません（このフォルダ内にAppIcon.icnsが必要）。"
  read -p "Enterキーで閉じます..."
  exit 1
fi

echo "1) アイコンをコピー: $RESOURCES/AppIcon.icns"
mkdir -p "$RESOURCES"
cp -f "$ICON_SRC" "$RESOURCES/AppIcon.icns"

echo "2) Info.plistにCFBundleIconFileを設定"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"

echo "3) アイコン/Launch Servicesキャッシュを更新"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo "4) Dockに追加"
CURRENT="$(defaults read com.apple.dock persistent-apps 2>/dev/null || echo "")"
if echo "$CURRENT" | grep -q "ZatsuTodo.app"; then
  echo "   既にDockにあるようなので追加はスキップします。"
else
  defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock
fi

echo ""
echo "完了しました。Dockにオレンジ地に黒い「雑」のアイコンが表示されているか確認してください。"
echo "反映が古いアイコンのまま変わらない場合は、Dockからいったんドラッグして外し、このcommandをもう一度実行してください。"
read -p "Enterキーでこのウインドウを閉じます..."
