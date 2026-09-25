#!/usr/bin/env python3
"""st97 ライブ用（iPadで見ながら話す版）。本文は通常ペイロードから引き、要点だけを live JSON から入れる。
2026-09-25 本人指示で新設。使い方: render_st97_live.py 〈通常payload.json〉 〈live.json〉 〈出力.html〉"""
from __future__ import annotations
import json, re, sys
from html import escape
from pathlib import Path

CSS = r"""
@page{size:150mm 200mm;margin:11mm 4mm 6mm;
 @top-center{content:"__HEADER__　" counter(page) " / " counter(pages);font-family:"Meiryo UI",Meiryo,sans-serif;font-size:8.5pt;color:#59636b}}
*{box-sizing:border-box}
body{margin:0;padding:0;color:#000;font-family:"Meiryo UI",Meiryo,sans-serif;font-size:17pt;line-height:1.5}
@media screen{body{padding:6mm 4mm;max-width:150mm;margin:auto}}
h1{font-size:21pt;margin:0 0 4mm;line-height:1.3}
h2{font-size:21pt;margin:0 0 3mm;color:#006699;line-height:1.3;break-after:avoid-page}
.sec{break-before:page}
.lead{margin:0 0 4mm;padding:3mm;border-left:2mm solid #006699;background:#fff6dd;font-weight:700;font-size:18pt}
.flow{margin:0 0 4mm;padding-left:0;list-style:none}
.flow li{margin:0 0 2mm}
.flow b{color:#006699}
.unit{break-inside:avoid-page;margin:0 0 4mm}
.verse{margin:0;padding:2.5mm 3mm;background:#dceaf5;border-top:.4mm solid #a8c9dc;border-bottom:.4mm solid #a8c9dc;font-size:21pt;font-weight:700;line-height:1.55}
.label{display:block;color:#006699;font-size:13pt;margin-bottom:1mm}
.cue{margin:1.5mm 0 0;padding-left:1.2em;text-indent:-1.2em;font-size:17pt;color:#003a57}
.cue::before{content:"▶ ";color:#006699}
.box{break-inside:avoid-page;margin:5mm 0 0;padding:3mm;border:.6mm solid #006699;border-radius:2mm}
.box h3{margin:0 0 1.5mm;font-size:15pt;color:#006699}
.box ul{margin:0;padding-left:1.2em}
.box li{margin:0 0 1.5mm}
.end{break-inside:avoid-page}
.key{margin:3mm 0 0;padding:3mm;background:#fff6dd;font-weight:700;font-size:19pt;border-left:2mm solid #c47a00}
ruby{ruby-position:over} rt{font-size:.5em;color:#333}
"""

def main():
    base = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    live = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    out = Path(sys.argv[3])
    rmap = {**base.get("ruby", {}), **live.get("ruby", {})}
    pat = re.compile("|".join(re.escape(w) for w in sorted(rmap, key=len, reverse=True))) if rmap else None
    def r(v):
        t = escape(str(v), quote=False)
        return pat.sub(lambda m: f"<ruby>{m.group(0)}<rt>{escape(rmap[m.group(0)])}</rt></ruby>", t) if pat else t
    def ml(v): return "<br>".join(r(v).splitlines())
    verses = {v["label"]: v["text"] for s in base["sections"] for v in s["verses"]}
    parts = [f'<h1>{ml(live["title"])}</h1>', f'<p class="lead">{ml(live["conclusion"])}</p>',
             '<ul class="flow">' + "".join(f'<li><b>{r(a)}</b>　{r(b)}</li>' for a, b in live["flow"]) + "</ul>"]
    if live.get("bridge"):
        parts.append(f'<div class="key">{ml(live["bridge"])}</div>')
    used = []
    for s in live["sections"]:
        h = [f'<section class="sec"><h2>{r(s["heading"])}</h2>']
        for u in s["units"]:
            lab = u["label"]; used.append(lab)
            cues = "".join(f'<p class="cue">{r(c)}</p>' for c in u.get("cues", []))
            h.append(f'<div class="unit"><p class="verse"><span class="label">{r(lab)}</span>{ml(verses[lab])}</p>{cues}</div>')
        h.append('<div class="end"><div class="box"><h3>ポイント</h3><ul>' + "".join(f"<li>{r(p)}</li>" for p in s["points"]) + "</ul></div>")
        if s.get("key"):
            h.append(f'<div class="key">{ml(s["key"])}</div>')
        h.append("</div></section>")
        parts.append("".join(h))
    missing = [l for l in verses if l not in used]
    if missing:
        raise SystemExit(f"本文の抜けがあります: {missing}")
    parts.append('<section class="sec"><h2>適用</h2><div class="box"><ul>' + "".join(f"<li>{r(a)}</li>" for a in live["applications"]) + "</ul></div>"
                 + (f'<div class="key">{ml(live["christ"])}</div>' if live.get("christ") else "") + "</section>")
    header = base["document_title"].replace(" 早天｜", "｜").replace('"', "") + "　ライブ用"
    html = f'<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(base["document_title"])} ライブ用</title><style>{CSS.replace("__HEADER__", header)}</style></head><body>{"".join(parts)}</body></html>'
    out.parent.mkdir(parents=True, exist_ok=True); out.write_text(html, encoding="utf-8"); print(out)

if __name__ == "__main__":
    main()
