#!/usr/bin/env python3
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


APP_DIR = Path(__file__).resolve().parent
DATA_DIR = Path.home() / "Documents" / "Codex" / "出席簿データ"
DATA_FILE = DATA_DIR / "attendance_data.json"


class AttendanceHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(APP_DIR), **kwargs)

    def _send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/health":
            self._send_json(200, {"ok": True})
            return
        if self.path == "/api/data":
            if not DATA_FILE.exists():
                self._send_json(404, {"ok": False, "error": "no data"})
                return
            try:
                self._send_json(200, json.loads(DATA_FILE.read_text(encoding="utf-8")))
            except Exception as error:
                self._send_json(500, {"ok": False, "error": str(error)})
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/data":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            tmp = DATA_FILE.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
            tmp.replace(DATA_FILE)
            self._send_json(200, {"ok": True, "path": str(DATA_FILE)})
        except Exception as error:
            self._send_json(500, {"ok": False, "error": str(error)})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), AttendanceHandler).serve_forever()
