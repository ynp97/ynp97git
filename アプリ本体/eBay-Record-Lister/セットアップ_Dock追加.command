#!/bin/zsh
# eBay Record Lister 用のDockランチャー（緑地に白の e）を作ってDockに入れる。
# 多重起動防止: ①起動時に既存ウインドウがあれば手前に出すだけ ②アプリ内でも二重画面を警告。
set -u
DIR="$HOME/Documents/Obsidian Vault/アプリ本体/eBay-Record-Lister"
HTML="$DIR/index.html"
ICON="$DIR/AppIcon.icns"
APP="/Applications/eBay Lister.app"

if [ ! -f "$HTML" ]; then
  echo "index.html が見つかりません: $HTML"; exit 1
fi

echo "== ① ランチャー.app を作成 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>eBay Lister</string>
<key>CFBundleDisplayName</key><string>eBay Lister</string>
<key>CFBundleIdentifier</key><string>com.yoshiakinagumo.ebaylister.launcher</string>
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
# 多重起動防止: 既にListerのウインドウがあれば手前に出して終わる。
# 保存分岐防止: Chromeプロファイルを Default に固定して開く。
HTML="$HOME/Documents/Obsidian Vault/アプリ本体/eBay-Record-Lister/index.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

RAISED=$(osascript <<'OSA' 2>/dev/null
tell application "Google Chrome"
  if it is running then
    repeat with w in windows
      if title of w contains "eBay Record Lister" then
        set index of w to 1
        activate
        return "yes"
      end if
    end repeat
  end if
  return "no"
end tell
OSA
)
[ "$RAISED" = "yes" ] && exit 0

if command -v python3 >/dev/null 2>&1; then
  URL="file://$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$HTML")"
else
  URL="file://$HTML"
fi
if [ -x "$CHROME" ]; then
  "$CHROME" --profile-directory=Default --app="${URL}?app=1" --window-size=1380,900 >/dev/null 2>&1 &
else
  open "$HTML"
fi
RUN
chmod +x "$APP/Contents/MacOS/run"

[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
touch "$APP"

echo "== ② Dockに追加 =="
# DockのURLはエンコード形式（eBay%20Lister.app）で保存されることがあるため両方チェック（重複追加防止）
if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -Eq "eBay Lister\.app|eBay%20Lister\.app"; then
  defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/eBay Lister.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'
  killall Dock
  echo "Dockに追加しました。"
else
  echo "すでにDockにあります。"
fi

sleep 1
echo "== ③ 起動 =="
open "$APP"
echo ""
echo "完了。Dockの緑『e』から開けます。"
echo "※初回、既存ウインドウ確認のためChromeの操作許可を求められたら「許可」してください（多重起動防止に使います）。"
sleep 2
