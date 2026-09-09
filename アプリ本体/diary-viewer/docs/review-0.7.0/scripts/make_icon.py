#!/usr/bin/env python3
"""DiaryViewer のアプリアイコンを生成する。

デザイン: 水色の角丸四角に、白い「D」。
本人指定（2026-08-03）＝「水色に白い字でDを入れて」。

出力: ../AppIcon.iconset/ に macOS が要求する10サイズのPNG。
そのあと build_app.sh が iconutil で AppIcon.icns へ変換する。

再生成:
    python3 scripts/make_icon.py

Pillow が要る。入っていなければ:
    pip3 install --user Pillow
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ---- デザイン定数 -----------------------------------------------------------

CANVAS = 1024          # 基準サイズ
SS = 2                 # スーパーサンプリング倍率（縁を滑らかにするため）

# macOS Big Sur 以降の標準的な比率。
# 1024pxのキャンバスに対し、角丸四角は824px、角丸半径はその22.5%。
SQUARE = 824
RADIUS_RATIO = 0.225

TOP_COLOR = (134, 220, 247)    # 明るい水色
BOTTOM_COLOR = (55, 174, 226)  # やや濃い水色
LETTER = "D"
LETTER_COLOR = (255, 255, 255)
LETTER_HEIGHT_RATIO = 0.56     # 角丸四角の高さに対する「D」の高さ

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",          # macOSで再生成する場合
    "/System/Library/Fonts/SFNS.ttf",
]

# iconutil が要求するファイル名とピクセルサイズ
ICONSET = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    raise SystemExit(
        "太字のサンセリフ体が見つかりません。FONT_CANDIDATES にフォントのパスを足してください。"
    )


def vertical_gradient(size: int, top, bottom) -> Image.Image:
    """上から下への線形グラデーションを作る"""
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        grad.putpixel(
            (0, y),
            tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return grad.resize((size, size), Image.BICUBIC)


def fit_font(font_path: str, target_height: int) -> ImageFont.FreeTypeFont:
    """「D」の実測の高さが target_height になるフォントサイズを二分探索で求める"""
    lo, hi = 10, target_height * 3
    best = ImageFont.truetype(font_path, lo)
    while lo <= hi:
        mid = (lo + hi) // 2
        font = ImageFont.truetype(font_path, mid)
        _, top, _, bottom = font.getbbox(LETTER)
        height = bottom - top
        if height <= target_height:
            best = font
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def build_master() -> Image.Image:
    """1024px相当のマスター画像を SS 倍で描いてから縮小する"""
    size = CANVAS * SS
    square = SQUARE * SS
    radius = round(square * RADIUS_RATIO)
    offset = (size - square) // 2

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 角丸四角のマスク
    mask = Image.new("L", (square, square), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (square - 1, square - 1)], radius=radius, fill=255
    )

    tile = vertical_gradient(square, TOP_COLOR, BOTTOM_COLOR).convert("RGBA")
    tile.putalpha(mask)
    canvas.alpha_composite(tile, (offset, offset))

    # 「D」を中央に置く。
    # 光学的な中心を取るため、描画位置は bbox の実測値から逆算する（フォントの
    # 内部余白をそのまま使うと、見た目が上寄り・左寄りになるため）。
    font = fit_font(find_font(), round(square * LETTER_HEIGHT_RATIO))
    draw = ImageDraw.Draw(canvas)
    left, top, right, bottom = font.getbbox(LETTER)
    x = (size - (right - left)) // 2 - left
    y = (size - (bottom - top)) // 2 - top
    draw.text((x, y), LETTER, font=font, fill=LETTER_COLOR)

    return canvas.resize((CANVAS, CANVAS), Image.LANCZOS)


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "AppIcon.iconset"
    out_dir.mkdir(parents=True, exist_ok=True)

    master = build_master()
    for name, px in ICONSET:
        master.resize((px, px), Image.LANCZOS).save(out_dir / name)
        print(f"  {name}  ({px}x{px})")

    print(f"\n{len(ICONSET)}個を書き出しました: {out_dir}")


if __name__ == "__main__":
    main()
