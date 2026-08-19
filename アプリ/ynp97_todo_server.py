#!/usr/bin/env python3
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKDOWN_PATH = ROOT / "TODOインボックス.md"
DATA_PATH = ROOT / "アプリ" / "ynp97 TODOインボックス.data.json"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        if self.path != "/api/save":
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            markdown = payload.get("markdown", "")
            data = payload.get("data", "{}")
            if not isinstance(markdown, str) or not isinstance(data, str):
                raise ValueError("Invalid payload")

            MARKDOWN_PATH.write_text(markdown + "\n", encoding="utf-8")
            DATA_PATH.write_text(data + "\n", encoding="utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        except Exception as error:
            self.send_response(400)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            body = json.dumps({"ok": False, "error": str(error)}).encode("utf-8")
            self.wfile.write(body)


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 8775), Handler)
    print("ynp97 TODO server: http://127.0.0.1:8775/アプリ/ynp97%20TODOインボックス.html")
    server.serve_forever()


if __name__ == "__main__":
    main()
