#!/usr/bin/env python3
"""Verify a backup before opening it. Read-only; usage: verify_backup.py BACKUP_DIR"""
from pathlib import Path, PurePosixPath
import hashlib, json, sys
root = Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'backup-manifest.json').read_text())['files']
for relative, expected in manifest.items():
    parts = PurePosixPath(relative)
    if parts.is_absolute() or '..' in parts.parts:
        raise SystemExit('Unsafe manifest path')
    path = root.joinpath(*parts.parts)
    if path.is_symlink() or root not in path.resolve().parents:
        raise SystemExit('Unsafe backup file')
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            size += len(chunk); digest.update(chunk)
    if size != expected['bytes'] or digest.hexdigest() != expected['sha256']:
        raise SystemExit('Mismatch: ' + relative)
actual = {'日記アプリデータ/library.sqlite'}
if (root / 'recovery-required.txt').exists(): actual.add('recovery-required.txt')
for folder in ['ジャーナル', 'journal', 'media', '日記アプリデータ/originals', '日記アプリデータ/operations', '日記アプリデータ/staging']:
    for path in (root / folder).rglob('*'):
        if path.is_symlink(): raise SystemExit('Symlink in backup')
        if path.is_file(): actual.add(path.relative_to(root).as_posix())
if actual != set(manifest): raise SystemExit('Backup file inventory differs from manifest')
print(f'Verified {len(manifest)} files, {sum(item["bytes"] for item in manifest.values())} bytes; no files modified.')
