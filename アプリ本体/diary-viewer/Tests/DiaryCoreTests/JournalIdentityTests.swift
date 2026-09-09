import XCTest
@testable import DiaryCore

final class JournalIdentityTests: XCTestCase {
    private var root: URL!
    private let a = "## 2026-01-01（木）1:00:00\n\n原文A 😀\n\n"
    private let b = "## 2026-01-02（金）2:00:00\n\n原文B\n\n"
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("IdentityTests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func files(_ body: String) -> [String: Data] { ["2026.md": Data(body.utf8)] }

    func testReopenAndBackupPreserveIDsWithoutChangingMarkdown() throws {
        let original = Data((a + b).utf8)
        let path = root.appendingPathComponent("ジャーナル/2026.md")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: path)
        let ids = try CaptureLibrary(root: root).journalIdentities(files: files(a + b))
        XCTAssertEqual(try CaptureLibrary(root: root).journalIdentities(files: files(a + b)), ids)
        let backup = root.appendingPathComponent("backup")
        try CaptureLibrary(root: root).backup(to: backup)
        XCTAssertEqual(try CaptureLibrary(root: backup).journalIdentities(files: files(a + b)), ids)
        XCTAssertEqual(try Data(contentsOf: path), original)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("ジャーナル/2026.md")), original)
    }

    func testReorderInsertAndFileMovePreserveUniqueOriginalIDs() throws {
        let library = try CaptureLibrary(root: root)
        let first = try library.journalIdentities(files: files(a + b))["2026.md"]!
        let reordered = try library.journalIdentities(files: files(b + a))["2026.md"]!
        XCTAssertEqual(reordered, first.reversed().map { $0 })
        let moved = try library.journalIdentities(files: ["2025.md": Data(a.utf8), "2026.md": Data(b.utf8)])
        XCTAssertEqual(moved["2025.md"], [first[0]])
        XCTAssertEqual(moved["2026.md"], [first[1]])
        let added = try library.journalIdentities(files: ["2025.md": Data(a.utf8), "2026.md": Data((b + "## 2026-03-01（日）3:00:00\n新規\n").utf8)])
        XCTAssertEqual(added["2026.md"]?.first, first[1])
        XCTAssertEqual(added["2026.md"]?.count, 2)
    }

    func testExternalBodyOrDateEditStopsWithoutReplacingMap() throws {
        let library = try CaptureLibrary(root: root)
        let first = try library.journalIdentities(files: files(a + b))
        XCTAssertThrowsError(try library.journalIdentities(files: files(a.replacingOccurrences(of: "原文A", with: "訂正A") + b)))
        XCTAssertThrowsError(try library.journalIdentities(files: files(a.replacingOccurrences(of: "01-01", with: "01-03") + b)))
        XCTAssertEqual(try CaptureLibrary(root: root).journalIdentities(files: files(a + b)), first)
    }

    func testIdenticalDuplicatesSurviveReopenButChangedFileIsAmbiguous() throws {
        let library = try CaptureLibrary(root: root)
        let first = try library.journalIdentities(files: files(a + a))
        XCTAssertEqual(Set(first["2026.md"]!).count, 2)
        XCTAssertEqual(try CaptureLibrary(root: root).journalIdentities(files: files(a + a)), first)
        XCTAssertThrowsError(try library.journalIdentities(files: files(b + a + a)))
        XCTAssertEqual(try library.journalIdentities(files: files(a + a)), first)
    }

    func testExplicitIDsAndCrossYearDuplicates() throws {
        let library = try CaptureLibrary(root: root)
        let id = UUID()
        let record = "## 2026-01-01（木）1:00:00\n<!-- diary-entry-id: \(id.uuidString) -->\n原文\n"
        XCTAssertEqual(try library.journalIdentities(files: files(record))["2026.md"], [id])
        XCTAssertThrowsError(try library.journalIdentities(files: ["2026.md": Data(record.utf8), "2027.md": Data(record.utf8)]))
        XCTAssertEqual(try library.journalIdentities(files: files(record))["2026.md"], [id])
    }

    func testInterruptedTransactionRollsBackAllFiles() throws {
        enum Stop: Error { case now }
        let library = try CaptureLibrary(root: root)
        let first = try library.journalIdentities(files: files(a))
        XCTAssertThrowsError(try library.journalIdentities(files: files(a + b)) { throw Stop.now })
        XCTAssertEqual(try CaptureLibrary(root: root).journalIdentities(files: files(a)), first)
        XCTAssertEqual(try library.journalIdentities(files: files(a + b))["2026.md"]?.first, first["2026.md"]?.first)
    }
}
