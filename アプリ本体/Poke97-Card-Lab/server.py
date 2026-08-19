#!/usr/bin/env python3
"""Small dependency-light local web UI for Poke97 Card Lab."""

from __future__ import annotations

import argparse
import json
import mimetypes
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import ai_ask
import card_db
from ai_ask import AIUnavailable
from card_db import DEFAULT_DB, connect, query_cards, stats


ROOT = Path(__file__).resolve().parent


def code_stamp() -> int:
    """Newest mtime of the server code. The launcher compares this with the files
    on disk, so a server left running from before an edit is replaced instead of
    silently serving the old build."""
    files = [Path(__file__), Path(card_db.__file__), Path(ai_ask.__file__), *(ROOT / "web").glob("*")]
    return max(int(path.stat().st_mtime) for path in files if path.is_file())


class Handler(BaseHTTPRequestHandler):
    db_path = DEFAULT_DB

    def send_json(self, payload: object, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/"):
            try:
                db = connect(self.db_path)
                if parsed.path == "/api/stats":
                    return self.send_json({**stats(db), "code_stamp": code_stamp()})
                if parsed.path == "/api/search":
                    params = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
                    return self.send_json(query_cards(db, params))
                if parsed.path == "/api/ai-config":
                    config = ai_ask.load_config()
                    # 鍵そのものは画面へ返さない。入っているかどうかだけ返す。
                    return self.send_json({**config, "api_key": "", "api_key_set": bool(config.get("api_key"))})
                if parsed.path == "/api/ai-models":
                    try:
                        return self.send_json({"models": ai_ask.list_models(ai_ask.load_config())})
                    except AIUnavailable as exc:
                        return self.send_json({"error": str(exc)}, 503)
                return self.send_json({"error": "見つかりません"}, 404)
            except Exception as exc:
                return self.send_json({"error": str(exc)}, 500)
        return self.serve_static(parsed.path)

    def read_body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8") or "{}")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        try:
            body = self.read_body()
            if parsed.path == "/api/ai-config":
                values = dict(body)
                # 空の鍵は「変更しない」の意味。うっかり消さないため。
                if not str(values.get("api_key", "")).strip():
                    values.pop("api_key", None)
                config = ai_ask.save_config(values)
                return self.send_json({**config, "api_key": "", "api_key_set": bool(config.get("api_key"))})
            if parsed.path == "/api/ask":
                db = connect(self.db_path)
                question = (body.get("question") or "").strip()

                def by_hand(extra: dict) -> dict:
                    """AIを使わない道。下の検索欄に入っている条件で候補を集め、
                    質問票にして返す。質問文をそのまま全文検索に投げると、助詞まで
                    一致を求めて0件になるだけなので、条件は画面のものを使う。"""
                    params = {k: str(v) for k, v in (body.get("params") or {}).items() if str(v).strip()}
                    used, cards, hit_total = ai_ask.run_searches(db, [params]) if params else ([], [], 0)
                    return {
                        "question": question, "searches": used, "hit_total": hit_total,
                        "candidate_count": len(cards), "cards": cards[:60],
                        "packet": ai_ask.build_packet(question, cards[:60], used) if question or params else "",
                        "no_conditions": not params,
                        **extra,
                    }

                if body.get("packet_only"):
                    return self.send_json(by_hand({"packet_only": True}))
                try:
                    return self.send_json(ai_ask.ask(db, question))
                except AIUnavailable as exc:
                    # AIが動かなくても、DBの走査と貼り付け用の質問票までは返す。
                    return self.send_json(by_hand({"error": str(exc)}), 503)
            return self.send_json({"error": "見つかりません"}, 404)
        except Exception as exc:
            return self.send_json({"error": str(exc)}, 500)

    def serve_static(self, path: str) -> None:
        relative = "index.html" if path == "/" else path.lstrip("/")
        target = (ROOT / "web" / relative).resolve()
        web_root = (ROOT / "web").resolve()
        if web_root not in target.parents and target != web_root:
            self.send_error(403)
            return
        if not target.is_file():
            self.send_error(404)
            return
        body = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self) -> None:
        parsed = urlparse(self.path)
        relative = "index.html" if parsed.path == "/" else parsed.path.lstrip("/")
        target = (ROOT / "web" / relative).resolve()
        web_root = (ROOT / "web").resolve()
        if (web_root not in target.parents and target != web_root) or not target.is_file():
            self.send_error(404)
            return
        body = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

    def log_message(self, fmt: str, *args: object) -> None:
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--port", type=int, default=8797)
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()
    Handler.db_path = args.db
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}"
    print(f"poke97 カード研究室: {url}")
    if not args.no_open:
        webbrowser.open(url)
    server.serve_forever()


if __name__ == "__main__":
    main()
