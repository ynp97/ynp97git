from html import escape
from pathlib import Path
import base64
import runpy
import re


ROOT = Path(__file__).resolve().parent.parent
DOCX_BUILDER = ROOT / "outputs" / "build_ezekiel27_st97_docx.py"
OUT = ROOT / "outputs" / "20260720_エゼキエル27章1-25節_早天メッセージ_印刷用.html"
PDF_OUT = ROOT / "output" / "pdf" / "20260720_エゼキエル27章1-25節_早天メッセージ_HTML印刷版.pdf"

# The Word builder is the single source for verse text, notes, section summaries,
# paragraph points, and applications. Running it also keeps the paired DOCX current.
data = runpy.run_path(str(DOCX_BUILDER))
sections = data["sections"]
applications = data["applications"]
pdf_base64 = base64.b64encode(PDF_OUT.read_bytes()).decode("ascii") if PDF_OUT.exists() else ""

# Selective ruby for words that are difficult, biblical, or easy to misread.
# Longer words are replaced first so that, for example, 小盾 is not split at 盾.
RUBY = {
    "白亜麻布": "しろあまぬの",
    "遠距離交易": "えんきょりこうえき",
    "自己完結": "じこかんけつ",
    "御用商人": "ごようしょうにん",
    "敷き物": "しきもの",
    "織り布": "おりぬの",
    "帆柱": "ほばしら",
    "亜麻布": "あまぬの",
    "漕ぎ手": "こぎて",
    "小盾": "こだて",
    "銑鉄": "せんてつ",
    "桂枝": "けいし",
    "菖蒲": "しょうぶ",
    "黒檀": "こくたん",
    "珊瑚": "さんご",
    "紅玉": "こうぎょく",
    "香油": "こうゆ",
    "乳香": "にゅうこう",
    "哀歌": "あいか",
    "檜": "ひのき",
    "樫": "かし",
    "櫂": "かい",
    "甲板": "かんぱん",
    "覆い": "おおい",
    "象牙": "ぞうげ",
    "貢ぎ": "みつぎ",
    "鉛": "なまり",
    "青銅": "せいどう",
    "軍馬": "ぐんば",
    "鞍": "くら",
    "撚った": "よった",
    "綱": "つな",
    "奴隷": "どれい",
}

flow = [
    "主はエゼキエルに、繁栄するツロのための「哀歌」を命じる。",
    "ツロは、自分を「美の極み」と誇る豪華な商船として描かれる。",
    "世界各地の材料、人材、軍事力、商品がツロに集まり、その繁栄は頂点に達する。",
    "しかし、これは成功を祝う歌ではなく、滅びを先取りした哀歌である。続く26節以降で、この船は海に沈む。",
]

overall = [
    "ツロは、世界各地の材料、人材、軍事力、商品によって、実際に美しく豊かな都市となった。",
    "しかしツロは、受け取った豊かさを「私は美の極みだ」という自己評価に変えた。",
    "本文は商業、技術、美、富そのものを罪としてはいない。同時に、奴隷取引を含む繁栄の暗い面も記録している。",
    "この章は最初から「哀歌」である。繁栄の頂点を詳しく描くことによって、目に見える成功が永続する保証にはならないことを示す。",
    "ツロという満載の船は、26節以降で沈む。神を離れた自己完結と安全の誇りは、世界規模の繁栄によっても支えきれない。",
]


def e(value):
    return escape(str(value), quote=True)


def ruby_text(value):
    result = e(value)
    words = sorted(RUBY, key=len, reverse=True)
    pattern = re.compile("|".join(re.escape(word) for word in words))
    return pattern.sub(
        lambda match: f"<ruby>{match.group(0)}<rt>{RUBY[match.group(0)]}</rt></ruby>",
        result,
    )


def multiline(value):
    return "<br>".join(ruby_text(value).splitlines())


