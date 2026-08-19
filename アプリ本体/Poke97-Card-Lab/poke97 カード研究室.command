#!/bin/zsh
# poke97 カード研究室 起動スクリプト（本体）
#
# .app からも、このファイルを直接ダブルクリックしても、ここへ入る。
# .app が自分で python3 を動かさないのは、書類フォルダの保護のため。
# 署名の無いアプリからは server.py を開けず「Operation not permitted」になる。
# ターミナルには書類フォルダの許可があるので、実処理はここで行う。
#
# 動いているサーバーに相乗りしない。コードを直した直後に古いサーバーが残っていると、
# 画面だけ新しく中身が古いという、原因の見えない状態になるため。
set -u
PORT=8797
LAB="${0:A:h}"
LOG="$LAB/data/launcher.log"
cd "$LAB" || exit 1

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" | /usr/bin/tee -a "$LOG" }
alive() { /usr/bin/nc -z 127.0.0.1 $PORT >/dev/null 2>&1 }

log "--- 起動要求 ---"
OLD=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null)
if [[ -n "$OLD" ]]; then
  log "ポート$PORTを使用中のプロセスを停止: $OLD"
  kill ${=OLD} 2>/dev/null
  for _ in {1..20}; do alive || break; sleep 0.25; done
  alive && { log "強制停止"; kill -9 ${=OLD} 2>/dev/null; sleep 0.5 }
fi
if alive; then
  log "ポート$PORTを空けられませんでした。この窓を閉じて、もう一度開いてください。"
  exit 1
fi

/usr/bin/python3 server.py --no-open --port $PORT 2>&1 | /usr/bin/tee -a "$LOG" &
for _ in {1..60}; do alive && break; sleep 0.25; done

if alive; then
  log "起動しました。画面を開きます → http://127.0.0.1:$PORT/"
  log "終了するときは、この窓で control+C を押すか、窓を閉じてください。"
  /usr/bin/open "http://127.0.0.1:$PORT/"
else
  log "起動できませんでした。上のメッセージを確認してください。"
fi
wait
