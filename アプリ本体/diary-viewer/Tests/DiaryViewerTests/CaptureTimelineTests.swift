import XCTest
@testable import DiaryViewer
#if canImport(DiaryCore)
import DiaryCore
#endif

final class CaptureTimelineTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureTimelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testUndatedTextWaitsInInboxAndOriginalSurvivesProjection() throws {
        let library = try CaptureLibrary(root: root)
        let raw = "  <!-- 原文コメント -->\r\n## 2020-01-01\r\n> これはメタ情報ではない\r\n![[まだ添付していない.jpg]]\r\n#映画  "
        let item = try library.capture(text: raw, date: nil)
        XCTAssertNil(Entry.fromCapture(item))
        try library.setDate("2027-01-01", for: item.id, expectedRevision: 1)
        let entry = try XCTUnwrap(Entry.fromCapture(XCTUnwrap(library.captures().first)))
        XCTAssertEqual(entry.body, raw)
        XCTAssertEqual(entry.displayBody, raw)
        XCTAssertEqual(entry.year, 2027)
        XCTAssertEqual(entry.weekday, "金")
        XCTAssertEqual(entry.time, "")
        XCTAssertEqual(entry.attachments, [])
        XCTAssertTrue(entry.tags.contains("#映画"))
        XCTAssertEqual(entry.id, item.id)
    }

    func testDateMovesAcrossYearsWithSameIDAndCanBecomeUndated() throws {
        let library = try CaptureLibrary(root: root)
        let item = try library.capture(text: "年を移す原文", date: "2026-12-31")
        let first = try XCTUnwrap(Entry.fromCapture(item))
        try library.setDate("2027-01-01", for: item.id, expectedRevision: 1)
        let moved = try XCTUnwrap(Entry.fromCapture(XCTUnwrap(library.captures().first)))
        XCTAssertEqual(first.id, moved.id)
        XCTAssertFalse(first == moved)
        XCTAssertEqual(moved.year, 2027)
        XCTAssertEqual(moved.displayDateShort, "1.1")
        try library.setDate(nil, for: item.id, expectedRevision: 2)
        XCTAssertEqual(try library.captures().compactMap(Entry.fromCapture).count, 0)
        XCTAssertEqual(try library.captures().first?.text, item.text)
    }

    func testSameDaySeparateTextsAndReopenKeepDistinctStableIDs() throws {
        let library = try CaptureLibrary(root: root)
        let a = try library.capture(text: "同じ文章", date: "2026-09-08")
        let b = try library.capture(text: "同じ文章", date: "2026-09-08")
        XCTAssertFalse(a.id == b.id)
        let before = try library.captures().compactMap(Entry.fromCapture)
        let after = try CaptureLibrary(root: root).captures().compactMap(Entry.fromCapture)
        XCTAssertEqual(Set(before.map(\.id)), Set(after.map(\.id)))
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.map(\.body), ["同じ文章", "同じ文章"])
    }

    func testAdoptedMarkdownKeepsOriginalAndAppearsOnceAfterRestart() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let raw = "\r\n<!-- コメント -->\n> 引用\n## 2020-01-01（水）1:00:00\n`````\n![[未添付.jpg]]\n#映画  \r\n"
        let item = try library.capture(text: raw, date: "2027-01-01")
        try library.adopt(item.id, expectedRevision: 1)
        let content = try String(contentsOf: root.appendingPathComponent("ジャーナル/2027.md"), encoding: .utf8)
        let parsed = JournalParser.parse(fileContent: content, year: 2027)
        XCTAssertNil(parsed.failure)
        XCTAssertEqual(parsed.entries.count, 1)
        let entry = try XCTUnwrap(parsed.entries.first)
        XCTAssertEqual(entry.body, raw)
        XCTAssertEqual(entry.displayBody, raw)
        XCTAssertEqual(entry.id, item.id)
        XCTAssertEqual(entry.time, "")
        XCTAssertNil(entry.weather)
        XCTAssertEqual(entry.attachments, [])
        XCTAssertFalse(entry.isCapture)
        let reopened = try CaptureLibrary(root: root)
        let merged = Entry.merge(journals: parsed.entries, captures: try reopened.captures())
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].tags.contains("#映画"))
        // DB確定前にMarkdownだけ見えていても、永続IDで二重表示しない。
        XCTAssertEqual(Entry.merge(journals: parsed.entries, captures: [item]).count, 1)
        // 採用後に年別ファイルが消えても、原文を正本として黙って復活させない。
        XCTAssertEqual(Entry.merge(journals: [], captures: try reopened.captures()).count, 0)
        XCTAssertEqual(JournalParser.parse(fileContent: content, year: 2027).entries[0].id, item.id)
    }

    func testLegacyFencedHeadingAndExplicitIdentityArePreserved() throws {
        let id = UUID()
        let content = "---\nentries: 1\n---\n## 2026-09-08（火）1:02:03\n<!-- diary-entry-id: \(id.uuidString) -->\n> 晴れ｜場所\n\n本文\n```md\n## 2020-01-01（水）1:00:00\n```\n"
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, id)
        XCTAssertEqual(result.entries[0].weather, "晴れ")
        XCTAssertTrue(result.entries[0].body.contains("2020-01-01"))
    }
}
