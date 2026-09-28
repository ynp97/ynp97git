#!/usr/bin/env python3
"""Refresh the service cache from the canonical Vault; never edit the originals."""
from pathlib import Path
import os
import shutil
import tempfile

VAULT = Path.home() / 'Documents/Obsidian Vault'
CACHE = Path.home() / 'Library/Application Support/SotenBroadcast/vault'

def sync():
    count = 0
    for relative in ('聖書（新改訳2017）', '.agents/skills/st97/references'):
        source = VAULT / relative
        if not source.is_dir():
            raise SystemExit('正本が見つかりません：' + str(source))
        target = CACHE / relative
        target.mkdir(parents=True, exist_ok=True)
        for path in source.glob('*.md'):
            dest = target / path.name
            if dest.exists() and dest.read_bytes() == path.read_bytes():
                continue
            fd, temp = tempfile.mkstemp(dir=target)
            os.close(fd)
            try:
                shutil.copy2(path, temp)
                os.replace(temp, dest)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
            count += 1
    print(f'正本から更新：{count}ファイル')

if __name__ == '__main__':
    sync()
