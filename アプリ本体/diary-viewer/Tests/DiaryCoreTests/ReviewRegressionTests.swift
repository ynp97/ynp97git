import XCTest
import SQLite3
import Darwin
@testable import DiaryCore

final class ReviewRegressionTests: XCTestCase {
    private var root: URL!
    private var libraryRoot: URL { root.appendingPathComponent("library") }
    private var database: URL { libraryRoot.appendingPathComponent("日記アプリデータ/library.sqlite") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let file as URL in files { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path) }
        }
        try FileManager.default.removeItem(at: root)
    }
    private func put(_ path: String, _ data: Data) throws {
        let file = libraryRoot.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
    private func sql(_ query: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw DiaryError.storage("test DB open failed") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else { throw DiaryError.storage("test SQL failed") }
    }
    private func expectInvalid(_ contains: String, _ action: () throws -> Void) {
        do { try action(); XCTFail("Expected specific invalid error") }
        catch DiaryError.invalid(let message) { XCTAssertTrue(message.contains(contains), message) }
        catch { XCTFail("Wrong error: \(error)") }
    }
    private func contents() throws -> [String: Data] {
        var result: [String: Data] = [:]
        if let files = FileManager.default.enumerator(at: libraryRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[file.path] = try Data(contentsOf: file)
            }
        }
        return result
    }
    func testSavingNeverDuplicatesMediaOrCreatesFullBackups() throws {
        let library = try CaptureLibrary(root: libraryRoot, allowJournalWrites: true)
        let media = Data(repeating: 7, count: 2 * 1024 * 1024)
        try put("media/video.mov", media)
        for n in 1...3 {
            let item = try library.capture(text: "架空\(n)", date: "2026-01-0\(n)")
            try library.adopt(item.id, expectedRevision: 1)
            try library.setDate("2027-01-0\(n)", for: item.id, expectedRevision: 1)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("バックアップ").path))
        XCTAssertEqual(try contents().values.filter { $0 == media }.count, 1)
    }
    func testReadOnlyOpenAndBackupDoNotWriteSourceOrRecover() throws {
        let item = try CaptureLibrary(root: libraryRoot).capture(text: "原文", date: nil)
        try FileManager.default.removeItem(at: libraryRoot.appendingPathComponent("日記アプリデータ/writer.lock"))
        let before = try contents()
        let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
        XCTAssertEqual(try reader.captures(), [item])
        expectInvalid("閲覧専用") { _ = try reader.capture(text: "禁止", date: nil) }
        try reader.backup(to: root.appendingPathComponent("outside-backup"))
        XCTAssertEqual(try contents(), before)
    }
    func testReadOnlyPendingAdoptionIsLabeledAndRescuable() throws {
        let writer = try CaptureLibrary(root: libraryRoot, allowJournalWrites: true)
        let item = try writer.capture(text: "中断した原文", date: "2026-01-01")
        do { try writer.adopt(item.id, expectedRevision: 1) { if $0 == .journalWritten { throw DiaryError.conflict } }; XCTFail() }
        catch DiaryError.conflict {} catch { XCTFail("Wrong interruption: \(error)") }
        let before = try contents()
        let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
        XCTAssertTrue(reader.recoveryIssue?.contains("保存途中") == true)
        expectInvalid("保存途中") { _ = try reader.captures() }
        let inspection = try reader.capturesForInspection()
        XCTAssertEqual(inspection[0].text, item.text)
        XCTAssertTrue(inspection[0].savePending)
        let rescue = root.appendingPathComponent("rescue")
        try reader.rescueBackup(to: rescue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rescue.appendingPathComponent("recovery-required.txt").path))
        XCTAssertEqual(try contents(), before)
        let rescued = try CaptureLibrary(root: rescue, readOnly: true)
        XCTAssertTrue(try rescued.capturesForInspection()[0].savePending)
    }
    func testWritableConflictStillAllowsInspectionAndRescue() throws {
        let writer = try CaptureLibrary(root: libraryRoot, allowJournalWrites: true)
        let item = try writer.capture(text: "競合時も残る原文", date: "2026-01-01")
        do { try writer.adopt(item.id, expectedRevision: 1) { if $0 == .prepared { throw DiaryError.conflict } }; XCTFail() }
        catch DiaryError.conflict {} catch { XCTFail("Wrong interruption: \(error)") }
        try put("ジャーナル/2026.md", Data("外部の変更".utf8))
        let degraded = try CaptureLibrary(root: libraryRoot, allowJournalWrites: true, tolerateRecoveryFailure: true)
        XCTAssertFalse(degraded.canWrite)
        XCTAssertTrue(degraded.recoveryIssue != nil)
        XCTAssertEqual(try degraded.capturesForInspection()[0].text, item.text)
        let rescue = root.appendingPathComponent("conflict-rescue")
        try degraded.rescueBackup(to: rescue)
        XCTAssertEqual(try Data(contentsOf: rescue.appendingPathComponent("ジャーナル/2026.md")), Data("外部の変更".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rescue.appendingPathComponent("日記アプリデータ/operations/\(item.id.uuidString)/after.md").path))
    }
    func testOldDatabaseNeedsExplicitBackupAndRetainsOldVersionThere() throws {
        _ = try CaptureLibrary(root: libraryRoot).capture(text: "移行前の原文", date: nil)
        try sql("PRAGMA user_version=4")
        let before = try Data(contentsOf: database)
        expectInvalid("旧形式") { _ = try CaptureLibrary(root: libraryRoot) }
        XCTAssertEqual(try Data(contentsOf: database), before)
        let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
        XCTAssertEqual(try reader.captures()[0].text, "移行前の原文")
        XCTAssertEqual(try Data(contentsOf: database), before)
        let backup = root.appendingPathComponent("before-upgrade")
        _ = try CaptureLibrary(root: libraryRoot, migrationBackup: backup)
        let old = try Data(contentsOf: backup.appendingPathComponent("日記アプリデータ/library.sqlite"))
        XCTAssertEqual(Array(old[60..<64]), [0, 0, 0, 4])
        XCTAssertEqual(Array(try Data(contentsOf: database)[60..<64]), [0, 0, 0, 5])
    }
    func testUnknownColumnsCannotChangeVersionEvenWithBackupSpecified() throws {
        _ = try CaptureLibrary(root: libraryRoot).capture(text: "原文", date: nil)
        try sql("ALTER TABLE captures RENAME COLUMN raw_hash TO unknown_hash; PRAGMA user_version=4")
        let before = try Data(contentsOf: database)
        expectInvalid("列構成") { _ = try CaptureLibrary(root: libraryRoot, migrationBackup: root.appendingPathComponent("must-not-exist")) }
        XCTAssertEqual(try Data(contentsOf: database), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("must-not-exist").path))
    }
    func testEnglishJournalRemainsTheWriteAndReadDirectory() throws {
        let original = Data("---\nentries: 1\n---\n## 2026-01-01（木）1:00:00\n架空の旧日記\n\n".utf8)
        try put("journal/2026.md", original)
        let library = try CaptureLibrary(root: libraryRoot, allowJournalWrites: true)
        let item = try library.capture(text: "追加", date: "2026-02-01")
        try library.adopt(item.id, expectedRevision: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("ジャーナル").path))
        XCTAssertEqual(try JournalLocation.directory(in: libraryRoot).lastPathComponent, "journal")
        let document = try OriginalJournal(data: Data(contentsOf: libraryRoot.appendingPathComponent("journal/2026.md")))
        XCTAssertEqual(document.blocks.count, 2)
        try library.setDate("2027-02-01", for: item.id, expectedRevision: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("journal/2027.md").path))
        try library.backup(to: root.appendingPathComponent("english-backup"))
    }
    func testTwoJournalDirectoriesBlockSelectionButBothAreRescued() throws {
        _ = try CaptureLibrary(root: libraryRoot)
        try put("journal/2026.md", Data("英語側".utf8))
        try put("ジャーナル/2026.md", Data("日本語側".utf8))
        expectInvalid("両方") { _ = try JournalLocation.directory(in: libraryRoot) }
        let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
        XCTAssertTrue(reader.recoveryIssue?.contains("両方") == true)
        let rescue = root.appendingPathComponent("two-roots-rescue")
        try reader.rescueBackup(to: rescue)
        XCTAssertEqual(try Data(contentsOf: rescue.appendingPathComponent("journal/2026.md")), Data("英語側".utf8))
        XCTAssertEqual(try Data(contentsOf: rescue.appendingPathComponent("ジャーナル/2026.md")), Data("日本語側".utf8))
    }
    func testReadOnlyAndImmutableMediaCanBeBackedUp() throws {
        let library = try CaptureLibrary(root: libraryRoot)
        let photo = Data([1, 2, 3])
        try put("media/readonly.jpg", photo)
        try put("media/locked.mov", photo)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: libraryRoot.appendingPathComponent("media/readonly.jpg").path)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: libraryRoot.appendingPathComponent("media/locked.mov").path)
        let backup = root.appendingPathComponent("locked-backup")
        try library.backup(to: backup)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("media/readonly.jpg")), photo)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("media/locked.mov")), photo)
    }
    func testSymlinkRejectionHasTheExpectedReason() throws {
        let library = try CaptureLibrary(root: libraryRoot)
        try put("media/real.jpg", Data([1]))
        try FileManager.default.createSymbolicLink(at: libraryRoot.appendingPathComponent("media/link.jpg"), withDestinationURL: libraryRoot.appendingPathComponent("media/real.jpg"))
        expectInvalid("シンボリックリンク") { try library.backup(to: root.appendingPathComponent("link-backup")) }
    }
    func testPendingCaptureRescueIncludesStagingWithoutRecovery() throws {
        let writer = try CaptureLibrary(root: libraryRoot)
        do { _ = try writer.capture(text: "まだ設置していない原文", date: nil) { if $0 == .prepared { throw DiaryError.conflict } }; XCTFail() }
        catch DiaryError.conflict {} catch { XCTFail("Wrong interruption: \(error)") }
        let before = try contents()
        let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
        XCTAssertTrue(reader.recoveryIssue?.contains("受け箱の保存途中") == true)
        let rescue = root.appendingPathComponent("staging-rescue")
        try reader.rescueBackup(to: rescue)
        let staging = try FileManager.default.contentsOfDirectory(at: rescue.appendingPathComponent("日記アプリデータ/staging"), includingPropertiesForKeys: nil)
        XCTAssertEqual(staging.count, 1)
        XCTAssertEqual(try Data(contentsOf: staging[0]), Data("まだ設置していない原文".utf8))
        XCTAssertEqual(try contents(), before)
    }
    func testDeclaredLegacySchemasAreCheckedAndBackedUpBeforeUpgrade() throws {
        for version in 1...4 {
            if FileManager.default.fileExists(atPath: libraryRoot.path) { try FileManager.default.removeItem(at: libraryRoot) }
            let item = try CaptureLibrary(root: libraryRoot).capture(text: "版\(version)の原文", date: nil)
            if version < 4 { try sql("DROP TABLE journal_identity") }
            if version < 3 { try sql("DROP TABLE journal_changes") }
            if version < 2 { try sql("DROP TABLE adoptions") }
            try sql("PRAGMA user_version=\(version)")
            let reader = try CaptureLibrary(root: libraryRoot, readOnly: true)
            XCTAssertEqual(try reader.captures(), [item])
            let backup = root.appendingPathComponent("version-\(version)-backup")
            let upgraded = try CaptureLibrary(root: libraryRoot, migrationBackup: backup)
            XCTAssertEqual(try upgraded.captures(), [item])
            let old = try CaptureLibrary(root: backup, readOnly: true)
            XCTAssertEqual(try old.captures(), [item])
            XCTAssertTrue(old.schemaNeedsUpgrade)
        }
    }

}
