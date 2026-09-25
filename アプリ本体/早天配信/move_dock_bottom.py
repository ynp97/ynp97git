"""このMacのOBS終了中のみ実行。既存の左右・下部構成を保持して聖書ドックを下へ。"""
import base64
from pathlib import Path
import re
import shutil
import struct
import sys
from datetime import datetime

p = Path.home() / 'Library/Application Support/obs-studio/user.ini'
s = p.read_text()
m = re.search(r'^DockState=(.*)$', s, re.M)
baseline = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else s
b = base64.b64decode(re.search(r'^DockState=(.*)$', baseline, re.M).group(1))
offset = 9


def integer():
    global offset
    v = struct.unpack_from('>i', b, offset)[0]
    offset += 4
    return v


def pack(*numbers):
    return struct.pack('>' + 'i' * len(numbers), *numbers)


def sequence():
    global offset
    begin = offset
    assert b[offset] == 0xfc, '既存のタブ/入れ子構成は自動変更しません'
    orientation = b[offset + 1]
    offset += 2
    count = integer()
    items = []
    for _ in range(count):
        start = offset
        assert b[offset] == 0xfb, '既存の入れ子構成は自動変更しません'
        offset += 1
        length = integer()
        name = b[offset:offset + length].decode('utf-16-be')
        offset += length + 1 + 16
        items.append((name, b[start:offset]))
    return orientation, items, b[begin:offset]


assert b[:9] == bytes.fromhex('000000ff00000000fd')
count = integer()
areas = []
for _ in range(count):
    area, width, height = integer(), integer(), integer()
    orientation, items, raw = sequence()
    areas.append([area, width, height, orientation, items, raw])
tail = b[offset:]
target = '聖書操作_extraBrowser'
found = [raw for area in areas for name, raw in area[4] if name == target]
assert len(found) == 1
bottom = next(a for a in areas if a[0] == 3)
assert all(name != target for name, _ in bottom[4]), 'すでに下側にあります'
kept = []
for area in areas:
    filtered = [(name, raw) for name, raw in area[4] if name != target]
    if not filtered:
        continue
    raw = b'\xfc' + bytes([area[3]]) + pack(len(filtered)) + b''.join(raw for _, raw in filtered)
    if area[0] == 3:
        name = target.encode('utf-16-be')
        dock = b'\xfb' + pack(len(name)) + name + b'\x01' + pack(0, 128, 80, 0xffffff)
        nested = b'\xfc' + pack(132, area[2], 244, 0xffffff) + raw
        raw = b'\xfc\x02' + pack(2) + dock + nested
        area[2] += 132
    kept.append(pack(*area[:3]) + raw)
result = b[:9] + pack(len(kept)) + b''.join(kept) + tail
backup = Path.home() / 'Desktop/AI関係/早天配信/設定控え' / ('user_before_bottom_' + datetime.now().strftime('%Y%m%d_%H%M%S') + '.ini')
shutil.copy2(p, backup)
replacement = base64.b64encode(result).decode()
p.write_text(s[:m.start(1)] + replacement + s[m.end(1):])
print('聖書操作を下部に固定。変更前の配置を保存:', backup.name)
