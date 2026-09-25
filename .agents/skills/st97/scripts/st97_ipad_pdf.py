#!/usr/bin/env python3
"""st97 iPad版PDF（2026-09-25 本人指示）。クラウド側で動かす（Playwright・pypdf・reportlab・IPAGothicが要る）。
1) render_st97.py --ipad でHTML → PDF（段落ごとに改ページ）
2) 各段落の開始ページを見つけ、目次行（①p.3 …）を入れて組み直す
3) 全ページの頭に「日付・箇所｜いまの段落｜ページ/総ページ」と、段落ごとの進行バーを重ねる
使い方: python3 st97_ipad_pdf.py 〈payload.json〉 〈出力.pdf〉
"""
import io, json, re, subprocess, sys, tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import mm

HERE = Path(__file__).resolve().parent
FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"
CIRC = "①②③④⑤⑥⑦⑧⑨⑩"
BLUE = (0/255, 102/255, 153/255)
# 区間ごとの色（導入・①〜・まとめ・適用）。現在の区間の色が、左端の帯・見出し・進行バーに出る。
def _rgb(h): return tuple(int(h[i:i+2], 16) / 255 for i in (1, 3, 5))
INTRO_C, SUM_C, APP_C = "#6B7B88", "#5B4E8C", "#B23A48"
SEC_C = ["#1F6FB2", "#2E8B57", "#D07A12", "#0E9AA7", "#8E44AD", "#C0392B", "#7F8C1A"]
def pale(c, k=.72): return tuple(v + (1 - v) * k for v in c)

def render(payload, html, toc=""):
    cmd = [sys.executable, str(HERE / "render_st97.py"), str(payload), str(html), "--ipad"]
    if toc: cmd += ["--toc", toc]
    subprocess.run(cmd, check=True, capture_output=True)

def to_pdf(html, pdf):
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path="/opt/pw-browsers/chromium", args=["--no-sandbox"])
        pg = b.new_page(); pg.goto(Path(html).resolve().as_uri()); pg.wait_for_load_state("networkidle")
        pg.pdf(path=str(pdf), prefer_css_page_size=True, print_background=True); b.close()

def starts(pdf, keys):
    texts = [re.sub(r"\s", "", pg.extract_text() or "") for pg in PdfReader(str(pdf)).pages]
    out = {}
    for k in keys:
        hit = [i for i, t in enumerate(texts) if f"§{k}§" in t]
        if not hit: raise SystemExit(f"段落の目印が見つからない: {k}")
        out[k] = hit[0] + 1
    return out, len(texts)

def main():
    payload, out = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(payload.read_text(encoding="utf-8"))
    secs = data["sections"]
    keys = [f"S{i}" for i in range(1, len(secs) + 1)] + ["SM", "SA"]
    short = [CIRC[i] for i in range(len(secs))] + ["まとめ", "適用"]
    titles = ["導入"] + [f"{CIRC[i]} " + re.sub(r"^\d+．", "", s["heading"]) for i, s in enumerate(secs)] + ["全体のまとめ", "五段階の適用"]
    tmp = Path(tempfile.mkdtemp())
    html, pdf = tmp / "a.html", tmp / "a.pdf"
    render(payload, html); to_pdf(html, pdf)
    st, _ = starts(pdf, keys)
    toc = "目次　" + "　".join(f"{s} p.{st[k]}" for s, k in zip(short, keys))
    render(payload, html, toc); to_pdf(html, pdf)
    st2, n = starts(pdf, keys)
    if st2 != st:  # 目次を入れてずれたら、ずれた値で組み直す
        toc = "目次　" + "　".join(f"{s} p.{st2[k]}" for s, k in zip(short, keys))
        render(payload, html, toc); to_pdf(html, pdf); st2, n = starts(pdf, keys)
    bounds = [1] + [st2[k] for k in keys] + [n + 1]  # 導入, 各段落, まとめ, 適用
    labels = ["導入"] + short
    colors = [_rgb(INTRO_C)] + [_rgb(SEC_C[i % len(SEC_C)]) for i in range(len(secs))] + [_rgb(SUM_C), _rgb(APP_C)]
    pdfmetrics.registerFont(TTFont("IPAG", FONT))
    head = re.sub(r"^\d+年", "", data["document_title"]).replace(" 早天｜", " ")
    reader = PdfReader(str(pdf)); writer = PdfWriter()
    for i, page in enumerate(reader.pages, start=1):
        W, H = float(page.mediabox.width), float(page.mediabox.height)
        seg = max(j for j in range(len(bounds) - 1) if bounds[j] <= i)
        buf = io.BytesIO(); c = canvas.Canvas(buf, pagesize=(W, H))
        x0, x1 = 4 * mm, W - 4 * mm
        c.setFont("IPAG", 7); c.setFillColorRGB(.35, .39, .42); c.drawString(x0, H - 5 * mm, head)
        c.setFont("IPAG", 9); c.setFillColorRGB(0, 0, 0); c.drawRightString(x1, H - 5 * mm, f"{i} / {n}")
        col = colors[seg]
        c.setFillColorRGB(*col); c.rect(0, 0, 3.2 * mm, H, stroke=0, fill=1); c.rect(W - 3.2 * mm, 0, 3.2 * mm, H, stroke=0, fill=1)  # 左右端の帯
        tx = x0 + c.stringWidth(head, "IPAG", 7) + 4 * mm
        room = (x1 - c.stringWidth(f"{n} / {n}", "IPAG", 9) - 4 * mm) - tx
        t = titles[seg]; c.setFillColorRGB(*col)
        while c.stringWidth(t, "IPAG", 8.5) > room: t = t[:-2] + "…"
        c.setFont("IPAG", 8.5); c.drawString(tx, H - 5 * mm, t)
        # 進行バー：段落ごとの区切り（幅はページ数に比例）
        y, h = H - 11.5 * mm, 4.2 * mm; span = x1 - x0
        for j in range(len(bounds) - 1):
            a = x0 + span * (bounds[j] - 1) / n; b = x0 + span * (bounds[j + 1] - 1) / n
            c.setFillColorRGB(*(colors[j] if j == seg else pale(colors[j], .55 if j < seg else .78)))
            c.rect(a + .3, y, b - a - .6, h, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1) if j == seg else c.setFillColorRGB(.2, .2, .2)
            c.setFont("IPAG", 6.5); c.drawCentredString((a + b) / 2, y + 1.2 * mm, labels[j])
        px = x0 + span * (i - .5) / n  # いまのページの位置
        c.setFillColorRGB(.85, .2, .1); p = c.beginPath(); p.moveTo(px - 1.6 * mm, y - 1.8 * mm); p.lineTo(px + 1.6 * mm, y - 1.8 * mm); p.lineTo(px, y - .2 * mm); p.close(); c.drawPath(p, stroke=0, fill=1)
        c.save(); buf.seek(0)
        page.merge_page(PdfReader(buf).pages[0]); writer.add_page(page)
    for k, lab in zip(["intro"] + keys, titles):
        writer.add_outline_item(lab, (1 if k == "intro" else st2[k]) - 1)
    with open(out, "wb") as f: writer.write(f)
    print(out, n, "pages", {k: st2[k] for k in keys})

if __name__ == "__main__":
    main()
