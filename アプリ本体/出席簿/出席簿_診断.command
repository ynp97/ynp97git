#!/bin/zsh
OUT="$HOME/Documents/Obsidian Vault/アプリ本体/出席簿/診断結果.txt"
{
echo "== date"; date
echo "== xcode-select"; xcode-select -p 2>&1
echo "== which python3"; which -a python3 2>&1
echo "== /usr/bin/python3 --version"; /usr/bin/python3 --version 2>&1; echo "exit=$?"
echo "== bundle"; ls -la "/Applications/出席簿.app/Contents/MacOS" "/Applications/出席簿.app/Contents/Resources" 2>&1
echo "== launch"; cat "/Applications/出席簿.app/Contents/MacOS/launch" 2>&1
echo "== port"; /usr/sbin/lsof -nP -iTCP:8765 -sTCP:LISTEN 2>&1
echo "== data"; ls -la "$HOME/Library/Application Support/出席簿" 2>&1
echo "== server test (6s)"
cd "/Applications/出席簿.app/Contents/Resources" && ( /usr/bin/python3 server.py > /tmp/att_diag.log 2>&1 & echo $! > /tmp/att_diag.pid )
sleep 6
curl -sS -m 3 http://127.0.0.1:8765/api/health 2>&1; echo " curl_exit=$?"
echo "-- server log"; cat /tmp/att_diag.log
kill $(cat /tmp/att_diag.pid) 2>/dev/null
} > "$OUT" 2>&1
echo "診断終了。このウィンドウは閉じてOKです。"
