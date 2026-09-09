import Foundation

/// DBを開かず、途中記録も含めて救出する。復旧済みDBや同時点スナップショットではない。
public enum RawLibraryRescue {
    public static func create(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard destination.path != source.path, !destination.path.hasPrefix(source.path + "/") else {
            throw DiaryError.invalid("救出先は元ライブラリの外に指定してください。")
        }
        guard !fm.fileExists(atPath: destination.path) else { throw DiaryError.invalid("救出先が既にあります。") }
        let paths = ["ジャーナル", "journal", "media", "日記アプリデータ"]
        let before = try BackupSnapshot.read(root: source, paths: paths)
        guard !before.files.isEmpty else { throw DiaryError.invalid("救出対象のファイルがありません。") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".rescue-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try before.copy(from: source, to: staging)
        guard try BackupSnapshot.read(root: source, paths: paths) == before,
              try BackupSnapshot.read(root: staging, paths: paths) == before else { throw DiaryError.conflict }
        let marker = staging.appendingPathComponent("raw-rescue.txt")
        try Data("DB未解釈の救出コピーです。SQLiteの途中記録を含みます。復旧作業はさらに複製して行ってください。原文はoriginals、保存済み本文は年別Markdownで読めます。\n".utf8).write(to: marker)
        try DurableFiles.syncFile(marker)
        var files = before.files
        files["raw-rescue.txt"] = try BackupSnapshot.fingerprint(marker)
        let manifest = staging.appendingPathComponent("backup-manifest.json")
        try JSONEncoder().encode(BackupSnapshot(files: files)).write(to: manifest)
        try DurableFiles.syncFile(manifest)
        try DurableFiles.syncTreeDirectories(staging)
        try fm.moveItem(at: staging, to: destination)
        try DurableFiles.syncDirectory(destination.deletingLastPathComponent())
    }
}
