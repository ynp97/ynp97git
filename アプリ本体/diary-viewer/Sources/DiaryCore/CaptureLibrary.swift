import Foundation
import SQLite3
import Darwin

public struct Capture: Identifiable, Equatable {
    public let id: UUID
    public let createdAt: String
    public let journalDate: String?
    public let text: String
    public let revision: Int
    public var adopted: Bool = false
    public var savePending: Bool = false

    public init(id: UUID, createdAt: String, journalDate: String?, text: String, revision: Int, adopted: Bool = false) {
        self.id = id; self.createdAt = createdAt; self.journalDate = journalDate
        self.text = text; self.revision = revision; self.adopted = adopted
    }
}

/// 原文は一度だけ保存。DBのpending行が操作記録となり、中断後に同じIDで回復する。
/// 年別Markdown採用は操作記録と退避版で回復する。通常起動では書込を有効にしない。
public final class CaptureLibrary {
    public enum Stage { case prepared, originalWritten, committed }
    private let root: URL
    private let directory: URL
    private var db: OpaquePointer?
    private let mutex = NSLock()
    private let fm = FileManager.default
    private static let schemaVersion = 5
    private let allowJournalWrites: Bool
    private let readOnly: Bool
    public private(set) var recoveryIssue: String?
    public private(set) var schemaNeedsUpgrade = false
    public var canWrite: Bool { !readOnly && recoveryIssue == nil }

    public init(root: URL, allowJournalWrites: Bool = false, readOnly: Bool = false,
                tolerateRecoveryFailure: Bool = false, migrationBackup: URL? = nil) throws {
        self.readOnly = readOnly
        self.allowJournalWrites = allowJournalWrites && !readOnly
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        directory = self.root.appendingPathComponent("日記アプリデータ")
        if !readOnly { try fm.createDirectory(at: self.root, withIntermediateDirectories: true) }
        try checkPath(directory)
        if !readOnly { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let database = directory.appendingPathComponent("library.sqlite")
        try checkPath(database)
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(database.path, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            db = nil
            throw DiaryError.storage("データベースを開けません。")
        }
        do {
            sqlite3_busy_timeout(db, 5000)
            try locked {
                let version = Int(try rows("PRAGMA user_version").first?.first ?? "-1") ?? -1
                guard version == 0 || version == 1 || version == 2 || version == 3 || version == 4 || version == Self.schemaVersion else {
                    throw DiaryError.invalid("このデータは別のバージョンで作られています。書き込みません。")
                }
                try validateSchema(version: version)
                schemaNeedsUpgrade = version > 0 && version < Self.schemaVersion
                if readOnly {
                    recoveryIssue = try pendingMessage()
                    do { _ = try JournalLocation.directory(in: self.root) }
                    catch { recoveryIssue = error.localizedDescription }
                    return
                }
                if version > 0 && version < Self.schemaVersion {
                    guard let migrationBackup else {
                        throw DiaryError.invalid("旧形式のデータです。閲覧は変更せず行えます。更新には、先に退避先を明示して移行してください。")
                    }
                    // バージョンも原文も更新する前に、旧版DBと媒体を含む退避を完成させる。
                    try backupUnlocked(to: migrationBackup, rescue: true)
                }
                try exec("PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;")
                try exec("""
                    BEGIN IMMEDIATE;
                    CREATE TABLE IF NOT EXISTS captures (
                      id TEXT PRIMARY KEY, created TEXT NOT NULL, journal_date TEXT,
                      raw_hash TEXT NOT NULL, phase TEXT NOT NULL CHECK(phase IN ('pending','ready')),
                      revision INTEGER NOT NULL DEFAULT 1
                    );
                    CREATE TABLE IF NOT EXISTS capture_revisions (
                      capture_id TEXT NOT NULL REFERENCES captures(id), revision INTEGER NOT NULL,
                      journal_date TEXT, changed TEXT NOT NULL, PRIMARY KEY(capture_id, revision)
                    );
                    CREATE TABLE IF NOT EXISTS adoptions (
                      capture_id TEXT PRIMARY KEY REFERENCES captures(id), year TEXT NOT NULL,
                      before_hash TEXT NOT NULL, after_hash TEXT NOT NULL,
                      phase TEXT NOT NULL CHECK(phase IN ('pending','ready'))
                    );
                    CREATE TABLE IF NOT EXISTS journal_changes (
                      id TEXT PRIMARY KEY, capture_id TEXT NOT NULL REFERENCES captures(id),
                      payload TEXT NOT NULL, phase TEXT NOT NULL CHECK(phase IN ('pending','ready'))
                    );
                    CREATE TABLE IF NOT EXISTS journal_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), payload TEXT NOT NULL);
                    PRAGMA user_version=5;
                    COMMIT;
                    """)
                schemaNeedsUpgrade = false
                do {
                    _ = try JournalLocation.directory(in: self.root)
                    try recoverUnlocked()
                } catch {
                    if tolerateRecoveryFailure { recoveryIssue = error.localizedDescription }
                    else { throw error }
                }
            }
        } catch {
            sqlite3_close(db); db = nil; throw error
        }
    }

    deinit { sqlite3_close(db) }

    /// 全年の同一スナップショットに対して解決する。本文へは一切書き込まない。
    /// 対応不能な変更ではトランザクションをロールバックし、前の対応表を残す。
    public func journalIdentities(files: [String: Data], interruption: (() throws -> Void)? = nil) throws -> [String: [UUID]] {
        try requireWritable()
        return try locked {
            var result: [String: [UUID]] = [:]
            try transaction {
                let previous = try rows("SELECT payload FROM journal_identity WHERE singleton=1").first
                    .map { try JSONDecoder().decode(JournalIdentity.self, from: Data($0[0].utf8)) } ?? JournalIdentity()
                let next = try previous.resolving(files: files)
                let payload = String(decoding: try JSONEncoder().encode(next), as: UTF8.self)
                try exec("INSERT OR REPLACE INTO journal_identity(singleton,payload) VALUES(1,?)", [payload])
                try interruption?()
                result = next.ids
            }
            return result
        }
    }

    public func capture(text: String, date: String?, id: UUID = UUID(), interruption: ((Stage) throws -> Void)? = nil) throws -> Capture {
        try requireWritable()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiaryError.invalid("文章を入力してください。") }
        try validateDate(date)
        return try locked {
            try recoverUnlocked()
            let key = id.uuidString
            let data = Data(text.utf8)
            let hash = contentHash(data)
            let existing = try rows("SELECT raw_hash, journal_date FROM captures WHERE id=?", [key])
            if let row = existing.first {
                guard row[0] == hash, row[1] == (date ?? "") else { throw DiaryError.conflict }
                return try getUnlocked(id)
            }
            let staging = try managed("staging/\(key).txt")
            try durableWrite(data, to: staging)
            // pendingの確定前に原文を永続化。pendingには再試行IDと原文ハッシュを含む。
            try transaction {
                try exec("INSERT INTO captures(id,created,journal_date,raw_hash,phase) VALUES(?,?,?,?, 'pending')", [key, now(), date, hash])
                try exec("INSERT INTO capture_revisions VALUES(?,1,?,?)", [key, date, now()])
            }
            try interruption?(.prepared)
            try installOriginal(id: id, hash: hash)
            try interruption?(.originalWritten)
            try exec("UPDATE captures SET phase='ready' WHERE id=?", [key])
            try interruption?(.committed)
            return try getUnlocked(id)
        }
    }

