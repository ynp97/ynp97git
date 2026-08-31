import SwiftUI
import SQLite3
import AppKit
import UniformTypeIdentifiers

// MARK: - Models

struct Deck: Identifiable, Hashable {
    var id: Int64
    var name: String
    var kind: String // "my" or "opponent"
    var imagePath: String?
    var representativeCard: String?
    var officialURL: String?
}

struct MatchRecord: Identifiable, Hashable {
    var id: Int64
    var playedAt: Date
    var myDeck: String
    var opponentDeck: String
    var turn: String
    var result: String
    var opening: String
    var eventName: String
    var memo: String
}

struct MatchupRow: Identifiable {
    var id: String { opponentDeck }
    let opponentDeck: String
    let wins: Int
    let losses: Int
    let firstWins: Int
    let firstTotal: Int
    let secondWins: Int
    let secondTotal: Int
    var total: Int { wins + losses }
    var winRate: Double { total == 0 ? 0 : Double(wins) / Double(total) }
    // Wilson/Bayesian-lite style: pull small samples toward 50%.
    // priorWeight 4 = 2 pseudo wins + 2 pseudo losses.
    var adjustedWinRate: Double { (Double(wins) + 2.0) / (Double(total) + 4.0) }
    var reliability: String {
        if total >= 10 { return "高" }
        if total >= 5 { return "中" }
        return "低"
    }
    var note: String {
        if total <= 2 { return "参考値" }
        if total <= 4 { return "要検証" }
        return ""
    }
}


struct StatRow: Identifiable {
    var id: String { key }
    let key: String
    let wins: Int
    let losses: Int
    let firstWins: Int
    let firstTotal: Int
    let secondWins: Int
    let secondTotal: Int
    var total: Int { wins + losses }
    var winRate: Double { total == 0 ? 0 : Double(wins) / Double(total) }
    var adjustedWinRate: Double { (Double(wins) + 2.0) / (Double(total) + 4.0) }
    var reliability: String {
        if total >= 20 { return "高" }
        if total >= 8 { return "中" }
        return "低"
    }
}

// MARK: - SQLite Store

@MainActor
final class AppStore: ObservableObject {
    @Published var records: [MatchRecord] = []
    @Published var decks: [Deck] = []
    @Published var selectedTab: Tab = .entry
    @Published var editingRecord: MatchRecord?
    @Published var startupError: String?
    @Published var lastErrorMessage: String?

