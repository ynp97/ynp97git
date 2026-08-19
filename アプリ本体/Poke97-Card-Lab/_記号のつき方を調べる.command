#!/bin/zsh
# 診断用。ダイゴのメタグロスex（cardID=50005）を1枚だけ取ってきて、
# 公式HTMLで本文中のエネルギー記号がどう書かれているかを見る。
# このカードは現在のDBで「自分のまたはポケモンに」と壊れているので、
# そこに何かの要素があったことが確実。
cd "${0:A:h}"
/usr/bin/python3 - <<'PY'
import re
from card_db import OfficialClient, text_with_icons, strip_tags

src = OfficialClient().detail("50005")
right = re.search(r'<div class="RightBox-inner">(.*?)</div>\s*</div>\s*<div class="clear">', src, re.S)
right = right.group(1) if right else src
paras = re.findall(r'<p\b[^>]*>(.*?)</p>', right, re.S)
target = next((p for p in paras if "ポケモンに" in p or "エネルギー" in p), paras[0] if paras else "")

print("=" * 60)
print("■ 公式HTMLの生の断片（ここに記号の書き方が出る）")
print(re.sub(r"\s+", " ", target)[:700])
print()
print("■ いまの text_with_icons の結果")
print(text_with_icons(target))
print()
print("■ 記号を落とす旧処理（比較用）")
print(strip_tags(target))
print()
print("■ 断片の中にあったタグ:", sorted(set(re.findall(r'<(\w+)[^>]*>', target)))[:12])
print("■ class の値:", sorted(set(re.findall(r'class="([^"]+)"', target)))[:12])
print("=" * 60)
PY
read -k 1
