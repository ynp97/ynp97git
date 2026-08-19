#!/bin/zsh
# 出席簿アプリ（Dock）を、Vaultの正本HTMLへ反映するスクリプト。
# ・正本 attendance_form_report.html を /Applications/出席簿.app のResourcesにコピー
# ・起動ファイル(launch)を、URLにキャッシュ回避パラメータ付きで開く版に更新
# ・サーバーを再起動し、最新HTMLをブラウザで開く
set -e

VAULT_DIR="$HOME/Documents/Obsidian Vault/アプリ本体/出席簿"
SRC="$VAULT_DIR/attendance_form_report.html"
SERVER_SRC="$VAULT_DIR/server.py"
PORT=8765

if [ ! -f "$SRC" ]; then
  echo "正本が見つかりません: $SRC"
  exit 1
fi

if [ ! -f "$SERVER_SRC" ]; then
  echo "サーバー正本が見つかりません: $SERVER_SRC"
  exit 1
fi

write_launch() {
  L="$1"
  cat > "$L" <<'LAUNCH'
#!/bin/sh
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="$APP_DIR/Resources"
PORT=8765

if ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
  PID="$(/usr/sbin/lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null)"
  if [ -n "$PID" ]; then
    kill $PID >/dev/null 2>&1
    sleep 0.3
  fi
  cd "$RESOURCES_DIR" || exit 1
  nohup /usr/bin/python3 "$RESOURCES_DIR/server.py" >/tmp/attendance_report_server.log 2>&1 </dev/null &
  sleep 0.5
fi

open "http://127.0.0.1:$PORT/attendance_form_report.html?v=$(date +%s)"
LAUNCH
  chmod +x "$L"
}

setup_bundle() {
  APP="$1"
  RES="$APP/Contents/Resources"
  if [ ! -d "$RES" ]; then
    echo "見つからないので飛ばします: $APP"
    return
  fi
  rm -f "$RES/attendance_form_report.html"
  cp "$SRC" "$RES/attendance_form_report.html"
  cp "$SERVER_SRC" "$RES/server.py"
  write_launch "$APP/Contents/MacOS/launch"
  echo "反映しました: $APP"
}

setup_bundle "/Applications/出席簿.app"

# 動いているサーバーを止めて再起動（HTML再読み込みのため）
PID="$(/usr/sbin/lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$PID" ]; then
  kill $PID >/dev/null 2>&1 || true
  sleep 0.3
fi

RES="/Applications/出席簿.app/Contents/Resources"
cd "$RES"
nohup /usr/bin/python3 "$RES/server.py" >/tmp/attendance_report_server.log 2>&1 </dev/null &
sleep 0.8

open "http://127.0.0.1:$PORT/attendance_form_report.html?v=$(date +%s)"

echo "完了しました。新しく開いたタブで、レポート欄に挨拶文の入力欄が出るか確認してください。"