    public func captures() throws -> [Capture] {
        try locked {
            try recoverUnlocked()
            return try rows("SELECT id FROM captures WHERE phase='ready' ORDER BY created DESC, id DESC").map {
                guard let id = UUID(uuidString: $0[0]) else { throw DiaryError.invalid("保存IDが不正です。") }
                return try getUnlocked(id)
            }
        }
    }

    public enum DateChangeStage: Equatable { case prepared, fileWritten(Int), committed }

    public func setDate(_ date: String?, for id: UUID, expectedRevision: Int, interruption: ((DateChangeStage) throws -> Void)? = nil) throws {
        try requireWritable()
        try validateDate(date)
        try locked {
            try recoverUnlocked()
            let existing = try getUnlocked(id)
            // 中断回復直後の同じリクエストを再実行しても、改訂と移動を二重にしない。
            if existing.revision == expectedRevision + 1, existing.journalDate == date {
                for row in try rows("SELECT payload FROM journal_changes WHERE capture_id=? AND phase='ready'", [id.uuidString]) {
                    let change = try JSONDecoder().decode(JournalChange.self, from: Data(row[0].utf8))
                    if change.revision == expectedRevision && change.newDate == date { return }
                }
            }
            guard existing.revision == expectedRevision else { throw DiaryError.conflict }
            if existing.adopted {
                guard allowJournalWrites else { throw DiaryError.invalid("保存済み日記の日付変更は検証用ライブラリだけで利用できます。") }
                if existing.journalDate == date { return }
                try changeAdoptedDate(date, item: existing, interruption: interruption)
            } else {
                guard try rows("SELECT capture_id FROM adoptions WHERE capture_id=?", [id.uuidString]).isEmpty else { throw DiaryError.conflict }
                try transaction {
                    try exec("UPDATE captures SET journal_date=?, revision=revision+1 WHERE id=?", [date, id.uuidString])
                    try exec("INSERT INTO capture_revisions VALUES(?,?,?,?)", [id.uuidString, String(expectedRevision + 1), date, now()])
                }
            }
        }
    }

