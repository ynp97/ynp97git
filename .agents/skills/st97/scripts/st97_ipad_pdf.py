#!/usr/bin/env python3
"""st97 iPad版PDF。クラウドのPlaywrightとローカルmacOSのChromeに対応。
1) render_st97.py --ipad でHTML → PDF（段落ごとに改ページ）
2) 各段落の開始ページを見つけ、目次行（①p.3 …）を入れて組み直す
3) 全ページの頭に「日付・箇所｜いまの段落｜ページ/総ページ」と、段落ごとの進行バーを重ねる
使い方: python3 st97_ipad_pdf.py 〈payload.json〉 〈出力.pdf〉
"""
import io, json, re, shutil, subprocess, sys, tempfile, time
from datetime import date
from pathlib import Path
try:
    from playwright.sync_api import sync_playwright
except ImportError:
    sync_playwright = None
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import mm

HERE = Path(__file__).resolve().parent
FONT = next((str(p) for p in [Path("/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"), Path("/Library/Fonts/Arial Unicode.ttf")] if p.exists()), None)
if FONT is None:
    raise RuntimeError("Japanese TrueType font not found")
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
    pdf.unlink(missing_ok=True)
    if sync_playwright is not None and Path("/opt/pw-browsers/chromium").exists():
        with sync_playwright() as p:
            b = p.chromium.launch(executable_path="/opt/pw-browsers/chromium", args=["--no-sandbox"])
            pg = b.new_page(); pg.goto(Path(html).resolve().as_uri()); pg.wait_for_load_state("networkidle")
            pg.pdf(path=str(pdf), prefer_css_page_size=True, print_background=True); b.close()
        return
    chrome = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    if not chrome.exists():
        raise RuntimeError("Chrome not found for iPad PDF rendering")
    profile = Path(tempfile.mkdtemp(prefix="st97-ipad-chrome-"))
    try:
        cmd = [str(chrome), "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--user-data-dir={profile}", f"--print-to-pdf={pdf}", Path(html).resolve().as_uri()]
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(120):
            if pdf.exists() and pdf.stat().st_size > 1000:
                break
            if proc.poll() is not None:
                raise RuntimeError(f"Chrome exited {proc.returncode} before PDF was written")
            time.sleep(.25)
        else:
            raise RuntimeError("Chrome did not write PDF")
        proc.terminate()
        try: proc.wait(timeout=3)
        except subprocess.TimeoutExpired: proc.kill()
    finally:
        shutil.rmtree(profile, ignore_errors=True)

def starts(pdf, keys):
    texts = [re.sub(r"\s", "", pg.extract_text() or "") for pg in PdfReader(str(pdf)).pages]
    out = {}
    for k in keys:
        hit = [i for i, t in enumerate(texts) if f"§{k}§" in t]
        if not hit: raise SystemExit(f"段落の目印が見つからない: {k}")
        out[k] = hit[0] + 1
    return out, len(texts)

def page_states(pdf):
    """各ページの先頭の目印（S=段落の頭, V=節, P=ポイント）。目印のないページは直前を引き継ぐ（節の解説があふれた続きのページ）。"""
    out, cur = [], ("intro",)
    for pg in PdfReader(str(pdf)).pages:
        t = re.sub(r"\s", "", pg.extract_text() or "")
        m = re.search(r"§(S\d+|V\d+_\d+|P\d+|SM|SA)§", t)
        if m:
            k = m.group(1)
            if k.startswith("S") and k[1:].isdigit(): cur = ("S", int(k[1:]))
            elif k.startswith("V"): a, b = k[1:].split("_"); cur = ("V", int(a), int(b))
            elif k.startswith("P"): cur = ("P", int(k[1:]))
            else: cur = (k,)
        out.append(cur)
    return out

def verse_no(label):
    m = re.search(r":\s*(\d+(?:\s*[–〜~\-]\s*\d+)?)\s*$", label)
    return m.group(1).replace(" ", "") if m else label

