#!/usr/bin/env python3
"""釈義mdの聖句を内蔵聖書から差し込む（2026-09-29）。
md中の、行全体が {{マルコ4:14}} や {{エゼキエル17:22-24}} の行を、
新改訳2017の本文ブロック（> マルコ4:14　本文）に置き換える。聖句を手で打たないための道具。
使い方: python3 scripts/expand_quotes.py 入力テンプレート.md 出力.md
"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse as V

PAT = re.compile(r'^\{\{\s*(.+?)(\d+):(\d+)(?:[-–](\d+))?\s*\}\}$')

def block(label, b, ch, v1, v2):
    t = V.load('sky', b)
    out = []
    for v in range(v1, v2 + 1):
        if (ch, v) not in t:
            raise SystemExit(f'本文なし: {label}{ch}:{v}')
        if out: out.append('>')
        out.append(f'> {label}{ch}:{v}　{t[(ch, v)]}')
    return out

def main(src, dst):
    lines, n = [], 0
    for line in Path(src).read_text(encoding='utf-8').split('\n'):
        m = PAT.match(line.strip())
        if m:
            label, ch, v1 = m.group(1), int(m.group(2)), int(m.group(3))
            v2 = int(m.group(4)) if m.group(4) else v1
            lines += block(label, V.book(label), ch, v1, v2); n += 1
        else:
            lines.append(line)
    Path(dst).write_text('\n'.join(lines), encoding='utf-8')
    print(f'差し込み {n} か所 → {dst}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
