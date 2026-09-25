#!/usr/bin/env python3
"""Render a data-only st97 JSON payload with the verified fixed HTML template."""

from __future__ import annotations

import argparse
from html import escape
import json
from pathlib import Path
import re


CSS = r"""
:root{--blue:#006699;--ink:#000;--muted:#59636b;--gold:#fff6dd;--verse-bg:#dceaf5}
@page{size:A4 portrait;margin:35mm 30mm 30mm;@bottom-center{content:counter(page);font-family:"Meiryo UI",Meiryo,sans-serif;font-size:9pt;color:#000}}
*{box-sizing:border-box}
html{background:#e8ebed}
body{width:210mm;min-height:297mm;margin:12mm auto;padding:35mm 30mm 30mm;background:#fff;color:var(--ink);font-family:"Meiryo UI",Meiryo,sans-serif;font-size:10.5pt;line-height:1.43;box-shadow:0 2mm 8mm rgba(0,0,0,.16)}
h1{margin:0 0 7mm;font-size:16pt;line-height:1.25;font-weight:700}
h2{margin:7mm 0 2.5mm;font-size:13pt;line-height:1.35;font-weight:700;break-after:avoid-page}
h3{margin:4mm 0 1.2mm;color:var(--blue);font-size:10.5pt;line-height:1.43;font-weight:700;break-after:avoid-page}
p{margin:0 0 2.3mm}
ol,ul{margin:0 0 3mm;padding-left:6.5mm}
li{margin:0 0 1.2mm;padding-left:.7mm;break-inside:avoid-page}
ruby{ruby-position:over}
rt{color:#4e6570;font-size:.5em;font-weight:500;letter-spacing:0}
.summary-box,.conclusion{margin:0 0 3mm;padding:1.8mm 2.3mm;border-left:1.6mm solid var(--blue);background:var(--gold)}
.conclusion{font-weight:700}
.overview{color:var(--muted)}
.verse-unit{break-inside:auto}
.verse{margin:6mm 0 5mm 6.35mm;padding:3.2mm 3.4mm 3.4mm;border-top:.35mm solid #a8c9dc;border-bottom:.35mm solid #a8c9dc;background:var(--verse-bg);font-size:15pt;font-weight:700;line-height:1.72;break-inside:avoid-page}
.verse-label{display:block;margin:0 0 1.8mm;color:var(--blue);font-size:11.5pt;line-height:1.4}
.verse-text{color:#000}
.notes,.points{margin-bottom:3mm}
.points-heading{margin-top:6mm;font-size:13pt;line-height:1.4}
.points{font-size:11.5pt;line-height:1.55;break-inside:avoid-page}
.points li{margin-bottom:2mm}
.application{break-inside:avoid-page}
.application h3{margin-bottom:1mm}
.overall-section{break-inside:avoid-page}
.check-inline{margin-left:1em;color:var(--muted);font-size:9pt;white-space:nowrap}
@media print{html{background:#fff}body{width:auto;min-height:0;margin:0;padding:0;box-shadow:none}}
@media screen and (max-width:850px){body{width:100%;margin:0;padding:22mm 10mm 20mm;box-shadow:none}}
"""


# iPad閲覧用（2026-09-25 本人指示）。--ipad のときだけ固定CSSの後ろに追記する。
# 4:3の小さい用紙・横余白ほぼなし・大きい字・ページ頭に「日付｜箇所｜ページ/総ページ」。
IPAD_CSS = r"""
@page{size:150mm 200mm;margin:15mm 4mm 5mm;@bottom-center{content:none}}
body{font-size:13.5pt;line-height:1.55}
h1{margin:0 0 4mm;font-size:17pt}
h2{margin:0 0 2.5mm;font-size:16pt}
h3{margin:3mm 0 1mm;font-size:12.5pt}
ol,ul{padding-left:6mm}
.verse{margin:3.5mm 0 3mm 0;padding:2.5mm 3mm;font-size:18pt;line-height:1.6}
.verse-label{font-size:12.5pt}
.points-heading{font-size:14.5pt}
.points{font-size:13.5pt}
.check-inline{font-size:10pt}
.overview{color:#000}
rt{color:#333}
.message-section,.overall-section,.apps-section{break-before:page}
.mk{font-size:1pt;color:#fff;line-height:0}
.toc{margin:0 0 4mm;padding:2mm 3mm;border:.4mm solid #006699;border-radius:1.5mm;font-size:12.5pt}
.toc b{color:#006699}
@media print{body{padding:0}}
@media screen{body{width:100%;margin:0;padding:6mm 4mm;box-shadow:none}}
"""


OPEN, CLOSE = "「『（(", "」』）)"


def ipad_breaks(text: str) -> str:
    """iPad版だけ：地の文の長いところに改行を入れる（本人指示・2026-09-25）。聖書本文には使わない。
    ①括弧の外の「。」の後 ②「——」の前の見出し部分が短いとき、その後 ③それでも70字を超える文は、括弧の外の「、」で中ほど付近。"""
    out, depth = [], 0
    for i, ch in enumerate(text):
        out.append(ch)
        if ch in OPEN: depth += 1
        elif ch in CLOSE: depth = max(0, depth - 1)
        elif depth == 0 and ch == "。" and i + 1 < len(text) and text[i + 1] != "\n":
            out.append("\n")
    lines = []
    for line in "".join(out).split("\n"):
        if "——" in line and line.index("——") <= 40 and len(line) > 45:
            k = line.index("——") + 2
            lines += [line[:k], line[k:]]
        else:
            lines.append(line)
    final = []
    for line in lines:
        while len(line) > 70:
            depth, cands = 0, []
            for i, ch in enumerate(line):
                if ch in OPEN: depth += 1
                elif ch in CLOSE: depth = max(0, depth - 1)
                elif ch == "、" and depth == 0 and 25 <= i <= len(line) - 15: cands.append(i)
            if not cands: break
            k = min(cands, key=lambda i: abs(i - len(line) / 2)) + 1
            final.append(line[:k]); line = line[k:]
        final.append(line)
    return "\n".join(x for x in final if x)


