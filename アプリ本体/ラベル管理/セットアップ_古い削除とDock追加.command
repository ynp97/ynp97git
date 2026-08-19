#!/bin/zsh
# 旧Streamlitプログラムを停止・削除し、新HTML用ランチャー.app（オレンジのラ）を作ってDockに入れる。
# 個人データ(~/Desktop/AI関係/ラベル管理 の sqlite等)は触らない。
set -u
DIR="$HOME/Documents/Obsidian Vault/アプリ本体/ラベル管理"
HTML="$DIR/資料請求ラベル管理.html"
ICON="$DIR/AppIcon.icns"
APP="/Applications/ラベル管理.app"

echo "== ① 古いプログラムを停止・削除 =="
pkill -9 -f "streamlit run" 2>/dev/null || true
pkill -9 -f "/Applications/ラベル管理.app" 2>/dev/null || true
killall -9 applet 2>/dev/null || true
killall -9 labelmgr 2>/dev/null || true
sleep 1
rm -rf "$APP"
for f in "ラベル管理_再ビルド.command" "ラベル管理_クリーン再構築.command" "強制終了して起動.command" \
         "調査だけ.command" "ラベル管理_起動.applescript" "launch" "LabelManagerLauncher.swift" \
         "app.py" "README.md" "_診断結果.txt"; do
  rm -f "$DIR/$f"
done
rm -rf "$DIR/__pycache__"
echo "古いアプリ・起動ファイルを削除しました（Desktopの個人データには触れていません）。"

echo "== ② 新ランチャー.app を作成 =="
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ラベル管理</string>
<key>CFBundleDisplayName</key><string>ラベル管理</string>
<key>CFBundleIdentifier</key><string>com.yoshiakinagumo.labelmgr.launcher</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>run</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cat > "$APP/Contents/MacOS/run" <<'RUN'
#!/bin/zsh
# 保存分岐防止: Chromeプロファイルを Default に固定し、?app=1 を付けて開く。
# （プロファイルが変わるとlocalStorageの保存場所が分かれ、データが別々になるため）
HTML="$HOME/Documents/Obsidian Vault/アプリ本体/ラベル管理/資料請求ラベル管理.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if command -v python3 >/dev/null 2>&1; then
  URL="file://$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$HTML")"
else
  URL="file://$HTML"
fi
if [ -x "$CHROME" ]; then
  "$CHROME" --profile-directory=Default --app="${URL}?app=1" --window-size=1200,840 >/dev/null 2>&1 &
else
  open "$HTML"
fi
RUN
chmod +x "$APP/Contents/MacOS/run"

[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
touch "$APP"

echo "== ③ Dockに追加 =="
# DockのURLはエンコード形式（%E3%83%A9...）で保存されることがあるため、両方の表記をチェック（重複追加防止）
if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -Eq "ラベル管理\.app|%E3%83%A9%E3%83%99%E3%83%AB%E7%AE%A1%E7%90%86\.app"; then
  defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/ラベル管理.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'
  killall Dock
  echo "Dockに追加しました。"
else
  echo "すでにDockにあります。"
fi

sleep 1
echo "== ④ 起動 =="
open "$APP"
echo ""
echo "完了。Dockのオレンジ『ラ』から開けます。閉じるときはウインドウを普通に閉じるだけ（常駐しません）。"
sleep 1
