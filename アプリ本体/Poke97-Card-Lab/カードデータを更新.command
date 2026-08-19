#!/bin/zsh
set -e
APP_DIR="${0:A:h}"
cd "$APP_DIR"
echo "poke97のカードデータを更新します。途中で閉じても、次回は続きから再開します。"
/usr/bin/python3 update_cards.py --retry-errors
/usr/bin/python3 enrich_metadata.py
echo ""
echo "更新が終わりました。この画面は閉じてかまいません。"
read -k 1