    /// 受け箱・年別Markdown・media内の写真/動画・操作履歴を照合して退避する。
    /// DBだけをコピーせず、全原文とハッシュ検査が通ってから完成ディレクトリへrenameする。
    public enum BackupStage { case inventoried, copied }

    public func backup(to destination: URL, interruption: ((BackupStage) throws -> Void)? = nil) throws {
        try locked {
            try recoverUnlocked()
            try backupUnlocked(to: destination, interruption: interruption)
        }
    }

    /// 競合中も操作記録をそのまま救出する。通常の復元完了版とは区別する。
    public func rescueBackup(to destination: URL) throws {
        try locked { try backupUnlocked(to: destination, rescue: true) }
    }

    private func backupUnlocked(to destination: URL, interruption: ((BackupStage) throws -> Void)? = nil, rescue: Bool = false) throws {
            guard try rescue || (rows("SELECT id FROM captures WHERE phase='pending'").isEmpty) else {
                throw DiaryError.invalid("原文の保存を回復してからバックアップしてください。")
            }
            let resolvedDestination = destination.standardizedFileURL.resolvingSymlinksInPath().path
            for path in BackupSnapshot.roots {
                let source = root.appendingPathComponent(path).path
                guard resolvedDestination != source, !resolvedDestination.hasPrefix(source + "/") else {
                    throw DiaryError.invalid("バックアップ先を日記や写真の保存フォルダ内には置けません。")
                }
            }
            // 全媒体は一旦検査する。列挙漏れやコピー中の変更は完成扱いにしない。
            let sourceSnapshot = try BackupSnapshot.read(root: root)
            try interruption?(.inventoried)
            guard try rescue || !hasTable("adoptions") || rows("SELECT capture_id FROM adoptions WHERE phase='pending'").isEmpty else {
                throw DiaryError.invalid("日記の保存を回復してからバックアップしてください。")
            }
            guard try rescue || !hasTable("journal_changes") || rows("SELECT id FROM journal_changes WHERE phase='pending'").isEmpty else {
                throw DiaryError.invalid("日付変更を回復してからバックアップしてください。")
            }
            let adoptedRows = try (rescue || !hasTable("adoptions")) ? [] : rows("SELECT capture_id,year FROM adoptions WHERE phase='ready'")
            for row in adoptedRows { try validateAdoptedRecord(row[0], year: row[1], in: root) }
            guard !fm.fileExists(atPath: destination.path) else { throw DiaryError.invalid("バックアップ先が既に存在します。") }
            let parent = destination.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporary = parent.appendingPathComponent(".diary-backup-\(UUID().uuidString)")
            try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
            do {
                let dbDir = temporary.appendingPathComponent("日記アプリデータ")
                try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)
                var copy: OpaquePointer?
                let result = sqlite3_open(dbDir.appendingPathComponent("library.sqlite").path, &copy)
                guard result == SQLITE_OK, let copy else { if let copy { sqlite3_close(copy) }; throw DiaryError.storage("バックアップDBを開けません。") }
                defer { sqlite3_close(copy) }
                guard let handle = sqlite3_backup_init(copy, "main", db, "main") else { throw DiaryError.storage("バックアップを開始できません。") }
                let step = sqlite3_backup_step(handle, -1)
                let finish = sqlite3_backup_finish(handle)
                guard step == SQLITE_DONE, finish == SQLITE_OK else { throw DiaryError.storage("DBのバックアップに失敗しました。") }
                for row in (rescue ? [] : try rows("SELECT id, raw_hash FROM captures WHERE phase='ready'")) {
                    guard let id = UUID(uuidString: row[0]) else { throw DiaryError.invalid("原本IDが不正です。") }
                    _ = try checkedOriginal(id: id, hash: row[1])
                }
                try sourceSnapshot.copy(from: root, to: temporary)
                try interruption?(.copied)
                guard try BackupSnapshot.read(root: root) == sourceSnapshot,
                      try BackupSnapshot.read(root: temporary) == sourceSnapshot else { throw DiaryError.conflict }
                if !rescue, try hasTable("journal_identity"), let payload = try rows("SELECT payload FROM journal_identity WHERE singleton=1").first?.first {
                    let identity = try JSONDecoder().decode(JournalIdentity.self, from: Data(payload.utf8))
                    let directory = try JournalLocation.directory(in: temporary).lastPathComponent
                    var years: [String: Data] = [:]
                    for path in sourceSnapshot.files.keys where path.hasPrefix(directory + "/") {
                        let url = temporary.appendingPathComponent(path)
                        let name = url.deletingPathExtension().lastPathComponent
                        if url.pathExtension == "md", name.count == 4, Int(name) != nil {
                            years[url.lastPathComponent] = try Data(contentsOf: url)
                        }
                    }
                    _ = try identity.resolving(files: years)
                }
                try DurableFiles.syncFile(dbDir.appendingPathComponent("library.sqlite"))
                var manifest = sourceSnapshot.files
                if rescue {
                    let notice = temporary.appendingPathComponent("recovery-required.txt")
                    try durableWrite(Data("救出用退避です。保存途中・競合・旧形式をそのまま保持しています。自動復旧せずコピーを閲覧して確認してください。\n".utf8), to: notice)
                    manifest["recovery-required.txt"] = try BackupSnapshot.fingerprint(notice)
                }
                manifest["日記アプリデータ/library.sqlite"] = try BackupSnapshot.fingerprint(dbDir.appendingPathComponent("library.sqlite"))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try durableWrite(try encoder.encode(BackupSnapshot(files: manifest)), to: temporary.appendingPathComponent("backup-manifest.json"))
                for row in adoptedRows { try validateAdoptedRecord(row[0], year: row[1], in: temporary) }
                try DurableFiles.syncTreeDirectories(temporary)
                try fm.moveItem(at: temporary, to: destination)
                try DurableFiles.syncDirectory(parent)
            } catch {
                try? fm.removeItem(at: temporary)
                throw error
            }
    }

    private func recoverUnlocked() throws {
        if readOnly {
            if let message = try pendingMessage() { throw DiaryError.invalid(message) }
            return
        }
        if allowJournalWrites {
            try recoverAdoptionsUnlocked()
            try recoverJournalChangesUnlocked()
        } else if let message = try pendingJournalMessage() {
            throw DiaryError.invalid(message)
        }
        for row in try rows("SELECT id, raw_hash FROM captures WHERE phase='pending'") {
            guard let id = UUID(uuidString: row[0]) else { throw DiaryError.invalid("中断記録のIDが不正です。") }
            try installOriginal(id: id, hash: row[1])
            try exec("UPDATE captures SET phase='ready' WHERE id=?", [id.uuidString])
        }
    }

    public enum AdoptionStage { case prepared, journalWritten, committed }

    /// 初期版は検証ライブラリで明示的に許可した場合だけ書く。
    /// 再試行はcapture UUID単位。同じ文章を別投入した場合は別の記録を維持する。
    public func adopt(_ id: UUID, expectedRevision: Int, interruption: ((AdoptionStage) throws -> Void)? = nil) throws {
        try requireWritable()
        guard allowJournalWrites else { throw DiaryError.invalid("日記への保存は検証中です。原文は受け箱に保存できます。") }
        try locked {
            try recoverUnlocked()
            let item = try getUnlocked(id)
            guard item.revision == expectedRevision else { throw DiaryError.conflict }
            if item.adopted {
                guard let row = try rows("SELECT year FROM adoptions WHERE capture_id=?", [id.uuidString]).first else { throw DiaryError.conflict }
                try validateAdoptedRecord(id.uuidString, year: row[0], in: root)
                return
            }
            guard let day = item.journalDate else { throw DiaryError.invalid("書いた日を指定してから日記へ保存してください。") }
            let year = String(day.prefix(4))
            let target = try journalFile(year)
            let old: Data?
            if fm.fileExists(atPath: target.path) { old = try Data(contentsOf: target) } else { old = nil }
            let source = old ?? Data("---\nentries: 0\n---\n\n# \(year)年の日記\n\n".utf8)
            let document = try OriginalJournal(data: source)
            let block = try PlainJournalRecord(id: id, day: day, text: item.text).encoded()
            let next = try document.prepending(block)
            // 同じIDが他の年に既にあれば勝手に新規採用しない。
            let directory = target.deletingLastPathComponent()
            if fm.fileExists(atPath: directory.path) {
                for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "md" {
                    try checkPath(file)
                    let parsed = try OriginalJournal(data: Data(contentsOf: file))
                    guard !parsed.blocks.contains(where: { $0.explicitID == id }) else { throw DiaryError.conflict }
                }
            }
            let key = id.uuidString
            // 復旧に必要な変更前後の本文だけを退避。media全体は明示バックアップのみ。
            if let old { try durableWrite(old, to: managed("operations/\(key)/before.md")) }
            try durableWrite(next, to: managed("operations/\(key)/after.md"))
            try exec("INSERT INTO adoptions VALUES(?,?,?,?, 'pending')", [key, year, old.map(contentHash) ?? "missing", contentHash(next)])
            try interruption?(.prepared)
            try installAdoption(id: id, year: year, before: old.map(contentHash) ?? "missing", after: contentHash(next))
            try interruption?(.journalWritten)
            try exec("UPDATE adoptions SET phase='ready' WHERE capture_id=?", [key])
            try interruption?(.committed)
        }
    }

    private struct JournalChange: Codable {
        struct File: Codable { let year: String; let before: String; let after: String }
        let id: UUID
        let captureID: UUID
        let revision: Int
        let oldDate: String
        let newDate: String?
        let files: [File]
    }

    private func changeAdoptedDate(_ date: String?, item: Capture, interruption: ((DateChangeStage) throws -> Void)?) throws {
        guard let oldDate = item.journalDate,
              let row = try rows("SELECT year FROM adoptions WHERE capture_id=? AND phase='ready'", [item.id.uuidString]).first,
              row[0] == String(oldDate.prefix(4)) else { throw DiaryError.conflict }
        let sourceYear = row[0]
        let source = try Data(contentsOf: journalFile(sourceYear))
        let document = try OriginalJournal(data: source)
        try document.validateForWriting()
        guard let index = document.blocks.firstIndex(where: { $0.explicitID == item.id }),
              let record = try PlainJournalRecord.decode(document.blocks[index].data),
              record.day == oldDate else { throw DiaryError.conflict }
        // Markdownが正本。外部で書き直した本文は年移動でもそのまま使う。
        // 未定へ戻す場合は元の受け箱原文と異なる本文を黙って失わない。
        if date == nil && record.text != item.text {
            throw DiaryError.invalid("日記の本文が受け箱の原文と異なります。変更した本文を残すため、日付未定には戻せません。")
        }
        let targetYear = date.map { String($0.prefix(4)) }
        var planned: [(year: String, before: Data?, after: Data)] = []
        if let date, targetYear == sourceYear {
            let replacement = try PlainJournalRecord(id: item.id, day: date, text: record.text).encoded()
            planned.append((sourceYear, source, try document.replacingBlock(at: index, with: replacement, expectedHash: contentHash(source))))
        } else {
            // 移動先を先に確保し、その後で元の年から外す。中断時の両方表示は回復まで止める。
            if let date, let targetYear {
                let target = try journalFile(targetYear)
                let before = fm.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
                let empty = Data("---\nentries: 0\n---\n\n# \(targetYear)年の日記\n\n".utf8)
                let targetDocument = try OriginalJournal(data: before ?? empty)
                let block = try PlainJournalRecord(id: item.id, day: date, text: record.text).encoded()
                planned.append((targetYear, before, try targetDocument.prepending(block)))
            }
            planned.append((sourceYear, source, try document.removingBlock(at: index, expectedHash: contentHash(source))))
        }
        let journalDirectory = try journalFile(sourceYear).deletingLastPathComponent()
        var occurrences = 0
        for file in try fm.contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil) where file.pathExtension == "md" {
            try checkPath(file)
            occurrences += try OriginalJournal(data: Data(contentsOf: file)).blocks.filter { $0.explicitID == item.id }.count
        }
        guard occurrences == 1 else { throw DiaryError.conflict }
        let operationID = UUID()
        // 変更対象の年別本文と操作記録だけで中断から回復する。
        let change = JournalChange(id: operationID, captureID: item.id, revision: item.revision, oldDate: oldDate,
                                   newDate: date, files: planned.map { .init(year: $0.year, before: $0.before.map(contentHash) ?? "missing", after: contentHash($0.after)) })
        for file in planned {
            if let before = file.before { try durableWrite(before, to: managed("operations/\(operationID.uuidString)/\(file.year)-before.md")) }
            try durableWrite(file.after, to: managed("operations/\(operationID.uuidString)/\(file.year)-after.md"))
        }
        let payload = String(decoding: try JSONEncoder().encode(change), as: UTF8.self)
        try exec("INSERT INTO journal_changes VALUES(?,?,?, 'pending')", [operationID.uuidString, item.id.uuidString, payload])
        try interruption?(.prepared)
        try finishJournalChange(change, interruption: interruption)
    }

    private func recoverJournalChangesUnlocked() throws {
        for row in try rows("SELECT id,capture_id,payload FROM journal_changes WHERE phase='pending'") {
            let change = try JSONDecoder().decode(JournalChange.self, from: Data(row[2].utf8))
            guard change.id.uuidString == row[0], change.captureID.uuidString == row[1] else { throw DiaryError.invalid("日付変更の操作記録が不正です。") }
            try finishJournalChange(change, interruption: nil)
        }
    }

    private func finishJournalChange(_ change: JournalChange, interruption: ((DateChangeStage) throws -> Void)?) throws {
        try validateDate(change.oldDate); try validateDate(change.newDate)
        let existing = try getUnlocked(change.captureID)
        guard existing.revision == change.revision, existing.journalDate == change.oldDate,
              existing.adopted, !change.files.isEmpty, change.files.count <= 2,
              Set(change.files.map(\.year)).count == change.files.count,
              Set(change.files.map(\.year)) == Set([Optional(String(change.oldDate.prefix(4))), change.newDate.map { String($0.prefix(4)) }].compactMap { $0 }) else { throw DiaryError.conflict }
        // 全ファイルの新版・退避版・現在版を先に検査し、一方の破損で他方を書き始めない。
        var outputs: [Data] = []
        for file in change.files {
            _ = try journalFile(file.year)
            let next = try Data(contentsOf: managed("operations/\(change.id.uuidString)/\(file.year)-after.md"))
            guard contentHash(next) == file.after else { throw DiaryError.invalid("日付変更途中の本文が一致しません。") }
            let parsed = try OriginalJournal(data: next)
            try parsed.validateForWriting()
            let matching = parsed.blocks.filter { $0.explicitID == change.captureID }
            if let date = change.newDate, file.year == String(date.prefix(4)) {
                guard matching.count == 1, try PlainJournalRecord.decode(matching[0].data)?.day == date else { throw DiaryError.conflict }
            } else if !matching.isEmpty { throw DiaryError.conflict }
            if file.before != "missing" {
                let old = try Data(contentsOf: managed("operations/\(change.id.uuidString)/\(file.year)-before.md"))
                guard contentHash(old) == file.before else { throw DiaryError.invalid("退避した本文が一致しません。") }
            }
            outputs.append(next)
        }
        func validateCurrentFiles() throws {
            for file in change.files {
                let target = try journalFile(file.year)
                let hash = fm.fileExists(atPath: target.path) ? try contentHash(Data(contentsOf: target)) : "missing"
                guard hash == file.before || hash == file.after else { throw DiaryError.conflict }
            }
        }
        try validateCurrentFiles()
        for (index, file) in change.files.enumerated() {
            try validateCurrentFiles()
            let target = try journalFile(file.year)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try GuardedJournalWrite.install(outputs[index], at: target, before: file.before,
                slot: managed("operations/\(change.id.uuidString)/\(file.year)-exchanged.md"))
            guard try contentHash(Data(contentsOf: target)) == file.after else { throw DiaryError.conflict }
            try interruption?(.fileWritten(index))
        }
        // DBを確定する前に、全ファイルが新版で揃っていることを確認する。
        for file in change.files {
            guard try contentHash(Data(contentsOf: journalFile(file.year))) == file.after else { throw DiaryError.conflict }
        }
        try transaction {
            try exec("UPDATE captures SET journal_date=?, revision=revision+1 WHERE id=?", [change.newDate, change.captureID.uuidString])
            try exec("INSERT INTO capture_revisions VALUES(?,?,?,?)", [change.captureID.uuidString, String(change.revision + 1), change.newDate, now()])
            if let date = change.newDate, let target = change.files.first(where: { $0.year == String(date.prefix(4)) }) {
                try exec("UPDATE adoptions SET year=?,before_hash=?,after_hash=? WHERE capture_id=?", [target.year, target.before, target.after, change.captureID.uuidString])
            } else {
                try exec("DELETE FROM adoptions WHERE capture_id=?", [change.captureID.uuidString])
            }
            try exec("UPDATE journal_changes SET phase='ready' WHERE id=?", [change.id.uuidString])
        }
        try interruption?(.committed)
    }

    private func journalFile(_ year: String) throws -> URL {
        guard year.count == 4, year.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { throw DiaryError.invalid("保存年が不正です。") }
        let url = try JournalLocation.directory(in: root).appendingPathComponent("\(year).md")
        try checkPath(url)
        return url
    }

    private func validateAdoptedRecord(_ key: String, year: String, in library: URL) throws {
        guard let id = UUID(uuidString: key), year.count == 4,
              year.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { throw DiaryError.invalid("保存先の記録が不正です。") }
        let file = try JournalLocation.directory(in: library).appendingPathComponent("\(year).md")
        if library == root { try checkPath(file) }
        let journal = try OriginalJournal(data: Data(contentsOf: file))
        try journal.validateForWriting()
        guard journal.blocks.filter({ $0.explicitID == id }).count == 1 else {
            throw DiaryError.invalid("採用済みの日記が見つかりません。年別ファイルを確認してください。")
        }
    }

    private func recoverAdoptionsUnlocked() throws {
        for row in try rows("SELECT capture_id,year,before_hash,after_hash FROM adoptions WHERE phase='pending'") {
            guard let id = UUID(uuidString: row[0]) else { throw DiaryError.invalid("日記保存の操作IDが不正です。") }
            try installAdoption(id: id, year: row[1], before: row[2], after: row[3])
            try exec("UPDATE adoptions SET phase='ready' WHERE capture_id=?", [row[0]])
        }
    }

    private func installAdoption(id: UUID, year: String, before: String, after: String) throws {
        let target = try journalFile(year)
        let current = fm.fileExists(atPath: target.path) ? try contentHash(Data(contentsOf: target)) : "missing"
        guard current == before || current == after else { throw DiaryError.conflict }
        let next = try Data(contentsOf: managed("operations/\(id.uuidString)/after.md"))
        guard contentHash(next) == after else { throw DiaryError.invalid("保存途中の日記が一致しません。") }
        if before != "missing" {
            let previous = try Data(contentsOf: managed("operations/\(id.uuidString)/before.md"))
            guard contentHash(previous) == before else { throw DiaryError.invalid("退避した日記が一致しません。") }
        }
        try OriginalJournal(data: next).validateForWriting()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 交換後の実物も確認し、途中再起動で競合を成功扱いにしない。
        try GuardedJournalWrite.install(next, at: target, before: before,
            slot: managed("operations/\(id.uuidString)/exchanged.md"))
        guard try contentHash(Data(contentsOf: target)) == after else { throw DiaryError.conflict }
    }

    private func installOriginal(id: UUID, hash: String) throws {
        let original = try managed("originals/\(id.uuidString).txt")
        if fm.fileExists(atPath: original.path) {
            _ = try checkedOriginal(id: id, hash: hash)
        } else {
            let staging = try managed("staging/\(id.uuidString).txt")
            let data = try Data(contentsOf: staging)
            guard contentHash(data) == hash else { throw DiaryError.invalid("保存途中の原文が一致しません。上書きしません。") }
            try durableWrite(data, to: original)
            _ = try checkedOriginal(id: id, hash: hash)
        }
        let staging = try managed("staging/\(id.uuidString).txt")
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
    }

    private func checkedOriginal(id: UUID, hash: String) throws -> Data {
        let data = try Data(contentsOf: managed("originals/\(id.uuidString).txt"))
        guard contentHash(data) == hash else { throw DiaryError.invalid("保存した原文とハッシュが一致しません。原文を確認してください。") }
        return data
    }

    private func getUnlocked(_ id: UUID) throws -> Capture {
        guard let row = try rows("SELECT created, journal_date, raw_hash, revision FROM captures WHERE id=? AND phase='ready'", [id.uuidString]).first else {
            throw DiaryError.invalid("保存された記録が見つかりません。")
        }
        let data = try checkedOriginal(id: id, hash: row[2])
        guard let text = String(data: data, encoding: .utf8), let revision = Int(row[3]) else { throw DiaryError.invalid("保存された記録の形式が不正です。") }
        var item = Capture(id: id, createdAt: row[0], journalDate: row[1].isEmpty ? nil : row[1], text: text, revision: revision)
        if try hasTable("adoptions") {
            let phases = try rows("SELECT phase FROM adoptions WHERE capture_id=?", [id.uuidString])
            item.adopted = phases.first?.first == "ready"
            item.savePending = phases.first?.first == "pending"
        }
        if try hasTable("journal_changes"), !(try rows("SELECT id FROM journal_changes WHERE capture_id=? AND phase='pending'", [id.uuidString])).isEmpty { item.savePending = true }
        return item
    }

    private func managed(_ relative: String) throws -> URL {
        let url = directory.appendingPathComponent(relative)
        try checkPath(url)
        if !readOnly { try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        return url
    }
    private func checkPath(_ url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root.path + "/") else { throw DiaryError.invalid("保存先がライブラリの外を参照しています。") }
    }

    private func durableWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        // 原文のファイル名がDBのpending記録より先に永続化されるようディレクトリも同期。
        let fd = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        if fd >= 0 { defer { Darwin.close(fd) }; guard fsync(fd) == 0 else { throw DiaryError.storage("フォルダを同期できません。") } }
        else { throw DiaryError.storage("保存先フォルダを開けません。") }
    }
    private func requireWritable() throws {
        guard !readOnly else { throw DiaryError.invalid("閲覧専用です。ライブラリは変更しません。") }
        if let recoveryIssue { throw DiaryError.invalid(recoveryIssue) }
        _ = try JournalLocation.directory(in: root)
    }

    private func hasTable(_ name: String) throws -> Bool {
        try !rows("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [name]).isEmpty
    }

    private func pendingJournalMessage() throws -> String? {
        for table in ["adoptions", "journal_changes"] {
            if try hasTable(table), !(try rows("SELECT phase FROM \(table) WHERE phase='pending'")).isEmpty {
                return "日記の保存途中または競合があります。通常表示と保存を停止しています。受け箱で原文を確認し、救出用の退避を作成してください。"
            }
        }
        return nil
    }

    private func pendingMessage() throws -> String? {
        if let message = try pendingJournalMessage() { return message }
        if try !rows("SELECT id FROM captures WHERE phase='pending'").isEmpty {
            return "受け箱の保存途中です。閲覧では回復処理を行いません。救出用の退避を作成してください。"
        }
        return nil
    }

    /// pendingを確定扱いにせず原文だけを点検する。日記一覧との統合には使わない。
    public func capturesForInspection() throws -> [Capture] {
        try locked {
            try rows("SELECT id FROM captures WHERE phase='ready' ORDER BY created DESC, id DESC").map {
                guard let id = UUID(uuidString: $0[0]) else { throw DiaryError.invalid("保存IDが不正です。") }
                return try getUnlocked(id)
            }
        }
    }

    private func validateSchema(version: Int) throws {
        // 名前だけでなく型・NOT NULL・複合主キーの順番まで、書換え前に照合する。
        let definitions: [(String, Int, [String])] = [
            ("captures", 1, ["id:TEXT:0:1", "created:TEXT:1:0", "journal_date:TEXT:0:0", "raw_hash:TEXT:1:0", "phase:TEXT:1:0", "revision:INTEGER:1:0"]),
            ("capture_revisions", 1, ["capture_id:TEXT:1:1", "revision:INTEGER:1:2", "journal_date:TEXT:0:0", "changed:TEXT:1:0"]),
            ("adoptions", 2, ["capture_id:TEXT:0:1", "year:TEXT:1:0", "before_hash:TEXT:1:0", "after_hash:TEXT:1:0", "phase:TEXT:1:0"]),
            ("journal_changes", 3, ["id:TEXT:0:1", "capture_id:TEXT:1:0", "payload:TEXT:1:0", "phase:TEXT:1:0"]),
            ("journal_identity", 4, ["singleton:INTEGER:0:1", "payload:TEXT:1:0"])
        ]
        if version == 0 {
            guard try rows("SELECT name FROM sqlite_master WHERE type='table'").isEmpty else {
                throw DiaryError.invalid("版番号のない既存DBです。変更せず停止しました。")
            }
            return
        }
        for (name, introduced, expected) in definitions {
            let columns = try rows("PRAGMA table_info(\(name))")
            if columns.isEmpty && version < introduced { continue }
            let actual = columns.map { "\($0[1]):\($0[2].uppercased()):\($0[3]):\($0[5])" }
            guard actual == expected else {
                throw DiaryError.invalid("DBの列構成が既知の形式と違います（\(name)）。版番号を変更せず停止しました。")
            }
            if name == "captures", columns[5][4] != "1" {
                throw DiaryError.invalid("DBの改訂番号の初期値が不正です。変更せず停止しました。")
            }
        }
        guard try rows("PRAGMA quick_check").first?.first == "ok",
              try rows("PRAGMA foreign_key_check").isEmpty else {
            throw DiaryError.invalid("DBの整合性検査に失敗しました。変更せず停止しました。")
        }
    }

    private func now() -> String { ISO8601DateFormatter().string(from: Date()) }
    private func validateDate(_ date: String?) throws {
        guard let date else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let parsed = f.date(from: date), f.string(from: parsed) == date else { throw DiaryError.invalid("日付をYYYY-MM-DDで指定してください。") }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        mutex.lock(); defer { mutex.unlock() }
        if readOnly { return try action() }
        let path = directory.appendingPathComponent("writer.lock"); try checkPath(path)
        let fd = Darwin.open(path.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DiaryError.storage("保存ロックを開けません。") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw DiaryError.storage("別の保存処理が動いています。少し待って再実行してください。") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    private func transaction(_ action: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do { try action(); try exec("COMMIT") }
        catch { try? exec("ROLLBACK"); throw error }
    }
    private func exec(_ sql: String, _ values: [String?] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw sqlError() }
        } else {
            let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw sqlError() }
        }
    }
    private func rows(_ sql: String, _ values: [String?] = []) throws -> [[String]] {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw sqlError() }
            result.append((0..<sqlite3_column_count(statement)).map { col in
                guard let text = sqlite3_column_text(statement, col) else { return "" }
                return String(cString: text)
            })
        }
    }
    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw sqlError() }
        for (index, value) in values.enumerated() {
            let code: Int32
            if let value { code = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
            else { code = sqlite3_bind_null(statement, Int32(index + 1)) }
            guard code == SQLITE_OK else { sqlite3_finalize(statement); throw sqlError() }
        }
        return statement
    }
    private func sqlError() -> DiaryError {
        DiaryError.storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "データベースが閉じています。")
    }
}
