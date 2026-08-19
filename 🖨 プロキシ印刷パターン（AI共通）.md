---
種別: 印刷パターン / AI共通
作成日: 2026-07-06
合図: プロキシ
役割: 画像をA4に9枚、カードサイズ固定で面付けする印刷用PDFの再現手順。
---

# 🖨 プロキシ印刷パターン（AI共通）

## 合図

ユーザーが画像を添付して `プロキシ` と言ったら、この印刷パターンを使う。

画像が添付されていない場合は、直近の画像を使えるならそれを使う。直近画像も不明なら「どの画像で作るか」を一度だけ確認する。

## 仕様

- 用紙: A4縦
- 配置: 3列 × 3行 = 9枚
- 1枚のサイズ: 63mm × 88mm
- 画像同士の隙間: 0mm
- 配置: ページ中央
- 余白: 左右10.5mm、上下16.5mm
- 画像は63mm × 88mmに合わせて描画する
- 出力先: `output/pdf/`
- ファイル名例: `proxy_9up_A4_63x88mm.pdf`
- 印刷時の注意: 「実際のサイズ」または「100%」で印刷する

## 再現手順

Python + reportlab でPDFを作る。A4は `reportlab.lib.pagesizes.A4`、mm変換は `reportlab.lib.units.mm` を使う。

```python
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from pathlib import Path

img_path = Path("INPUT_IMAGE_PATH")
out_path = Path("output/pdf/proxy_9up_A4_63x88mm.pdf")
out_path.parent.mkdir(parents=True, exist_ok=True)

page_w, page_h = A4
card_w = 63 * mm
card_h = 88 * mm
cols = rows = 3

grid_w = card_w * cols
grid_h = card_h * rows
x0 = (page_w - grid_w) / 2
y0 = (page_h - grid_h) / 2

img = ImageReader(str(img_path))
c = canvas.Canvas(str(out_path), pagesize=A4)
c.setTitle("Proxy 9-up A4 63x88mm")

for r in range(rows):
    for col in range(cols):
        x = x0 + col * card_w
        y = y0 + (rows - 1 - r) * card_h
        c.drawImage(
            img,
            x,
            y,
            width=card_w,
            height=card_h,
            preserveAspectRatio=False,
            mask="auto",
        )

c.showPage()
c.save()
```

## 検証

生成後はPDFをPNGへレンダーして、次を確認する。

- A4 1ページである
- 3×3の9枚
- 画像同士の隙間がない
- 全体がA4中央にある
- 1枚が63mm × 88mm相当

Popplerが使える場合:

```bash
pdftoppm -png -r 150 output/pdf/proxy_9up_A4_63x88mm.pdf tmp/pdfs/proxy_9up_A4_63x88mm_preview
pdfinfo output/pdf/proxy_9up_A4_63x88mm.pdf
```

## ブラウザ版が主（2026-08-03〜）

> [!important] まずHTML版を案内する
> 2026-08-03、同じ仕様をブラウザだけで完結させるHTML版を作成し、**本人が「こちらの方が使いやすい」と判断した。** 以後、カード面付け印刷の相談を受けたら、このPython手順を実行する前にHTML版の存在を案内する。
> - 実体: **`アプリ本体/カード印刷/card_print_a4.html`（Vault内）** ← 2026-08-16に移設。**旧 `~/Documents/カード印刷/` は15インチAirに存在しない**（移行スクリプトの対象外だったため）。旧パスを案内しない。
> - 引き継ぎ: [[V カード印刷テンプレート]]

画像をドラッグ＆ドロップまたは⌘Vで貼り、⌘Pで印刷する。AIに画像を渡す往復が不要で、複数種を混ぜる・1枚あたりの枚数を変えるのもこちらが速い。

**このPython版を使うのは**、AIと作業中で画像がすでに手元にあり、PDFファイルを成果物として残したい場合に限る。

## 直近の実例

2026-07-06に、ポケモンカード画像をこのパターンで面付けした。

- 元画像: `/var/folders/t9/s6j28ly12zs64hq3nzb3dxnw0000gn/T/codex-clipboard-bac0056f-07a9-4ac3-b795-7e7d095d2bea.png`
- 出力PDF: `output/pdf/megamawfoxy_9up_A4_63x88mm.pdf`
- 実測配置: 1枚63.00mm × 88.00mm、全体189.00mm × 264.00mm、余白 左右10.50mm / 上下16.50mm