    private var db: OpaquePointer?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    enum Tab: String, CaseIterable, Identifiable {
        case entry = "入力"
        case records = "一覧"
        case matchup = "相性"
        case stats = "統計"
        case dayStats = "日別"
        case decks = "デッキ"
        case backup = "バックアップ"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .entry: return "square.and.pencil"
            case .records: return "list.bullet.rectangle"
            case .matchup: return "chart.bar.xaxis"
            case .stats: return "chart.pie"
            case .dayStats: return "calendar"
            case .decks: return "rectangle.stack"
            case .backup: return "externaldrive"
            }
        }
    }

    func allDeckNames() -> [String] {
        var set = Set<String>()
        for d in decks {
            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        for r in records {
            let my = r.myDeck.trimmingCharacters(in: .whitespacesAndNewlines)
            let op = r.opponentDeck.trimmingCharacters(in: .whitespacesAndNewlines)
            if !my.isEmpty { set.insert(my) }
            if !op.isEmpty { set.insert(op) }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func myDeckNames() -> [String] {
        var set = Set<String>()
        for d in decks where d.kind == "my" {
            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        for r in records {
            let name = r.myDeck.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func opponentDeckNames() -> [String] {
        var set = Set<String>()
        for d in decks where d.kind == "opponent" {
            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        for r in records {
            let name = r.opponentDeck.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func eventNames() -> [String] {
        var set = Set<String>()
        for r in records {
            let name = r.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { set.insert(name) }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init() {
        do {
            try openDatabase()
            try migrate()
            try loadAll()
        } catch {
            let message = "起動時エラー: \(error.localizedDescription)"
            startupError = message
            lastErrorMessage = message
            writeLog(message)
        }
    }

    func report(_ error: Error) {
        let message = error.localizedDescription
        lastErrorMessage = message
        writeLog("エラー: \(message)")
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func writeLog(_ message: String) {
        let dir = (try? appSupportDirectory()) ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("app_error.log")
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    deinit { sqlite3_close(db) }

    private func appSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PokecaRecordsSwiftUI", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Images", isDirectory: true), withIntermediateDirectories: true)
        return dir
    }

    private func openDatabase() throws {
        let url = try appSupportDirectory().appendingPathComponent("records.sqlite3")
        if sqlite3_open(url.path, &db) != SQLITE_OK { throw StoreError.sqlite("DBを開けませんでした") }
        try exec("PRAGMA foreign_keys = ON;")
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS decks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL COLLATE NOCASE,
            kind TEXT NOT NULL DEFAULT 'my',
            imagePath TEXT,
            representativeCard TEXT,
            officialURL TEXT,
            createdAt TEXT NOT NULL,
            UNIQUE(name, kind)
        );
        """)
        try normalizeDeckTableSchemaIfNeeded()
        try exec("""
        CREATE TABLE IF NOT EXISTS records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playedAt TEXT NOT NULL,
            myDeck TEXT NOT NULL,
            opponentDeck TEXT NOT NULL,
            turn TEXT NOT NULL,
            result TEXT NOT NULL,
            opening TEXT NOT NULL,
            eventName TEXT NOT NULL,
            memo TEXT NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_records_playedAt ON records(playedAt);")
        try exec("CREATE INDEX IF NOT EXISTS idx_records_myDeck ON records(myDeck);")
        try exec("CREATE INDEX IF NOT EXISTS idx_records_opponentDeck ON records(opponentDeck);")
    }

    private func normalizeDeckTableSchemaIfNeeded() throws {
        var createSQL = ""
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='decks';", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { createSQL = colText(stmt, 0) ?? "" }
        }
        sqlite3_finalize(stmt)

        var hasKind = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(decks);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let col = colText(stmt, 1), col == "kind" { hasKind = true }
            }
        }
        sqlite3_finalize(stmt)

        let hasOldUniqueNameOnly = createSQL.contains("UNIQUE COLLATE NOCASE") || createSQL.contains("name TEXT NOT NULL UNIQUE")
        if !hasKind || hasOldUniqueNameOnly {
            try exec("""
            CREATE TABLE IF NOT EXISTS decks_fixed (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL COLLATE NOCASE,
                kind TEXT NOT NULL DEFAULT 'my',
                imagePath TEXT,
                representativeCard TEXT,
                officialURL TEXT,
                createdAt TEXT NOT NULL,
                UNIQUE(name, kind)
            );
            """)
            if hasKind {
                try exec("INSERT OR IGNORE INTO decks_fixed (id,name,kind,imagePath,representativeCard,officialURL,createdAt) SELECT id,name,kind,imagePath,representativeCard,officialURL,createdAt FROM decks;")
            } else {
                try exec("INSERT OR IGNORE INTO decks_fixed (id,name,kind,imagePath,representativeCard,officialURL,createdAt) SELECT id,name,'my',imagePath,representativeCard,officialURL,createdAt FROM decks;")
            }
            try exec("DROP TABLE decks;")
            try exec("ALTER TABLE decks_fixed RENAME TO decks;")
        }
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_decks_name_kind ON decks(name, kind);")
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(err)
            throw StoreError.sqlite(msg)
        }
    }

    func loadAll() throws {
        decks = try fetchDecks()
        records = try fetchRecords()
    }

    private func fetchDecks() throws -> [Deck] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, kind, imagePath, representativeCard, officialURL FROM decks ORDER BY kind ASC, name COLLATE NOCASE ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sqlite(sqliteLastError()) }
        defer { sqlite3_finalize(stmt) }
        var out: [Deck] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Deck(
                id: sqlite3_column_int64(stmt, 0),
                name: colText(stmt, 1) ?? "",
                kind: colText(stmt, 2) ?? "my",
                imagePath: colText(stmt, 3),
                representativeCard: colText(stmt, 4),
                officialURL: colText(stmt, 5)
            ))
        }
        return out
    }

    private func fetchRecords() throws -> [MatchRecord] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, playedAt, myDeck, opponentDeck, turn, result, opening, eventName, memo FROM records ORDER BY playedAt DESC, id DESC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sqlite(sqliteLastError()) }
        defer { sqlite3_finalize(stmt) }
        var out: [MatchRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let iso = colText(stmt, 1) ?? ""
            out.append(MatchRecord(
                id: sqlite3_column_int64(stmt, 0),
                playedAt: dateFormatter.date(from: iso) ?? Date(),
                myDeck: colText(stmt, 2) ?? "",
                opponentDeck: colText(stmt, 3) ?? "",
                turn: colText(stmt, 4) ?? "",
                result: colText(stmt, 5) ?? "",
                opening: colText(stmt, 6) ?? "",
                eventName: colText(stmt, 7) ?? "",
                memo: colText(stmt, 8) ?? ""
            ))
        }
        return out
    }

    func saveRecord(_ record: MatchRecord) throws {
        if record.id == 0 { try insertRecord(record) } else { try updateRecord(record) }
        try ensureDeck(record.myDeck, kind: "my")
        try ensureDeck(record.opponentDeck, kind: "opponent")
        try loadAll()
    }

    private func insertRecord(_ r: MatchRecord) throws {
        let sql = "INSERT INTO records (playedAt,myDeck,opponentDeck,turn,result,opening,eventName,memo) VALUES (?,?,?,?,?,?,?,?);"
        try withStatement(sql) { stmt in
            bindText(stmt, 1, dateFormatter.string(from: r.playedAt))
            bindText(stmt, 2, r.myDeck)
            bindText(stmt, 3, r.opponentDeck)
            bindText(stmt, 4, r.turn)
            bindText(stmt, 5, r.result)
            bindText(stmt, 6, r.opening)
            bindText(stmt, 7, r.eventName)
            bindText(stmt, 8, r.memo)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
        }
    }

    private func updateRecord(_ r: MatchRecord) throws {
        let sql = "UPDATE records SET playedAt=?,myDeck=?,opponentDeck=?,turn=?,result=?,opening=?,eventName=?,memo=? WHERE id=?;"
        try withStatement(sql) { stmt in
            bindText(stmt, 1, dateFormatter.string(from: r.playedAt))
            bindText(stmt, 2, r.myDeck)
            bindText(stmt, 3, r.opponentDeck)
            bindText(stmt, 4, r.turn)
            bindText(stmt, 5, r.result)
            bindText(stmt, 6, r.opening)
            bindText(stmt, 7, r.eventName)
            bindText(stmt, 8, r.memo)
            sqlite3_bind_int64(stmt, 9, r.id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
        }
    }

    func deleteRecord(_ id: Int64) throws {
        try withStatement("DELETE FROM records WHERE id=?;") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
        }
        try loadAll()
    }

    func ensureDeck(_ name: String, kind: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try withStatement("INSERT OR IGNORE INTO decks (name, kind, createdAt) VALUES (?, ?, ?);") { stmt in
            bindText(stmt, 1, trimmed)
            bindText(stmt, 2, kind)
            bindText(stmt, 3, dateFormatter.string(from: Date()))
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
        }
    }

    func registerDeckName(_ name: String, kind: String) throws {
        try ensureDeck(name, kind: kind)
        try loadAll()
    }

    func beginEditingRecord(_ record: MatchRecord) {
        editingRecord = record
        selectedTab = .entry
    }

    func beginDuplicatingRecord(_ record: MatchRecord) {
        editingRecord = MatchRecord(id: 0, playedAt: Date(), myDeck: record.myDeck, opponentDeck: record.opponentDeck, turn: record.turn, result: record.result, opening: record.opening, eventName: record.eventName, memo: record.memo)
        selectedTab = .entry
    }

    func saveDeck(_ deck: Deck) throws {
        if deck.id == 0 {
            try withStatement("""
            INSERT INTO decks (name,kind,imagePath,representativeCard,officialURL,createdAt)
            VALUES (?,?,?,?,?,?)
            ON CONFLICT(name, kind) DO UPDATE SET
                imagePath = CASE WHEN excluded.imagePath <> '' THEN excluded.imagePath ELSE decks.imagePath END,
                representativeCard = CASE WHEN excluded.representativeCard <> '' THEN excluded.representativeCard ELSE decks.representativeCard END,
                officialURL = CASE WHEN excluded.officialURL <> '' THEN excluded.officialURL ELSE decks.officialURL END;
            """) { stmt in
                bindText(stmt, 1, deck.name)
                bindText(stmt, 2, deck.kind)
                bindText(stmt, 3, deck.imagePath ?? "")
                bindText(stmt, 4, deck.representativeCard ?? "")
                bindText(stmt, 5, deck.officialURL ?? "")
                bindText(stmt, 6, dateFormatter.string(from: Date()))
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
            }
        } else {
            try withStatement("UPDATE decks SET name=?, kind=?, imagePath=?, representativeCard=?, officialURL=? WHERE id=?;") { stmt in
                bindText(stmt, 1, deck.name)
                bindText(stmt, 2, deck.kind)
                bindText(stmt, 3, deck.imagePath ?? "")
                bindText(stmt, 4, deck.representativeCard ?? "")
                bindText(stmt, 5, deck.officialURL ?? "")
                sqlite3_bind_int64(stmt, 6, deck.id)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
            }
        }
        try loadAll()
    }

    func deleteDeck(_ id: Int64) throws {
        try withStatement("DELETE FROM decks WHERE id=?;") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sqlite(sqliteLastError()) }
        }
        try loadAll()
    }

    func copyImageForDeck(source: URL) throws -> String {
        let dir = try appSupportDirectory().appendingPathComponent("Images", isDirectory: true)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let dest = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.path
    }

    func matchupRows(myDeck: String, minimumGames: Int, sort: MatchupSort) -> [MatchupRow] {
        let filtered = records.filter { $0.myDeck == myDeck }
        let grouped = Dictionary(grouping: filtered, by: { $0.opponentDeck })
        var rows = grouped.map { opponent, items -> MatchupRow in
            let wins = items.filter { $0.result == "勝ち" }.count
            let losses = items.filter { $0.result == "負け" }.count
            let first = items.filter { $0.turn == "先攻" }
            let second = items.filter { $0.turn == "後攻" }
            return MatchupRow(
                opponentDeck: opponent,
                wins: wins,
                losses: losses,
                firstWins: first.filter { $0.result == "勝ち" }.count,
                firstTotal: first.count,
                secondWins: second.filter { $0.result == "勝ち" }.count,
                secondTotal: second.count
            )
        }.filter { $0.total >= minimumGames }

        switch sort {
        case .adjustedDesc: rows.sort { $0.adjustedWinRate > $1.adjustedWinRate }
        case .weakness: rows.sort { $0.adjustedWinRate < $1.adjustedWinRate }
        case .actualDesc: rows.sort { $0.winRate > $1.winRate }
        case .gamesDesc: rows.sort { $0.total > $1.total }
        case .needsTesting: rows.sort { ($0.note.isEmpty ? 1 : 0, $0.total) < ($1.note.isEmpty ? 1 : 0, $1.total) }
        case .name: rows.sort { $0.opponentDeck.localizedStandardCompare($1.opponentDeck) == .orderedAscending }
        }
        return rows
    }

    func monthStats() -> [StatRow] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年MM月"
        let grouped = Dictionary(grouping: records, by: { formatter.string(from: $0.playedAt) })
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted { $0.key > $1.key }
    }


    func dayStats() -> [StatRow] {
        let grouped = Dictionary(grouping: records, by: { dayKey(for: $0.playedAt) })
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted { $0.key > $1.key }
    }

    func records(forDayKey key: String) -> [MatchRecord] {
        records.filter { dayKey(for: $0.playedAt) == key }
            .sorted { $0.playedAt < $1.playedAt }
    }

    func dayDetailStats(dayKey key: String, scope: DayDetailScope) -> [StatRow] {
        let items = records(forDayKey: key)
        let grouped: [String: [MatchRecord]]
        switch scope {
        case .myDeck:
            grouped = Dictionary(grouping: items, by: { $0.myDeck.isEmpty ? "未入力" : $0.myDeck })
        case .opponentDeck:
            grouped = Dictionary(grouping: items, by: { $0.opponentDeck.isEmpty ? "未入力" : $0.opponentDeck })
        case .event:
            grouped = Dictionary(grouping: items, by: { $0.eventName.isEmpty ? "未入力" : $0.eventName })
        }
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted {
                if $0.total != $1.total { return $0.total > $1.total }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
    }

    func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "ja_JP_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    enum DayDetailScope: String, CaseIterable, Identifiable {
        case myDeck = "自分デッキ"
        case opponentDeck = "相手デッキ"
        case event = "大会"
        var id: String { rawValue }
    }

    func myDeckStats() -> [StatRow] {
        let grouped = Dictionary(grouping: records, by: { $0.myDeck.isEmpty ? "未入力" : $0.myDeck })
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted {
                if $0.total != $1.total { return $0.total > $1.total }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
    }

    func opponentDeckStats() -> [StatRow] {
        let grouped = Dictionary(grouping: records, by: { $0.opponentDeck.isEmpty ? "未入力" : $0.opponentDeck })
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted {
                if $0.total != $1.total { return $0.total > $1.total }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
    }

    func eventStats() -> [StatRow] {
        let grouped = Dictionary(grouping: records, by: { $0.eventName.isEmpty ? "未入力" : $0.eventName })
        return grouped.map { key, items in statRow(key: key, items: items) }
            .sorted { $0.total > $1.total }
    }

    func overallStats() -> StatRow {
        statRow(key: "全体", items: records)
    }

    private func statRow(key: String, items: [MatchRecord]) -> StatRow {
        let wins = items.filter { $0.result == "勝ち" }.count
        let losses = items.filter { $0.result == "負け" }.count
        let first = items.filter { $0.turn == "先攻" }
        let second = items.filter { $0.turn == "後攻" }
        return StatRow(
            key: key,
            wins: wins,
            losses: losses,
            firstWins: first.filter { $0.result == "勝ち" }.count,
            firstTotal: first.count,
            secondWins: second.filter { $0.result == "勝ち" }.count,
            secondTotal: second.count
        )
    }

    enum MatchupSort: String, CaseIterable, Identifiable {
        case adjustedDesc = "補正勝率順"
        case weakness = "苦手順"
        case actualDesc = "実勝率順"
        case gamesDesc = "試合数順"
        case needsTesting = "要検証順"
        case name = "あいうえお順"
        var id: String { rawValue }
    }

    func exportJSON(to url: URL) throws {
        let payload = BackupPayload(records: records, decks: decks)
        let data = try JSONEncoder.withDates.encode(payload)
        try data.write(to: url)
    }

    func importJSON(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder.withDates.decode(BackupPayload.self, from: data)
        try exec("DELETE FROM records; DELETE FROM decks;")
        for d in payload.decks { try saveDeck(d) }
        for r in payload.records { try saveRecord(MatchRecord(id: 0, playedAt: r.playedAt, myDeck: r.myDeck, opponentDeck: r.opponentDeck, turn: r.turn, result: r.result, opening: r.opening, eventName: r.eventName, memo: r.memo)) }
        try loadAll()
    }

    func exportCSV(to url: URL) throws {
        var lines = ["日付,時刻,自分のデッキ,相手のデッキ,先後,勝敗,初手,大会,メモ"]
        let df = DateFormatter(); df.calendar = Calendar(identifier: .gregorian); df.locale = Locale(identifier: "ja_JP_POSIX"); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.calendar = Calendar(identifier: .gregorian); tf.locale = Locale(identifier: "ja_JP_POSIX"); tf.dateFormat = "HH:mm:ss"
        for r in records {
            lines.append([df.string(from: r.playedAt), tf.string(from: r.playedAt), r.myDeck, r.opponentDeck, r.turn, r.result, r.opening, r.eventName, r.memo].map(csvEscape).joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func withStatement(_ sql: String, _ block: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sqlite(sqliteLastError()) }
        defer { sqlite3_finalize(stmt) }
        try block(stmt)
    }

    private func sqliteLastError() -> String { String(cString: sqlite3_errmsg(db)) }
}

private enum StoreError: LocalizedError {
    case sqlite(String)
    case message(String)
    var errorDescription: String? {
        switch self {
        case .sqlite(let s): return s
        case .message(let s): return s
        }
    }
}

private func colText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
    guard let c = sqlite3_column_text(stmt, index) else { return nil }
    let s = String(cString: c)
    return s.isEmpty ? nil : s
}

private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct BackupPayload: Codable {
    let records: [MatchRecord]
    let decks: [Deck]
}

extension Deck: Codable {
    enum CodingKeys: String, CodingKey { case id, name, kind, imagePath, representativeCard, officialURL }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "my"
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        representativeCard = try c.decodeIfPresent(String.self, forKey: .representativeCard)
        officialURL = try c.decodeIfPresent(String.self, forKey: .officialURL)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(imagePath, forKey: .imagePath)
        try c.encodeIfPresent(representativeCard, forKey: .representativeCard)
        try c.encodeIfPresent(officialURL, forKey: .officialURL)
    }
}
extension MatchRecord: Codable {}

extension JSONEncoder {
    static var withDates: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
extension JSONDecoder {
    static var withDates: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - App

@main
struct PokecaRecordsApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("ポケカ戦績") {
            RootView().environmentObject(store)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}

// MARK: - Views

struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedTab) {
                Section("メニュー") {
                    ForEach(AppStore.Tab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
            }
            .navigationSplitViewColumnWidth(195)
            .listStyle(.sidebar)
            .tint(.blue)
        } detail: {
            VStack(spacing: 0) {
                if let startupError = store.startupError {
                    ErrorBanner(text: startupError)
                } else if let lastErrorMessage = store.lastErrorMessage {
                    ErrorBanner(text: lastErrorMessage)
                }
                Group {
                    switch store.selectedTab {
                    case .entry: EntryView()
                    case .records: RecordsView()
                    case .matchup: MatchupView()
                    case .stats: StatsView()
                    case .dayStats: DayStatsView()
                    case .decks: DecksView()
                    case .backup: BackupView()
                    }
                }
                .background(AppTheme.background)
            }
        }
    }
}


struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
    }
}

