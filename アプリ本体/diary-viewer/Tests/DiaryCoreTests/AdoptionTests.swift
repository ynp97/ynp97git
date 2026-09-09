import XCTest
import SQLite3
@testable import DiaryCore

final class AdoptionTests: XCTestCase {
    private var root: URL!
    private let original = Data("---\r\nentries: 1\r\ncustom: 保持\r\n---\r\n\r\n# 既存\r\n\r\n## 2026-01-01（木）1:02:03\r\n<!-- dayone-uuid: existing -->\r\n\r\n> 引用\r\n  本文😀  ".utf8)
    private let raw = " \r\n<!-- 原文コメント -->\r\n> 天気ではない引用\r\n## 2020-01-01（水）1:00:00\n````text\n例\n````\n![[未添付.jpg]]\n#映画  \r\n"
    private enum Stop: Error { case now }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AdoptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ジャーナル"), withIntermediateDirectories: true)
        try original.write(to: file("2026"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func file(_ year: String) -> URL { root.appendingPathComponent("ジャーナル/\(year).md") }

    func testAdoptionPreservesExistingBytesRawAndStableID() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: "2026-09-08")
        try library.adopt(item.id, expectedRevision: 1)
        let data = try Data(contentsOf: file("2026"))
        let document = try OriginalJournal(data: data)
        XCTAssertEqual(document.expectedCount, 2)
        XCTAssertEqual(document.blocks[1].data, try OriginalJournal(data: original).blocks[0].data)
        let record = try XCTUnwrap(PlainJournalRecord.decode(document.blocks[0].data))
        XCTAssertEqual(Data(record.text.utf8), Data(raw.utf8))
        XCTAssertEqual(record.id, item.id)
        XCTAssertEqual(record.day, "2026-09-08")
        XCTAssertTrue(try library.captures()[0].adopted)
        XCTAssertEqual(try library.captures()[0].text, raw)
        try library.adopt(item.id, expectedRevision: 1)
        XCTAssertEqual(try Data(contentsOf: file("2026")), data)
        XCTAssertThrowsError(try CaptureLibrary(root: root).setDate("2027-01-01", for: item.id, expectedRevision: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("バックアップ").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("日記アプリデータ/operations/\(item.id.uuidString)/before.md")), original)
    }

