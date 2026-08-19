#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""説教原稿（説教台で読む印刷用 .docx）ビルダー

正本の様式: 📄 説教原稿Word出力仕様（AI共通）.md
テンプレート: scripts/sermon_docx_template.docx（本人の原稿から本文だけ抜いたもの。
              用紙・余白・フッター・スタイル定義「説教題／メッセージ本文／
              メッセージ聖書個所／引用聖書箇所」がそのまま入っている）

使い方:
    python3 sermon_docx_build.py manuscript.json "20260809マルコ2-18-22 「新しい皮袋」.docx"

manuscript.json の形式:
    {
      "title": "20260809マルコ2:18-22 「新しい皮袋」",
      "blocks": [
        {"t": "body",      "text": "今日もマルコの福音書を読んでいきましょう。"},
        {"t": "blank"},
        {"t": "scripture", "label": "マルコ2:18",  "text": "さて、ヨハネの弟子たちと…"},
        {"t": "quote",     "label": "イザヤ58:3", "text": "『なぜあなたは…"}
      ]
    }

  body      = 地の文（メッセージ本文・10.5pt・両端揃え）
  blank     = 空行（本文スタイルの空段落）
  scripture = その日の中心テキスト（メッセージ聖書個所・字下げ・太字・ラベル青#006699）
  quote     = 他箇所からの引用聖句（引用聖書箇所・上に加えて本文が#833C0B）

body は自動で改行し直す（本人の癖に合わせる）:
  ・1行はなるべく「。」で終わる。1文＝1行。
  ・1文が長すぎるときだけ「、」で割る。
  ・**行をつなげることはしない。** ラフ原稿の改行位置は壊さず、長い行を割るだけ。
  {"t": "body", "text": "…", "wrap": false} で、その行だけ自動改行を切れる。

ページの割れ方:
  ・聖句は必ず1ページに収める（keepLines）。連続する聖句は離さない（keepNext）。
  ・空行で挟まれた地の文のかたまりは、KEEP_BLOCK_LINES 行以下なら割らない。
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
TEMPLATE = os.path.join(HERE, "sermon_docx_template.docx")

BODY_RPR = '<w:rFonts w:ascii="Meiryo UI" w:hAnsi="Meiryo UI"/><w:sz w:val="21"/>'
LABEL_RPR = '<w:bCs/><w:color w:val="006699"/><w:sz w:val="21"/>'
TEXT_RPR = '<w:sz w:val="21"/>'

MAX_W = 45              # 1行の上限（全角換算）。実原稿の90パーセンタイル47から
KEEP_BLOCK_LINES = 0    # 地の文にはkeepNextを付けない（0で無効）。
                        # 2026-08-16 本人指示: Wordの左端に出る黒い四角（「次の段落と分離しない」の印）が
                        # 多すぎて、原稿を手で調整するときに邪魔になるため。聖句側の keepLines は残す。
KEEP_SCRIPTURE_RUN = 6  # 続けて並ぶ聖句をこの段落数まで離さない


def w(s):
    """全角=1、半角=0.5 で数えた表示幅"""
    return sum(1.0 if unicodedata.east_asian_width(c) in ("W", "F", "A") else 0.5 for c in s)


def split_sentences(text):
    """「。」で切る。直後の閉じ括弧は連れていく。"""
    parts = re.split(r'(?<=。)(?![」』）\)】〕”"])', text)
    return [p for p in (x.strip() for x in parts) if p]


def split_by_comma(sentence, limit=MAX_W):
    """長い文を「、」で割る。何本に割るかを先に決め、なるべく均等な長さにする。

    貪欲に limit まで詰めると、最後に数文字だけの行が残って不格好になる。
    先に本数 k を決めて limit/k を目標幅にすると、行の長さがそろう。
    """
    total = w(sentence)
    if total <= limit:
        return [sentence]
    chunks = re.split(r'(?<=、)', sentence)
    if len(chunks) == 1:
        return [sentence]          # 「、」が無いので割れない
    k = math.ceil(total / limit)
    target = total / k
    out, cur = [], ""
    for c in chunks:
        # 足すと目標幅を越え、かつ残りでまだ行数を作れるなら、ここで切る
        if cur and w(cur) + w(c) > target and len(out) < k - 1:
            out.append(cur)
            cur = c
        else:
            cur += c
    if cur:
        out.append(cur)
    return out


def rewrap(text, limit=MAX_W):
    """本人の癖に合わせて1行を割る。つなげることはしない。"""
    lines = []
    for s in split_sentences(text):
        lines.extend(split_by_comma(s, limit))
    return lines or [text]


def p_title(text):
    return ('<w:p><w:pPr><w:pStyle w:val="ae"/></w:pPr>'
            '<w:r><w:t xml:space="preserve">' + escape(text) + '</w:t></w:r></w:p>')


def p_body(text, keep_next=False):
    keep = '<w:keepNext/>' if keep_next else ''
    pr = '<w:pPr><w:pStyle w:val="a8"/>' + keep + '<w:rPr>' + BODY_RPR + '</w:rPr></w:pPr>'
    if not text:
        return '<w:p>' + pr + '</w:p>'
    return ('<w:p>' + pr + '<w:r><w:rPr>' + BODY_RPR + '</w:rPr>'
            '<w:t xml:space="preserve">' + escape(text) + '</w:t></w:r></w:p>')


