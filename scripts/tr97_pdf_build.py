#!/usr/bin/env python3
"""tr97（英訳モード）の英訳本文テキスト → 印刷用PDF。

使い方（クラウド側コンテナで実行する。macOS の device_bash では Playwright が動かない）:
    python3 tr97_pdf_build.py 入力.txt 出力.pdf

入力.txt の作り方:
  - 1行目 = タイトル（例: 20260906 Mark 3:20-35 "The Beelzebul Controversy"）
  - 2行目以降 = 英訳本文。空行で段落を区切る。段落内の改行はそのまま保つ。
  - 単独行 "@@" は区切り線になる（日本語原稿の ＠＠ と対応）。

自動判定:
  - 段落の1行目が書名+章節（Mark 3:13 等）で始まる → 引用ブロック（斜体・インデント）
  - 段落の1行目が数字+空白で始まる → 本文の聖書箇所（太字・インデント）
  - それ以外 → 通常段落
"""
import html
import pathlib
import re
import sys

SCRIP = re.compile(
    r'^(Gen|Exod|Lev|Num|Deut|Josh|Judg|Ruth|1 Sam|2 Sam|1 Kgs|2 Kgs|1 Chr|2 Chr|Ezra|Neh|Esth|Job|Ps|Prov|Eccl|Song|Isaiah|Isa|Jer|Lam|Ezek|Dan|Hos|Joel|Amos|Obad|Jonah|Mic|Nah|Hab|Zeph|Hag|Zech|Mal|'
    r'Matthew|Matt|Mark|Luke|John|Acts|Rom|1 Cor|2 Cor|Gal|Eph|Phil|Col|1 Thess|2 Thess|1 Tim|2 Tim|Titus|Phlm|Heb|Jas|1 Pet|2 Pet|1 John|2 John|3 John|Jude|Rev)\s+\d'
)
VERSE = re.compile(r'^\d+\s')

CSS = """
@page { size: A4; margin: 22mm 20mm 20mm 20mm; }
body { font-family: "Times New Roman", Georgia, serif; font-size: 11.5pt; line-height: 1.62; color: #000; }
h1 { font-size: 15pt; text-align: center; margin: 0 0 20pt; line-height: 1.4; font-weight: bold; }
p { margin: 0 0 10pt; text-align: left; orphans: 2; widows: 2; }
p.ref { margin-left: 8mm; margin-right: 4mm; font-style: italic; }
p.text { margin-left: 4mm; font-weight: bold; }
hr.sec { border: none; border-top: 1px solid #999; width: 40%; margin: 18pt auto; }
"""


def build_html(src: str) -> tuple:
    src = src.replace('※', '* ')  # ※ は欧文フォントに無いので * に置換
    lines = src.split('\n')
    title = lines[0].strip()
    rest = '\n'.join(lines[1:]).strip('\n')

    out = []
    for block in re.split(r'\n\s*\n', rest):
        bl = [l for l in block.split('\n') if l.strip()]
        if not bl:
            continue
        head = bl[0].strip()
        if head in ('@@', '＠＠'):
            out.append('<hr class="sec">')
            continue
        if SCRIP.match(head):
            cls = 'ref'
        elif VERSE.match(head):
            cls = 'text'
        else:
            cls = 'p'
        body = '<br>'.join(html.escape(l) for l in bl)
        out.append('<p class="%s">%s</p>' % (cls, body))

    doc = (
        '<!doctype html>\n<html><head><meta charset="utf-8"><title>%s</title>\n<style>%s</style></head><body>\n'
        '<h1>%s</h1>\n%s\n</body></html>'
        % (html.escape(title), CSS, html.escape(title), '\n'.join(out))
    )
    return title, doc


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src_path = pathlib.Path(sys.argv[1])
    pdf_path = pathlib.Path(sys.argv[2])

    title, doc = build_html(src_path.read_text(encoding='utf-8'))
    html_path = pdf_path.with_suffix('.html')
    html_path.write_text(doc, encoding='utf-8')

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        page.goto('file://%s' % html_path.resolve())
        page.pdf(
            path=str(pdf_path),
            format='A4',
            print_background=True,
            margin={'top': '22mm', 'bottom': '20mm', 'left': '20mm', 'right': '20mm'},
            display_header_footer=True,
            header_template='<span></span>',
            footer_template=(
                '<div style="width:100%;font-size:9px;font-family:Georgia,serif;'
                'text-align:center;color:#555;"><span class="pageNumber"></span></div>'
            ),
        )
        browser.close()
    html_path.unlink(missing_ok=True)
    print('OK: %s' % pdf_path)


if __name__ == '__main__':
    main()
