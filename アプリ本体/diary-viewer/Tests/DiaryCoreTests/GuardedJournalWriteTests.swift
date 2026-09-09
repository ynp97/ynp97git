import XCTest
import SQLite3
@testable import DiaryCore

final class GuardedJournalWriteTests: XCTestCase {
    private var root: URL!
    private let old = Data("旧日記".utf8)
    private let next = Data("新日記".utf8)
    private let external = Data("外部エディタの追記".utf8)
    private var target: URL { root.appendingPathComponent("2026.md") }
    private var slot: URL { root.appendingPathComponent("operations/exchanged.md") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GuardedWrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testSchemaFourUpgradesAndKeepsCapture() throws {
        let item = try CaptureLibrary(root: root).capture(text: "保持する原文", date: nil)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("日記アプリデータ/library.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version=4", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try CaptureLibrary(root: root, migrationBackup: root.appendingPathComponent("schema4-backup")).captures(), [item])
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 5)
    }
    func testReplaceGapKeepsExternalBytesAndRecoveryStops() throws {
        try old.write(to: target)
        XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: contentHash(old), slot: slot) { stage in
            if stage == .prepared { try self.external.write(to: self.target, options: .atomic) }
        })
        XCTAssertEqual(try Data(contentsOf: slot), external)
        XCTAssertEqual(try Data(contentsOf: target), next)
        XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: contentHash(old), slot: slot))
        XCTAssertEqual(try Data(contentsOf: slot), external)
    }
    func testNewYearDoesNotOverwriteFileCreatedInGap() throws {
        XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: "missing", slot: slot) { stage in
            if stage == .prepared { try self.external.write(to: self.target) }
        })
        XCTAssertEqual(try Data(contentsOf: target), external)
        XCTAssertEqual(try Data(contentsOf: slot), next)
    }
    func testInterruptedExchangeRecoversOnceAndRetainsOriginal() throws {
        try old.write(to: target)
        XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: contentHash(old), slot: slot) { stage in
            if stage == .exchanged { throw DiaryError.conflict }
        })
        try GuardedJournalWrite.install(next, at: target, before: contentHash(old), slot: slot)
        XCTAssertEqual(try Data(contentsOf: target), next)
        XCTAssertEqual(try Data(contentsOf: slot), old)
    }
    func testPreparedExchangeAndNewFileResume() throws {
        for existed in [true, false] {
            if existed { try old.write(to: target) }
            let before = existed ? contentHash(old) : "missing"
            XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: before, slot: slot) { stage in
                if stage == .prepared { throw DiaryError.conflict }
            })
            try GuardedJournalWrite.install(next, at: target, before: before, slot: slot)
            try GuardedJournalWrite.install(next, at: target, before: before, slot: slot)
            XCTAssertEqual(try Data(contentsOf: target), next)
            try FileManager.default.removeItem(at: target)
            if existed { try FileManager.default.removeItem(at: slot) }
        }
    }
    func testDeletedTargetInGapDoesNotDiscardPreparedData() throws {
        try old.write(to: target)
        XCTAssertThrowsError(try GuardedJournalWrite.install(next, at: target, before: contentHash(old), slot: slot) { stage in
            if stage == .prepared { try FileManager.default.removeItem(at: self.target) }
        })
        XCTAssertEqual(try Data(contentsOf: slot), next)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
