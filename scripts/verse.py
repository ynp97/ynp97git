#!/usr/bin/env python3
"""内蔵聖書から指定箇所だけを取り出す（2026-09-28）。巻ファイルを丸ごと読まずに済ませ、記憶による引用を避けるため。
使い方: python3 scripts/verse.py マルコ4:26-34 [sky] [esv] [gk] [he]
  版を省略すると 新改訳2017・ESV・原語（新約=NA28／旧約=HMT）を全部出す。
  見つからない節は「本文なし」と明示する（黙って飛ばさない）。
  ヘブル語は章節がヘブル語聖書の番号。ESVと章の節数が違う章では警告を出す。
"""
import re, sys
from pathlib import Path
V = Path(__file__).resolve().parent.parent
JP = ["創世記","出エジプト記","レビ記","民数記","申命記","ヨシュア記","士師記","ルツ記","サムエル記第一","サムエル記第二","列王記第一","列王記第二","歴代誌第一","歴代誌第二","エズラ記","ネヘミヤ記","エステル記","ヨブ記","詩篇","箴言","伝道者の書","雅歌","イザヤ書","エレミヤ書","哀歌","エゼキエル書","ダニエル書","ホセア書","ヨエル書","アモス書","オバデヤ書","ヨナ書","ミカ書","ナホム書","ハバクク書","ゼパニヤ書","ハガイ書","ゼカリヤ書","マラキ書","マタイの福音書","マルコの福音書","ルカの福音書","ヨハネの福音書","使徒の働き","ローマ人への手紙","コリント人への手紙第一","コリント人への手紙第二","ガラテヤ人への手紙","エペソ人への手紙","ピリピ人への手紙","コロサイ人への手紙","テサロニケ人への手紙第一","テサロニケ人への手紙第二","テモテへの手紙第一","テモテへの手紙第二","テトスへの手紙","ピレモンへの手紙","ヘブル人への手紙","ヤコブの手紙","ペテロの手紙第一","ペテロの手紙第二","ヨハネの手紙第一","ヨハネの手紙第二","ヨハネの手紙第三","ユダの手紙","ヨハネの黙示録"]
EN = ["Gen","Exod","Lev","Num","Deut","Josh","Judg","Ruth","1Sam","2Sam","1Kgs","2Kgs","1Chr","2Chr","Ezra","Neh","Esth","Job","Ps","Prov","Eccl","Song","Isa","Jer","Lam","Ezek","Dan","Hos","Joel","Amos","Obad","Jonah","Mic","Nah","Hab","Zeph","Hag","Zech","Mal","Matt","Mark","Luke","John","Acts","Rom","1Cor","2Cor","Gal","Eph","Phil","Col","1Thess","2Thess","1Tim","2Tim","Titus","Phlm","Heb","Jas","1Pet","2Pet","1John","2John","3John","Jude","Rev"]
ALIAS = {"ヨハネ":"ヨハネの福音書","黙示録":"ヨハネの黙示録","使徒":"使徒の働き","ローマ":"ローマ人への手紙","ヘブル":"ヘブル人への手紙","ヤコブ":"ヤコブの手紙","ユダ":"ユダの手紙","伝道者":"伝道者の書"}
for k, n in [("Ⅰ","第一"),("Ⅱ","第二"),("Ⅲ","第三"),("1","第一"),("2","第二"),("3","第三")]:
    for base in ["サムエル記","列王記","歴代誌","コリント人への手紙","テサロニケ人への手紙","テモテへの手紙","ペテロの手紙","ヨハネの手紙"]:
        ALIAS[k + base.replace("人への手紙","").replace("への手紙","").replace("の手紙","").replace("記","").replace("誌","")] = base + n
def book(name):
    if name in JP: return JP.index(name)
    if name in ALIAS: return JP.index(ALIAS[name])
    low = {e.lower(): i for i, e in enumerate(EN)}
    if name.lower() in low: return low[name.lower()]
    c = [i for i, j in enumerate(JP) if j.startswith(name)]
    if len(c) == 1: return c[0]
    raise SystemExit(f"書名を特定できない: {name}（候補: {[JP[i] for i in c]}）")
ED = {"sky": ("聖書（新改訳2017）", "{}"), "esv": ("聖書（ESV）", "ESV {}"),
      "gk": ("聖書（ギリシャ語NA28）", "NA28 {}"), "he": ("聖書（ヘブル語HMT）", "HMT {}")}
def load(ed, b):
    d, f = ED[ed]; p = V / d / (f.format(JP[b]) + ".md")
    out = {}
    for m in re.finditer(r"^(\d+)　(.+?) \^(\d+)-(\d+)$", p.read_text(encoding="utf-8"), re.M):
        out[(int(m.group(3)), int(m.group(4)))] = m.group(2)
    return out
def main():
    a = sys.argv[1:]
    if not a: raise SystemExit(__doc__)
    m = re.fullmatch(r"(.+?)\s*(\d+)[:：章](\d+)(?:節)?(?:[-–〜~](?:(\d+)[:：])?(\d+))?", a[0].replace(" ", ""))
    if not m: raise SystemExit("例: マルコ4:26-34 / Gen1:1-3 / 詩篇23:1-6 / ヨハネ3:36-4:3")
    b = book(m.group(1)); c1, v1 = int(m.group(2)), int(m.group(3))
    c2 = int(m.group(4)) if m.group(4) else c1; v2 = int(m.group(5)) if m.group(5) else v1
    eds = [e for e in a[1:] if e in ED] or ["sky", "esv", "gk" if b >= 39 else "he"]
    for ed in eds:
        if (ed == "gk" and b < 39) or (ed == "he" and b >= 39): continue
        t = load(ed, b)
        rng = f"{c1}:{v1}" + ("" if (c1, v1) == (c2, v2) else "–" + (f"{c2}:" if c2 != c1 else "") + f"{v2}")
        print(f"### {ED[ed][0]} {JP[b]} {rng}")
        if ed == "he":
            esv = load("esv", b)
            for c in range(c1, c2 + 1):
                nh = len([k for k in t if k[0] == c and k[1] > 0]); ne = len([k for k in esv if k[0] == c and k[1] > 0])
                if nh != ne: print(f"⚠ ヘブル語の{c}章は{nh}節、ESVは{ne}節。英語・日本語と節番号がずれている可能性がある。本文で照合すること。")
        keys = sorted(k for k in t if (c1, v1) <= k <= (c2, v2))
        if (c1, v1) not in t: print(f"（{c1}:{v1} はこの版に本文なし）")
        prev = None
        for k in keys:
            if prev and k[0] == prev[0] and k[1] != prev[1] + 1 and prev[1] != 0:
                for x in range(prev[1] + 1, k[1]): print(f"（{k[0]}:{x} はこの版に本文なし）")
            print(f"> {EN[b]} {k[0]}:{k[1]}　{t[k]}"); prev = k
        if (c2, v2) not in t and (c2, v2) != (c1, v1): print(f"（{c2}:{v2} はこの版に本文なし）")
        print()
if __name__ == "__main__": main()
