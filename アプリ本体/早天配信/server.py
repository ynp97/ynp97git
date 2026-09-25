#!/usr/bin/env python3
"""早天配信 — Python標準ライブラリだけで動く、この端末専用の表示サーバー。"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import threading
import time
import unicodedata
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = Path(__file__).resolve().parent
PORT = 19797


def find_vault(explicit=None):
    candidates = [Path(explicit)] if explicit else []
    if os.environ.get('SOTEN_VAULT'):
        candidates.append(Path(os.environ['SOTEN_VAULT']))
    candidates += list(HERE.parents) + [Path.home() / 'Documents' / 'Obsidian Vault']
    for path in candidates:
        if (path / '聖書（新改訳2017）').is_dir():
            return path.resolve()
    raise ValueError('Vaultが見つかりません。--vault で保存場所を指定してください。')


def schedules(vault):
    result = {}
    for path in sorted((vault / '.agents/skills/st97/references').glob('????-??.md')):
        for day, ref in re.findall(r'^\|\s*(\d{1,2})\s*\|\s*([^|]+)\|', path.read_text(), re.M):
            date = f'{path.stem}-{int(day):02d}'
            dt.date.fromisoformat(date)
            result[date] = ref.strip()
    return result


def read_range(vault, reference):
    normalized = unicodedata.normalize('NFKC', reference)
    normalized = re.sub(r'[–—−〜～]', '-', normalized).replace(' ', '')
    m = re.fullmatch(r'([^0-9]+)(\d+)(?::(\d+))?(?:-(?:(\d+):)?(\d+))?章?', normalized)
    if not m:
        raise ValueError(f'箇所の形式を読み取れません：{reference}')
    book, ch, verse, endch, end = m.groups()
    ch = int(ch)
    if verse:
        start = (ch, int(verse))
        finish = (int(endch or ch), int(end or verse))
    else:
        if endch:
            raise ValueError('章の範囲を確認してください。')
        start, finish = (ch, 1), (int(end or ch), None)
    aliases = {}
    for candidate in (vault / '聖書（新改訳2017）').glob('*.md'):
        name = candidate.stem
        short = name
        for suffix in ('の福音書', '人への手紙', 'への手紙', 'の手紙'):
            short = short.replace(suffix, '')
        aliases[short] = name
    aliases.update({'ヨハネ':'ヨハネの福音書', '使徒':'使徒の働き', '黙示録':'ヨハネの黙示録', '詩編':'詩篇'})
    book = aliases.get(book, book)
    path = vault / '聖書（新改訳2017）' / f'{book}.md' 
    if not path.is_file():
        raise ValueError(f'本文ファイルがありません：{book}')
    verses = {}
    # 一節は行末のObsidianブロックIDで特定。本文を改変・推測しない。
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'(\d+)[\s　]+(.+?)\s+\^(\d+)-(\d+)\s*', line)
        if match:
            number, text, chapter, ident = match.groups()
            key = (int(chapter), int(ident))
            if int(number) != key[1] or key in verses:
                raise ValueError(f'本文データの節番号が不整合です：{book} {key}')
            verses[key] = text
    if finish[1] is None:
        finish = (finish[0], max((v for c, v in verses if c == finish[0]), default=0))
    if start > finish or start not in verses or finish not in verses:
        raise ValueError(f'指定範囲の本文が揃っていません：{reference}')
    selected = []
    for c in range(start[0], finish[0] + 1):
        lo = start[1] if c == start[0] else 1
        hi = finish[1] if c == finish[0] else max((v for cc, v in verses if cc == c), default=0)
        if not hi:
            raise ValueError(f'本文に章がありません：{book}{c}章')
        for v in range(lo, hi + 1):
            if (c, v) not in verses:
                raise ValueError(f'本文に欠けがあります：{book}{c}:{v}')
            selected.append({'label': f'{book} {c}:{v}', 'text': verses[c, v]})
    return selected


def split_text(text, limit=104):
    """字を失わず分割。句読点を優先し、長い節も画面からはみ出させない。"""
    parts = []
    while text:
        width, cut = 0, 0
        for char in text:
            step = 1 if unicodedata.east_asian_width(char) in 'WFA' else .55
            if width + step > limit:
                break
            width += step
            cut += 1
        if cut == len(text):
            parts.append(text)
            break
        preferred = [i + 1 for i, char in enumerate(text[:cut]) if char in '。、！？']
        if preferred and preferred[-1] >= cut * .5:
            cut = preferred[-1]
        parts.append(text[:cut])
        text = text[cut:]
    return parts


def prepare(vault, date):
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', date):
        raise ValueError('日付を選んでください。')
    dt.date.fromisoformat(date)
    reference = schedules(vault).get(date)
    if not reference:
        raise ValueError(f'{date[:7]}の予定、または指定日の箇所が未登録です。st97の月間一覧を追加すると使えます。表示中の箇所は変更していません。')
    verses = read_range(vault, reference)
    pages = []
    for verse in verses:
        parts = split_text(verse['text'])
        for i, text in enumerate(parts):
            pages.append({'label': verse['label'], 'text': text,
                          'part': f'{i + 1}/{len(parts)}' if len(parts) > 1 else ''})
    warnings = []
    if any(v['label'] == '歴代誌第一 15:10' for v in verses):
        warnings.append('本文データの要確認箇所：歴代誌第一15:10の人数。st97の記録に誤記の疑いがあります。本文はVaultの原文のままです。')
    return {'date': date, 'reference': reference, 'pages': pages,
            'verseCount': len(verses), 'warnings': warnings}


class Broadcast:
    def __init__(self, vault, storage=None):
        self.vault = vault
        self.storage = Path(storage) if storage else None
        self.extras = json.loads(self.storage.read_text()) if self.storage and self.storage.exists() else {}
        self.extra_id = ''
        self.extra_page = 0
        self.lock = threading.RLock()
        self.obs_seen = 0
        self.revision = time.time_ns()
        self.state = {'date': dt.date.today().isoformat(), 'reference': '', 'pages': [], 'verseCount': 0,
                      'warnings': [], 'mode': 'hidden', 'page': 0, 'startupError': ''}
        try:
            self.state.update(prepare(vault, dt.date.today().isoformat()))
            self.state['mode'] = 'reference'
        except ValueError as error:
            self.state['startupError'] = str(error)

    def snapshot(self, obs=False):
        with self.lock:
            if obs:
                self.obs_seen = time.monotonic()
            entries = self.extras.get(self.state['date'], [])
            selected = next((e for e in entries if e['id'] == self.extra_id), None)
            return dict(self.state, extras=entries, extraId=self.extra_id, extraPage=self.extra_page,
                        extraSelected=selected, revision=str(self.revision),
                        obsConnected=time.monotonic() - self.obs_seen < 4,
                        today=dt.date.today().isoformat())

    def action(self, body):
        with self.lock:
            action = body.get('action')
            if action in ('add_extra', 'remove_extra', 'move_extra', 'show_extra'):
                day = self.state['date'] or dt.date.today().isoformat()
                entries = self.extras.setdefault(day, [])
                if action == 'add_extra':
                    reference = str(body.get('reference', '')).strip()
                    text = str(body.get('text', '')).strip()
                    if reference:
                        verses = read_range(self.vault, reference)
                        pages = [dict(label=v['label'], text=t, part='', copyright=True)
                                 for v in verses for t in split_text(v['text'])]
                        title = reference
                    else:
                        title = str(body.get('title', '')).strip() or '説明'
                        if not text or len(text) > 10000 or len(title) > 100:
                            raise ValueError('本文は1〜10000文字、見出しは100文字以内で入力してください。')
                        pages = [dict(label=title, text=t, part='', copyright=False) for t in split_text(text)]
                    entries.append(dict(id=uuid.uuid4().hex, title=title, pages=pages))
                else:
                    index = next((i for i,e in enumerate(entries) if e['id'] == body.get('id')), None)
                    if index is None:
                        raise ValueError('追加ページが見つかりません。')
                    if action == 'show_extra':
                        self.extra_id = entries[index]['id']
                        self.extra_page = 0
                        self.state['mode'] = 'extra'
                    elif action == 'move_extra':
                        target = max(0, min(len(entries)-1, index + (1 if body.get('direction') == 'down' else -1)))
                        entries.insert(target, entries.pop(index))
                    else:
                        removed = entries.pop(index)
                        if removed['id'] == self.extra_id:
                            self.state['mode'] = 'body' if self.state['pages'] else 'hidden'
                            self.extra_id = ''
                if self.storage and action != 'show_extra':
                    self.storage.parent.mkdir(parents=True, exist_ok=True)
                    temporary = self.storage.with_suffix('.tmp')
                    temporary.write_text(json.dumps(self.extras, ensure_ascii=False, indent=2))
                    temporary.replace(self.storage)
            elif action == 'open_today':
                today = dt.date.today().isoformat()
                if self.state['date'] != today:
                    try:
                        self.state.update(prepare(self.vault, today), mode='reference', page=0, startupError='')
                    except ValueError as error:
                        self.state.update(date=today, reference='', pages=[], verseCount=0,
                                          warnings=[], mode='hidden', page=0, startupError=str(error))
            elif action == 'prepare':
                data = prepare(self.vault, body.get('date', ''))
                self.state.update(data, mode='reference', page=0, startupError='')
            elif action == 'mode' and body.get('mode') in ('reference', 'body', 'hidden', 'prayer', 'lords_prayer'):
                if not self.state['pages'] and body['mode'] in ('reference', 'body'):
                    raise ValueError('先に日付を選んで準備してください。')
                self.state['mode'] = body['mode']
            elif action in ('next', 'previous', 'page'):
                if self.state['mode'] == 'extra':
                    entry = next(e for e in self.extras[self.state['date']] if e['id'] == self.extra_id)
                    index = int(body['page']) if action == 'page' else self.extra_page + (1 if action == 'next' else -1)
                    self.extra_page = max(0, min(index, len(entry['pages'])-1))
                    self.revision += 1
                    return self.snapshot()
                if not self.state['pages']:
                    raise ValueError('先に日付を選んで準備してください。')
                index = (self.state['page'] + (1 if action == 'next' else -1)
                         if action != 'page' else int(body['page']))
                self.state['page'] = max(0, min(index, len(self.state['pages']) - 1))
                self.state['mode'] = 'body'
            else:
                raise ValueError('操作を確認してください。')
            self.revision += 1
            return self.snapshot()


def handler(app):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def respond(self, value, status=200, content_type='application/json; charset=utf-8'):
            data = json.dumps(value, ensure_ascii=False).encode() if content_type.startswith('application/json') else value
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'self'; connect-src 'self'")
            self.end_headers()
            self.wfile.write(data)

        def valid_host(self):
            return self.headers.get('Host') in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}')

        def do_GET(self):
            if not self.valid_host():
                return self.respond({'error': 'Host not allowed'}, 403)
            url = urlparse(self.path)
            if url.path == '/api/state':
                return self.respond(app.snapshot(obs=parse_qs(url.query).get('obs') == ['1']))
            if url.path == '/api/health':
                return self.respond({'app': 'soten-broadcast', 'version': 1})
            if url.path == '/api/dates':
                return self.respond(schedules(app.vault))
            files = {'/': ('index.html', 'text/html'), '/display': ('display.html', 'text/html'),
                     '/app.js': ('app.js', 'text/javascript'), '/display.js': ('display.js', 'text/javascript'),
                     '/style.css': ('style.css', 'text/css'), '/display.css': ('display.css', 'text/css')}
            if url.path not in files:
                return self.respond({'error': 'Not found'}, 404)
            name, mime = files[url.path]
            self.respond((HERE / 'web' / name).read_bytes(), content_type=mime + '; charset=utf-8')

        def do_POST(self):
            allowed = {f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'}
            if not self.valid_host() or self.headers.get('Origin') not in allowed:
                return self.respond({'error': 'Origin not allowed'}, 403)
            if self.path != '/api/action':
                return self.respond({'error': 'Not found'}, 404)
            try:
                length = int(self.headers.get('Content-Length', 0))
                if length < 1 or length > 65536 or not self.headers.get('Content-Type', '').startswith('application/json'):
                    raise ValueError('操作データを確認してください。')
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('操作データを確認してください。')
                self.respond(app.action(body))
            except (ValueError, KeyError, TypeError) as error:
                self.respond({'error': str(error)}, 400)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vault')
    parser.add_argument('--port', type=int, default=PORT)
    args = parser.parse_args()
    app = Broadcast(find_vault(args.vault), HERE / 'user_data/extra_pages.json')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler(app))
    print(f'早天配信 http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
