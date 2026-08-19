#!/bin/bash
# 三本立てTODO カレンダー同期の修復コマンド
# 「同期できませんでした / Failed to fetch」が出たら、これをダブルクリック。
# アプリのウインドウは閉じなくてよい。サーバーだけ立て直す。
SERVER="/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ/three_todo_calendar_server.py"
LOG="/tmp/three_todo_calendar.log"

echo "== 三本立てTODO 同期サーバー修復 =="

if curl -fsS "http://127.0.0.1:8769/health" >/dev/null 2>&1; then
  echo "✅ サーバーは既に動いています（127.0.0.1:8769）。"
  echo "   それでも失敗する場合は、非公開iCal URLが正しいか確認してください。"
  exit 0
fi

echo "サーバーが動いていません。立て直します…"

# 残骸プロセスがあれば止める
pkill -f "three_todo_calendar_server.py" 2>/dev/null
sleep 0.5

if [ ! -f "$SERVER" ]; then
  echo "❌ サーバー本体が見つかりません: $SERVER"
  exit 1
fi

nohup /usr/bin/python3 "$SERVER" >>"$LOG" 2>&1 &

ok=""
for _ in 1 2 3 4 5 6 7 8; do
  sleep 0.5
  if curl -fsS "http://127.0.0.1:8769/health" >/dev/null 2>&1; then ok=1; break; fi
done

if [ -n "$ok" ]; then
  echo "✅ サーバーを起動しました。"
  echo "   アプリに戻って、もう一度「今すぐ同期」を押してください。"
else
  echo "❌ 起動に失敗しました。ログの末尾:"
  echo "----------------------------------------"
  tail -n 20 "$LOG" 2>/dev/null || echo "（ログなし）"
  echo "----------------------------------------"
  echo "この画面をAIに見せてください。"
fi
