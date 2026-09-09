import XCTest
@testable import DiaryCore

final class DateChangeTests: XCTestCase {
    private var root: URL!
    private let raw = "  原文😀\r\n<!-- コメント -->\n> 引用\n## 2020-01-01（水）1:00:00\n```\n#映画  "
    private enum Stop: Error { case now }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DateChangeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func file(_ root: URL, _ year: String) -> URL { root.appendingPathComponent("ジャーナル/\(year).md") }
    private func records(_ root: URL, _ year: String) throws -> [OriginalJournal.Block] {
        try OriginalJournal(data: Data(contentsOf: file(root, year))).blocks
    }
    private func seed(_ root: URL) throws -> (CaptureLibrary, Capture) {
        let library = try CaptureLibrary(root: root, allowJournalWrites: true)
        let item = try library.capture(text: raw, date: "2026-12-31")
        try library.adopt(item.id, expectedRevision: 1)
        return (library, item)
    }

    func testDateCorrectionYearMoveUndatedAndReadoptionKeepIdentityAndRaw() throws {
        let (library, item) = try seed(root)
        let other = try library.capture(text: "同じ年の別本文\r\n末尾なし", date: "2026-01-01")
        try library.adopt(other.id, expectedRevision: 1)
        let otherBlock = try XCTUnwrap(records(root, "2026").first { $0.explicitID == other.id }).data
        try library.setDate("2026-12-30", for: item.id, expectedRevision: 1)
        XCTAssertEqual(try library.captures().first { $0.id == item.id }?.revision, 2)
        try library.setDate("2027-01-01", for: item.id, expectedRevision: 2)
        XCTAssertEqual(try records(root, "2026").count, 1)
        XCTAssertEqual(try records(root, "2026")[0].data, otherBlock)
        let moved = try XCTUnwrap(PlainJournalRecord.decode(records(root, "2027")[0].data))
        XCTAssertEqual(moved.id, item.id)
        XCTAssertEqual(moved.text, raw)
        XCTAssertEqual(moved.day, "2027-01-01")
        try library.setDate(nil, for: item.id, expectedRevision: 3)
        XCTAssertEqual(try records(root, "2027").count, 0)
        let inbox = try XCTUnwrap(library.captures().first { $0.id == item.id })
        XCTAssertFalse(inbox.adopted)
        XCTAssertNil(inbox.journalDate)
        XCTAssertEqual(inbox.text, raw)
        try library.setDate("2028-02-29", for: item.id, expectedRevision: 4)
        try library.adopt(item.id, expectedRevision: 5)
        XCTAssertEqual(try records(root, "2028")[0].explicitID, item.id)
        XCTAssertEqual(try records(root, "2026")[0].data, otherBlock)
    }

    func testCrossYearMoveRecoversAtEachStageExactlyOnce() throws {
        for existingTarget in [false, true] {
            for stage in [CaptureLibrary.DateChangeStage.prepared, .fileWritten(0), .fileWritten(1), .committed] {
                let isolated = root.appendingPathComponent(UUID().uuidString)
                let (library, item) = try seed(isolated)
                var otherBlock: Data?
                if existingTarget {
                    let other = try library.capture(text: "移動先の既存日記", date: "2027-06-01")
                    try library.adopt(other.id, expectedRevision: 1)
                    otherBlock = try records(isolated, "2027")[0].data
                }
                XCTAssertThrowsError(try library.setDate("2027-01-01", for: item.id, expectedRevision: 1) { if $0 == stage { throw Stop.now } })
                let reopened = try CaptureLibrary(root: isolated, allowJournalWrites: true)
                try reopened.setDate("2027-01-01", for: item.id, expectedRevision: 1)
                XCTAssertEqual(try records(isolated, "2026").count, 0)
                let target = try records(isolated, "2027")
                XCTAssertEqual(target.filter { $0.explicitID == item.id }.count, 1)
                if let otherBlock { XCTAssertEqual(target.last?.data, otherBlock) }
                let current = try XCTUnwrap(reopened.captures().first { $0.id == item.id })
                XCTAssertEqual(current.revision, 2)
                XCTAssertEqual(current.journalDate, "2027-01-01")
                XCTAssertEqual(current.text, raw)
            }
        }
    }