struct EntryView: View {
    @EnvironmentObject var store: AppStore
    @State private var playedAt = Date()
    @State private var myDeck = ""
    @State private var opponentDeck = ""
    @State private var turn = "先攻"
    @State private var result = "勝ち"
    @State private var opening = "B"
    @State private var eventName = ""
    @State private var memo = ""
    @State private var saveFeedback: String?
    @State private var saveFeedbackIsUpdate = false
    @State private var myDeckPriority: [String] = UserDefaults.standard.stringArray(forKey: "priority_myDecks") ?? []
    @State private var opponentDeckPriority: [String] = UserDefaults.standard.stringArray(forKey: "priority_opponentDecks") ?? []
    @State private var eventPriority: [String] = UserDefaults.standard.stringArray(forKey: "priority_events") ?? []

    let memoButtons = ["事故", "プレミ", "相手事故", "リソース切れ", "サイド先行", "後半逆転", "要練習"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.editingRecord == nil ? "戦績入力" : "戦績編集").font(.largeTitle.bold())
                        Text(store.editingRecord == nil ? "新しい対戦を記録" : "選択した対戦を更新")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("今日・現在時刻") { playedAt = Date() }
                    Button("直近を複製") { duplicateLatest() }.disabled(store.records.isEmpty)
                }
                if let saveFeedback {
                    SaveFeedbackBanner(text: saveFeedback, isUpdate: saveFeedbackIsUpdate)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow { Text("日時"); DatePicker("", selection: $playedAt).labelsHidden().environment(\.locale, Locale(identifier: "ja_JP@calendar=gregorian")) }
                    GridRow { Text("自分のデッキ"); deckField($myDeck, names: store.myDeckNames(), kind: "my", priority: $myDeckPriority, priorityKey: "priority_myDecks") }
                    GridRow { Text("相手のデッキ"); deckField($opponentDeck, names: store.opponentDeckNames(), kind: "opponent", priority: $opponentDeckPriority, priorityKey: "priority_opponentDecks") }
                    GridRow { Text("先/後"); segmented($turn, ["先攻", "後攻"]) }
                    GridRow { Text("勝敗"); HStack { segmented($result, ["勝ち", "負け"]); ResultBadge(result: result) } }
                    GridRow { Text("初手"); segmented($opening, ["A", "B", "C", "D"]) }
                    GridRow { Text("大会"); eventField($eventName, names: store.eventNames(), priority: $eventPriority, priorityKey: "priority_events") }
                    GridRow { Text("メモ"); TextEditor(text: $memo).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary)) }
                }
                HStack {
                    ForEach(memoButtons, id: \.self) { word in Button(word) { appendMemo(word) } }
                }
                HStack {
                    Button(store.editingRecord == nil ? "保存する" : "更新する") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(result == "勝ち" ? winColor : lossColor)
                    if store.editingRecord != nil { Button("編集をキャンセル") { clear(editing: true) } }
                }
                }
                .padding(18)
                .background(LinearGradient(colors: [Color.blue.opacity(0.105), Color.green.opacity(0.065), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.blue.opacity(0.18)))
                .shadow(color: Color.blue.opacity(0.08), radius: 12, x: 0, y: 5)
            }.padding(24)
        }
        .onAppear {
            loadEditingRecord(store.editingRecord)
        }
        .onChange(of: store.editingRecord) { record in
            loadEditingRecord(record)
        }
    }

    private func loadEditingRecord(_ record: MatchRecord?) {
        guard let r = record else { return }
        playedAt = r.playedAt
        myDeck = r.myDeck
        opponentDeck = r.opponentDeck
        turn = r.turn
        result = r.result
        opening = r.opening
        eventName = r.eventName
        memo = r.memo
        saveFeedback = nil
    }

    private func deckField(_ binding: Binding<String>, names: [String], kind: String, priority: Binding<[String]>, priorityKey: String) -> some View {
        let ordered = orderedCandidates(names: names, counts: usageCounts(kind: kind), priority: priority.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("デッキ名を入力、または右の選択から選ぶ", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 440)
                Menu("選択") {
                    if ordered.isEmpty {
                        Text("まだ候補がありません")
                    } else {
                        ForEach(ordered, id: \.self) { name in
                            Button(candidateTitle(name, counts: usageCounts(kind: kind))) { binding.wrappedValue = name }
                        }
                    }
                }
                .menuStyle(.borderedButton)
                Button("登録") { registerDeckFromInput(binding.wrappedValue, kind: kind) }
                    .disabled(binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("クリア") { binding.wrappedValue = "" }
            }
            candidatePinControls(value: binding.wrappedValue, priority: priority, priorityKey: priorityKey)
            if !ordered.isEmpty {
                candidateChips(ordered: ordered, binding: binding, counts: usageCounts(kind: kind))
            }
        }
    }

    private func registerDeckFromInput(_ value: String, kind: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.registerDeckName(trimmed, kind: kind)
            showSaveFeedback("デッキを登録しました！")
        } catch { store.report(error) }
    }

    private func eventField(_ binding: Binding<String>, names: [String], priority: Binding<[String]>, priorityKey: String) -> some View {
        let ordered = orderedCandidates(names: names, counts: usageCounts(kind: "event"), priority: priority.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("例：ジムバトル / フリー", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 440)
                Menu("選択") {
                    if ordered.isEmpty {
                        Text("まだ候補がありません")
                    } else {
                        ForEach(ordered, id: \.self) { name in
                            Button(candidateTitle(name, counts: usageCounts(kind: "event"))) { binding.wrappedValue = name }
                        }
                    }
                }
                .menuStyle(.borderedButton)
                Button("クリア") { binding.wrappedValue = "" }
            }
            candidatePinControls(value: binding.wrappedValue, priority: priority, priorityKey: priorityKey)
            if !ordered.isEmpty {
                candidateChips(ordered: ordered, binding: binding, counts: usageCounts(kind: "event"))
            }
        }
    }

    private func usageCounts(kind: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for r in store.records {
            let raw: String
            switch kind {
            case "my": raw = r.myDeck
            case "opponent": raw = r.opponentDeck
            default: raw = r.eventName
            }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { counts[name, default: 0] += 1 }
        }
        return counts
    }

    private func orderedCandidates(names: [String], counts: [String: Int], priority: [String]) -> [String] {
        let unique = Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        let priorityIndex = Dictionary(uniqueKeysWithValues: priority.enumerated().map { ($0.element, $0.offset) })
        return unique.sorted { a, b in
            let ai = priorityIndex[a]
            let bi = priorityIndex[b]
            if ai != nil || bi != nil {
                if let ai, let bi { return ai < bi }
                return ai != nil
            }
            let ac = counts[a, default: 0]
            let bc = counts[b, default: 0]
            if ac != bc { return ac > bc }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    private func candidateTitle(_ name: String, counts: [String: Int]) -> String {
        let c = counts[name, default: 0]
        return c > 0 ? "\(name)（\(c)回）" : name
    }

    private func candidateChips(ordered: [String], binding: Binding<String>, counts: [String: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ordered, id: \.self) { name in
                    Button(candidateTitle(name, counts: counts)) { binding.wrappedValue = name }
                        .buttonStyle(.bordered)
                        .tint(binding.wrappedValue == name ? Color.blue : Color.secondary)
                }
            }
        }
        .frame(height: 38)
    }

    private func candidatePinControls(value: String, priority: Binding<[String]>, priorityKey: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPinned = priority.wrappedValue.contains(trimmed)
        return HStack(spacing: 6) {
            if !trimmed.isEmpty {
                Button(isPinned ? "固定を解除" : "左端に固定") {
                    if isPinned {
                        unpinCandidate(trimmed, priority: priority, key: priorityKey)
                    } else {
                        pinCandidate(trimmed, priority: priority, key: priorityKey)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func pinCandidate(_ value: String, priority: Binding<[String]>, key: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var list = priority.wrappedValue.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        list.removeAll { $0 == name }
        list.insert(name, at: 0)
        priority.wrappedValue = list
        UserDefaults.standard.set(list, forKey: key)
    }

    private func unpinCandidate(_ value: String, priority: Binding<[String]>, key: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = priority.wrappedValue
        list.removeAll { $0 == name }
        priority.wrappedValue = list
        UserDefaults.standard.set(list, forKey: key)
    }

    private func segmented(_ binding: Binding<String>, _ values: [String]) -> some View { Picker("", selection: binding) { ForEach(values, id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(maxWidth: 300) }
    private func appendMemo(_ word: String) { memo += memo.isEmpty ? word : "、\(word)" }
    private func duplicateLatest() {
        guard let r = store.records.first else { return }
        myDeck = r.myDeck; opponentDeck = r.opponentDeck; turn = r.turn; result = r.result; opening = r.opening; eventName = r.eventName; memo = r.memo; playedAt = Date()
    }
    private func save() {
        let trimmedMyDeck = myDeck.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpponentDeck = opponentDeck.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMyDeck.isEmpty, !trimmedOpponentDeck.isEmpty else {
            showSaveFeedback("自分のデッキと相手デッキを入力してください")
            return
        }
        let id = store.editingRecord?.id ?? 0
        do {
            let wasEditing = store.editingRecord != nil
            try store.saveRecord(MatchRecord(id: id, playedAt: playedAt, myDeck: trimmedMyDeck, opponentDeck: trimmedOpponentDeck, turn: turn, result: result, opening: opening, eventName: eventName.trimmingCharacters(in: .whitespacesAndNewlines), memo: memo))
            showSaveFeedback(wasEditing ? "更新しました！" : "保存しました！")
            clear(editing: true, keepFeedback: true)
        } catch { store.report(error) }
    }
    private func showSaveFeedback(_ text: String) {
        saveFeedback = text
        saveFeedbackIsUpdate = text.contains("更新")
        store.clearLastError()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            saveFeedback = nil
        }
    }

    private func clear(editing: Bool, keepFeedback: Bool = false) {
        playedAt = Date(); myDeck = ""; opponentDeck = ""; turn = "先攻"; result = "勝ち"; opening = "B"; eventName = ""; memo = ""
        if !keepFeedback { saveFeedback = nil }
        if editing { store.editingRecord = nil }
    }
}

struct RecordsView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var selectedRecordId: MatchRecord.ID? = nil
    @State private var pendingDeleteRecordId: Int64? = nil
    var filtered: [MatchRecord] {
        query.isEmpty ? store.records : store.records.filter { [$0.myDeck,$0.opponentDeck,$0.eventName,$0.memo].joined(separator: " ").localizedCaseInsensitiveContains(query) }
    }
    var selectedRecord: MatchRecord? {
        guard let selectedRecordId else { return nil }
        return store.records.first(where: { $0.id == selectedRecordId })
    }
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                HeaderTitle(title: "戦績一覧", subtitle: "勝敗を色で俯瞰", systemImage: "list.bullet.rectangle", accent: .blue).frame(maxWidth: 360)
                Spacer()
                Button("選択した戦績を編集") {
                    if let record = selectedRecord { pendingDeleteRecordId = nil; store.beginEditingRecord(record) }
                }
                .disabled(selectedRecord == nil)
                .buttonStyle(.bordered)
                Button("選択した戦績を複製") {
                    if let record = selectedRecord { pendingDeleteRecordId = nil; store.beginDuplicatingRecord(record) }
                }
                .disabled(selectedRecord == nil)
                .buttonStyle(.bordered)
                Button("選択した戦績を削除") {
                    if let id = selectedRecordId { pendingDeleteRecordId = id }
                }
                .disabled(selectedRecordId == nil)
                .buttonStyle(.bordered)
                TextField("検索", text: $query).textFieldStyle(.roundedBorder).frame(width: 260)
            }
             if let id = pendingDeleteRecordId, let target = store.records.first(where: { $0.id == id }) {
                HStack(spacing: 10) {
                    Text("削除確認：\(date(target.playedAt))  \(target.myDeck) vs \(target.opponentDeck)")
                        .font(.callout.weight(.semibold))
                    Button("本当に削除", role: .destructive) {
                        do {
                            try store.deleteRecord(id)
                            if selectedRecordId == id { selectedRecordId = nil }
                            pendingDeleteRecordId = nil
                        } catch { store.report(error) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("取消") { pendingDeleteRecordId = nil }
                }
                .padding(10)
                .background(.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Table(filtered, selection: $selectedRecordId) {
                TableColumn("日付") { Text(date($0.playedAt)) }.width(90)
                TableColumn("時刻") { Text(time($0.playedAt)) }.width(70)
                TableColumn("自分のデッキ") { DeckNameView(name: $0.myDeck) }.width(min: 150, ideal: 190)
                TableColumn("相手のデッキ") { DeckNameView(name: $0.opponentDeck) }.width(min: 150, ideal: 190)
                TableColumn("先/後") { TurnBadge(turn: $0.turn) }.width(64)
                TableColumn("勝敗") { ResultBadge(result: $0.result) }.width(74)
                TableColumn("初手") { OpeningBadge(opening: $0.opening) }.width(54)
                TableColumn("大会") { Text($0.eventName) }.width(min: 110, ideal: 150)
                TableColumn("メモ") { Text($0.memo).lineLimit(1) }.width(min: 180, ideal: 260)
                TableColumn("操作") { r in
                    HStack(spacing: 6) {
                        Button("編集") {
                            selectedRecordId = r.id
                            pendingDeleteRecordId = nil
                            store.beginEditingRecord(r)
                        }
                        .buttonStyle(.borderless)
                        Button("複製") {
                            selectedRecordId = r.id
                            pendingDeleteRecordId = nil
                            store.beginDuplicatingRecord(r)
                        }
                        .buttonStyle(.borderless)
                        Button(pendingDeleteRecordId == r.id ? "確認中" : "削除") {
                            selectedRecordId = r.id
                            pendingDeleteRecordId = r.id
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }.width(190)
            }
        }.padding(20)
        .onChange(of: filtered.map(\.id)) { ids in
            if let selectedRecordId, !ids.contains(selectedRecordId) { self.selectedRecordId = nil }
        }
    }
    private func date(_ d: Date) -> String { gregorianDateString(d) }
    private func time(_ d: Date) -> String { gregorianTimeString(d) }
}

struct EmptyStateView: View {
    let message: String
    let systemImage: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.55))
            Text(message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(44)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.blue.opacity(0.12)))
    }
}

struct MatchupView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedDeck = ""
    @State private var minimumGames = 1
    @State private var sort: AppStore.MatchupSort = .adjustedDesc
    var selectableDecks: [String] { store.myDeckNames() }
    var rows: [MatchupRow] { store.matchupRows(myDeck: selectedDeck, minimumGames: minimumGames, sort: sort) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderTitle(title: "相性表", subtitle: "実勝率と補正勝率を色で比較", systemImage: "chart.bar.xaxis", accent: .purple)
            HStack {
                Picker("自分のデッキ", selection: $selectedDeck) { Text("選択").tag(""); ForEach(selectableDecks, id: \.self) { Text($0).tag($0) } }.frame(width: 280)
                Picker("最低試合数", selection: $minimumGames) { ForEach([1,2,3,5,10], id: \.self) { Text($0 == 1 ? "全部" : "\($0)戦以上").tag($0) } }.frame(width: 180)
                Picker("並び順", selection: $sort) { ForEach(AppStore.MatchupSort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 220)
            }
            if selectableDecks.isEmpty {
                EmptyStateView(message: "まだ戦績がありません。入力画面でデッキ名を直接入力して保存すると、相性表に出ます。", systemImage: "rectangle.stack")
            } else if selectedDeck.isEmpty {
                EmptyStateView(message: "デッキを選択してください", systemImage: "rectangle.stack")
            } else if rows.isEmpty {
                EmptyStateView(message: "条件に合う相性データがありません。最低試合数を下げてください。", systemImage: "chart.bar")
            } else {
                ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) { ForEach(rows) { MatchupCard(row: $0) } }.padding(.vertical, 4) }
            }
        }.padding(20)
        .onAppear { selectDefaultDeckIfNeeded() }
        .onChange(of: store.records) { _ in selectDefaultDeckIfNeeded() }
        .onChange(of: store.decks) { _ in selectDefaultDeckIfNeeded() }
    }

    private func selectDefaultDeckIfNeeded() {
        let names = selectableDecks
        if selectedDeck.isEmpty || !names.contains(selectedDeck) {
            selectedDeck = names.first ?? ""
        }
    }
}

