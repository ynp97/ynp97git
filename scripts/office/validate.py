#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""説教原稿docxが『📄 説教原稿Word出力仕様（AI共通）.md』どおりに組まれているかを機械で検査する。

使い方:
    python3 scripts/office/validate.py <out.docx> [--original scripts/sermon_docx_template.docx]

出力は PASS / FAIL / NOTE の行だけ。FAIL が1件でもあれば終了コード 1。
人が紙を見て判断する項目（文字の大きさが説教台で足りるか等）は検査しない。
"""
import sys, re, argparse, zipfile
from lxml import etree

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
STYLES = {'説教題', 'メッセージ本文', 'メッセージ聖書個所', '引用聖書箇所'}
VERSE_STYLES = {'メッセージ聖書個所', '引用聖書箇所'}
LABEL_BLUE = '006699'
QUOTE_BROWN = '833C0B'
MAX_WIDTH = 45
ABBR = set("""Gen. Ex. Lev. Num. Deut. Josh. Judg. Ruth 1Sam. 2Sam. 1Kings 2Kings 1Chr. 2Chr.
Ezra Neh. Esth. Job Psa. Prov. Eccl. Song Is. Jer. Lam. Ezek. Dan. Hos. Joel Amos Obad. Jonah
Mic. Nah. Hab. Zeph. Hag. Zech. Mal. Matt. Mark Luke John Acts Rom. 1Cor. 2Cor. Gal. Eph. Phil.
Col. 1Thess. 2Thess. 1Tim. 2Tim. Titus Philem. Heb. James 1Pet. 2Pet. 1John 2John 3John Jude Rev.""".split())

results = []
def ok(msg):   results.append(('PASS', msg))
def bad(msg):  results.append(('FAIL', msg))
def note(msg): results.append(('NOTE', msg))

def xml(path, name):
    with zipfile.ZipFile(path) as z:
        try:    return etree.fromstring(z.read(name))
        except KeyError: return None

def width(s):
    return sum(1 if ord(c) < 0x3000 and ord(c) < 128 else 2 for c in s) / 2

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('docx'); ap.add_argument('--original')
    a = ap.parse_args()

    doc = xml(a.docx, 'word/document.xml')
    if doc is None:
        print('FAIL  document.xml が読めない'); return 1
    body = doc.find(W+'body')
    paras = body.findall(W+'p')

    def style_of(p):
        pr = p.find(W+'pPr')
        if pr is None: return 'Normal'
        s = pr.find(W+'pStyle')
        return s.get(W+'val') if s is not None else 'Normal'

    # styles.xml: styleId -> 表示名
    st = xml(a.docx, 'word/styles.xml')
    id2name = {}
    for s in st.findall(W+'style'):
        n = s.find(W+'name')
        if n is not None: id2name[s.get(W+'styleId')] = n.get(W+'val')

    def text(p): return ''.join(t.text or '' for t in p.iter(W+'t'))

    named = [(id2name.get(style_of(p), style_of(p)), p) for p in paras]

    # 1. スタイルは4種＋Normal（空段落）だけか
    used = {n for n, p in named if text(p).strip()}
    stray = used - STYLES
    if stray: bad('未知のスタイルが本文に使われている: %s' % sorted(stray))
    else:     ok('スタイルは仕様の4種のみ（%s）' % '／'.join(sorted(used)))

    # 2. 1行目が説教題
    first = next(((n, p) for n, p in named if text(p).strip()), None)
    if not first or first[0] != '説教題':
        bad('1行目が説教題スタイルではない')
    else:
        title = text(first[1]).strip()
        ok('1行目＝説教題スタイル: %s' % title)
        if not title.startswith('草稿'):
            note('1行目に「草稿」が無い（本人の完成原稿ならこれで正しい／AI生成なら仕様§5違反）')

    # 3. 聖句段落の形（ラベル＋半角スペース2つ＋本文）とラベルの書式
    verses = [(n, p) for n, p in named if n in VERSE_STYLES]
    if not verses: bad('聖句段落が1つも無い')
    bad_form, bad_abbr, jp_book, num_only, bad_color, no_keep = [], [], [], [], [], []
    for n, p in verses:
        t = text(p)
        m = re.match(r'^([^\s]+(?: [^\s]+)?)  (\S)', t)
        if not m:
            bad_form.append(t[:30]); continue
        label = m.group(1)
        if re.fullmatch(r'\d+(?:[:\-]\d+)*', label): num_only.append(label)
        elif re.search(r'[ぁ-んァ-ン一-龥]', label):  jp_book.append(label)
        else:
            book = label.split(' ')[0]
            if book not in ABBR: bad_abbr.append(label)
        # ラベルrunの色
        runs = p.findall(W+'r')
        col = None
        for r in runs:
            if (''.join(x.text or '' for x in r.iter(W+'t'))).strip():
                c = r.find(W+'rPr/'+W+'color')
                col = c.get(W+'val').upper() if c is not None else None
                break
        if col != LABEL_BLUE: bad_color.append('%s(%s)' % (label, col))
        if p.find(W+'pPr/'+W+'keepLines') is None: no_keep.append(label)

    for lst, msg in ((bad_form, 'ラベルと本文が「半角スペース2つ」で区切られていない'),
                     (num_only, '節番号だけのラベルがある（仕様§4：中心テキストも書名つき）'),
                     (jp_book, '日本語書名のラベルが残っている（仕様§4：英略記）'),
                     (bad_abbr, '仕様の略記リストに無い書名'),
                     (bad_color, 'ラベルの色が #006699 でない'),
                     (no_keep, 'keepLines が付いていない聖句段落がある（仕様§3-2）')):
        if lst: bad('%s: %s' % (msg, lst[:5]))
    if not (bad_form or num_only or jp_book or bad_abbr):
        ok('節ラベル %d 件すべて英略記・書名つき・スペース2つ' % len(verses))
    if not bad_color: ok('ラベルの色は全件 #006699')
    if not no_keep:   ok('聖句段落は全件 keepLines あり')

    # 4. 引用聖句スタイルの既定色
    s_quote = next((s for s in st.findall(W+'style') if id2name.get(s.get(W+'styleId')) == '引用聖書箇所'), None)
    c = s_quote.find(W+'rPr/'+W+'color') if s_quote is not None else None
    if c is None or c.get(W+'val').upper() != QUOTE_BROWN:
        bad('引用聖書箇所スタイルの既定色が #833C0B でない')
    else:
        ok('引用聖書箇所スタイルの既定色＝#833C0B')
    for n, p in verses:
        if n == '引用聖書箇所':
            for r in p.findall(W+'r')[1:]:
                cc = r.find(W+'rPr/'+W+'color')
                if cc is not None and cc.get(W+'val').upper() not in (QUOTE_BROWN,):
                    bad('引用聖句の本文に色が直接指定されている（スタイル継承にする）'); break
            else: continue
            break

    # 5. 地の文の行幅
    longs = [text(p) for n, p in named if n == 'メッセージ本文' and width(text(p)) > MAX_WIDTH]
    if longs:
        note('全角%d超の行 %d本（「、」が無く割れなかった分。本人が語順を変えるしかない）: %s'
             % (MAX_WIDTH, len(longs), longs[0][:40] + '…'))
    else:
        ok('地の文は全行が全角%d以内' % MAX_WIDTH)

    # 6. 地の文に keepNext が付いていないこと（仕様§3-2の2026-08-16撤回）
    kn = [text(p)[:20] for n, p in named if n == 'メッセージ本文' and p.find(W+'pPr/'+W+'keepNext') is not None]
    if kn: bad('地の文に keepNext が付いている（仕様§3-2で撤回済み）: %s' % kn[:3])
    else:  ok('地の文に keepNext は無い')

    # 7. 用紙・余白をテンプレートと突き合わせる
    if a.original:
        o = xml(a.original, 'word/document.xml')
        def sect(d):
            s = d.find(W+'body/'+W+'sectPr')
            pg, mg = s.find(W+'pgSz'), s.find(W+'pgMar')
            return (dict(pg.attrib), dict(mg.attrib))
        if sect(doc) == sect(o): ok('用紙・余白がテンプレートと一致')
        else:                    bad('用紙・余白がテンプレートと違う')
        miss = {n for n in STYLES if n not in id2name.values()}
        if miss: bad('テンプレートのスタイルが欠けている: %s' % sorted(miss))

    print('段落 %d（本文 %d／聖句 %d）' % (len(paras),
          sum(1 for n, p in named if n == 'メッセージ本文'), len(verses)))
    for kind, msg in results: print('%-4s  %s' % (kind, msg))
    nf = sum(1 for k, _ in results if k == 'FAIL')
    print('--- FAIL %d / PASS %d ---' % (nf, sum(1 for k, _ in results if k == 'PASS')))
    return 1 if nf else 0

if __name__ == '__main__':
    sys.exit(main())
