import Foundation
import CryptoKit

/// 退避対象の全ファイルを列挙し、コピー前後を照合する。外部編集をロックするAPIではない。
struct BackupSnapshot: Codable, Equatable {
    struct Fingerprint: Codable, Equatable {
        let bytes: UInt64
        let sha256: String
    }
    let files: [String: Fingerprint]
    static let roots = ["ジャーナル", "journal", "media", "日記アプリデータ/originals", "日記アプリデータ/operations"]

    static func fingerprint(_ url: URL) throws -> Fingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes: UInt64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data); bytes += UInt64(data.count)
        }
        return Fingerprint(bytes: bytes, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func read(root: URL) throws -> BackupSnapshot {
        let fm = FileManager.default
        var files: [String: Fingerprint] = [:]
        func visit(_ url: URL, relative: String) throws {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw DiaryError.invalid("バックアップ対象にシンボリックリンクがあります: \(relative)") }
            if values.isDirectory == true {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else {
                guard values.isRegularFile == true else { throw DiaryError.invalid("通常ファイル以外をバックアップできません: \(relative)") }
                files[relative] = try fingerprint(url)
            }
        }
        for path in roots {
            let url = root.appendingPathComponent(path)
            // dangling symlinkも「存在しないから省略」しない。
            if fm.fileExists(atPath: url.path) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try visit(url, relative: path)
            }
        }
        return BackupSnapshot(files: files)
    }

    func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        for path in files.keys.sorted() {
            let target = destination.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source.appendingPathComponent(path), to: target)
            guard try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                  try Self.fingerprint(target) == files[path] else { throw DiaryError.conflict }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.synchronize()
        }
    }
}
