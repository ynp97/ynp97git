#!/usr/bin/env python3
"""
Markdown → A4縦の印刷用HTML＋PDF を作る（Vault共通）

Markdownを正本にして、同じ内容の印刷用HTMLとPDFを生成する。
手で両方を直すとズレるので、必ずこれを通す。

使い方:
    python3 .agents/scripts/md2print.py "ファイル名.md"
    → 同じ場所に .html と .pdf を出す

対応:
    - 表、見出し、箇条書き、チェックボックス、引用
    - Obsidianのコールアウト（> [!important] など）を囲み枠に変換
    - 日本語フォント（Noto Sans CJK JP / Meiryo UI）

必要なもの:
    pip install markdown weasyprint --break-system-packages

最終確認: 2026-07-27（🗓 三本立て進行表 で使用・実PDFを目視確認）
"""
import re
import sys
from pathlib import Path

import markdown

CALLOUT_LABEL = {
    "important": "要点", "warning": "注意", "danger": "危険",
    "info": "メモ", "note": "メモ", "tip": "ヒント",
    "done": "決着", "success": "決着", "question": "問い",
    "example": "例", "quote": "引用",
}
CALLOUT_COLOR = {
    "important": "#b3261e", "warning": "#b3261e", "danger": "#b3261e",
    "info": "#2b6cb0", "note": "#2b6cb0", "tip": "#2b6cb0",
    "done": "#2f7a4d", "success": "#2f7a4d", "question": "#7a5b2f",
    "example": "#555", "quote": "#555",
}

CSS = """
@page { size: A4 portrait; margin: 16mm 14mm 15mm 14mm;
        @bottom-center { content: counter(page) " / " counter(pages);
                         font-size: 8pt; color: #888; } }
* { box-sizing: border-box; }
body { font-family: "Meiryo UI","Noto Sans CJK JP","Hiragino Kaku Gothic ProN",sans-serif;
       font-size: 9.6pt; line-height: 1.62; color: #1b1b1b; margin: 0; }
h1 { font-size: 15pt; margin: 0 0 4mm; padding-bottom: 3mm;
     border-bottom: 1.6pt solid #1b1b1b; letter-spacing: .02em; }
h2 { font-size: 11pt; margin: 6mm 0 2.4mm; padding: 1.4mm 0 1.4mm 3mm;
     border-left: 4pt solid #1b1b1b; background: #f2f2f2; page-break-after: avoid; }
h3 { font-size: 9.9pt; margin: 4mm 0 1.6mm; color: #333; page-break-after: avoid; }
p { margin: 0 0 2mm; }
ul, ol { margin: 0 0 2.5mm; padding-left: 5mm; }
li { margin-bottom: 1.1mm; }
li > ul, li > ol { margin-top: 1.1mm; }
table { width: 100%; border-collapse: collapse; margin: 0 0 3mm;
        font-size: 9pt; page-break-inside: avoid; }
th, td { border: .6pt solid #b8b8b8; padding: 1.5mm 2mm; vertical-align: top; text-align: left; }
th { background: #ececec; font-weight: bold; }
td:first-child { white-space: nowrap; }
b, strong { font-weight: bold; }
code { font-family: "DejaVu Sans Mono",monospace; font-size: 8.6pt;
       background: #f0f0f0; padding: .2mm 1mm; border-radius: 1mm; }
blockquote { margin: 0 0 2.5mm; padding: 1mm 0 1mm 3mm;
             border-left: 2pt solid #ccc; color: #444; font-size: 9.2pt; }
.callout { border: .8pt solid #bbb; background: #fafafa; padding: 2.4mm 3mm;
           margin: 0 0 3mm; font-size: 9pt; page-break-inside: avoid;
           border-left-width: 3pt; }
.callout .ct { font-weight: bold; display: block; margin-bottom: 1mm; }
.callout p:last-child, .callout ul:last-child { margin-bottom: 0; }
.chk { list-style: none; padding-left: 0; page-break-inside: avoid; }
.chk li { padding-left: 6mm; text-indent: -6mm; }
hr { border: 0; border-top: .6pt solid #bbb; margin: 5mm 0 3mm; }
em { font-style: normal; color: #666; font-size: 9pt; }
"""


EMOJI = re.compile("[\U0001F000-\U0001FAFF\U0001F1E6-\U0001F1FF\U0000FE0F]+")


def strip_emoji(text: str) -> str:
    """印刷用フォント（Noto Sans CJK）に絵文字がなく豆腐になるので落とす。
    色分けは項目名で判別できるため、印刷版では情報を失わない。
    ※矢印（→）や★はCJKフォントに入っていて豆腐にならないので、範囲から外して残す。"""
    return re.sub(r"[ 　]{2,}", " ", EMOJI.sub("", text)).strip()


def strip_frontmatter(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[text.find("\n", end + 1) + 1:]
    return text


def convert_callouts(text: str) -> str:
    """Obsidianのコールアウトを、markdownが扱えるHTMLブロックへ先に変換する。"""
    lines = text.split("\n")
    out, i = [], 0
    pat = re.compile(r"^>\s*\[!(\w+)\]\s*(.*)$")
    while i < len(lines):
        m = pat.match(lines[i])
        if not m:
            out.append(lines[i]); i += 1; continue
        kind = m.group(1).lower()
        title = m.group(2).strip() or CALLOUT_LABEL.get(kind, "メモ")
        body, i = [], i + 1
        while i < len(lines) and lines[i].startswith(">"):
            body.append(re.sub(r"^>\s?", "", lines[i])); i += 1
        color = CALLOUT_COLOR.get(kind, "#888")
        title = re.sub(r"</?p>", "", markdown.markdown(title)).strip()
        inner = markdown.markdown("\n".join(body), extensions=["extra", "sane_lists"])
        out.append(
            f'<div class="callout" style="border-left-color:{color}">'
            f'<span class="ct" style="color:{color}">{title}</span>{inner}</div>'
        )
        out.append("")
    return "\n".join(out)


def build(md_path: Path) -> tuple[Path, Path]:
    raw = strip_frontmatter(md_path.read_text(encoding="utf-8"))
    raw = "\n".join(strip_emoji(ln) for ln in raw.split("\n"))
    raw = convert_callouts(raw)
    html_body = markdown.markdown(
        raw, extensions=["extra", "tables", "sane_lists", "md_in_html"]
    )
    # - [ ] / - [x] をチェックボックス表示にする
    html_body = html_body.replace("<li>[ ] ", "<li>☐　").replace("<li>[x] ", "<li>☑　")
    html_body = re.sub(
        r"<ul>\s*(<li>[☐☑])", r'<ul class="chk">\1', html_body
    )
    title = strip_emoji(md_path.stem)
    doc = (f'<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="utf-8">\n'
           f'<title>{title}</title>\n<style>{CSS}</style>\n</head>\n<body>\n'
           f'{html_body}\n</body>\n</html>\n')
    html_path = md_path.with_suffix(".html")
    html_path.write_text(doc, encoding="utf-8")

    from weasyprint import HTML
    pdf_path = md_path.with_suffix(".pdf")
    HTML(string=doc, base_url=str(md_path.parent)).write_pdf(str(pdf_path))
    return html_path, pdf_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("使い方: python3 md2print.py <ファイル名.md>")
    h, p = build(Path(sys.argv[1]))
    print(f"HTML: {h}\nPDF : {p}")
