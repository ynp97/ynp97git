#!/usr/bin/env python3
import json
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


APP_DIR = Path(__file__).resolve().parent
DATA_DIR = Path.home() / "Library" / "Application Support" / "出席簿"
DATA_FILE = DATA_DIR / "attendance_data.json"
BACKUP_DIR = DATA_DIR / "Backups"
BACKUP_RETENTION_DAYS = 90


def json_bytes(payload):
    return json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")


def atomic_write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(body)
    tmp.replace(path)


def write_daily_backup(body):
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup_file = BACKUP_DIR / f"attendance_backup_{datetime.now().date().isoformat()}.json"
    atomic_write(backup_file, body)

    backups = sorted(BACKUP_DIR.glob("attendance_backup_????-??-??.json"), reverse=True)
    for old_backup in backups[BACKUP_RETENTION_DAYS:]:
        old_backup.unlink(missing_ok=True)
    return backup_file


class AttendanceHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(APP_DIR), **kwargs)

    def _send_json(self, status, payload):
        body = json_bytes(payload)
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
        if self.path == "/api/backup-status":
            backups = sorted(BACKUP_DIR.glob("attendance_backup_????-??-??.json")) if BACKUP_DIR.exists() else []
            self._send_json(200, {
                "ok": True,
                "backupDirectory": str(BACKUP_DIR),
                "backupCount": len(backups),
                "latestBackup": backups[-1].name if backups else None,
                "retentionDays": BACKUP_RETENTION_DAYS,
            })
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/data":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not all(isinstance(payload.get(key), list) for key in ("schools", "students", "entries")):
                raise ValueError("invalid attendance data")

            body = json_bytes(payload)
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            atomic_write(DATA_FILE, body)
            backup_file = write_daily_backup(body)
            self._send_json(200, {
                "ok": True,
                "path": str(DATA_FILE),
                "backupPath": str(backup_file),
            })
        except Exception as error:
            self._send_json(500, {"ok": False, "error": str(error)})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), AttendanceHandler).serve_forever()
