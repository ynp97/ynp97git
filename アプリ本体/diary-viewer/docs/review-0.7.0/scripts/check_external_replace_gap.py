#!/usr/bin/env python3
"""Exercise the real save/recovery path with a deterministic race or SIGKILL.
Only a temporary source copy is instrumented, and all data is fictional.
"""
from pathlib import Path
import os, select, sqlite3, subprocess, tempfile
base = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='diary-replace-gap-'))
for source in (base / 'Sources/DiaryCore').glob('*.swift'):
    text = source.read_text()
    if source.name == 'GuardedJournalWrite.swift':
        needle = '        let flags = before == "missing"'
        assert text.count(needle) == 1
        text = text.replace(needle, '''        if ProcessInfo.processInfo.environment["DIARY_GAP_TEST"] == "race" {
            try Data("EXTERNAL_EDIT_AT_REPLACE\\n".utf8).write(to: target, options: .atomic)
        }
''' + needle)
        needle = '        try syncDirectory(target.deletingLastPathComponent())'
        assert text.count(needle) == 1
        text = text.replace(needle, '''        if ProcessInfo.processInfo.environment["DIARY_GAP_TEST"] == "kill" {
            FileHandle.standardOutput.write(Data("READY\\n".utf8)); raise(SIGSTOP)
        }
''' + needle)
    (work / source.name).write_text(text)
(work / 'main.swift').write_text(r'''
import Foundation
let mode = CommandLine.arguments[1]
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let library = try CaptureLibrary(root: root, allowJournalWrites: true)
if mode == "seed" {
    _ = try library.capture(text: "架空の新規日記", date: "2026-02-01")
} else if mode == "write" {
    let item = try library.captures()[0]
    do {
        try library.adopt(item.id, expectedRevision: 1)
        fatalError("Expected injected conflict")
    } catch { print("PASS: save stopped on injected conflict: \(error)") }
} else if mode == "blocked" {
    fatalError("Pending conflict was incorrectly accepted on reopen")
} else if mode == "inspect" {
    guard library.recoveryIssue != nil, !library.canWrite else { fatalError("Expected degraded mode") }
    let original = try library.capturesForInspection()
    guard original.count == 1, original[0].savePending, original[0].text == "架空の新規日記" else { fatalError("Inspection lost original or pending state") }
    try library.rescueBackup(to: root.appendingPathComponent("rescue"))
    print("PASS: conflict permits original inspection and rescue without committing")
} else if mode == "recover" {
    let items = try library.captures()
    guard items.count == 1, items[0].adopted else { fatalError("Recovery failed") }
    let file = root.appendingPathComponent("ジャーナル/2026.md")
    let journal = try OriginalJournal(data: Data(contentsOf: file))
    guard journal.blocks.filter({ $0.explicitID == items[0].id }).count == 1 else { fatalError("Duplicate") }
    try library.backup(to: root.appendingPathComponent("backups/full"))
    print("PASS: recovered once and created full backup")
}
'''.replace('let library = try CaptureLibrary(root: root, allowJournalWrites: true)', '''let library: CaptureLibrary
 do { library = try CaptureLibrary(root: root, allowJournalWrites: true, tolerateRecoveryFailure: mode == "inspect") }
 catch { if mode == "blocked" { print("PASS: reopen remains blocked"); exit(0) }; throw error }'''))
binary = work / 'gap'
subprocess.run(['swiftc', '-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path','/private/tmp/diary-viewer-build-0907/arm64-apple-macosx/debug/ModuleCache',*map(str,work.glob('*.swift')),'-o',str(binary)], check=True)
for scenario in ['existing', 'new', 'kill']:
    root = work / scenario
    journal = root / 'ジャーナル'
    journal.mkdir(parents=True)
    target = journal / '2026.md'
    original = '---\nentries: 1\n---\n## 2026-01-01（木）1:00:00\n架空の旧日記\n\n'.encode()
    if scenario != 'new': target.write_bytes(original)
    media = root / 'media'
    media.mkdir()
    (media / 'fixture.jpg').write_bytes(b'fictional-photo-bytes')
    (media / 'fixture.mov').write_bytes(b'fictional-video-bytes' * 100000)
    subprocess.run([str(binary), 'seed', str(root)], check=True)
    env = dict(os.environ, DIARY_GAP_TEST='kill' if scenario == 'kill' else 'race')
    if scenario == 'kill':
        process = subprocess.Popen([str(binary), 'write', str(root)], env=env, stdout=subprocess.PIPE)
        try:
            assert select.select([process.stdout], [], [], 30)[0]
            assert process.stdout.readline().strip() == b'READY'
            process.kill(); process.wait(timeout=10)
        finally:
            if process.poll() is None: process.kill(); process.wait(timeout=10)
        subprocess.run([str(binary), 'recover', str(root)], check=True)
        subprocess.run(['python3', str(base / 'scripts/verify_backup.py'), str(root / 'backups/full')], check=True)
        assert next((root / '日記アプリデータ/operations').glob('*/exchanged.md')).read_bytes() == original
    else:
        subprocess.run([str(binary), 'write', str(root)], env=env, check=True)
        subprocess.run([str(binary), 'blocked', str(root)], check=True)
        subprocess.run([str(binary), 'inspect', str(root)], check=True)
        subprocess.run(['python3', str(base / 'scripts/verify_backup.py'), str(root / 'rescue')], check=True)
        preserved = target if scenario == 'new' else next((root / '日記アプリデータ/operations').glob('*/exchanged.md'))
        assert preserved.read_bytes() == b'EXTERNAL_EDIT_AT_REPLACE\n'
        with sqlite3.connect(root / '日記アプリデータ/library.sqlite') as db:
            assert db.execute("select count(*) from adoptions where phase='pending'").fetchone()[0] == 1
    print('PASS:', scenario, flush=True)
print('Verification artifacts:',work)
