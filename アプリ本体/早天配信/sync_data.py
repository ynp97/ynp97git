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
    sync_web()


def sync_web():
    """画面（web）はVaultのアプリ本体が正本。表示ファイルだけなのでOBS起動中に差し替えてよい。"""
    source = VAULT / 'アプリ本体/早天配信/web'
    target = CACHE.parent / 'web'
    if not source.is_dir() or not target.is_dir():
        return
    count = 0
    for path in source.rglob('*'):
        if not path.is_file() or path.name.startswith('.'):
            continue
        dest = target / path.relative_to(source)
        if dest.exists() and dest.read_bytes() == path.read_bytes():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(dir=dest.parent)
        os.close(fd)
        try:
            shutil.copy2(path, temp)
            os.replace(temp, dest)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        count += 1
    thumbnail_source = VAULT / 'アプリ本体/早天サムネ'
    for name in ('index.html', 'passages.js', 'thumbnail.js'):
        path = thumbnail_source / name
        if not path.is_file():
            raise SystemExit('サムネ画面が見つかりません：' + str(path))
        dest = target / 'thumbnail' / name
        if dest.exists() and dest.read_bytes() == path.read_bytes():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(dir=dest.parent)
        os.close(fd)
        try:
            shutil.copy2(path, temp)
            os.replace(temp, dest)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        count += 1
    if count:
        print(f'画面を更新：{count}ファイル')

if __name__ == '__main__':
    sync()
