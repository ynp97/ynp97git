#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
レコード査定パイプライン（ローカルQwen3-VL版）
================================================
写真フォルダ → ローカルのQwen3-VL(Ollama)で型番など読み取り → 表(MD/CSV)を出力。
※ 画像処理はすべてあなたのMac上で完結。クラウド/外部AIには送りません（Discogs照合をONにした時だけ型番等のテキストをDiscogsへ送ります）。

使い方:
    1) Ollamaを入れて、モデルを取得:
         ollama pull qwen3-vl:8b
    2) 必要ライブラリ:
         pip3 install requests pillow
    3) 実行（フォルダは初期値=デスクトップの e-bay PIC）:
         python3 record_lister.py
       別フォルダ:
         python3 record_lister.py --photos "/path/to/photos"
       Discogsの相場・再発も自動で引きたい場合（無料トークンが必要・後述）:
         DISCOGS_TOKEN=xxxx python3 record_lister.py --discogs

出力（写真フォルダの隣の _査定結果 フォルダ）:
    - results.json         … 1枚ごとの生データ
    - 査定シート_qwen.md    … 表（Obsidianで開ける）
    - 査定シート_qwen.csv   … 表（Excel用）
"""

import argparse, base64, csv, io, json, os, sys, time, urllib.request, urllib.parse

OLLAMA_URL = "http://localhost:11434/api/chat"
LMSTUDIO_URL = "http://localhost:1234/v1/chat/completions"   # LM StudioのローカルOpenAI互換サーバー
DEFAULT_PHOTOS = os.path.expanduser("~/Desktop/e-bay PIC")

# ---- Qwenへ渡す指示（JSONだけ返させる）----
PROMPT = """あなたはレコードの査定アシスタントです。この写真はアナログレコードのジャケットまたは盤のラベル面です。
写真に写っている文字情報だけを根拠に、次のJSONを1つだけ返してください。読めない項目は空文字 "" にし、推測で埋めないこと。

{
  "side": "front | back | label | unknown",   // ジャケ表/裏/盤ラベル/不明
  "artist": "アーティスト名",
  "title": "アルバム/タイトル",
  "label": "レコードレーベル名",
  "catalog_number": "型番（例 RBF-108, DAMGOOD 132）",
  "barcode": "バーコードの数字（あれば。なければ空）",
  "country": "国（推定できれば）",
  "year": "年（書いてあれば）",
  "format": "7inch | 10inch | 12inch LP | picture disc | unknown",
  "other_text": "他に読める手がかり（マトリクス刻印、PO Box、収録曲など）",
  "confidence": "high | medium | low"
}

