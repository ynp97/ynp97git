#!/usr/bin/env python3
"""内蔵聖書（新改訳2017・ESV・NA28・HMT）の機械チェック。生成・差し替えの後に必ず実行する。
失敗があれば終了コード1。 使い方: python3 scripts/accordance_extract/verify_bibles.py"""
import re, sys, glob, collections
from pathlib import Path
V = Path(__file__).resolve().parents[2]
fail = []
def chk(cond, msg):
    print(("OK  " if cond else "NG  ") + msg)
    if not cond: fail.append(msg)
EXP = {"聖書（新改訳2017）": 31202, "聖書（ESV）": 31202, "聖書（ギリシャ語NA28）": 7968, "聖書（ヘブル語HMT）": 23213}
text = {}
for d, n in EXP.items():
    tot = dup = 0
    for f in glob.glob(str(V / d / "*.md")):
        if "索引" in f: continue
        t = open(f, encoding="utf-8").read(); text[(d, Path(f).stem)] = t
        a = re.findall(r"\^(\d+-\d+)$", t, re.M); tot += len(a)
        dup += sum(1 for k, c in collections.Counter(a).items() if c > 1)
    chk(tot == n, f"{d}: 節数 {tot}（期待 {n}）"); chk(dup == 0, f"{d}: 重複アンカー {dup}")
def line(d, stem, anc):
    m = re.search(rf"^\d+　(.+?) \^{anc}$", text.get((d, stem), ""), re.M); return m.group(1) if m else None
S = [("聖書（ESV）", "ESV ヨハネの福音書", "3-16", "“For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life."),
     ("聖書（ESV）", "ESV 詩篇", "23-1", "The LORD is my shepherd; I shall not want."),
     ("聖書（ESV）", "ESV 創世記", "15-2", "But Abram said, “O Lord GOD, what will you give me, for I continue childless, and the heir of my house is Eliezer of Damascus?”"),
     ("聖書（ギリシャ語NA28）", "NA28 ヨハネの福音書", "1-1", "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος."),
     ("聖書（ギリシャ語NA28）", "NA28 マタイの福音書", "1-1", "Βίβλος γενέσεως Ἰησοῦ Χριστοῦ υἱοῦ Δαυὶδ υἱοῦ Ἀβραάμ."),
     ("聖書（ヘブル語HMT）", "HMT 創世記", "1-1", "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃"),
     ("聖書（ヘブル語HMT）", "HMT 申命記", "6-4", "שְׁמַ֖ע יִשְׂרָאֵ֑ל יְהוָ֥ה אֱלֹהֵ֖ינוּ יְהוָ֥ה ׀ אֶחָֽד׃")]
for d, stem, anc, exp in S: chk(line(d, stem, anc) == exp, f"{stem} {anc} の本文が既知の値と一致")
nt = "".join(t for (d, s), t in text.items() if d == "聖書（ギリシャ語NA28）")
nx = nt.count("Χριστ") + nt.count("χριστ")
chk(nx > 500 and "Ξριστ" not in nt and "ξριστ" not in nt, f"NA28: χ/ξ の取り違えなし（Χριστ/χριστ {nx}件）")
esv = "".join(t for (d, s), t in text.items() if d == "聖書（ESV）")
chk(esv.count("LORD") > 6000, f"ESV: LORD の小型大文字が復元されている（{esv.count('LORD')}件）")
vl = "\n".join(re.findall(r"^\d+　.*$", esv, re.M))
chk("[[" not in vl and "]]" not in vl, "ESV: 本文中に [[ ]] が無い（Obsidianのリンク化を防ぐ）")
print("\n結果:", "全項目OK" if not fail else f"NG {len(fail)}件"); sys.exit(1 if fail else 0)
