import XCTest
import SQLite3
@testable import DiaryCore

final class CaptureLibraryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DiaryCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testOriginalAndIDSurviveReopeningWithoutTouchingJournal() throws {
        let journal = root.appendingPathComponent("ジャーナル/2026.md")
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = Data("原本の日記。\r\n<!-- コメント -->\r\n".utf8)
        try old.write(to: journal)
        let text = "  雑感😀\r\n\r\n> 引用\r\n<!-- 大切なコメント -->\r\n#映画  \n"
        let saved = try CaptureLibrary(root: root).capture(text: text, date: nil)
        let reopened = try XCTUnwrap(CaptureLibrary(root: root).captures().first)
        XCTAssertEqual(reopened, saved)
        XCTAssertEqual(Data(reopened.text.utf8), Data(text.utf8))
        XCTAssertNil(reopened.journalDate)
        XCTAssertEqual(try Data(contentsOf: journal), old)
    }

    func testRecoverAtEveryInterruptionAndRetryExactlyOnce() throws {
        enum Interruption: Error { case stopped }
        for (index, stage) in [CaptureLibrary.Stage.prepared, .originalWritten, .committed].enumerated() {
            let path = root.appendingPathComponent(String(index))
            let id = UUID()
            do {
                _ = try CaptureLibrary(root: path).capture(text: "原文 \(index)", date: "2026-09-07", id: id) {
                    if $0 == stage { throw Interruption.stopped }
                }
                XCTFail("中断しなかった")
            } catch Interruption.stopped { }
            let recovered = try CaptureLibrary(root: path)
            let once = try recovered.capture(text: "原文 \(index)", date: "2026-09-07", id: id)
            XCTAssertEqual(once.id, id)
            XCTAssertEqual(try recovered.captures().count, 1)
            XCTAssertThrowsError(try recovered.capture(text: "別の内容", date: "2026-09-07", id: id))
            XCTAssertEqual(try recovered.captures().first?.text, "原文 \(index)")
        }
    }

    func testDateCorrectionIsVersionedAndRejectsStaleEdit() throws {
        let library = try CaptureLibrary(root: root)
        let original = try library.capture(text: "日付は後から", date: nil)
        try library.setDate("2027-01-01", for: original.id, expectedRevision: 1)
        XCTAssertThrowsError(try library.setDate("2026-09-07", for: original.id, expectedRevision: 1))
        let updated = try XCTUnwrap(library.captures().first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.text, original.text)
        XCTAssertEqual(updated.journalDate, "2027-01-01")
        XCTAssertEqual(updated.revision, 2)
        try library.setDate(nil, for: original.id, expectedRevision: 2)
        XCTAssertNil(try library.captures().first?.journalDate)
    }

    func testBackupOpensAsIndependentLibraryWithDatesAndOriginals() throws {
        let library = try CaptureLibrary(root: root.appendingPathComponent("source"))
        let item = try library.capture(text: "  復元したい原文\r\n", date: nil)
        try library.setDate("2026-09-01", for: item.id, expectedRevision: 1)
        let backup = root.appendingPathComponent("restore")
        try library.backup(to: backup)
        let restored = try CaptureLibrary(root: backup)
        XCTAssertEqual(try restored.captures(), try library.captures())
        _ = try library.capture(text: "バックアップ後の追加", date: nil)
        XCTAssertEqual(try restored.captures().count, 1)
        XCTAssertThrowsError(try library.backup(to: backup))
    }

    func testTamperedOriginalIsNeverSilentlyAccepted() throws {
        let library = try CaptureLibrary(root: root)
        let item = try library.capture(text: "変更してはいけない", date: nil)
        let file = root.appendingPathComponent("日記アプリデータ/originals/\(item.id.uuidString).txt")
        try Data("外部変更".utf8).write(to: file)
        XCTAssertThrowsError(try library.captures())
        XCTAssertThrowsError(try library.backup(to: root.appendingPathComponent("bad-backup")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad-backup").path))
        XCTAssertEqual(try String(contentsOf: file), "外部変更")
    }

    func testInvalidDatesAndEmptyCaptureDoNotCreateRecords() throws {
        let library = try CaptureLibrary(root: root)
        for date in ["2026-02-30", "2026-2-01", "2026-13-01", "2026-09-07\n"] {
            XCTAssertThrowsError(try library.capture(text: "記録", date: date))
        }
        XCTAssertThrowsError(try library.capture(text: " \n\t", date: nil))
        XCTAssertEqual(try library.captures().count, 0)
    }

    func testTwoConnectionsObserveSameCommittedData() throws {
        let one = try CaptureLibrary(root: root)
        let two = try CaptureLibrary(root: root)
        let capture = try one.capture(text: "一つだけ", date: "2026-09-07")
        XCTAssertEqual(try two.captures(), [capture])
        try two.setDate("2026-09-06", for: capture.id, expectedRevision: 1)
        XCTAssertThrowsError(try one.setDate(nil, for: capture.id, expectedRevision: 1))
    }

    func testFutureDatabaseVersionIsRejected() throws {
        do { _ = try CaptureLibrary(root: root) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("日記アプリデータ/library.sqlite").path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try CaptureLibrary(root: root))
    }

    func testManagedDirectoryCannotEscapeThroughSymlink() throws {
        let outside = root.appendingPathComponent("outside")
        let inside = root.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("日記アプリデータ"), withDestinationURL: outside)
        XCTAssertThrowsError(try CaptureLibrary(root: inside))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testFailedOriginalWriteRetainsStagingAndResumesWithoutDuplicate() throws {
        let library = try CaptureLibrary(root: root)
        let originals = root.appendingPathComponent("日記アプリデータ/originals")
        // 書込先にファイルがある状態を作り、容量不足等と同じ「原本配置に失敗」を再現する。
        try Data("書き込みを妨げるテスト用ファイル".utf8).write(to: originals)
        let id = UUID()
        XCTAssertThrowsError(try library.capture(text: "失いたくない原文", date: nil, id: id))
        let staging = root.appendingPathComponent("日記アプリデータ/staging/\(id.uuidString).txt")
        XCTAssertEqual(try String(contentsOf: staging), "失いたくない原文")
        try FileManager.default.removeItem(at: originals)
        let recovered = try CaptureLibrary(root: root)
        XCTAssertEqual(try recovered.capture(text: "失いたくない原文", date: nil, id: id).id, id)
        XCTAssertEqual(try recovered.captures().count, 1)
    }
}
