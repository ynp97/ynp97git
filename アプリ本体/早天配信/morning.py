#!/usr/bin/env python3
"""毎朝の起動補助：今日のPDFを見つけて渡し、OBSと原稿画面を並べる。

失敗しても配信の起動そのものは止めない（呼び出し側が例外を握る）。
"""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time

HOME = Path.home()
SEARCH_DIRS = [HOME / 'Downloads', HOME / 'Documents/Obsidian Vault/output/pdf']
SERVICE = HOME / 'Library/Application Support/SotenBroadcast'
OBS_INI = HOME / 'Library/Application Support/obs-studio/user.ini'
READER_SHARE = 0.45   # 画面の左45%を原稿、残りをOBS
TITLE_BAR = 28


# ---- 今日のPDF -------------------------------------------------------------

def find_today_pdf(day=None, dirs=None):
    """ファイル名に今日のYYYYMMDDを含むPDF。iPad版を優先し、同格なら新しいもの。"""
    token = (day or dt.date.today()).strftime('%Y%m%d')
    found = []
    for folder in dirs or SEARCH_DIRS:
        if not folder.is_dir():
            continue
        for path in folder.glob('*.pdf'):
            if token in path.name and not path.name.startswith('.'):
                found.append(path)
    if not found:
        return None
    return max(found, key=lambda p: ('ipad' in p.name.lower(), p.stat().st_mtime))


def stage_today_pdf(target_dir=None, day=None, dirs=None):
    """見つけたPDFをサービス側へ複写する。無ければ前日の分を消して None。"""
    target_dir = Path(target_dir or SERVICE / 'user_data')
    target_dir.mkdir(parents=True, exist_ok=True)
    pdf, meta = target_dir / 'today.pdf', target_dir / 'today.json'
    source = find_today_pdf(day, dirs)
    if source is None:
        for path in (pdf, meta):
            if path.exists():
                path.unlink()
        return None
    fd, temp = tempfile.mkstemp(dir=target_dir, suffix='.pdf')
    os.close(fd)
    shutil.copyfile(source, temp)
    os.replace(temp, pdf)
    stat = source.stat()
    info = {'name': source.name, 'folder': source.parent.name, 'size': stat.st_size,
            'mtime': int(stat.st_mtime), 'date': (day or dt.date.today()).isoformat()}
    meta.write_text(json.dumps(info, ensure_ascii=False))
    return source


# ---- 画面配置 ---------------------------------------------------------------

def screen_frame():
    """メニューバーのある画面の使える範囲（左上原点のx, y, 幅, 高さ）。Dockとメニューバーを除く。"""
    script = ('ObjC.import("AppKit");var s=$.NSScreen.screens.objectAtIndex(0);var f=s.frame,v=s.visibleFrame;'
              'JSON.stringify([f.size.height,v.origin.x,v.origin.y,v.size.width,v.size.height])')
    out = subprocess.run(['osascript', '-l', 'JavaScript', '-e', script],
                         capture_output=True, text=True, timeout=10, check=True).stdout
    full_h, vx, vy, vw, vh = json.loads(out)
    return int(vx), int(full_h - (vy + vh)), int(vw), int(vh)


def plan(frame):
    x, y, w, h = frame
    reader_w = int(w * READER_SHARE)
    return {'reader': (x, y, x + reader_w, y + h), 'obs': (x + reader_w, y, x + w, y + h)}


def _rect(left, top, right, bottom):
    return struct.pack('>iiii', left, top, right - 1, bottom - 1)


def rewrite_qt_geometry(blob, bounds):
    """QWidget::saveGeometry（Qt5/6）の位置だけを書き換える。形式が違えば None。"""
    if len(blob) < 8 + 32 or struct.unpack('>I', blob[:4])[0] != 0x1D9D0CB:
        return None
    major = struct.unpack('>H', blob[4:6])[0]
    if major not in (1, 2, 3):
        return None
    left, top, right, bottom = bounds
    frame = _rect(left, top, right, bottom)
    client = _rect(left, top + TITLE_BAR, right, bottom)
    out = bytearray(blob)
    out[8:24] = frame
    out[24:40] = client
    # 画面番号(4)・最大化(1)・全画面(1)・画面幅(4) の後ろに v2 以降は geometry() がある
    tail = 40 + 4
    if len(out) >= tail + 2:
        out[tail] = 0
        out[tail + 1] = 0
    if major >= 2 and len(out) >= tail + 2 + 4 + 16:
        out[tail + 6:tail + 22] = client
    return bytes(out)


def set_obs_geometry(bounds, ini=OBS_INI, backup_dir=None):
    """OBS終了中だけ user.ini の [BasicWindow] geometry を書き換える。"""
    if not ini.exists():
        return 'OBSの設定ファイルがありません'
    lines = ini.read_text(encoding='utf-8').splitlines(keepends=True)
    section, changed = None, False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            section = stripped[1:-1]
            continue
        if section == 'BasicWindow' and stripped.startswith('geometry='):
            value = stripped.split('=', 1)[1]
            blob = rewrite_qt_geometry(base64.b64decode(value), bounds)
            if blob is None:
                return 'OBSの位置情報の形式が想定と違うため変更しません'
            new = base64.b64encode(blob).decode()
            if new != value:
                lines[i] = 'geometry=' + new + '\n'
                changed = True
            break
    else:
        return 'OBSの位置情報がまだありません（一度OBSを終了すると作られます）'
    if not changed:
        return None
    if backup_dir is not None:
        backup_dir.mkdir(parents=True, exist_ok=True)
        marker = backup_dir / 'user_before_layout.ini'
        if not marker.exists():
            shutil.copy2(ini, marker)
    fd, temp = tempfile.mkstemp(dir=ini.parent)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    os.replace(temp, ini)
    return None


READER_APP = Path(__file__).resolve().parent / '早天原稿.app'


def reader_command(url, bounds, app=READER_APP):
    left, top, right, bottom = bounds
    return [str(app / 'Contents/MacOS/soten-reader'), url,
            str(left), str(top), str(right - left), str(bottom - top)]


def open_reader(url, bounds, app=READER_APP):
    """Chromeのログイン状態から独立した原稿専用窓を開く。"""
    if not (app / 'Contents/MacOS/soten-reader').exists():
        raise FileNotFoundError(f'早天原稿.app がありません: {app}')
    subprocess.run(['pkill', '-x', 'soten-reader'], capture_output=True)
    for _ in range(50):
        if subprocess.run(['pgrep', '-x', 'soten-reader'], capture_output=True).returncode != 0:
            break
        time.sleep(0.1)
    process = subprocess.Popen(reader_command(url, bounds, app),
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    if process.poll() is not None:
        raise RuntimeError('早天原稿.app を起動できませんでした')


def obs_running():
    return subprocess.run(['pgrep', '-x', 'OBS'], capture_output=True).returncode == 0
