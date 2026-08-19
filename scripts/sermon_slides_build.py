#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""説教スライド（礼拝投影用 .pptx）ビルダー

正本の様式: 🖥 説教スライド出力仕様（AI共通）.md
テンプレート: scripts/sermon_slides_template.pptx（本人が実際に使っているPPから）

使い方:
    python3 sermon_slides_build.py verses.json "20260809マルコ2-18-22「新しい皮袋」.pptx"

verses.json の形式（引用の出てくる順に並べる）:
    [
      {"label": "Mark 2:18", "text": "さて、ヨハネの弟子たちと…"},
      {"break": true},
      {"label": "Is. 58:3",  "text": "『なぜあなたは…"},
      {"label": "Is. 58:4",  "text": "見よ。…"}
    ]

  - {"break": true} は「ここでスライドを必ず切る」印。別々の引用箇所の境目に置く。
  - break で挟まれた連続節は同じ枚にまとめる。ただし約11行を超えたら節の切れ目で次の枚へ送る。
"""
import json
import math
import os
import re
import shutil
import sys
import tempfile
import unicodedata
import zipfile
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "sermon_slides_template.pptx")
SLIDE_RID0 = 1000  # スライドの rId の起点。テンプレに残る rId（マスター・tableStyles等）と衝突させないため

CHARS_PER_LINE = 25.0   # 36pt・全角換算で1行に入る文字数
MAX_LINES = 11          # 1枚の上限（サンプルPPの最大枚＝創世記17:23-26 の実測）

FONTS = ('<a:latin typeface="小塚明朝 Pro L"/>'
         '<a:ea typeface="Meiryo UI" panose="020B0604030504040204" pitchFamily="34" charset="-128"/>'
         '<a:cs typeface="ＭＳ Ｐゴシック" panose="020B0600070205080204" pitchFamily="34" charset="-128"/>')

SLIDE_RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
              'relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>')


def width(s):
    """全角=1、半角=0.5 で数えた表示幅"""
    return sum(1.0 if unicodedata.east_asian_width(ch) in ("W", "F", "A") else 0.5 for ch in s)


def lines_of(label, text):
    return max(1, math.ceil((width(label) + 2 + width(text)) / CHARS_PER_LINE))


def pack(items):
    """引用リストを枚に割る。break で必ず切り、MAX_LINES を超えたら節の切れ目で送る。"""
    slides, cur, cur_lines = [], [], 0
    for it in items:
        if it.get("break"):
            if cur:
                slides.append(cur)
            cur, cur_lines = [], 0
            continue
        label, text = it["label"], it["text"]
        n = lines_of(label, text)
        if cur and cur_lines + n > MAX_LINES:
            slides.append(cur)
            cur, cur_lines = [], 0
        cur.append((label, text, n))
        cur_lines += n
    if cur:
        slides.append(cur)
    return slides


def para(label, text):
    p = '<a:p><a:pPr marL="152400" marR="152400"/>'
    # 2026-08-16 本人指示: スライドの文字は全部白に統一する（節ラベルの青 #006699 をやめた）。
    # 色指定を外すと、テーマの tx1=lt1 を継承して白になる。紙（Word）側は青のままで変えない。
    p += ('<a:r><a:rPr lang="en-US" altLang="ja-JP" dirty="0">' + FONTS +
          '</a:rPr><a:t>' + escape(label) + '</a:t></a:r>')
    p += ('<a:r><a:rPr lang="en-US" altLang="ja-JP" dirty="0">' + FONTS +
          '</a:rPr><a:t xml:space="preserve">  </a:t></a:r>')
    p += ('<a:r><a:rPr lang="ja-JP" altLang="ja-JP">' + FONTS +
          '</a:rPr><a:t>' + escape(text) + '</a:t></a:r>')
    return p + '</a:p>'


def build(items, outfile, template=TEMPLATE):
    slides = pack(items)
    n = len(slides)

    work = tempfile.mkdtemp(prefix="sermonslides_")
    try:
        with zipfile.ZipFile(template) as zf:
            zf.extractall(work)

        tpl = open(os.path.join(work, "ppt/slides/slide1.xml"), encoding="utf-8").read()
        head, rest = tpl.split("<a:lstStyle/>", 1)
        head += "<a:lstStyle/>"
        tail = rest[rest.index("</p:txBody>"):]

        # 既存の slideN.xml を全部消してから作り直す
        sdir = os.path.join(work, "ppt/slides")
        for f in os.listdir(sdir):
            if f.endswith(".xml"):
                os.remove(os.path.join(sdir, f))
        rdir = os.path.join(sdir, "_rels")
        os.makedirs(rdir, exist_ok=True)
        for f in os.listdir(rdir):
            os.remove(os.path.join(rdir, f))

        for idx, sl in enumerate(slides, 1):
            body = "".join(para(l, t) for l, t, _ in sl)
            body += '<a:p><a:endParaRPr kumimoji="1" lang="ja-JP" altLang="en-US"/></a:p>'
            open(os.path.join(sdir, "slide%d.xml" % idx), "w", encoding="utf-8").write(head + body + tail)
            open(os.path.join(rdir, "slide%d.xml.rels" % idx), "w", encoding="utf-8").write(SLIDE_RELS)

        # presentation.xml
        pp = os.path.join(work, "ppt/presentation.xml")
        pres = open(pp, encoding="utf-8").read()
        # 2026-08-16 修正: スライドの rId は 1000 番台から振る。
        # 以前は rId2 から順に振っていたので、枚数がテンプレの20枚を超えると
        # テンプレ側に残る rId25（tableStyles）等とぶつかり、PowerPointが破損扱いにした。
        lst = "".join('<p:sldId id="%d" r:id="rId%d"/>' % (289 + i, SLIDE_RID0 + i) for i in range(1, n + 1))
        pres = re.sub(r"<p:sldIdLst>.*?</p:sldIdLst>", "<p:sldIdLst>" + lst + "</p:sldIdLst>", pres, flags=re.S)
        open(pp, "w", encoding="utf-8").write(pres)

        # presentation.xml.rels
        rp = os.path.join(work, "ppt/_rels/presentation.xml.rels")
        rels = open(rp, encoding="utf-8").read()
        keep = [r for r in re.findall(r"<Relationship [^>]*/>", rels) if 'relationships/slide"' not in r]
        srel = "".join('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/'
                       '2006/relationships/slide" Target="slides/slide%d.xml"/>' % (SLIDE_RID0 + i, i)
                       for i in range(1, n + 1))
        open(rp, "w", encoding="utf-8").write(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + srel + "".join(keep) + "</Relationships>")

        # [Content_Types].xml
        cp = os.path.join(work, "[Content_Types].xml")
        ct = open(cp, encoding="utf-8").read()
        ct = re.sub(r'<Override PartName="/ppt/slides/slide\d+\.xml"[^/]*/>', "", ct)
        ov = "".join('<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.'
                     'openxmlformats-officedocument.presentationml.slide+xml"/>' % i for i in range(1, n + 1))
        ct = ct.replace("</Types>", ov + "</Types>")
        open(cp, "w", encoding="utf-8").write(ct)

        if os.path.exists(outfile):
            os.remove(outfile)
        with zipfile.ZipFile(outfile, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(work):
                for f in files:
                    fp = os.path.join(root, f)
                    zf.write(fp, os.path.relpath(fp, work))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    for i, sl in enumerate(slides, 1):
        print("%2d枚目 %2d行  %s" % (i, sum(x[2] for x in sl), " / ".join(x[0] for x in sl)))
    print("計 %d枚 → %s" % (n, outfile))
    return n


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1], encoding="utf-8") as f:
        build(json.load(f), sys.argv[2])
