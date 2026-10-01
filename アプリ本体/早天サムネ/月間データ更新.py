"""Vaultの月間予定から、このアプリの読取用データを更新する。"""
import datetime as dt
import json
from pathlib import Path
import re

root = Path.home() / 'Documents/Obsidian Vault'
references = root / '.agents/skills/st97/references'
data = {}
for path in sorted(references.glob('20??-??.md')):
    for day, passage in re.findall(r'^\|\s*(\d{1,2})\s*\|\s*([^|]+)\|', path.read_text(), re.M):
        date = f'{path.stem}-{int(day):02d}'
        dt.date.fromisoformat(date)
        if date in data:
            raise ValueError(f'月間予定の日付が重複しています：{date}')
        data[date] = passage.strip()

if not data:
    raise ValueError('月間予定が見つかりません')

out = Path(__file__).resolve().parent
temporary = out / 'passages.js.tmp'
temporary.write_text('window.PASSAGES = ' + json.dumps(data, ensure_ascii=False, indent=2) + ';\n')
temporary.replace(out / 'passages.js')
print(f'{len(data)} days loaded')
