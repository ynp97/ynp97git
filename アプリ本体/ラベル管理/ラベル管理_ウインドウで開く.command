#!/bin/zsh
# 資料請求ラベル管理.html を Chromeのアプリモード（タブ・アドレスバー無しの独自ウインドウ）で開く。
# 常駐プロセスは作らない。このスクリプトは開いたら即終了する。
HTML="$HOME/Documents/Obsidian Vault/アプリ本体/ラベル管理/資料請求ラベル管理.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -f "$HTML" ]; then
  osascript -e 'display alert "HTMLが見つかりません" message "資料請求ラベル管理.html を同じフォルダに置いてください。"'
  exit 1
fi

# 空白・日本語を含むパスを安全にfile URL化（python3が無ければ生パス）
if command -v python3 >/dev/null 2>&1; then
  URL="file://$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$HTML")"
else
  URL="file://$HTML"
fi

if [ -x "$CHROME" ]; then
  # 保存分岐防止: プロファイルをDefaultに固定し、?app=1 を付ける
  "$CHROME" --profile-directory=Default --app="${URL}?app=1" --window-size=1200,840 >/dev/null 2>&1 &
else
  # Chromeが無ければ通常ブラウザで開く（独自ウインドウにはならない）
  open "$HTML"
fi
exit 0
