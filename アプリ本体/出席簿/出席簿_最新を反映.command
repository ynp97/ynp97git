#!/bin/zsh
# 出席簿アプリ（Dock）を、Vaultの正本へ反映するスクリプト。
# ・正本 attendance_form_report.html / server.py を /Applications/出席簿.app のResourcesにコピー
# ・サーバーは launchd（ログイン中は常駐・落ちたら自動再起動）で動かす
#   （2026-09-29変更：アプリ起動時にnohupで立てる方式では、ページを開いた後にサーバーが消えることがあった）
# ・起動ファイル(launch)は「サーバーの応答を待ってからブラウザで開く」だけにする
set -e

VAULT_DIR="$HOME/Documents/Obsidian Vault/アプリ本体/出席簿"
APP="/Applications/出席簿.app"
RES="$APP/Contents/Resources"
LABEL="local.nagumo.attendance"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT=8765

for f in attendance_form_report.html server.py; do
  if [ ! -f "$VAULT_DIR/$f" ]; then echo "正本が見つかりません: $VAULT_DIR/$f"; exit 1; fi
done
if [ ! -d "$RES" ]; then echo "アプリが見つかりません: $APP"; exit 1; fi

cp "$VAULT_DIR/attendance_form_report.html" "$RES/attendance_form_report.html"
cp "$VAULT_DIR/server.py" "$RES/server.py"

cat > "$APP/Contents/MacOS/launch" <<'LAUNCH'
#!/bin/sh
PORT=8765
LABEL="local.nagumo.attendance"
if ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
  launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1 \
    || launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist" >/dev/null 2>&1
  i=0
  while [ $i -lt 50 ] && ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; do
    sleep 0.2; i=$((i+1))
  done
fi
open "http://127.0.0.1:$PORT/attendance_form_report.html?v=$(date +%s)"
LAUNCH
chmod +x "$APP/Contents/MacOS/launch"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$RES/server.py</string>
  </array>
  <key>WorkingDirectory</key><string>$RES</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/attendance_report_server.log</string>
  <key>StandardErrorPath</key><string>/tmp/attendance_report_server.log</string>
</dict>
</plist>
PL

# 古い手動起動のサーバーが残っていれば止める
PID="$(/usr/sbin/lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null || true)"
[ -n "$PID" ] && kill $PID 2>/dev/null || true
sleep 0.3

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
sleep 0.3
launchctl bootstrap "gui/$(id -u)" "$PLIST"

i=0
while [ $i -lt 50 ] && ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; do
  sleep 0.2; i=$((i+1))
done
if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
  echo "サーバー起動OK（launchd常駐）"
else
  echo "サーバーが応答しません。/tmp/attendance_report_server.log を確認してください"; exit 1
fi

open "http://127.0.0.1:$PORT/attendance_form_report.html?v=$(date +%s)"
echo "完了しました。"
