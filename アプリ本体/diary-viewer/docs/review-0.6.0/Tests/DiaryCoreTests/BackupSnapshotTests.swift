import XCTest
@testable import DiaryCore

final class BackupSnapshotTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func put(_ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func testMediaOperationsAndManifestRestoreIndependently() throws {
        let library = try CaptureLibrary(root: root)
        let capture = try library.capture(text: "原文", date: nil)
        let photo = Data([0, 255, 34, 65])
        let video = Data(repeating: 137, count: 3 * 1024 * 1024 + 9)
        try put("media/ジャーナル写真/写真.jpg", photo)
        try put("media/ジャーナル動画/年/映像.mov", video)
        try put("日記アプリデータ/operations/履歴/before.md", Data("退避版".utf8))
        let destination = root.appendingPathComponent("backups/full")
        try library.backup(to: destination)
        try put("media/ジャーナル写真/写真.jpg", Data("変更".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("media/ジャーナル写真/写真.jpg")), photo)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("media/ジャーナル動画/年/映像.mov")), video)
        let restored = root.appendingPathComponent("restore")
        try FileManager.default.copyItem(at: destination, to: restored)
        XCTAssertEqual(try CaptureLibrary(root: restored).captures(), [capture])
        let manifest = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: destination.appendingPathComponent("backup-manifest.json")))
        for (path, expected) in manifest.files {
            XCTAssertEqual(try BackupSnapshot.fingerprint(destination.appendingPathComponent(path)), expected)
        }
        XCTAssertTrue(manifest.files["日記アプリデータ/operations/履歴/before.md"] != nil)
    }
    func testExternalMutationAdditionAndDeletionPreventCompletedBackup() throws {
        let library = try CaptureLibrary(root: root)
        for mutation in ["edit", "add", "delete"] {
            try put("media/a.bin", Data("元".utf8))
            let destination = root.appendingPathComponent("backups/\(mutation)")
            XCTAssertThrowsError(try library.backup(to: destination) { stage in
                if stage == .copied {
                    switch mutation {
                    case "edit": try self.put("media/a.bin", Data("外部編集".utf8))
                    case "add": try self.put("media/new.bin", Data("追加".utf8))
                    default: try FileManager.default.removeItem(at: self.root.appendingPathComponent("media/a.bin"))
                    }
                }
            })
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }
    func testSymlinkIsRejectedRatherThanSilentlyOmitted() throws {
        let library = try CaptureLibrary(root: root)
        try put("outside.txt", Data("リンク先".utf8))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("media"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("media/link"), withDestinationURL: root.appendingPathComponent("outside.txt"))
        XCTAssertThrowsError(try library.backup(to: root.appendingPathComponent("backup")))
    }
}
