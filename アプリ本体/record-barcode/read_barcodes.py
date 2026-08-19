#!/usr/bin/env python3
"""
レコード写真からバーコード(EAN/UPC等)を読み取る ── AI非依存・無料・自己完結。
zxing-cpp + OpenCV を使用。撮影が斜め/低コントラストでも拾えるよう前処理を複数試す。

使い方:
    python3 read_barcodes.py <写真フォルダ> [出力CSVパス]

出力:
    - 端末に「読めた/読めなかった」の一覧
    - CSV (ファイル名, 読めた番号, 形式, 試行で当たった前処理)
"""
import sys, os, csv, glob
import numpy as np
import cv2
import zxingcpp

EXTS = (".jpg", ".jpeg", ".png", ".heic", ".webp", ".bmp", ".tif", ".tiff")

def load_image(path):
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:  # HEIC等でcv2が読めない場合はPILにフォールバック
        try:
            from PIL import Image
            img = cv2.cvtColor(np.array(Image.open(path).convert("RGB")), cv2.COLOR_RGB2BGR)
        except Exception:
            return None
    return img

def _cap(img, longest=2600):
    """長辺をlongestに収める。巨大写真の処理を軽くする(zxingは縞さえ解像していれば十分)。"""
    h, w = img.shape[:2]
    m = max(h, w)
    if m > longest:
        s = longest / m
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img

def variants(img):
    """前処理のバリエーションを順に返す。当たり次第そこで止める。"""
    img = _cap(img)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    yield "gray", gray
    yield "original", img
    # コントラスト強調
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    yield "clahe", clahe.apply(gray)
    # 回転(縦置きバーコード対策) ※zxingは回転にほぼ強いが念のため180のみ
    yield "rot180", cv2.rotate(gray, cv2.ROTATE_180)

def read_one(path):
    img = load_image(path)
    if img is None:
        return None, None, "load-failed"
    for name, v in variants(img):
        try:
            results = zxingcpp.read_barcodes(v)
        except Exception:
            results = []
        for r in results:
            if r.text and r.text.strip():
                return r.text.strip(), str(r.format), name
    return None, None, None

def main():
    if len(sys.argv) < 2:
        print("使い方: python3 read_barcodes.py <写真フォルダ> [出力CSV]")
        sys.exit(1)
    folder = sys.argv[1]
    out_csv = sys.argv[2] if len(sys.argv) > 2 else os.path.join(folder, "barcodes.csv")

    files = sorted(
        p for p in glob.glob(os.path.join(folder, "**", "*"), recursive=True)
        if p.lower().endswith(EXTS)
    )
    if not files:
        print(f"画像が見つかりません: {folder}")
        sys.exit(1)

    rows, hit = [], 0
    for p in files:
        code, fmt, how = read_one(p)
        name = os.path.relpath(p, folder)
        if code:
            hit += 1
            print(f"  ✓ {name}: {code} ({fmt}, via {how})")
        else:
            print(f"  ・ {name}: バーコードなし/読めず")
        rows.append({"file": name, "barcode": code or "", "format": fmt or "", "via": how or ""})

    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["file", "barcode", "format", "via"])
        w.writeheader()
        w.writerows(rows)

    print(f"\n結果: 画像 {len(files)} 枚中 {hit} 枚でバーコードを読み取り")
    print(f"CSV: {out_csv}")

if __name__ == "__main__":
    main()