struct MatchupCard: View {
    let row: MatchupRow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("対 \(row.opponentDeck)").font(.headline).lineLimit(1)
                Spacer()
                ReliabilityBadge(text: row.reliability)
                if !row.note.isEmpty { NoteBadge(text: row.note) }
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(percent(row.winRate)).font(.system(size: 32, weight: .bold)).foregroundStyle(winRateColor(row.winRate))
                    Text("実勝率").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(percent(row.adjustedWinRate)).font(.system(size: 24, weight: .semibold)).foregroundStyle(winRateColor(row.adjustedWinRate))
                    Text("補正勝率").font(.caption).foregroundStyle(.secondary)
                }
            }
            WinLossBar(wins: row.wins, losses: row.losses)
            HStack {
                ResultCountBadge(label: "勝ち", count: row.wins, color: winColor)
                ResultCountBadge(label: "負け", count: row.losses, color: lossColor)
                Text("/ \(row.total)戦").foregroundStyle(.secondary)
                Spacer()
            }
            Text("先攻：\(row.firstWins)勝\(max(0,row.firstTotal-row.firstWins))敗 / 後攻：\(row.secondWins)勝\(max(0,row.secondTotal-row.secondWins))敗")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(LinearGradient(colors: [winRateBackground(row.adjustedWinRate), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(winRateColor(row.adjustedWinRate).opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: winRateColor(row.adjustedWinRate).opacity(0.10), radius: 10, x: 0, y: 4)
    }
    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}



struct DayStatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedDayKey: String?
    @State private var detailScope: AppStore.DayDetailScope = .myDeck

    var dayRows: [StatRow] { store.dayStats() }
    var selectedSummary: StatRow? {
        guard let selectedDayKey else { return nil }
        return dayRows.first { $0.key == selectedDayKey }
    }
    var selectedRecords: [MatchRecord] {
        guard let selectedDayKey else { return [] }
        return store.records(forDayKey: selectedDayKey)
    }
    var detailRows: [StatRow] {
        guard let selectedDayKey else { return [] }
        return store.dayDetailStats(dayKey: selectedDayKey, scope: detailScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("日別統計")
                    .font(.largeTitle.bold())
                Spacer()
                Text("各日をクリックすると詳細分析を表示")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if dayRows.isEmpty {
                EmptyStateView(message: "まだ日別統計を表示できる戦績がありません。", systemImage: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                HSplitView {
                    DayStatsListPanel(dayRows: dayRows, selectedDayKey: $selectedDayKey)
                        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560)
                        .onAppear {
                            if selectedDayKey == nil { selectedDayKey = dayRows.first?.key }
                        }

                    DayDetailPanel(
                        dayKey: selectedDayKey,
                        summary: selectedSummary,
                        records: selectedRecords,
                        detailScope: $detailScope,
                        detailRows: detailRows
                    )
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

struct DayStatsListPanel: View {
    let dayRows: [StatRow]
    @Binding var selectedDayKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("日ごとの成績")
                    .font(.headline)
                Spacer()
                Text("\(dayRows.count)日")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            DayStatsHeaderRow()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(dayRows) { row in
                        Button {
                            selectedDayKey = row.key
                        } label: {
                            DayStatsListRow(row: row, isSelected: selectedDayKey == row.key)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.14)))
        .shadow(color: Color.blue.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

struct DayStatsHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("日付").frame(width: 112, alignment: .leading)
            Text("勝敗").frame(width: 86, alignment: .center)
            Text("勝率").frame(width: 58, alignment: .trailing)
            Text("先/後").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.gray.opacity(0.10))
    }
}

struct DayStatsListRow: View {
    let row: StatRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.key)
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                Text("\(row.total)戦")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)

            HStack(spacing: 4) {
                Text("\(row.wins)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(winColor)
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(row.losses)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(lossColor)
            }
            .frame(width: 86)

            Text(percent(row.winRate))
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(winRateColor(row.winRate))
                .frame(width: 58, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text("先 " + turnText(wins: row.firstWins, total: row.firstTotal))
                    .lineLimit(1)
                Text("後 " + turnText(wins: row.secondWins, total: row.secondTotal))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.18) : winRateBackground(row.adjustedWinRate).opacity(0.66))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

struct DayDetailPanel: View {
    let dayKey: String?
    let summary: StatRow?
    let records: [MatchRecord]
    @Binding var detailScope: AppStore.DayDetailScope
    let detailRows: [StatRow]

    var body: some View {
        Group {
            if let dayKey, let summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(dayKey)
                                    .font(.title.bold())
                                    .monospacedDigit()
                                Text("この日の分析")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ReliabilityBadge(text: summary.reliability)
                        }

                        HStack(spacing: 12) {
                            StatSummaryCard(title: "試合", value: "\(summary.total)戦", detail: "\(summary.wins)勝\(summary.losses)敗")
                            StatSummaryCard(title: "実勝率", value: percent(summary.winRate), detail: "補正 \(percent(summary.adjustedWinRate))")
                            StatSummaryCard(title: "先攻/後攻", value: "\(summary.firstTotal)/\(summary.secondTotal)", detail: "先\(summary.firstWins)勝・後\(summary.secondWins)勝")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            WinLossBar(wins: summary.wins, losses: summary.losses)
                                .frame(height: 12)
                            HStack(spacing: 10) {
                                TurnBadge(turn: "先攻")
                                Text(turnText(wins: summary.firstWins, total: summary.firstTotal))
                                TurnBadge(turn: "後攻")
                                Text(turnText(wins: summary.secondWins, total: summary.secondTotal))
                                Spacer()
                            }
                            .font(.callout)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("内訳")
                                    .font(.headline)
                                Spacer()
                            }
                            Picker("分析", selection: $detailScope) {
                                ForEach(AppStore.DayDetailScope.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            if detailRows.isEmpty {
                                EmptyStateView(message: "表示できる内訳がありません。", systemImage: "chart.bar")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(detailRows) { row in
                                        DayDetailStatRow(row: row)
                                        Divider()
                                    }
                                }
                                .background(Color.white.opacity(0.62))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.20)))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("この日の対戦履歴")
                                .font(.headline)
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(records) { r in
                                    DayRecordMiniRow(record: r)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .background(Color.white.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                EmptyStateView(message: "左の一覧から日付を選択してください。", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct DayDetailStatRow: View {
    let row: StatRow
    var body: some View {
        HStack(spacing: 8) {
            Text(row.key)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.total)戦")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            HStack(spacing: 3) {
                Text("\(row.wins)").font(.caption.bold()).foregroundStyle(winColor)
                Text("-").font(.caption)
                Text("\(row.losses)").font(.caption.bold()).foregroundStyle(lossColor)
            }
            .frame(width: 48, alignment: .trailing)
            Text(percent(row.winRate))
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(winRateColor(row.winRate))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(winRateBackground(row.adjustedWinRate).opacity(0.55))
    }
}

struct DayRecordMiniRow: View {
    let record: MatchRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(gregorianTimeString(record.playedAt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                ResultBadge(result: record.result)
                TurnBadge(turn: record.turn)
                OpeningBadge(opening: record.opening)
                Spacer()
            }
            HStack(spacing: 6) {
                Text(record.myDeck).font(.callout.weight(.semibold)).lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.opponentDeck).font(.callout).lineLimit(1)
            }
            if !record.eventName.isEmpty || !record.memo.isEmpty {
                Text([record.eventName, record.memo].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background((record.result == "勝ち" ? Color.green : Color.red).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var scope: Scope = .month
    @State private var minimumGames = 1

    enum Scope: String, CaseIterable, Identifiable {
        case month = "月別"
        case myDeck = "自分デッキ別"
        case opponentDeck = "相手デッキ別"
        case event = "大会別"
        var id: String { rawValue }
    }

    var rows: [StatRow] {
        let base: [StatRow]
        switch scope {
        case .month: base = store.monthStats()
        case .myDeck: base = store.myDeckStats()
        case .opponentDeck: base = store.opponentDeckStats()
        case .event: base = store.eventStats()
        }
        return base.filter { $0.total >= minimumGames }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderTitle(title: "統計", subtitle: "月別・デッキ別・大会別の傾向", systemImage: "chart.pie", accent: .orange)
            HStack(spacing: 12) {
                Picker("表示", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Picker("最低試合数", selection: $minimumGames) {
                    Text("全部").tag(1)
                    Text("3戦以上").tag(3)
                    Text("5戦以上").tag(5)
                    Text("10戦以上").tag(10)
                }
                .frame(width: 150)
                Spacer()
            }

            let total = store.overallStats()
            HStack(spacing: 12) {
                StatSummaryCard(title: "総試合", value: "\(total.total)戦", detail: "\(total.wins)勝\(total.losses)敗")
                StatSummaryCard(title: "全体勝率", value: percent(total.winRate), detail: "補正 \(percent(total.adjustedWinRate))")
                StatSummaryCard(title: "先攻", value: turnText(wins: total.firstWins, total: total.firstTotal), detail: "後攻 \(turnText(wins: total.secondWins, total: total.secondTotal))")
            }

            if rows.isEmpty {
                EmptyStateView(message: "表示できる統計がありません。戦績を入力するか、最低試合数フィルターを下げてください。", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    StatsHeaderRow()
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                StatsDataRow(row: row)
                                Divider()
                            }
                        }
                    }
                }
                .background(AppTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.14)))
                .shadow(color: Color.blue.opacity(0.06), radius: 10, x: 0, y: 5)
            }
        }
        .padding(20)
    }
}

struct StatSummaryCard: View {
    let title: String
    let value: String
    let detail: String
    var accent: Color {
        if title.contains("勝率"), let rate = percentStringToDouble(value) { return winRateColor(rate) }
        if title.contains("総試合") { return Color.accentColor }
        return Color.blue
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).foregroundStyle(accent)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 160, alignment: .leading)
        .padding(14)
        .background(LinearGradient(colors: [accent.opacity(0.13), Color.white.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.24), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: accent.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct StatsHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("項目").frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            Text("試合").frame(width: 55, alignment: .trailing)
            Text("勝敗").frame(width: 80, alignment: .trailing)
            Text("勝率").frame(width: 70, alignment: .trailing)
            Text("補正").frame(width: 70, alignment: .trailing)
            Text("先攻").frame(width: 90, alignment: .trailing)
            Text("後攻").frame(width: 90, alignment: .trailing)
            Text("信頼").frame(width: 55, alignment: .center)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.12))
    }
}

struct StatsDataRow: View {
    let row: StatRow
    var body: some View {
        HStack(spacing: 8) {
            Text(row.key).font(.body.weight(.medium)).lineLimit(1).frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            Text("\(row.total)").frame(width: 55, alignment: .trailing)
            HStack(spacing: 4) {
                Text("\(row.wins)").font(.callout.weight(.bold)).foregroundStyle(winColor)
                Text("-")
                Text("\(row.losses)").font(.callout.weight(.bold)).foregroundStyle(lossColor)
            }.frame(width: 80, alignment: .trailing)
            Text(percent(row.winRate)).font(.callout.weight(.semibold)).foregroundStyle(winRateColor(row.winRate)).frame(width: 70, alignment: .trailing)
            Text(percent(row.adjustedWinRate)).foregroundStyle(winRateColor(row.adjustedWinRate)).frame(width: 70, alignment: .trailing)
            Text(turnText(wins: row.firstWins, total: row.firstTotal)).frame(width: 90, alignment: .trailing)
            Text(turnText(wins: row.secondWins, total: row.secondTotal)).frame(width: 90, alignment: .trailing)
            ReliabilityBadge(text: row.reliability).frame(width: 55, alignment: .center)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(winRateBackground(row.adjustedWinRate).opacity(0.65))
    }
}

struct DecksView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedKind = "my"
    @State private var name = ""
    @State private var representative = ""
    @State private var officialURL = ""
    @State private var imagePath: String?
    @State private var editing: Deck?
    @State private var pendingDeleteID: Int64?
    @State private var localMessage: String?
    @State private var localMessageIsError = false

    var filteredDecks: [Deck] {
        store.decks
            .filter { $0.kind == selectedKind }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var kindLabel: String { selectedKind == "my" ? "自分のデッキ" : "相手デッキ" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HeaderTitle(title: editing == nil ? "\(kindLabel) 登録" : "\(kindLabel) 編集", subtitle: "候補として入力画面に反映", systemImage: "rectangle.stack", accent: selectedKind == "my" ? Color.blue : Color.purple)
                Picker("種類", selection: $selectedKind) {
                    Text("自分のデッキ").tag("my")
                    Text("相手デッキ").tag("opponent")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedKind) { _ in clear() }

                TextField("デッキ名", text: $name).textFieldStyle(.roundedBorder)
                if let localMessage {
                    Text(localMessage)
                        .font(.caption.bold())
                        .foregroundStyle(localMessageIsError ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background((localMessageIsError ? Color.red : Color.green).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                TextField("代表カード", text: $representative).textFieldStyle(.roundedBorder)
                TextField("公式URL", text: $officialURL).textFieldStyle(.roundedBorder)
                HStack {
                    Button("画像を選ぶ") { chooseImage() }
                    Text(imagePath ?? "未選択").lineLimit(1).foregroundStyle(.secondary)
                }
                HStack {
                    Button(editing == nil ? "保存" : "更新") { save() }
                        .keyboardShortcut(.return, modifiers: [.command])
                    if editing != nil { Button("キャンセル") { clear() } }
                }
                Text("削除しても過去の戦績は消えません。戦績に残っているデッキ名は一覧・相性表には引き続き表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 380)
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(kindLabel).font(.title2.bold())
                    Spacer()
                    Text("\(filteredDecks.count)件").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                if filteredDecks.isEmpty {
                    EmptyStateView(message: "まだ\(kindLabel)が登録されていません。左側でデッキ名を入力して保存してください。", systemImage: "rectangle.stack.badge.plus")
                        .padding(20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredDecks) { deck in
                                DeckRowView(
                                    deck: deck,
                                    isPendingDelete: pendingDeleteID == deck.id,
                                    onEdit: { edit(deck) },
                                    onAskDelete: { pendingDeleteID = deck.id },
                                    onCancelDelete: { pendingDeleteID = nil },
                                    onConfirmDelete: { delete(deck) }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(minWidth: 520)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { imagePath = try store.copyImageForDeck(source: url) }
            catch { store.report(error) }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showLocalMessage("デッキ名を入力してください", isError: true)
            return
        }
        do {
            let wasEditing = editing != nil
            let deck = Deck(id: editing?.id ?? 0, name: trimmed, kind: selectedKind, imagePath: imagePath, representativeCard: representative, officialURL: officialURL)
            try store.saveDeck(deck)
            clear(keepMessage: true)
            showLocalMessage(wasEditing ? "更新しました！" : "保存しました！", isError: false)
        } catch { store.report(error) }
    }

    private func edit(_ d: Deck) {
        pendingDeleteID = nil
        editing = d
        selectedKind = d.kind
        name = d.name
        representative = d.representativeCard ?? ""
        officialURL = d.officialURL ?? ""
        imagePath = d.imagePath
    }

    private func delete(_ d: Deck) {
        do {
            try store.deleteDeck(d.id)
            if editing?.id == d.id { clear() }
            pendingDeleteID = nil
        } catch { store.report(error) }
    }

    private func showLocalMessage(_ text: String, isError: Bool) {
        localMessage = text
        localMessageIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { localMessage = nil }
    }

    private func clear(keepMessage: Bool = false) {
        editing = nil
        pendingDeleteID = nil
        name = ""
        representative = ""
        officialURL = ""
        imagePath = nil
        if !keepMessage { localMessage = nil }
        localMessageIsError = false
    }
}

struct DeckRowView: View {
    let deck: Deck
    let isPendingDelete: Bool
    let onEdit: () -> Void
    let onAskDelete: () -> Void
    let onCancelDelete: () -> Void
    let onConfirmDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DeckImageView(path: deck.imagePath, fallback: deck.name)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name).font(.headline).lineLimit(1)
                if let rep = deck.representativeCard, !rep.isEmpty {
                    Text("代表カード：\(rep)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let url = deck.officialURL, !url.isEmpty {
                    Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if isPendingDelete {
                Button("やめる") { onCancelDelete() }
                Button("本当に削除", role: .destructive) { onConfirmDelete() }
            } else {
                Button("編集") { onEdit() }
                Button("削除", role: .destructive) { onAskDelete() }
            }
        }
        .padding(12)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.12)))
        .shadow(color: Color.blue.opacity(0.05), radius: 6, x: 0, y: 3)
    }
}

struct BackupView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("バックアップ").font(.largeTitle.bold())
            Button("JSONを書き出す") { savePanel(ext: "json") { try store.exportJSON(to: $0) } }
            Button("JSONを読み込む") { openPanel(types: [.json]) { try store.importJSON(from: $0) } }
            Divider()
            Button("CSVを書き出す") { savePanel(ext: "csv") { try store.exportCSV(to: $0) } }
            Text("データは ~/Library/Application Support/PokecaRecordsSwiftUI/records.sqlite3 に保存されます。").foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }
    private func savePanel(ext: String, action: (URL) throws -> Void) { let p = NSSavePanel(); p.nameFieldStringValue = "pokeca_records.\(ext)"; if p.runModal() == .OK, let url = p.url { do { try action(url) } catch { store.report(error) } } }
    private func openPanel(types: [UTType], action: (URL) throws -> Void) { let p = NSOpenPanel(); p.allowedContentTypes = types; if p.runModal() == .OK, let url = p.url { do { try action(url) } catch { store.report(error) } } }
}




struct AppTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.98, blue: 1.00),
            Color(red: 0.97, green: 0.96, blue: 1.00),
            Color(red: 1.00, green: 0.98, blue: 0.93)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = LinearGradient(
        colors: [Color.white.opacity(0.78), Color.blue.opacity(0.055)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let warmPanel = LinearGradient(
        colors: [Color.orange.opacity(0.10), Color.white.opacity(0.72)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let coolPanel = LinearGradient(
        colors: [Color.blue.opacity(0.10), Color.white.opacity(0.72)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct HeaderTitle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.14))
                Image(systemName: systemImage).font(.title2.weight(.bold)).foregroundStyle(accent)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.largeTitle.bold())
                if !subtitle.isEmpty { Text(subtitle).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }
}

struct SoftPanel: ViewModifier {
    var accent: Color = .blue
    func body(content: Content) -> some View {
        content
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.16), lineWidth: 1))
            .shadow(color: accent.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func softPanel(accent: Color = .blue) -> some View { modifier(SoftPanel(accent: accent)) }
}

private func gregorianDateString(_ d: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "ja_JP_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

private func gregorianTimeString(_ d: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "ja_JP_POSIX")
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

struct SaveFeedbackBanner: View {
    let text: String
    let isUpdate: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isUpdate ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline.bold())
                Text("一覧・統計に反映されました")
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(LinearGradient(colors: [Color.green, Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4, y: 2)
    }
}

// MARK: - Visual Helpers

private let winColor = Color.green
private let lossColor = Color.red

private func winRateColor(_ value: Double) -> Color {
    if value >= 0.65 { return .green }
    if value >= 0.50 { return .blue }
    if value >= 0.40 { return .orange }
    return .red
}

private func winRateBackground(_ value: Double) -> Color {
    winRateColor(value).opacity(0.10)
}

private func percentStringToDouble(_ text: String) -> Double? {
    let raw = text.replacingOccurrences(of: "%", with: "")
    guard let n = Double(raw) else { return nil }
    return n / 100.0
}

struct ResultBadge: View {
    let result: String
    var color: Color { result == "勝ち" ? winColor : lossColor }
    var body: some View {
        Text(result)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

struct TurnBadge: View {
    let turn: String
    var body: some View {
        Text(turn)
            .font(.caption.weight(.semibold))
            .foregroundStyle(turn == "先攻" ? .blue : .purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((turn == "先攻" ? Color.blue : Color.purple).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct OpeningBadge: View {
    let opening: String
    var color: Color {
        switch opening {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        default: return .red
        }
    }
    var body: some View {
        Text(opening)
            .font(.caption.bold())
            .foregroundStyle(color)
            .frame(width: 28, height: 22)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ReliabilityBadge: View {
    let text: String
    var color: Color {
        switch text {
        case "高": return .green
        case "中": return .orange
        default: return .gray
        }
    }
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct NoteBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.14))
            .clipShape(Capsule())
    }
}

struct ResultCountBadge: View {
    let label: String
    let count: Int
    let color: Color
    var body: some View {
        Text("\(label) \(count)")
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct WinLossBar: View {
    let wins: Int
    let losses: Int
    var total: Int { wins + losses }
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(winColor).frame(width: total == 0 ? 0 : geo.size.width * CGFloat(wins) / CGFloat(total))
                Rectangle().fill(lossColor).frame(width: total == 0 ? 0 : geo.size.width * CGFloat(losses) / CGFloat(total))
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
    }
}

private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

private func turnText(wins: Int, total: Int) -> String {
    guard total > 0 else { return "-" }
    let rate = Double(wins) / Double(total)
    return "\(wins)/\(total)・\(percent(rate))"
}

struct DeckNameView: View { let name: String; var body: some View { HStack { Text(name).lineLimit(1) } } }
struct DeckImageView: View {
    let path: String?
    let fallback: String
    var body: some View {
        if let path, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(.quaternary); Text(String(fallback.prefix(1))).font(.headline) }
        }
    }
}
