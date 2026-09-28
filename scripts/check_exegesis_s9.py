#!/usr/bin/env python3
"""釈義md §9（霊的適用・深掘り構造・線ごと）の機械検査。2026-09-28。
項目見出し（行頭）: 【A1-1】 / 【A2-1 ← A1-1】  （線の記号＋層＋番号）
合格条件:
  - §9に項目がある
  - 各線に第1層がある
  - 第2層以降の各項目に「← 親」があり、親は同じ線の一つ上の層に実在する
  - 番号の重複がない
使い方: python3 check_exegesis_s9.py 釈義/xxx.md   （不合格なら終了コード1）
"""
import re, sys

ITEM = re.compile(r'^\s*[-*]?\s*【\s*([A-Z])(\d+)-(\d+)\s*(?:←\s*([A-Z])(\d+)-(\d+)\s*)?】', re.M)

def section9(text):
    m = re.search(r'^##\s*9[.．].*?$(.*?)(?=^##\s*(?!9)\d+[.．]|^##\s[^#\d]|\Z)', text, re.M | re.S)
    return m.group(1) if m else None

def check(path):
    s9 = section9(open(path, encoding='utf-8').read())
    if s9 is None:
        return ['§9 が見つからない'], {}
    items = ITEM.findall(s9)
    if not items:
        return ['§9 に【A1-1】形式の項目がない（旧形式のまま）'], {}
    errs, seen = [], set()
    for L, n, k, *_ in items:
        key = (L, int(n), int(k))
        if key in seen: errs.append(f'【{L}{n}-{k}】番号が重複')
        seen.add(key)
    lines = sorted({L for L, *_ in seen})
    for L in lines:
        if not any(l == L and n == 1 for l, n, _ in seen):
            errs.append(f'線{L}に第1層がない')
    for L, n, k, pL, pn, pk in items:
        n = int(n); tag = f'【{L}{n}-{k}】'
        if n == 1:
            if pL: errs.append(f'{tag}第1層に親がついている')
            continue
        if not pL:
            errs.append(f'{tag}親の表示がない'); continue
        if pL != L: errs.append(f'{tag}親 {pL}{pn}-{pk} が別の線')
        elif int(pn) != n - 1: errs.append(f'{tag}親 {pL}{pn}-{pk} が一つ上の層ではない')
        elif (pL, int(pn), int(pk)) not in seen: errs.append(f'{tag}親 {pL}{pn}-{pk} が実在しない')
    depth = {L: max(n for l, n, _ in seen if l == L) for L in lines}
    return errs, depth

if __name__ == '__main__':
    bad = False
    for p in sys.argv[1:]:
        errs, depth = check(p)
        if errs:
            bad = True; print(f'不合格 {p}:'); [print('  - ' + e) for e in errs]
        else:
            print(f'合格 {p}: ' + '、'.join(f'線{L} 第{d}層まで' for L, d in depth.items()))
    sys.exit(1 if bad else 0)