    func testEveryInterruptionRecoversOnceForExistingAndNewYears() throws {
        for year in ["2026", "2027"] {
            for stage in [CaptureLibrary.AdoptionStage.prepared, .journalWritten, .committed] {
                let library = try CaptureLibrary(root: root, allowJournalWrites: true)
                let item = try library.capture(text: raw, date: "\(year)-09-08")
                let before = FileManager.default.fileExists(atPath: file(year).path) ? try OriginalJournal(data: Data(contentsOf: file(year))).blocks.count : 0
                XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1) { if $0 == stage { throw Stop.now } })
                let reopened = try CaptureLibrary(root: root, allowJournalWrites: true)
                try reopened.adopt(item.id, expectedRevision: 1)
                let journal = try OriginalJournal(data: Data(contentsOf: file(year)))
                XCTAssertEqual(journal.blocks.count, before + 1)
                XCTAssertEqual(journal.blocks.filter { $0.explicitID == item.id }.count, 1)
                XCTAssertTrue(try reopened.captures().first { $0.id == item.id }!.adopted)
            }
        }
    }

    func testExternalEditAfterPrepareOrWriteIsNeverReplaced() throws {
        for stage in [CaptureLibrary.AdoptionStage.prepared, .journalWritten] {
            let isolated = root.appendingPathComponent(UUID().uuidString)
            let library = try CaptureLibrary(root: isolated, allowJournalWrites: true)
            let item = try library.capture(text: raw, date: "2027-01-01")
            XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1) { if $0 == stage { throw Stop.now } })
            let target = isolated.appendingPathComponent("ジャーナル/2027.md")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let external = Data("外部で編集した内容\n".utf8)
            try external.write(to: target)
            XCTAssertThrowsError(try CaptureLibrary(root: isolated, allowJournalWrites: true))
            XCTAssertEqual(try Data(contentsOf: target), external)
            XCTAssertEqual(try CaptureLibrary(root: isolated, readOnly: true).capturesForInspection()[0].text, raw)
        }
    }

    func testBackupRestoresAdoptedMarkdownAndIndependentOriginals() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: "2027-01-01")
        try library.adopt(item.id, expectedRevision: 1)
        let destination = root.appendingPathComponent("復元用")
        try library.backup(to: destination)
        let copy = try CaptureLibrary(root: destination, allowJournalWrites: true)
        XCTAssertEqual(try copy.captures()[0].id, item.id)
        XCTAssertTrue(try copy.captures()[0].adopted)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("ジャーナル/2027.md")), try Data(contentsOf: file("2027")))
        let another = try library.capture(text: "その後の追加", date: "2027-01-02")
        try library.adopt(another.id, expectedRevision: 1)
        XCTAssertEqual(try copy.captures().count, 1)
        XCTAssertEqual(try OriginalJournal(data: Data(contentsOf: destination.appendingPathComponent("ジャーナル/2027.md"))).blocks.count, 1)
    }

    func testUndatedStaleRevisionDisabledAndCountMismatchRejectWrites() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: nil)
        XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1))
        try library.setDate("2026-09-08", for: item.id, expectedRevision: 1)
        XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1))
        XCTAssertThrowsError(try CaptureLibrary(root: root).adopt(item.id, expectedRevision: 2))
        XCTAssertEqual(try Data(contentsOf: file("2026")), original)
        let invalid = Data("---\nentries: 7\n---\n".utf8)
        try invalid.write(to: file("2026"))
        XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 2))
        XCTAssertEqual(try Data(contentsOf: file("2026")), invalid)
    }

    func testSameTextSeparateCapturesStaySeparateAndOldSchemaMigrates() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let a = try library.capture(text: raw, date: "2026-09-08")
        let b = try library.capture(text: raw, date: "2026-09-08")
        try library.adopt(a.id, expectedRevision: 1)
        try library.adopt(b.id, expectedRevision: 1)
        XCTAssertEqual(try OriginalJournal(data: Data(contentsOf: file("2026"))).blocks.count, 3)
        let oldRoot = root.appendingPathComponent("old")
        let old = try CaptureLibrary(root: oldRoot)
        let oldCapture = try old.capture(text: raw, date: nil)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(oldRoot.appendingPathComponent("日記アプリデータ/library.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE adoptions; PRAGMA user_version=1", nil, nil, nil), SQLITE_OK)
        let migrated = try CaptureLibrary(root: oldRoot, migrationBackup: oldRoot.appendingPathComponent("旧形式の退避"))
        XCTAssertEqual(try migrated.captures()[0].id, oldCapture.id)
        XCTAssertEqual(try migrated.captures()[0].text, raw)
    }

    func testSymlinkAndDamagedStagingCannotOverwriteJournal() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: "2026-09-08")
        XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1) { if $0 == .prepared { throw Stop.now } })
        try Data("破損".utf8).write(to: root.appendingPathComponent("日記アプリデータ/operations/\(item.id.uuidString)/after.md"))
        XCTAssertThrowsError(try CaptureLibrary(root: root, allowJournalWrites: true))
        XCTAssertEqual(try Data(contentsOf: file("2026")), original)
        let other = root.appendingPathComponent("symlink")
        let linked = try CaptureLibrary(root: other, allowJournalWrites: true)
        let entry = try linked.capture(text: raw, date: "2026-01-01")
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("ジャーナル"), withDestinationURL: root.appendingPathComponent("ジャーナル"))
        XCTAssertThrowsError(try linked.adopt(entry.id, expectedRevision: 1))
        XCTAssertEqual(try Data(contentsOf: file("2026")), original)
    }

    func testMissingAdoptedMarkdownBlocksBackupAndSuccessfulRetryReport() throws {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: "2027-01-01")
        try library.adopt(item.id, expectedRevision: 1)
        try FileManager.default.removeItem(at: file("2027"))
        let destination = root.appendingPathComponent("不完全バックアップ")
        XCTAssertThrowsError(try library.backup(to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertThrowsError(try library.adopt(item.id, expectedRevision: 1))
        XCTAssertEqual(try library.captures()[0].text, raw)
    }
}