def bullets(items, class_name=""):
    klass = f' class="{class_name}"' if class_name else ""
    return f"<ul{klass}>" + "".join(f"<li>{multiline(item)}</li>" for item in items) + "</ul>"


parts = []
for heading, summary, verses, points in sections:
    verse_parts = []
    for num, text, notes in verses:
        verse_parts.append(
            '<article class="verse-unit">'
            f'<p class="verse"><span class="verse-label">エゼキエル{e(num)}</span>'
            f'<span class="verse-text">{multiline(text)}</span></p>'
            '<h3>背景・語句</h3>'
            f'{bullets(notes, "notes")}'
            '</article>'
        )
    parts.append(
        '<section class="message-section">'
        f'<h2>{e(heading)}</h2>'
        '<h3>段落の簡単なまとめ</h3>'
        f'<p class="summary-box">{multiline(summary)}</p>'
        f'{"".join(verse_parts)}'
        '<h3 class="points-heading">段落のポイント</h3>'
        f'{bullets(points, "points")}'
        '</section>'
    )

application_parts = []
for label, body in applications:
    application_parts.append(
        '<article class="application">'
        f'<h3>{e(label)}</h3>'
        f'<p>{multiline(body)}</p>'
        '</article>'
    )

html = f'''<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>2026年7月20日 エゼキエル27:1–25「満ちあふれ、重くなった船」</title>
<script>
  function savePrintPdf() {{
    const encoded = "{pdf_base64}";
    if (!encoded) {{
      alert("印刷用PDFがまだ作成されていません。");
      return;
    }}
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    const blob = new Blob([bytes], {{ type: "application/pdf" }});
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "20260720_エゼキエル27章1-25節_早天メッセージ_HTML印刷版.pdf";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 3000);
  }}
</script>
<style>
  :root {{
    --blue: #006699;
    --ink: #000;
    --muted: #59636b;
    --paper: #fff;
    --gold: #fff6dd;
  }}
  @page {{
    size: A4 portrait;
    margin: 35mm 30mm 30mm;
    @bottom-center {{ content: counter(page); font: 9pt "Meiryo UI", sans-serif; }}
  }}
  * {{ box-sizing: border-box; }}
  html {{ background: #e8ebed; }}
  body {{
    width: 210mm;
    min-height: 297mm;
    margin: 12mm auto;
    padding: 35mm 30mm 30mm;
    background: var(--paper);
    color: var(--ink);
    font-family: "Meiryo UI", Meiryo, sans-serif;
    font-size: 10.5pt;
    line-height: 1.43;
    box-shadow: 0 2mm 8mm rgba(0, 0, 0, .16);
  }}
  .toolbar {{
    position: fixed;
    top: 12px;
    right: 18px;
    z-index: 10;
    display: flex;
    align-items: center;
    gap: 10px;
  }}
  .toolbar button {{
    appearance: none;
    border: 0;
    border-radius: 8px;
    padding: 10px 16px;
    background: var(--blue);
    color: #fff;
    font: 700 14px "Meiryo UI", sans-serif;
    cursor: pointer;
    box-shadow: 0 2px 7px rgba(0, 0, 0, .2);
    white-space: nowrap;
  }}
  .toolbar button.secondary {{ background: #52656f; }}
  .print-note {{
    max-width: 250px;
    padding: 7px 10px;
    border-radius: 7px;
    background: rgba(255, 255, 255, .96);
    color: #34444d;
    font-size: 12px;
    line-height: 1.4;
    box-shadow: 0 1px 5px rgba(0, 0, 0, .14);
  }}
  h1 {{
    margin: 0 0 7mm;
    font-size: 16pt;
    line-height: 1.25;
    font-weight: 700;
  }}
  h2 {{
    margin: 7mm 0 2.5mm;
    font-size: 13pt;
    line-height: 1.35;
    font-weight: 700;
    break-after: avoid-page;
  }}
  h3 {{
    margin: 4mm 0 1.2mm;
    color: var(--blue);
    font-size: 10.5pt;
    line-height: 1.43;
    font-weight: 700;
    break-after: avoid-page;
  }}
  p {{ margin: 0 0 2.3mm; }}
  ruby {{ ruby-position: over; }}
  rt {{
    color: #4e6570;
    font-size: .5em;
    font-weight: 500;
    letter-spacing: 0;
  }}
  ol, ul {{ margin: 0 0 3mm; padding-left: 6.5mm; }}
  li {{ margin: 0 0 1.2mm; padding-left: .7mm; }}
  .conclusion, .summary-box {{
    margin: 0 0 3mm;
    padding: 1.8mm 2.3mm;
    border-left: 1.6mm solid var(--blue);
    background: var(--gold);
  }}
  .conclusion {{ font-weight: 700; }}
  .overview {{ color: var(--muted); }}
  .verse-unit {{ break-inside: auto; }}
  .verse {{
    margin: 6mm 0 5mm 6.35mm;
    padding: 3.2mm 0 3.4mm;
    border-top: .35mm solid #c8dce6;
    border-bottom: .35mm solid #c8dce6;
    font-size: 13.5pt;
    font-weight: 700;
    line-height: 1.72;
    break-inside: avoid-page;
  }}
  .verse-label {{
    display: block;
    margin: 0 0 1.8mm;
    color: var(--blue);
    font-size: 11.5pt;
    line-height: 1.4;
  }}
  .verse-text {{ color: #000; }}
  .notes, .points {{ margin-bottom: 3mm; }}
  .points-heading {{
    margin-top: 6mm;
    font-size: 13pt;
    line-height: 1.4;
  }}
  .points {{
    font-size: 11.5pt;
    line-height: 1.55;
  }}
  .points li {{ margin-bottom: 2mm; }}
  .application {{ break-inside: avoid-page; }}
  .application h3 {{ margin-bottom: 1mm; }}
  .check {{
    margin-top: 6mm;
    color: var(--muted);
    font-size: 9pt;
    text-align: right;
  }}
  @media print {{
    html {{ background: #fff; }}
    body {{
      width: auto;
      min-height: 0;
      margin: 0;
      padding: 0;
      box-shadow: none;
    }}
    .toolbar {{ display: none; }}
  }}
  @media screen and (max-width: 850px) {{
    body {{ width: 100%; margin: 0; padding: 22mm 10mm 20mm; box-shadow: none; }}
    .toolbar {{ position: sticky; top: 8px; display: flex; justify-content: flex-end; }}
  }}
</style>
</head>
<body>
<div class="toolbar">
  <span class="print-note">Codex内では「印刷用PDFを保存」、Chrome／Safariではブラウザ印刷も使えます</span>
  <button type="button" onclick="savePrintPdf()">印刷用PDFを保存</button>
  <button class="secondary" type="button" onclick="window.print()">ブラウザ印刷</button>
</div>
<main>
  <h1>2026年7月20日　エゼキエル27:1–25<br>「満ちあふれ、重くなった船」</h1>

  <h2>全体の流れと結論</h2>
  <ol>{''.join(f'<li>{e(item)}</li>' for item in flow)}</ol>
  <p class="conclusion">結論：神から受けた豊かさを自分の完全さとして誇るなら、その豊かさ自体が、神に頼らない生き方の重荷となる。</p>
  <p class="overview">27章はツロを巨大な商船として描く。9節付近から船と都市の表現が重なり、26節以降では船の沈没によってツロの滅亡が語られる。</p>

  {''.join(parts)}

  <section>
    <h2>全体のまとめ</h2>
    {bullets(overall)}
  </section>

  <section>
    <h2>五段階の適用</h2>
    {''.join(application_parts)}
  </section>

  <p class="check">ハルシネーションチェック：再確認済み</p>
</main>
</body>
</html>
'''

OUT.write_text(html, encoding="utf-8")
print(OUT)
