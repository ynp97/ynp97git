#!/bin/bash
# 三本立てTODOのカレンダー同期を、ログイン中は常時監視・自動再起動する。
set -u
LABEL="com.ynp97.threetodo-calendar"
SOURCE="/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ/${LABEL}.plist"
SERVER_SOURCE="/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ/three_todo_calendar_server.py"
SUPPORT="$HOME/Library/Application Support/ThreeTodo"
TARGET="$HOME/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$SUPPORT"
cp "$SERVER_SOURCE" "$SUPPORT/three_todo_calendar_server.py"
cp "$SOURCE" "$TARGET"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$TARGET"
launchctl enable "$DOMAIN/$LABEL"
launchctl kickstart -k "$DOMAIN/$LABEL"

for _ in 1 2 3 4 5 6 7 8; do
  sleep 0.5
  if curl -fsS "http://127.0.0.1:8769/health" >/dev/null 2>&1; then
    echo "✅ 常時自動復旧を設定しました。同期機能が落ちてもMacが自動で起動し直します。"
    exit 0
  fi
done

echo "❌ 起動確認に失敗しました。ログの末尾:"
tail -n 30 /tmp/three_todo_calendar.log 2>/dev/null || true
exit 1
