#!/usr/bin/env python3
import json
import re
import urllib.request
from datetime import date, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", 8769

def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text)

def unescape(value):
    return (value.replace("\\n", " ").replace("\\N", " ")
                 .replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\"))

def parse_dt(raw):
    value = raw.split(":", 1)[-1].strip()
    all_day = len(value) == 8
    digits = re.sub(r"[^0-9]", "", value)
    if len(digits) < 8:
        return None
    date = f"{digits[:4]}-{digits[4:6]}-{digits[6:8]}"
    time = "" if all_day or len(digits) < 12 else f"{digits[8:10]}:{digits[10:12]}"
    return date, time, all_day

def parse_ics(text, start, end):
    events = []
    start_date, end_date = date.fromisoformat(start), date.fromisoformat(end)
    for block in unfold(text).split("BEGIN:VEVENT")[1:]:
        block = block.split("END:VEVENT", 1)[0]
        fields = {}
        for line in block.splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            fields.setdefault(key.split(";", 1)[0], value)
        parsed = parse_dt("DTSTART:" + fields.get("DTSTART", ""))
        if not parsed:
            continue
        event_date, time, all_day = parsed
        title = unescape(fields.get("SUMMARY", "予定"))
        uid = fields.get("UID", event_date + time + title)
        rule = fields.get("RRULE", "")
        dates = [date.fromisoformat(event_date)]
        if rule:
            parts = dict(x.split("=", 1) for x in rule.split(";") if "=" in x)
            freq = parts.get("FREQ", "")
            interval = max(1, int(parts.get("INTERVAL", "1") or "1"))
            count = int(parts.get("COUNT", "0") or "0")
            until_raw = re.sub(r"[^0-9]", "", parts.get("UNTIL", ""))
            until_date = date.fromisoformat(f"{until_raw[:4]}-{until_raw[4:6]}-{until_raw[6:8]}") if len(until_raw) >= 8 else None
            first = dates[0]
            dates = []
            if freq == "WEEKLY":
                cursor, occurrence_no = first, 1
                while cursor < end_date and (not count or occurrence_no <= count):
                    if until_date and cursor > until_date:
                        break
                    if cursor >= start_date:
                        dates.append(cursor)
                    cursor += timedelta(weeks=interval)
                    occurrence_no += 1
            elif freq == "DAILY":
                cursor, occurrence_no = first, 1
                while cursor < end_date and (not count or occurrence_no <= count):
                    if until_date and cursor > until_date:
                        break
                    if cursor >= start_date:
                        dates.append(cursor)
                    cursor += timedelta(days=interval)
                    occurrence_no += 1
            else:
                dates = [first]
        for occurrence in dates:
            iso = occurrence.isoformat()
            if start <= iso < end:
                events.append({
                    "id": uid + ":" + iso,
                    "title": title,
                    "date": iso, "time": time, "allDay": all_day
                })
    return sorted(events, key=lambda e: (e["date"], e["time"], e["title"]))

class Handler(BaseHTTPRequestHandler):
    def send_common(self, status=200, content_type="application/json; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_OPTIONS(self):
        self.send_common(204)

    def do_GET(self):
        if self.path == "/health":
            self.send_common(200, "text/plain; charset=utf-8")
            self.wfile.write(b"ok")
        else:
            self.send_common(404)
            self.wfile.write(b'{"error":"not found"}')

    def do_POST(self):
        if self.path != "/calendar":
            self.send_common(404); self.wfile.write(b'{"error":"not found"}'); return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(size) or b"{}")
            url = str(data.get("url", ""))
            if not url.startswith("https://calendar.google.com/calendar/ical/"):
                raise ValueError("Googleカレンダーの非公開iCal URLではありません")
            req = urllib.request.Request(url, headers={"User-Agent": "ThreeTodoCalendar/1.0"})
            with urllib.request.urlopen(req, timeout=15) as response:
                text = response.read().decode("utf-8", "replace")
            events = parse_ics(text, data.get("start", "2026-06-26"), data.get("end", "2026-08-16"))
            body = json.dumps({"events": events, "syncedAt": datetime.now().isoformat()}, ensure_ascii=False).encode()
            self.send_common(); self.wfile.write(body)
        except Exception as exc:
            body = json.dumps({"error": str(exc)}, ensure_ascii=False).encode()
            self.send_common(400); self.wfile.write(body)

    def log_message(self, *_):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
