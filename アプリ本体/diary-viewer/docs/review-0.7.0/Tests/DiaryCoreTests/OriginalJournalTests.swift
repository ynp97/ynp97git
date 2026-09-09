import XCTest
@testable import DiaryCore

final class OriginalJournalTests: XCTestCase {
    private func document(_ newline: String = "\n") -> Data {
        Data([
            "---", "entries: 2", "custom: preserved", "---", "", "# 年別日記", "",
            "## 2026-09-07（月）6:04:03", "<!-- dayone-uuid: original-id -->", "", "> 本文の引用", "",
            "## 普通の見出し", "  絵文字😀と空白  ", "```markdown", "## 2026-09-01（火）1:00:00", "```", "",
            "## 2026-09-07（月）6:04:03", "<!-- diary-entry-id: 52450396-FC13-4429-A29B-BF06EFA3A443 -->", "", ""
        ].joined(separator: newline).utf8)
    }
    func testNoOpIsByteIdenticalIncludingCommentsAndMixedContent() throws {
        for newline in ["\n", "\r\n"] {
            let data = document(newline)
            let parsed = try OriginalJournal(data: data)
            XCTAssertEqual(parsed.blocks.count, 2)
            XCTAssertEqual(parsed.blocks[1].explicitID?.uuidString, "52450396-FC13-4429-A29B-BF06EFA3A443")
            let output = try parsed.replacingBlock(at: 0, with: parsed.blocks[0].data, expectedHash: contentHash(data))
            XCTAssertEqual(output, data)
            XCTAssertEqual(parsed.data, data)
        }
    }
    func testEditKeepsUnrelatedEntryAndHeaderExactly() throws {
        let parsed = try OriginalJournal(data: document())
        let replacement = Data(String(decoding: parsed.blocks[0].data, as: UTF8.self).replacingOccurrences(of: "絵文字😀", with: "変更した文字").utf8)
        let output = try parsed.replacingBlock(at: 0, with: replacement, expectedHash: contentHash(parsed.data))
        let changed = try OriginalJournal(data: output)
        XCTAssertEqual(changed.blocks[1].data, parsed.blocks[1].data)
        XCTAssertEqual(output.prefix(parsed.blocks[0].range.lowerBound), parsed.data.prefix(parsed.blocks[0].range.lowerBound))
    }
    func testMissingCountMismatchAndStaleHashBlockWriting() throws {
        let parsed = try OriginalJournal(data: document())
        XCTAssertThrowsError(try parsed.replacingBlock(at: 0, with: parsed.blocks[0].data, expectedHash: "stale"))
        let mismatch = Data(String(decoding: document(), as: UTF8.self).replacingOccurrences(of: "entries: 2", with: "entries: 3").utf8)
        XCTAssertThrowsError(try OriginalJournal(data: mismatch).validateForWriting())
        XCTAssertThrowsError(try OriginalJournal(data: Data("# no count".utf8)).validateForWriting())
        XCTAssertThrowsError(try parsed.replacingBlock(at: 0, with: Data(), expectedHash: contentHash(parsed.data)))
    }
    func testDuplicateIDsAndInvalidUTF8AreRejected() throws {
        let data = String(decoding: document(), as: UTF8.self).replacingOccurrences(of: "<!-- dayone-uuid: original-id -->", with: "<!-- diary-entry-id: 52450396-FC13-4429-A29B-BF06EFA3A443 -->")
        XCTAssertThrowsError(try OriginalJournal(data: Data(data.utf8)))
        XCTAssertThrowsError(try OriginalJournal(data: Data([0xff, 0xfe])))
    }
}
