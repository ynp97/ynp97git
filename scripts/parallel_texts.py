#!/usr/bin/env python3
"""主日の釈義用：指定箇所と、その並行箇所の本文を節ごとに並べて出す（本人指示・2026-09-25）。
並行箇所は `📖 説教箇所の進行表（AI共通）.md` の「並行箇所マップ」から引く。本文は `聖書（新改訳2017）/` から引く。
使い方: python3 scripts/parallel_texts.py マルコ4:26-34 [-o 出力.md]
"""
import re, sys
from pathlib import Path

VAULT = Path(__file__).resolve().parent.parent
BOOKS = {"マタイ": "マタイの福音書", "マルコ": "マルコの福音書", "ルカ": "ルカの福音書", "ヨハネ": "ヨハネの福音書"}
REF = re.compile(r"(マタイ|マルコ|ルカ|ヨハネ)?(\d+):(\d+)(?:[–\-〜](\d+))?")

def verses(book, ch, a, b):
    text = (VAULT / "聖書（新改訳2017）" / f"{BOOKS[book]}.md").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(rf"^(\d+)　(.+?) \^{ch}-\d+$", text, re.M):
        n = int(m.group(1))
        if a <= n <= b:
            out[n] = m.group(2)
    missing = [n for n in range(a, b + 1) if n not in out]
    if missing:
        raise SystemExit(f"本文が見つからない節: {book}{ch}:{missing}")
    return out

def block(book, ch, a, b):
    vs = verses(book, ch, a, b)
    lines = [f"### {book}{ch}:{a}–{b}"] + [f"> {book}{ch}:{n}　{t}" for n, t in vs.items()]
    return "\n".join(lines)

def main():
    args = sys.argv[1:]
    outpath = None
    if "-o" in args:
        i = args.index("-o"); outpath = Path(args[i + 1]); del args[i:i + 2]
    m = REF.fullmatch(args[0].replace("章", ":").replace("節", ""))
    if not m or not m.group(1):
        raise SystemExit("例: マルコ4:26-34")
    book, ch, a = m.group(1), int(m.group(2)), int(m.group(3)); b = int(m.group(4) or a)
    table = (VAULT / "📖 説教箇所の進行表（AI共通）.md").read_text(encoding="utf-8")
    body = [f"# 並行箇所の本文対照：{book}{ch}:{a}–{b}", "", block(book, ch, a, b), ""]
    hits = 0
    for row in re.finditer(r"^\| *(\d+):(\d+)[–\-](\d+) *\| *([^|]+)\|", table, re.M):
        rc, ra, rb = int(row.group(1)), int(row.group(2)), int(row.group(3))
        if book != "マルコ" or rc != ch or rb < a or ra > b:
            continue
        hits += 1
        body.append(f"## マルコ{rc}:{ra}–{rb} の並行（表の記載：{row.group(4).strip()}）")
        found = False
        for r in REF.finditer(re.sub(r"\*", "", row.group(4))):
            if not r.group(1):
                continue
            found = True
            body += ["", block(r.group(1), int(r.group(2)), int(r.group(3)), int(r.group(4) or r.group(3)))]
        if not found:
            body.append("\n（並行なし）")
        body.append("")
    if hits == 0:
        body.append("※並行箇所マップに該当行がありません（マルコ以外、または表が未作成の範囲）。対観表を見て表に行を足してください。")
    text = "\n".join(body)
    if outpath:
        outpath.write_text(text, encoding="utf-8"); print(outpath)
    else:
        print(text)

if __name__ == "__main__":
    main()
