#!/usr/bin/env python3
"""釈義md §9（霊的適用・深掘り構造）の機械検査。2026-09-28。
合格条件:
  - §9に【n-k】形式の項目がある
  - 第1層の項目がある
  - 第2層以降の各項目に「← 親」があり、親は一つ上の層に実在する
  - 番号の重複がない
使い方: python3 check_exegesis_s9.py 釈義/xxx.md   （不合格なら終了コード1）
"""
import re, sys

def section9(text):
    m = re.search(r'^#{2,3} *9[.．].*?$(.*?)(?=^#{2,3} *(?:10|[0-9]{2})[.．]|^## (?!#)(?! *9)|\Z)', text, re.M | re.S)
    return m.group(1) if m else None

def check(path):
    text = open(path, encoding='utf-8').read()
    s9 = section9(text)
    errs = []
    if s9 is None:
        return ['§9 が見つからない']
    items = re.findall(r'【\s*(\d+)-(\d+)\s*(?:←\s*(\d+)-(\d+)\s*)?】', s9)
    if not items:
        return ['§9 に【n-k】形式の項目がない（旧形式の四層のまま）']
    seen = set()
    for n, k, pn, pk in items:
        key = (int(n), int(k))
        if key in seen:
            errs.append(f'【{n}-{k}】番号が重複')
        seen.add(key)
    if not any(n == 1 for n, _ in seen):
        errs.append('第1層の項目がない')
    for n, k, pn, pk in items:
        n = int(n)
        if n == 1:
            if pn:
                errs.append(f'【1-{k}】第1層に親がついている')
            continue
        if not pn:
            errs.append(f'【{n}-{k}】親の表示がない（横に並べただけの項目）')
            continue
        if int(pn) != n - 1:
            errs.append(f'【{n}-{k}】親 {pn}-{pk} が一つ上の層ではない')
        elif (int(pn), int(pk)) not in seen:
            errs.append(f'【{n}-{k}】親 {pn}-{pk} が実在しない')
    depth = max(n for n, _ in seen)
    return errs, depth, len(seen)

if __name__ == '__main__':
    bad = False
    for p in sys.argv[1:]:
        r = check(p)
        if isinstance(r, list):
            print(f'不合格 {p}: ' + '; '.join(r)); bad = True; continue
        errs, depth, count = r
        if errs:
            print(f'不合格 {p}:'); [print('  - ' + e) for e in errs]; bad = True
        else:
            print(f'合格 {p}: {count}項目・第{depth}層まで')
    sys.exit(1 if bad else 0)
