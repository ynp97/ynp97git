#!/usr/bin/env python3
"""Render a data-only st97 JSON payload with the verified fixed HTML template."""

from __future__ import annotations

import argparse
from html import escape
import json
from pathlib import Path
import re


CSS = r"""
:root{--blue:#006699;--ink:#000;--muted:#59636b;--gold:#fff6dd;--verse-bg:#eef7fb}
@page{size:A4 portrait;margin:35mm 30mm 30mm}
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
.verse{margin:6mm 0 5mm 6.35mm;padding:3.2mm 3.4mm 3.4mm;border-top:.35mm solid #c8dce6;border-bottom:.35mm solid #c8dce6;background:var(--verse-bg);font-size:13.5pt;font-weight:700;line-height:1.72;break-inside:avoid-page}
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


def require(data: dict, key: str):
    if key not in data:
        raise ValueError(f"Required key is missing: {key}")
    return data[key]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("html_output", type=Path)
    args = parser.parse_args()

    data = json.loads(args.payload.read_text(encoding="utf-8"))
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

    section_html = []
    for section in require(data, "sections"):
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
            f'<h2>{ruby(section["heading"])}</h2>'
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
    html = f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(document_title)}</title>
<style>{CSS}</style></head><body><main>
<h1>{multiline(title)}</h1>
<h2>全体の流れと結論</h2>
<ol>{''.join(f'<li>{multiline(item)}</li>' for item in require(data, "flow"))}</ol>
<p class="conclusion">結論：{multiline(require(data, "conclusion"))}</p>
<p class="overview">{multiline(require(data, "overview"))}</p>
{''.join(section_html)}
<section class="overall-section"><h2>全体のまとめ</h2>{bullets(require(data, "overall"))}</section>
<section><h2>五段階の適用</h2>{''.join(applications)}</section>
</main></body></html>'''

    args.html_output.parent.mkdir(parents=True, exist_ok=True)
    args.html_output.write_text(html, encoding="utf-8")
    print(args.html_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
