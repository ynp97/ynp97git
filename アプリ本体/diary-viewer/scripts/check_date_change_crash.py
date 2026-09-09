#!/usr/bin/env python3
"""Kill a fictional-library writer at each cross-year save boundary, then reopen it.

This checks process termination, not power loss or concurrent external editor writes.
"""
from pathlib import Path
import os
import subprocess
import tempfile

base = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='diary-date-change-crash-'))
(work / 'main.swift').write_text(r'''
import Foundation
import Darwin
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let raw = "  Fictional original\r\n> quote\n#test  "
if CommandLine.arguments[1] == "crash" {
    let library = try CaptureLibrary(root: root, allowJournalWrites: true)
    let item = try library.capture(text: raw, date: "2026-12-31")
    try library.adopt(item.id, expectedRevision: 1)
    let stage = CommandLine.arguments[3]
    try library.setDate("2027-01-01", for: item.id, expectedRevision: 1) { current in
        if String(describing: current) == stage {
            FileHandle.standardOutput.write(Data("READY\n".utf8))
            raise(SIGSTOP)
        }
    }
    fatalError("Crash hook was not reached")
} else {
    let library = try CaptureLibrary(root: root, allowJournalWrites: true)
    let items = try library.captures()
    guard items.count == 1 else { fatalError("Duplicate capture") }
    let item = items[0]
    guard item.revision == 2, item.journalDate == "2027-01-01", item.text == raw, item.adopted else { fatalError("Capture mismatch") }
    try library.setDate("2027-01-01", for: item.id, expectedRevision: 1)
    let old = try OriginalJournal(data: Data(contentsOf: root.appendingPathComponent("ジャーナル/2026.md")))
    let new = try OriginalJournal(data: Data(contentsOf: root.appendingPathComponent("ジャーナル/2027.md")))
    try old.validateForWriting(); try new.validateForWriting()
    guard old.blocks.isEmpty, new.blocks.count == 1, new.blocks[0].explicitID == item.id,
          try PlainJournalRecord.decode(new.blocks[0].data)?.text == raw else { fatalError("Journal mismatch") }
    print("Recovered once: revision 2, stable UUID, exact original, source 0 / target 1")
}
''')
binary = work / 'crash-check'
sources = sorted((base / 'Sources/DiaryCore').glob('*.swift'))
subprocess.run(['swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', '/private/tmp/diary-viewer-build-0907/arm64-apple-macosx/debug/ModuleCache', *map(str, sources), str(work / 'main.swift'), '-o', str(binary)], check=True)
for stage in ['prepared', 'fileWritten(0)', 'fileWritten(1)', 'committed']:
    root = work / stage
    process = subprocess.Popen([str(binary), 'crash', str(root), stage], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        # A bounded select prevents a regression from leaving the check hung.
        import select
        readable, _, _ = select.select([process.stdout], [], [], 30)
        if not readable or process.stdout.readline().strip() != 'READY':
            raise RuntimeError(f'Crash boundary not reached: {stage}')
        process.kill()
        process.wait(timeout=10)
        result = subprocess.run([str(binary), 'recover', str(root)], capture_output=True, text=True, timeout=30, check=True)
        print(f'PASS SIGKILL at {stage}: {result.stdout.strip()}', flush=True)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
print('4 process-kill recovery checks passed; fictional libraries only.')
