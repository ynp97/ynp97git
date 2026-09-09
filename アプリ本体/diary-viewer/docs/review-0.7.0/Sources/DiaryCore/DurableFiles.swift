import Foundation
import Darwin

enum DurableFiles {
    static func syncFile(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DiaryError.storage("退避したファイルを開けません。") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw DiaryError.storage("退避したファイルを同期できません。") }
    }
    static func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DiaryError.storage("退避先フォルダを開けません。") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw DiaryError.storage("退避先フォルダを同期できません。") }
    }
    static func syncTreeDirectories(_ root: URL) throws {
        for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw DiaryError.invalid("退避先にリンクがあります。") }
            if values.isDirectory == true { try syncTreeDirectories(child) }
        }
        try syncDirectory(root)
    }
}