def main():
    payload, out = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(payload.read_text(encoding="utf-8"))
    match = re.match(r"^(\d{4})年(\d{1,2})月(\d{1,2})日", data["document_title"])
    if not match:
        raise ValueError("document_title must begin with YYYY年M月D日")
    day = date(*(int(value) for value in match.groups()))
    weekday = "月火水木金土日"[day.weekday()]
    date_label = f"{day.month}月{day.day}日（{weekday}）"
    full_date_label = match.group(0) + f"（{weekday}）"
    for field in ("document_title", "title"):
        data[field] = data[field].replace(match.group(0), full_date_label, 1)
    reference = data["document_title"].split("早天｜", 1)[-1]
    secs = data["sections"]
    keys = [f"S{i}" for i in range(1, len(secs) + 1)] + ["SM", "SA"]
    short = [CIRC[i] for i in range(len(secs))] + ["まとめ", "適用"]
    titles = ["導入"] + [f"{CIRC[i]} " + re.sub(r"^\d+．", "", s["heading"]) for i, s in enumerate(secs)] + ["全体のまとめ", "五段階の適用"]
    tmp = Path(tempfile.mkdtemp())
    html, pdf = tmp / "a.html", tmp / "a.pdf"
    render_payload = tmp / "payload.json"
    render_payload.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    render(render_payload, html); to_pdf(html, pdf)
    st, _ = starts(pdf, keys)
    toc = "目次　" + "　".join(f"{s} p.{st[k]}" for s, k in zip(short, keys))
    render(render_payload, html, toc); to_pdf(html, pdf)
    st2, n = starts(pdf, keys)
    if st2 != st:  # 目次を入れてずれたら、ずれた値で組み直す
        toc = "目次　" + "　".join(f"{s} p.{st2[k]}" for s, k in zip(short, keys))
        render(render_payload, html, toc); to_pdf(html, pdf); st2, n = starts(pdf, keys)
    bounds = [1] + [st2[k] for k in keys] + [n + 1]  # 導入, 各段落, まとめ, 適用
    labels = ["導入"] + short
    colors = [_rgb(INTRO_C)] + [_rgb(SEC_C[i % len(SEC_C)]) for i in range(len(secs))] + [_rgb(SUM_C), _rgb(APP_C)]
    pdfmetrics.registerFont(TTFont("IPAG", FONT))
    states = page_states(pdf)
    vnums = [[verse_no(v["label"]) for v in sec["verses"]] for sec in secs]
    reader = PdfReader(str(pdf)); writer = PdfWriter()
    for i, page in enumerate(reader.pages, start=1):
        W, H = float(page.mediabox.width), float(page.mediabox.height)
        seg = max(j for j in range(len(bounds) - 1) if bounds[j] <= i)
        buf = io.BytesIO(); c = canvas.Canvas(buf, pagesize=(W, H))
        x0, x1 = 4 * mm, W - 4 * mm
        c.setFont("IPAG", 9.5); c.setFillColorRGB(0, 0, 0); c.drawString(x0, H - 5 * mm, date_label)
        reference_x = x0 + c.stringWidth(date_label, "IPAG", 9.5) + 2 * mm
        c.setFont("IPAG", 7); c.setFillColorRGB(.35, .39, .42); c.drawString(reference_x, H - 5 * mm, reference)
        c.setFont("IPAG", 9); c.setFillColorRGB(0, 0, 0); c.drawRightString(x1, H - 5 * mm, f"{i} / {n}")
        col = colors[seg]
        c.setFillColorRGB(*col); c.rect(0, 0, 3.2 * mm, H, stroke=0, fill=1); c.rect(W - 3.2 * mm, 0, 3.2 * mm, H, stroke=0, fill=1)  # 左右端の帯
        tx = reference_x + c.stringWidth(reference, "IPAG", 7) + 3 * mm
        room = (x1 - c.stringWidth(f"{n} / {n}", "IPAG", 9) - 3 * mm) - tx
        t = titles[seg]
        while t and c.stringWidth(t, "IPAG", 8.5) > room:
            t = t[:-1]
        if t != titles[seg] and len(t) > 1:
            t = t[:-1] + "…"
        if t:
            c.setFillColorRGB(*col); c.setFont("IPAG", 8.5); c.drawString(tx, H - 5 * mm, t)
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
        # 段落の中の位置（2026-09-28 本人指示）：「要」＝まとめ、節番号、「点」＝ポイント。済＝淡色、いま＝濃色、これから＝枠だけ
        stt = states[i - 1]
        if stt[0] in ("S", "V", "P"):
            si = stt[1] - 1; nums = vnums[si]
            cells = ["要"] + nums + ["点"]
            cur = 0 if stt[0] == "S" else (len(cells) - 1 if stt[0] == "P" else stt[2])
            ty, th = H - 19 * mm, 5.6 * mm
            lab = f"{CIRC[si]} {nums[0].split('–')[0]}〜{re.split(r'[–〜~-]', nums[-1])[-1]}節"
            c.setFont("IPAG", 10); c.setFillColorRGB(*col); c.drawString(x0, ty + 1.6 * mm, lab)
            cx = x0 + c.stringWidth(lab, "IPAG", 10) + 2.5 * mm
            if stt[0] == "V": right = f"{stt[2]} / {len(nums)}節目"
            elif stt[0] == "S": right = f"全{len(nums)}節"
            else: right = "段落のおわり"
            c.setFont("IPAG", 10); rw = c.stringWidth(right, "IPAG", 10)
            avail = x1 - rw - 2.5 * mm - cx
            cw = min(11 * mm, avail / len(cells))
            for j, lab2 in enumerate(cells):
                a = cx + j * cw
                if j < cur: c.setFillColorRGB(*pale(col, .6)); c.roundRect(a + .5, ty, cw - 1, th, 1.2, stroke=0, fill=1); tc = (.25, .25, .25)
                elif j == cur: c.setFillColorRGB(*col); c.roundRect(a + .5, ty - .6 * mm, cw - 1, th + 1.2 * mm, 1.4, stroke=0, fill=1); tc = (1, 1, 1)
                else: c.setStrokeColorRGB(*col); c.setLineWidth(.6); c.setFillColorRGB(1, 1, 1); c.roundRect(a + .5, ty, cw - 1, th, 1.2, stroke=1, fill=1); tc = col
                fs = 9 if len(lab2) <= 2 else 7
                while c.stringWidth(lab2, "IPAG", fs) > cw - 1.5 and fs > 5: fs -= .5
                c.setFont("IPAG", fs); c.setFillColorRGB(*tc); c.drawCentredString(a + cw / 2, ty + (th - fs * .35 * mm / 1) / 2 + .2 * mm, lab2)
            c.setFont("IPAG", 10); c.setFillColorRGB(*col); c.drawRightString(x1, ty + 1.6 * mm, right)
            # 下端の「次へ」案内
            if stt[0] == "S": nxt = f"次 → {nums[0]}節"
            elif stt[0] == "V" and stt[2] < len(nums): nxt = f"次 → {nums[stt[2]]}節"
            elif stt[0] == "V": nxt = f"この節で段落{CIRC[si]}の本文おわり → ポイント"
            elif si + 1 < len(secs): nxt = f"次 → 段落{CIRC[si + 1]}"
            else: nxt = "次 → 全体のまとめ"
            c.setFont("IPAG", 8); c.setFillColorRGB(*col); c.drawRightString(x1, 1.8 * mm, nxt)
        c.setFont("IPAG", 7); c.setFillColorRGB(0, 0, 0); c.drawCentredString(W / 2, 2 * mm, str(i))
        c.save(); buf.seek(0)
        page.merge_page(PdfReader(buf).pages[0]); writer.add_page(page)
    for k, lab in zip(["intro"] + keys, titles):
        writer.add_outline_item(lab, (1 if k == "intro" else st2[k]) - 1)
    with open(out, "wb") as f: writer.write(f)
    print(out, n, "pages", {k: st2[k] for k in keys})

if __name__ == "__main__":
    main()