def p_scripture(label, text, quote=False, keep_next=False):
    # w:pPr の子要素は順序が決まっている: pStyle → keepNext → keepLines → … → ind → … → rPr
    style = "af" if quote else "a9"
    ind = "" if quote else '<w:ind w:right="240"/>'
    keep = ('<w:keepNext/>' if keep_next else '') + '<w:keepLines/>'
    pr = '<w:pPr><w:pStyle w:val="%s"/>%s%s<w:rPr>%s</w:rPr></w:pPr>' % (style, keep, ind, TEXT_RPR)
    runs = ''
    if label:
        runs += ('<w:r><w:rPr>' + LABEL_RPR + '</w:rPr>'
                 '<w:t xml:space="preserve">' + escape(label) + '</w:t></w:r>')
        runs += ('<w:r><w:rPr>' + TEXT_RPR + '</w:rPr>'
                 '<w:t xml:space="preserve">  </w:t></w:r>')
    runs += ('<w:r><w:rPr>' + TEXT_RPR + '</w:rPr>'
             '<w:t xml:space="preserve">' + escape(text) + '</w:t></w:r></w:p>')
    return '<w:p>' + pr + runs


def expand(blocks):
    """入力ブロックを、実際の段落の並びへ広げる（本文の自動改行を含む）"""
    items = []   # (kind, payload)
    for b in blocks:
        t = b.get("t", "body")
        if t == "blank":
            items.append(("blank", None))
        elif t == "body":
            if b.get("wrap", True):
                for line in rewrap(b["text"]):
                    items.append(("body", line))
            else:
                items.append(("body", b["text"]))
        elif t in ("scripture", "quote"):
            items.append((t, (b.get("label", ""), b["text"])))
        else:
            raise ValueError("不明なブロック種別: %r" % t)
    return items


def apply_keeps(items):
    """どの段落を次と離さないか（keepNext）を決める。

    ・続けて並ぶ聖句は一続きの朗読なので離さない（KEEP_SCRIPTURE_RUN 段落まで）。
    ・地の文は、空行で挟まれた短いかたまり（KEEP_BLOCK_LINES 行以下）だけ離さない。
    長いかたまりまで丸ごと固めると、ページの下半分が空く。
    """
    keeps = [False] * len(items)
    i = 0
    while i < len(items):
        kind = items[i][0]
        if kind == "blank":
            i += 1
            continue
        # 同じ種別（聖句同士／地の文同士）が続くところで区切る
        j = i
        same = (lambda k: k in ("scripture", "quote")) if kind in ("scripture", "quote") \
            else (lambda k: k == "body")
        while j < len(items) and same(items[j][0]):
            j += 1
        run_len = j - i
        if kind in ("scripture", "quote"):
            if run_len <= KEEP_SCRIPTURE_RUN:
                for k in range(i, j - 1):
                    keeps[k] = True
        else:
            if run_len <= KEEP_BLOCK_LINES:
                for k in range(i, j - 1):
                    keeps[k] = True
        i = j
    return keeps


def build(doc, outfile, template=TEMPLATE):
    items = expand(doc["blocks"])
    keeps = apply_keeps(items)

    parts = [p_title(doc["title"])]
    counts = {"body": 0, "blank": 0, "scripture": 0, "quote": 0}
    for (kind, payload), kn in zip(items, keeps):
        counts[kind] += 1
        if kind == "blank":
            parts.append(p_body(""))
        elif kind == "body":
            parts.append(p_body(payload, keep_next=kn))
        else:
            parts.append(p_scripture(payload[0], payload[1],
                                     quote=(kind == "quote"), keep_next=kn))

    work = tempfile.mkdtemp(prefix="sermondocx_")
    try:
        with zipfile.ZipFile(template) as zf:
            zf.extractall(work)
        dp = os.path.join(work, "word/document.xml")
        s = open(dp, encoding="utf-8").read()
        sect = re.search(r"<w:sectPr.*?</w:sectPr>", s, re.S).group(0)
        head = s[:s.index("<w:body>") + len("<w:body>")]
        open(dp, "w", encoding="utf-8").write(head + "".join(parts) + sect + "</w:body></w:document>")

        if os.path.exists(outfile):
            os.remove(outfile)
        with zipfile.ZipFile(outfile, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(work):
                for f in files:
                    fp = os.path.join(root, f)
                    zf.write(fp, os.path.relpath(fp, work))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    body_lines = [p for k, p in items if k == "body"]
    over = [x for x in body_lines if w(x) > MAX_W]
    print("段落 %d（本文%d／空行%d／中心テキスト%d／引用聖句%d）"
          % (len(parts), counts["body"], counts["blank"], counts["scripture"], counts["quote"]))
    if body_lines:
        print("本文の行幅 全角換算: 平均%.1f  最大%.0f  上限%d超の行 %d本"
              % (sum(w(x) for x in body_lines) / len(body_lines),
                 max(w(x) for x in body_lines), MAX_W, len(over)))
        for x in over[:5]:
            print("   長い行（「、」が無く割れなかった）: %s" % x[:60])
    print("→ %s" % outfile)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1], encoding="utf-8") as f:
        build(json.load(f), sys.argv[2])
