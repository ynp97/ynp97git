#!/usr/bin/env python3
"""Separate-process persistence / SIGKILL / read-only real-journal verification.
Only temporary DBs are written; source Markdown is never modified.
"""
from pathlib import Path
import hashlib
import json
import select
import subprocess
import tempfile
import sys

base = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='diary-identity-'))
(work / 'main.swift').write_text(r'''
import Foundation
import Darwin
let mode = CommandLine.arguments[1]
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let source = URL(fileURLWithPath: CommandLine.arguments[3])
var files: [String: Data] = [:]
for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
    let name = file.deletingPathExtension().lastPathComponent
    guard file.pathExtension == "md", name.count == 4, Int(name) != nil else { continue }
    files[file.lastPathComponent] = try Data(contentsOf: file)
}
let library = try CaptureLibrary(root: root)
let ids = try library.journalIdentities(files: files) {
    if mode == "crash" {
        FileHandle.standardOutput.write(Data("READY\n".utf8)); raise(SIGSTOP)
    }
}
for (name, data) in files {
    let parsed = JournalParser.parse(fileContent: String(decoding: data, as: UTF8.self), year: Int(name.prefix(4))!, persistentIDs: ids[name])
    guard parsed.failure == nil, parsed.entries.map(\.id) == ids[name] else { fatalError("Parser identity mismatch") }
}
FileHandle.standardOutput.write(try JSONEncoder().encode(ids))
''')
sources = sorted((base / 'Sources/DiaryCore').glob('*.swift'))
sources += [base / 'Sources/DiaryViewer' / x for x in ['Entry.swift', 'JournalParser.swift']]
binary = work / 'identity-check'
subprocess.run(['swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', '/private/tmp/diary-viewer-build-0907/arm64-apple-macosx/debug/ModuleCache', *map(str, sources), str(work / 'main.swift'), '-o', str(binary)], check=True)
fixture = work / 'fixture'
fixture.mkdir()
a = '## 2026-01-01（木）1:00:00\n架空A\n\n'
(fixture / '2026.md').write_text(a)
root = work / 'db'
def run(source, target=root):
    return json.loads(subprocess.check_output([str(binary), 'read', str(target), str(source)], timeout=30))
first = run(fixture)
assert run(fixture) == first
(fixture / '2026.md').write_text(a + '## 2026-01-02（金）2:00:00\n架空B\n\n')
process = subprocess.Popen([str(binary), 'crash', str(root), str(fixture)], stdout=subprocess.PIPE)
try:
    assert select.select([process.stdout], [], [], 30)[0]
    assert process.stdout.readline().strip() == b'READY'
    process.kill(); process.wait(timeout=10)
finally:
    if process.poll() is None:
        process.kill(); process.wait(timeout=10)
(fixture / '2026.md').write_text(a)
assert run(fixture) == first
print('PASS: separate-process reopen and SIGKILL before COMMIT preserve previous IDs')
if len(sys.argv) > 1:
    source = Path(sys.argv[1])
    hashes = lambda: {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in source.glob('[0-9][0-9][0-9][0-9].md')}
    before = hashes()
    mapped = run(source, work / 'real-readonly-db')
    assert run(source, work / 'real-readonly-db') == mapped
    flat = [item for items in mapped.values() for item in items]
    assert len(flat) == len(set(flat))
    assert hashes() == before
    print(f'PASS: {len(mapped)} real year files, {len(flat)} distinct IDs, reopen equal, all source hashes unchanged; temporary DB only')
print('Temporary verification artifacts:', work)