JSON以外は一切出力しないこと。"""

def log(*a):
    print(*a, file=sys.stderr, flush=True)

def load_image_b64(path, max_side=1500):
    """PILがあれば縮小して軽く・速く。なければそのまま送る。"""
    try:
        from PIL import Image, ImageOps
        im = Image.open(path)
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=82)
        return base64.b64encode(buf.getvalue()).decode()
    except Exception as e:
        log(f"  (PIL未使用 {os.path.basename(path)}: {e})")
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode()

def ask_qwen(model, img_b64, backend="lmstudio", base_url=None):
    """backend = 'lmstudio'(OpenAI互換) または 'ollama'。"""
    if backend == "ollama":
        url = base_url or OLLAMA_URL
        body = {
            "model": model,
            "messages": [{"role": "user", "content": PROMPT, "images": [img_b64]}],
            "stream": False, "format": "json", "options": {"temperature": 0},
        }
        req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            resp = json.loads(r.read().decode())
        content = resp.get("message", {}).get("content", "{}")
    else:  # lmstudio / 一般のOpenAI互換
        url = base_url or LMSTUDIO_URL
        body = {
            "model": model,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": PROMPT},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + img_b64}},
            ]}],
            "temperature": 0, "stream": False,
            "response_format": {"type": "json_object"},
        }
        req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            resp = json.loads(r.read().decode())
        content = resp["choices"][0]["message"]["content"]
    try:
        return json.loads(content)
    except Exception:
        return {"_raw": content, "confidence": "low"}

# ---------- Discogs（任意・無料トークン）----------
def discogs_get(path, params):
    token = os.environ.get("DISCOGS_TOKEN", "")
    params = dict(params); params["token"] = token
    url = "https://api.discogs.com/" + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "RecordLister/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

def discogs_lookup(rec):
    """バーコード→無ければ型番＋アーティストで検索。版数とマーケット最安値を返す。"""
    try:
        res = None
        if rec.get("barcode"):
            res = discogs_get("database/search", {"barcode": rec["barcode"], "type": "release"})
        if (not res or not res.get("results")) and rec.get("catalog_number"):
            q = {"catno": rec["catalog_number"], "type": "release"}
            if rec.get("artist"): q["artist"] = rec["artist"]
            res = discogs_get("database/search", q)
        if not res or not res.get("results"):
            return {"discogs": "no match"}
        top = res["results"][0]
        out = {"discogs_title": top.get("title", ""), "discogs_year": top.get("year", ""),
               "discogs_url": "https://www.discogs.com" + top.get("uri", "")}
        # 再発の目安＝同masterのバージョン数
        if top.get("master_id"):
            time.sleep(1.2)
            ver = discogs_get(f"masters/{top['master_id']}/versions", {"per_page": 1})
            out["versions"] = ver.get("pagination", {}).get("items", "")
        # マーケット相場
        if top.get("id"):
            time.sleep(1.2)
            try:
                st = discogs_get(f"marketplace/stats/{top['id']}", {})
                lp = st.get("lowest_price") or {}
                out["lowest_price"] = lp.get("value", "")
                out["currency"] = lp.get("currency", "")
                out["num_for_sale"] = st.get("num_for_sale", "")
            except Exception:
                pass
        time.sleep(1.2)
        return out
    except Exception as e:
        return {"discogs_error": str(e)}

# ---------- 出力 ----------
COLS = ["file","seq","side","artist","title","label","catalog_number","barcode",
        "country","year","format","confidence",
        "versions","lowest_price","currency","num_for_sale","discogs_url","other_text"]

def write_outputs(rows, outdir):
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "results.json"), "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    # CSV
    with open(os.path.join(outdir, "査定シート_qwen.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS); w.writeheader()
        for r in rows: w.writerow({c: r.get(c, "") for c in COLS})
    # Markdown
    with open(os.path.join(outdir, "査定シート_qwen.md"), "w", encoding="utf-8") as f:
        f.write("# レコード査定シート（Qwen3-VL読み取り）\n\n")
        f.write("> 自動読み取りのたたき台。相場・再発は要確認。最終判断は本人。\n\n")
        head = ["#","写真","side","アーティスト","タイトル","レーベル","型番","バーコード","国","年","版数","最安値","出品数","確度"]
        f.write("| " + " | ".join(head) + " |\n")
        f.write("|" + "---|"*len(head) + "\n")
        for i, r in enumerate(rows, 1):
            price = f"{r.get('lowest_price','')}{r.get('currency','')}".strip()
            f.write("| " + " | ".join(str(x) for x in [
                i, r.get("file",""), r.get("side",""), r.get("artist",""), r.get("title",""),
                r.get("label",""), r.get("catalog_number",""), r.get("barcode",""),
                r.get("country",""), r.get("year",""), r.get("versions",""),
                price, r.get("num_for_sale",""), r.get("confidence","")]) + " |\n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", default=DEFAULT_PHOTOS, help="写真フォルダ")
    ap.add_argument("--backend", default="lmstudio", choices=["lmstudio", "ollama"],
                    help="使うAIランナー（既定: lmstudio）")
    ap.add_argument("--model", default="qwen/qwen3-vl-30b",
                    help="モデル名。LM Studioはロード中モデルのID、Ollamaは例 qwen3-vl:30b-a3b")
    ap.add_argument("--base-url", default=None, help="APIのURLを上書きしたいとき")
    ap.add_argument("--discogs", action="store_true", help="Discogs照合を行う(要 DISCOGS_TOKEN)")
    args = ap.parse_args()

    if not os.path.isdir(args.photos):
        log(f"フォルダが見つかりません: {args.photos}"); sys.exit(1)
    exts = (".jpg", ".jpeg", ".png", ".heic")
    files = sorted(f for f in os.listdir(args.photos) if f.lower().endswith(exts))
    if not files:
        log("画像がありません。"); sys.exit(1)
    if args.discogs and not os.environ.get("DISCOGS_TOKEN"):
        log("⚠ --discogs 指定だが DISCOGS_TOKEN が未設定。読み取りのみ実行します。")
        args.discogs = False

    log(f"{len(files)}枚を {args.backend}/{args.model} で読み取ります…")
    rows = []
    for i, name in enumerate(files, 1):
        path = os.path.join(args.photos, name)
        log(f"[{i}/{len(files)}] {name}")
        try:
            rec = ask_qwen(args.model, load_image_b64(path), args.backend, args.base_url)
        except Exception as e:
            log(f"  読み取り失敗: {e}"); rec = {"confidence": "low", "error": str(e)}
        rec["file"] = name; rec["seq"] = i
        if args.discogs and rec.get("confidence") != "low":
            rec.update(discogs_lookup(rec))
        rows.append(rec)

    outdir = os.path.join(os.path.dirname(args.photos.rstrip("/")), "_査定結果")
    write_outputs(rows, outdir)
    log(f"\n完了。出力 → {outdir}")
    log("  - 査定シート_qwen.md / .csv / results.json")

if __name__ == "__main__":
    main()
