#!/usr/bin/env python3
"""釈義md・説教mdの聖句引用を、内蔵の新改訳2017と一字一句照合する（2026-09-29）。
対象: 「> 書名章:節　本文」の形の行（書名は日本語の略称。例 マルコ4:14／Ⅰコリント3:6）。
一つでも食い違えば一覧を出して終了コード1。記録は --log ファイル名 で追記できる。
使い方: python3 scripts/check_quotes.py 釈義/xxx.md [--log 記録.md]
"""
import re, sys, datetime
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse as V

LINE = re.compile(r'^>\s*([^\d\sA-Za-z>][^\d]*?)(\d+):(\d+)　(.+)$')

def check(path):
    ok, bad, cache = 0, [], {}
    for no, line in enumerate(Path(path).read_text(encoding='utf-8').split('\n'), 1):
        m = LINE.match(line.strip())
        if not m: continue
        label, ch, v, body = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4).strip()
        try:
            b = V.book(label)
        except SystemExit as e:
            bad.append(f'{no}行 {label}{ch}:{v} 書名不明 ({e})'); continue
        t = cache.setdefault(b, V.load('sky', b))
        want = t.get((ch, v))
        if want is None:
            bad.append(f'{no}行 {label}{ch}:{v} 内蔵本文に無い節')
        elif body != want:
            bad.append(f'{no}行 {label}{ch}:{v}\n    md  : {body}\n    内蔵: {want}')
        else:
            ok += 1
    return ok, bad

if __name__ == '__main__':
    args = sys.argv[1:]
    log = None
    if '--log' in args:
        i = args.index('--log'); log = args[i + 1]; del args[i:i + 2]
    fail = False
    for p in args:
        ok, bad = check(p)
        head = f'{"不合格" if bad else "合格"} {p}: 一致 {ok} 節／食い違い {len(bad)} 節'
        print(head); [print('  - ' + b) for b in bad]
        if log:
            with open(log, 'a', encoding='utf-8') as f:
                f.write(f'- {datetime.date.today()} {head}\n')
        fail |= bool(bad)
    sys.exit(1 if fail else 0)
