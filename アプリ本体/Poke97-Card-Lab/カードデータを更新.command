#!/bin/zsh
set -e
APP_DIR="${0:A:h}"
cd "$APP_DIR"
echo "poke97のカードデータを更新します。途中で閉じても、次回は続きから再開します。"
# requests が消えていたら入れ直す（2026-09-18、/usr/bin/python3 から requests が消えて更新が止まったため）
/usr/bin/python3 -c "import requests" 2>/dev/null || /usr/bin/python3 -m pip install --user requests
/usr/bin/python3 update_cards.py --retry-errors
/usr/bin/python3 enrich_metadata.py
echo ""
echo "更新が終わりました。この画面は閉じてかまいません。"
read -k 1
