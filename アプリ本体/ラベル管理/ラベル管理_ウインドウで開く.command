#!/bin/zsh
# 資料請求ラベル管理.html を Chromeのアプリモード（タブ・アドレスバー無しの独自ウインドウ）で開く。
# 常駐プロセスは作らない。このスクリプトは開いたら即終了する。
HTML="$HOME/Documents/Obsidian Vault/アプリ本体/ラベル管理/資料請求ラベル管理.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -f "$HTML" ]; then
  osascript -e 'display alert "HTMLが見つかりません" message "資料請求ラベル管理.html を同じフォルダに置いてください。"'
  exit 1
fi

# 起動を速くするため python3 は呼ばない。file URL に必要なのは空白の %20 だけ。
zmodload zsh/datetime 2>/dev/null
T=${EPOCHREALTIME:-0}
URL="file://${HTML// /%20}"

if [ -x "$CHROME" ]; then
  # 保存分岐防止: プロファイルをDefaultに固定し、?app=1 を付ける
  "$CHROME" --profile-directory=Default --app="${URL}?app=1&t=${T}" --window-size=1200,840 >/dev/null 2>&1 &
else
  # Chromeが無ければ通常ブラウザで開く（独自ウインドウにはならない）
  open "$HTML"
fi
exit 0
