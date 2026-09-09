import XCTest
@testable import DiaryCore

final class PersonalUseTests: XCTestCase {
    func testSavedTextSurvivesReopenAndBrokenDatabaseCanBeRescued() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("library")
        let original = "個人使用の確認用文章\n改行もそのまま残す。"
        var savedID: UUID!
        do {
            let library = try CaptureLibrary(root: root, allowJournalWrites: true)
            let saved = try library.capture(text: original, date: "2026-09-09")
            savedID = saved.id
            try library.adopt(saved.id, expectedRevision: saved.revision)
        }
        do {
            let reopened = try CaptureLibrary(root: root, allowJournalWrites: true)
            let items = try reopened.captures()
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.id, savedID)
            XCTAssertEqual(items.first?.text, original)
            XCTAssertTrue(items.first?.adopted == true)
        }
        let db = root.appendingPathComponent("日記アプリデータ/library.sqlite")
        try Data("intentionally broken DB".utf8).write(to: db)
        try Data("preserve journal bytes".utf8).write(to: URL(fileURLWithPath: db.path + "-journal"))
        let paths = ["ジャーナル", "journal", "media", "日記アプリデータ"]
        let before = try BackupSnapshot.read(root: root, paths: paths)
        do { _ = try CaptureLibrary(root: root, readOnly: true); XCTFail("Broken DB accepted") } catch {}
        let rescue = base.appendingPathComponent("rescue")
        try RawLibraryRescue.create(from: root, to: rescue)
        XCTAssertEqual(try BackupSnapshot.read(root: root, paths: paths), before)
        XCTAssertEqual(try BackupSnapshot.read(root: rescue, paths: paths), before)
        let originals = rescue.appendingPathComponent("日記アプリデータ/originals")
        let files = FileManager.default.enumerator(at: originals, includingPropertiesForKeys: nil)!
        var recovered = false
        for case let file as URL in files {
            if (try? String(contentsOf: file, encoding: .utf8)) == original { recovered = true }
        }
        XCTAssertTrue(recovered, "Text must be readable without opening SQLite")
        do {
            try RawLibraryRescue.create(from: root, to: root.appendingPathComponent("bad"))
            XCTFail("Internal rescue destination accepted")
        } catch DiaryError.invalid(let message) { XCTAssertTrue(message.contains("外")) }
    }
}
