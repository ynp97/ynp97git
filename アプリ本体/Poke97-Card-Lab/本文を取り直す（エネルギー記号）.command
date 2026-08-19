#!/bin/zsh
# 2026-08-07 追加。
# それまでの取得では、本文中のエネルギー・タイプが「アイコン要素」だったため
# 消えていた。「基本【水】エネルギー」→「基本エネルギー」、
# 「自分の【鋼】または【超】ポケモンに」→「自分のまたはポケモンに」。
# 解析を直したので、全カードの本文を一度だけ取り直す。
#
# いきなり5,550枚を取りに行かず、まず10枚で【】が入るか確かめる。
# 入らなければ解析側がまだ違うので、そこで止める（40分をムダにしないため）。
set -e
APP_DIR="${0:A:h}"
cd "$APP_DIR"

# 下見に使うカードは「記号が確実に入っているもの」を名指しする。
# 最初は update_cards.py --limit 10 で新しい順に10枚取っていたが、それは
# 基本エネルギー8枚など本文の無いカードで、記号が0件でも当たり前だった。
# 「取れていない」のか「そもそも無い」のかを区別できない下見は、下見にならない。
#   50005 ダイゴのメタグロスex … 「自分の【超】または【鋼】ポケモンに」
#   50416 パーモット            … 「基本【雷】エネルギー」
#   50351 ブーバーン            … 「基本【炎】」と「基本【雷】」の2色
echo "■ 手順1／2：記号が確実にあるカードを3枚だけ取って、読み取れるか確かめます"

FOUND=$(/usr/bin/python3 - <<'PY'
import re, sys
from card_db import OfficialClient, text_with_icons

client = OfficialClient()
hits = 0
for card_id in ("50005", "50416", "50351"):
    try:
        src = client.detail(card_id)
    except Exception as exc:
        print(f"  {card_id}: 取得できません（{exc}）", file=sys.stderr)
        continue
    body = "\n".join(text_with_icons(p) for p in re.findall(r'<p\b[^>]*>(.*?)</p>', src, re.S))
    marks = re.findall(r"【[^】]+】", body)
    print(f"  {card_id}: 記号 {len(marks)}個 {' '.join(dict.fromkeys(marks))}", file=sys.stderr)
    hits += len(marks)
print(hits)
PY
)

echo ""
if [ "$FOUND" -eq 0 ]; then
  echo "× 下見の3枚から【超】のような記号が1つも読み取れませんでした。"
  echo "  公式ページの書き方が変わっています。card_db.py の text_with_icons を直してください。"
  echo "  何がどう書かれているかは _記号のつき方を調べる.command で見られます。"
  echo "  ここで止めます（全件の取り直しはしていません）。"
  read -k 1
  exit 1
fi
echo "○ 記号を ${FOUND} 個 読み取れました。全件の取り直しへ進みます。"
echo ""
echo "■ 手順2／2：全カードを取り直します。30〜50分ほどかかります。"
echo "  途中で閉じても構いません。次回は続きから再開します。"
echo ""
/usr/bin/python3 update_cards.py --refresh-all
/usr/bin/python3 enrich_metadata.py

echo ""
/usr/bin/python3 - <<'PY'
import sqlite3
from card_db import DEFAULT_DB
db = sqlite3.connect(DEFAULT_DB)
ab = db.execute("SELECT COUNT(*) FROM abilities WHERE text LIKE '%【%'").fetchone()[0]
ax = db.execute("SELECT COUNT(*) FROM attacks WHERE text LIKE '%【%'").fetchone()[0]
bd = db.execute("SELECT COUNT(*) FROM cards WHERE body_text LIKE '%【%'").fetchone()[0]
print(f"エネルギー記号の入った文：特性 {ab}件 / ワザ {ax}件 / 本文 {bd}件")
row = db.execute("""SELECT c.name, a.text FROM abilities a JOIN cards c ON c.card_id=a.card_id
                    WHERE a.text LIKE '%【%' LIMIT 1""").fetchone()
if row:
    print(f"例）{row[0]}：{row[1][:70]}")
PY
echo ""
echo "終わりました。研究室を開き直すと、AIへの質問窓の警告が消えます。"
read -k 1