def apply_ipad_breaks(data: dict) -> None:
    for key in ("conclusion", "overview"):
        data[key] = ipad_breaks(data[key])
    data["flow"] = [ipad_breaks(x) for x in data["flow"]]
    data["overall"] = [ipad_breaks(x) for x in data["overall"]]
    for sec in data["sections"]:
        sec["summary"] = ipad_breaks(sec["summary"])
        sec["points"] = [ipad_breaks(x) for x in sec["points"]]
        for v in sec["verses"]:
            v["notes"] = [ipad_breaks(x) for x in v["notes"]]
    for a in data["applications"]:
        a["text"] = ipad_breaks(a["text"])


def require(data: dict, key: str):
    if key not in data:
        raise ValueError(f"Required key is missing: {key}")
    return data[key]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("html_output", type=Path)
    parser.add_argument("--ipad", action="store_true", help="iPad閲覧用の版（4:3用紙・大きい字・段落ごとに改ページ・位置表示は st97_ipad_pdf.py が重ねる）")
    parser.add_argument("--toc", default="", help="iPad版の目次行（st97_ipad_pdf.py が2回目の組版で渡す）")
    args = parser.parse_args()

    data = json.loads(args.payload.read_text(encoding="utf-8"))
    if args.ipad:
        apply_ipad_breaks(data)
    ruby_map = data.get("ruby", {})
    words = sorted(ruby_map, key=len, reverse=True)
    ruby_pattern = re.compile("|".join(re.escape(word) for word in words)) if words else None

    def ruby(value) -> str:
        result = escape(str(value), quote=False)
        if not ruby_pattern:
            return result
        return ruby_pattern.sub(
            lambda match: f"<ruby>{match.group(0)}<rt>{escape(str(ruby_map[match.group(0)]))}</rt></ruby>",
            result,
        )

    def multiline(value) -> str:
        return "<br>".join(ruby(value).splitlines())

    def bullets(items, class_name="") -> str:
        attr = f' class="{class_name}"' if class_name else ""
        return f"<ul{attr}>" + "".join(f"<li>{multiline(item)}</li>" for item in items) + "</ul>"

    def mk(tag: str) -> str:
        return f'<span class="mk">§{tag}§</span>' if args.ipad else ""

    section_html = []
    for sec_index, section in enumerate(require(data, "sections"), start=1):
        verse_html = []
        for verse in section["verses"]:
            verse_html.append(
                '<article class="verse-unit">'
                f'<p class="verse"><span class="verse-label">{ruby(verse["label"])}</span>'
                f'<span class="verse-text">{multiline(verse["text"])}</span></p>'
                '<h3>背景・語句</h3>'
                f'{bullets(verse["notes"], "notes")}'
                '</article>'
            )
        section_html.append(
            '<section class="message-section">'
            f'{mk(f"S{sec_index}")}<h2>{ruby(section["heading"])}</h2>'
            '<h3>段落の簡単なまとめ</h3>'
            f'<p class="summary-box">{multiline(section["summary"])}</p>'
            f'{"".join(verse_html)}'
            '<h3 class="points-heading">段落のポイント</h3>'
            f'{bullets(section["points"], "points")}'
            '</section>'
        )

    applications = []
    app_data = require(data, "applications")
    for index, application in enumerate(app_data):
        check = (
            '<span class="check-inline">ハルシネーションチェック：再確認済み</span>'
            if index == len(app_data) - 1 else ""
        )
        applications.append(
            '<article class="application">'
            f'<h3>{ruby(application["label"])}</h3>'
            f'<p>{multiline(application["text"])}{check}</p>'
            '</article>'
        )

    title = require(data, "title")
    document_title = require(data, "document_title")
    # 系図など、一つの本文ボックスが1ページに収まらない日だけ true にする。
    # avoid-page のままだとボックスが丸ごと次ページへ送られ、前ページが大きく空く。
    long_blocks_css = (
        "\n.verse{break-inside:auto}\n.verse-label{break-after:avoid-page}\n" if data.get("long_verse_blocks") else ""
    )
    toc_html = f'<p class="toc">{escape(args.toc)}</p>' if args.toc else ""
    if args.ipad:
        long_blocks_css += IPAD_CSS
    html = f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(document_title)}</title>
<style>{CSS}{long_blocks_css}</style></head><body><main>
<h1>{multiline(title)}</h1>
<h2>全体の流れと結論</h2>
<ol>{''.join(f'<li>{multiline(item)}</li>' for item in require(data, "flow"))}</ol>
{toc_html}<p class="conclusion">結論：{multiline(require(data, "conclusion"))}</p>
<p class="overview">{multiline(require(data, "overview"))}</p>
{''.join(section_html)}
<section class="overall-section">{mk("SM")}<h2>全体のまとめ</h2>{bullets(require(data, "overall"))}</section>
<section class="apps-section">{mk("SA")}<h2>五段階の適用</h2>{''.join(applications)}</section>
</main></body></html>'''

    args.html_output.parent.mkdir(parents=True, exist_ok=True)
    args.html_output.write_text(html, encoding="utf-8")
    print(args.html_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
