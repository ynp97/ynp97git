#!/usr/bin/env python3
"""XCTestがないCommand Line Tools環境で、同じ同期テストのassertionを実行する。

swift testの代替エンジンではなく、このプロジェクトの同期assertion用の小さな実行器。
正本のテストは変更せず、一時コピーのimportとfixture参照のみ置換する。
未知のXCT APIが追加されたらコンパイルで失敗し、検査を黙って省略しない。
"""
from pathlib import Path
import os
import platform
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix="diary-portable-checks-"))
cache = Path(os.environ.get("DIARY_MODULE_CACHE", "/private/tmp/diary-viewer-build-0907/arm64-apple-macosx/debug/ModuleCache"))
cache.mkdir(parents=True, exist_ok=True)

shim = r'''
import Foundation
var failures = 0
enum CheckFailure: Error { case unwrap }
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line) \(message)")
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(); let b = try rhs(); if a != b { XCTFail("\(message) expected \(b), got \(a)", file: file, line: line) } }
    catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { XCTFail(message, file: file, line: line) } }
    catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(try !value(), message, file: file, line: line)
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { XCTFail(message, file: file, line: line) } }
    catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail("Expected error: \(message)", file: file, line: line) } catch {}
}
func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let result = try value() else { XCTFail(message, file: file, line: line); throw CheckFailure.unwrap }
    return result
}
'''
(work / "Assertions.swift").write_text(shim)
tests = sorted((root / "Tests").glob("*Tests/*Tests.swift"))
calls = []
for test in tests:
    source = test.read_text()
    suite = re.search(r"final class (\w+): XCTestCase", source)[1]
    methods = re.findall(r"^    func (test\w+)\(\)", source, re.M)
    source = source.replace("import XCTest\n", "import Foundation\n")
    source = re.sub(r"^@testable import \w+\n", "", source, flags=re.M)
    fixture_root = str(test.parent).replace("\\", "\\\\").replace('"', '\\"')
    source = source.replace("Bundle.module.resourceURL?", f'Optional(URL(fileURLWithPath: "{fixture_root}"))?')
    (work / test.name).write_text(source)
    for method in methods:
        calls.append(f'''do {{
    let before = failures
    let test = {suite}()
    do {{ try test.setUpWithError(); try test.{method}() }} catch {{ XCTFail("{suite}.{method}: \\(error)") }}
    do {{ try test.tearDownWithError() }} catch {{ XCTFail("cleanup: \\(error)") }}
    print("\\(failures == before ? "PASS" : "FAIL") {suite}.{method}")
}}''')
(work / "main.swift").write_text("import Foundation\n" + "\n".join(calls) + f'\nprint("{len(calls)} synchronous checks; \\(failures) failures (portable assertion runner, not XCTest).")\nexit(failures == 0 ? 0 : 1)\n')
sources = sorted((root / "Sources/DiaryCore").glob("*.swift"))
sources += [root / "Sources/DiaryViewer" / name for name in ["Entry.swift", "JournalParser.swift", "MarkdownText.swift"]]
sources += sorted(work.glob("*.swift"))
binary = work / "checks"
command = ["swiftc", "-swift-version", "5", "-target", f"{platform.machine()}-apple-macosx14.0", "-module-cache-path", str(cache)]
command += list(map(str, sources)) + ["-o", str(binary)]
print(f"Compiling {len(calls)} existing test methods into {binary}", flush=True)
subprocess.run(command, check=True)
subprocess.run([str(binary)], check=True)
