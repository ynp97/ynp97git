#!/bin/bash
# ------------------------------------------------------------
# Vault バックアップ ／ ZatsuTodo 復元
#
#   正本 = 15インチAir の内蔵SSD  ~/Documents/Obsidian Vault
#   経路 = Air内蔵(正本) → BENJAMIN → M5(家に残る控え)
#
#   BENJAMIN は渡航に持っていくので、それ単体では控えにならない。
#   家に残る M5 が控え先。BENJAMIN 上のコピーは旅先での2本目。
#
# 使い方
#   Airで:  bash vault_backup.sh push    正本 → BENJAMIN
#   M5で:   bash vault_backup.sh pull    BENJAMIN → M5の控え
#   Airで:  bash vault_backup.sh zatsu   BENJAMIN → Air の ZatsuTodo（一度だけ）
#
# 出発直前（8/22頃）に push → SSDを持ってM5へ → pull を もう一度回す。
# 作成: 2026-08-16
# ------------------------------------------------------------
set -u

SRC_AIR="$HOME/Documents/Obsidian Vault"
BEN="/Volumes/BENJAMIN/Obsidian Vault"
DST_M5="$HOME/Documents/Obsidian Vault 控え"
ZT_DST="$HOME/Library/Application Support/ZatsuTodo"

if [ ! -d /Volumes/BENJAMIN ]; then
  echo "✗ BENJAMIN がマウントされていない。SSDを挿してから実行する。"
  exit 1
fi

count() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

case "${1:-}" in
  push)
    [ -d "$SRC_AIR" ] || { echo "✗ 正本が見つからない: $SRC_AIR"; exit 1; }
    echo "→ 正本 → BENJAMIN"
    rsync -a --delete --exclude '.DS_Store' "$SRC_AIR/" "$BEN/" || exit 1
    echo "--- 確認 ---"
    echo "  正本      : $(count "$SRC_AIR") ファイル"
    echo "  BENJAMIN  : $(count "$BEN") ファイル"
    ;;

  pull)
    [ -d "$BEN" ] || { echo "✗ BENJAMIN上にVaultがない: $BEN"; exit 1; }
    echo "→ BENJAMIN → M5の控え（$DST_M5）"
    mkdir -p "$DST_M5"
    rsync -a --delete --exclude '.DS_Store' "$BEN/" "$DST_M5/" || exit 1
    echo "--- 確認 ---"
    echo "  BENJAMIN  : $(count "$BEN") ファイル"
    echo "  M5の控え  : $(count "$DST_M5") ファイル"
    echo "  最終更新  : $(find "$DST_M5" -type f -exec stat -f '%Sm %N' -t '%Y-%m-%d %H:%M' {} + 2>/dev/null | sort | tail -1)"
    ;;

  zatsu)
    # BENJAMIN 側のフォルダ名は移行時に / を ∕ へ置換した平たい名前なので glob で拾う
    ZT_SRC=$(ls -d /Volumes/BENJAMIN/_移行データ/*ZatsuTodo 2>/dev/null | head -1)
    [ -n "$ZT_SRC" ] || { echo "✗ BENJAMIN上に ZatsuTodo データが見つからない"; exit 1; }
    if pgrep -qx "ZatsuTodo" 2>/dev/null; then
      echo "✗ 雑TODOアプリが起動中。終了してから実行する（起動中だと終了時に古い中身で上書きされる）。"
      exit 1
    fi
    echo "→ $ZT_SRC"
    echo "  → $ZT_DST"
    mkdir -p "$ZT_DST"
    rsync -a --exclude '.DS_Store' "$ZT_SRC/" "$ZT_DST/" || exit 1
    echo "--- 確認 ---"
    ls -l "$ZT_DST"
    ;;

  *)
    echo "使い方: bash vault_backup.sh push | pull | zatsu"
    exit 1
    ;;
esac

echo "完了。"