    func testSameYearAndUndatedRecoverAtEveryApplicableStage() throws {
        for date: String? in ["2026-11-01", nil] {
            for stage in [CaptureLibrary.DateChangeStage.prepared, .fileWritten(0), .committed] {
                let isolated = root.appendingPathComponent(UUID().uuidString)
                let (library, item) = try seed(isolated)
                XCTAssertThrowsError(try library.setDate(date, for: item.id, expectedRevision: 1) { if $0 == stage { throw Stop.now } })
                let reopened = try CaptureLibrary(root: isolated, allowJournalWrites: true)
                try reopened.setDate(date, for: item.id, expectedRevision: 1)
                let current = try XCTUnwrap(reopened.captures().first)
                XCTAssertEqual(current.revision, 2)
                XCTAssertEqual(current.adopted, date != nil)
                XCTAssertEqual(current.journalDate, date)
                XCTAssertEqual(try records(isolated, "2026").count, date == nil ? 0 : 1)
            }
        }
    }

    func testConflictBeforeAnyWriteAndAfterFirstWritePreservesExternalData() throws {
        for stage in [CaptureLibrary.DateChangeStage.prepared, .fileWritten(0)] {
            let isolated = root.appendingPathComponent(UUID().uuidString)
            let (library, item) = try seed(isolated)
            XCTAssertThrowsError(try library.setDate("2027-01-01", for: item.id, expectedRevision: 1) { if $0 == stage { throw Stop.now } })
            let external = Data("外部編集\n".utf8)
            try external.write(to: file(isolated, "2026"))
            XCTAssertThrowsError(try CaptureLibrary(root: isolated, allowJournalWrites: true))
            XCTAssertEqual(try Data(contentsOf: file(isolated, "2026")), external)
            XCTAssertThrowsError(try CaptureLibrary(root: isolated))
        }
    }

    func testMissingStagingDoesNotStartTheOtherFileAndBackupRefusesPending() throws {
        let (library, item) = try seed(root)
        let old = try Data(contentsOf: file(root, "2026"))
        XCTAssertThrowsError(try library.setDate("2027-01-01", for: item.id, expectedRevision: 1) { if $0 == .prepared { throw Stop.now } })
        let operations = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("日記アプリデータ/operations"), includingPropertiesForKeys: nil)
        let operation = try XCTUnwrap(operations.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("2026-after.md").path) })
        try FileManager.default.removeItem(at: operation.appendingPathComponent("2026-after.md"))
        XCTAssertThrowsError(try CaptureLibrary(root: root, allowJournalWrites: true))
        XCTAssertThrowsError(try library.backup(to: root.appendingPathComponent("bad-backup")))
        XCTAssertEqual(try Data(contentsOf: file(root, "2026")), old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, "2027").path))
    }

    func testExternalBodyEditSurvivesMoveAndBlocksUndatedReturn() throws {
        let (library, item) = try seed(root)
        let journal = try String(contentsOf: file(root, "2026"), encoding: .utf8)
        try journal.replacingOccurrences(of: "原文😀", with: "本人が加筆😀").write(to: file(root, "2026"), atomically: true, encoding: .utf8)
        try library.setDate("2027-01-01", for: item.id, expectedRevision: 1)
        XCTAssertTrue(try PlainJournalRecord.decode(records(root, "2027")[0].data)!.text.contains("本人が加筆😀"))
        XCTAssertThrowsError(try library.setDate(nil, for: item.id, expectedRevision: 2))
        XCTAssertEqual(try library.captures()[0].text, raw)
    }

    func testMoveBackupRestoresOriginalDateAndCompletedBackupRestoresNewDate() throws {
        let (library, item) = try seed(root)
        try library.setDate("2027-01-01", for: item.id, expectedRevision: 1)
        let before = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("バックアップ/日付変更前"), includingPropertiesForKeys: nil).first)
        let old = try CaptureLibrary(root: before, allowJournalWrites: true)
        XCTAssertEqual(try old.captures()[0].journalDate, "2026-12-31")
        XCTAssertEqual(try records(before, "2026").count, 1)
        let destination = root.appendingPathComponent("移動後バックアップ")
        try library.backup(to: destination)
        let restored = try CaptureLibrary(root: destination, allowJournalWrites: true)
        XCTAssertEqual(try restored.captures()[0].journalDate, "2027-01-01")
        XCTAssertEqual(try records(destination, "2027")[0].explicitID, item.id)
        XCTAssertEqual(try records(destination, "2026").count, 0)
        XCTAssertThrowsError(try library.setDate("2028-01-01", for: item.id, expectedRevision: 1))
    }
}
