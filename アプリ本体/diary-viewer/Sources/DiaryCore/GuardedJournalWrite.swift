import Foundation
import Darwin

/// 置換した実物を操作フォルダへ残す。ハッシュ確認とrenameの間の編集も破棄しない。
/// 非協調エディタの継続書込を止めるものではなく、競合時の自動巻戻しもしない。
enum GuardedJournalWrite {
    enum Stage { case prepared, exchanged }

    static func install(_ data: Data, at target: URL, before: String, slot: URL,
                        interruption: ((Stage) throws -> Void)? = nil) throws {
        let fm = FileManager.default
        let after = contentHash(data)
        let retainedConflict = DiaryError.invalid("外部編集と日記の保存が競合しました。自動復旧を停止しています。置換時のファイルを次の場所に残しました。削除せず確認してください。\n\(slot.path)")
        func hash(_ url: URL) throws -> String {
            if !fm.fileExists(atPath: url.path) {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw DiaryError.conflict }
                return "missing"
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiaryError.conflict }
            return try contentHash(Data(contentsOf: url))
        }
        let current = try hash(target)
        let saved = try hash(slot)
        if current == after {
            // 旧版のpending回復（slotなし）も許容。交換後の競合退避版は決して無視しない。
            guard saved == "missing" || (before != "missing" && saved == before) else { throw retainedConflict }
            return
        }
        guard current == before, saved == "missing" || saved == after else { throw DiaryError.conflict }
        try fm.createDirectory(at: slot.deletingLastPathComponent(), withIntermediateDirectories: true)
        if saved == "missing" {
            try data.write(to: slot, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: slot)
            defer { try? handle.close() }
            try handle.synchronize()
            try syncDirectory(slot.deletingLastPathComponent())
        }
        guard try hash(slot) == after, try hash(target) == before else { throw DiaryError.conflict }
        try interruption?(.prepared)
        // 同一ファイルシステムのOS原子操作。未対応時は通常renameへフォールバックしない。
        let flags = before == "missing" ? UInt32(RENAME_EXCL) : UInt32(RENAME_SWAP)
        let result = renamex_np(slot.path, target.path, flags)
        let savedErrno = errno
        guard result == 0 else {
            throw DiaryError.storage("日記の安全な置換を完了できません（errno: \(savedErrno)）。原文と操作記録を残しました。")
        }
        try syncDirectory(target.deletingLastPathComponent())
        try syncDirectory(slot.deletingLastPathComponent())
        try interruption?(.exchanged)
        guard try hash(target) == after,
              try hash(slot) == before else { throw retainedConflict }
    }

    private static func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw DiaryError.storage("保存先フォルダを開けません。") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw DiaryError.storage("保存先フォルダを同期できません。") }
    }
}
