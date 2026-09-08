import Foundation
import SwiftUI
import DiaryCore

// MARK: - Journal Store

/// ジャーナルフォルダを管理し、全エントリを統一的に提供する
@MainActor
class JournalStore: ObservableObject {

    /// いま何を表示しているか。
    ///
    /// ★踏んではいけない地雷（2026-08-03）
    /// 以前は、フォルダ未選択のときに**黙って同梱サンプル（2024〜2026の3年分）を
    /// 表示していた。** `.app` 化でバンドルIDが変わりUserDefaultsが別枠になった際、
    /// 本人が「2024年からしか見えない」と混乱した。日記アプリが偽データを本物と
    /// 見分けにくい形で出すのは危険なので、**未選択なら何も読まない。**
    /// サンプルは環境変数 `DIARY_USE_FIXTURES=1` を明示したときだけ読む。
    enum DataSource: Equatable {
        case notSelected     // フォルダ未選択。何も表示しない。
        case folder(URL)     // 本物の日記
        case fixtures        // 開発用サンプル（明示要求時のみ）
    }

    @Published private(set) var dataSource: DataSource = .notSelected

    @Published var entries: [Entry] = [] { didSet { recomputeCaches() } }
    @Published private(set) var captureLoadError: String?
    private var journalEntries: [Entry] = []
    private var journalLoadErrors: [String] = []
    @Published var selectedEntry: Entry?
    @Published var allTags: [String] = []
    @Published var selectedTags: Set<String> = [] { didSet { recomputeCaches() } }
    @Published var searchQuery: String = "" { didSet { recomputeCaches() } }
    @Published var filterMode: FilterMode = .all { didSet { recomputeCaches() } }
    @Published var baseURL: URL? = nil {
        didSet {
            // 実機検証用の隔離ライブラリで本人の保存済みパスを変更しない。
            if ProcessInfo.processInfo.environment["DIARY_LIBRARY_PATH"] == nil {
                UserDefaults.standard.set(baseURL?.path, forKey: "diaryBaseURL")
            }
        }
    }


    // MARK: - キャッシュ（1,113件を毎描画で filter+sort し直さないため）

    @Published private(set) var filteredEntries: [Entry] = []
    @Published private(set) var entriesGroupedByMonth: [(month: DateComponents, entries: [Entry])] = []

    /// 絞り込みの入力が変わったときだけ再計算する
    private func recomputeCaches() {
        filteredEntries = computeFilteredEntries
        entriesGroupedByMonth = computeGroupedByMonth
    }

    /// 実際の計算（キャッシュ経由でのみ呼ぶ）
    private var computeFilteredEntries: [Entry] {
        var result = entries

        // 検索絞り込み
        if !searchQuery.isEmpty {
            result = result.filter { entry in
                let query = searchQuery.lowercased()
                if entry.body.lowercased().contains(query) { return true }
                if entry.tags.contains(where: { $0.lowercased().contains(query) }) { return true }
                return false
            }
        }

        // タグ絞り込み
        if !selectedTags.isEmpty {
            result = result.filter { entry in
                !selectedTags.isDisjoint(with: Set(entry.tags))
            }
        }

        // フィルタモード
        switch filterMode {
        case .all:
            break
        case .today:
            let today = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: Date())
            result = result.filter { entry in
                let dc = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: entry.date)
                return dc.month == today.month && dc.day == today.day
            }
        case .thisDay(let month, let day):
            result = result.filter { entry in
                let dc = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: entry.date)
                return dc.month == month && dc.day == day
            }
        case .year(let y):
            result = result.filter { $0.year == y }
        }

        // 新しい日付順（降順）
        result.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }

        return result
    }

    /// 年別エントリ数
    var entriesByYear: [(year: Int, count: Int)] {
        let grouped = Dictionary(grouping: entries, by: { $0.year })
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.year > $1.year }
    }

    /// 月別グループ化の実際の計算（キャッシュ経由でのみ呼ぶ）
    private var computeGroupedByMonth: [(month: DateComponents, entries: [Entry])] {
        let filtered = filteredEntries
        let grouped = Dictionary(grouping: filtered) { entry -> DateComponents in
            let cal = Calendar(identifier: .gregorian)
            return cal.dateComponents([.year, .month], from: entry.date)
        }
        return grouped.map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let lYear = lhs.month.year ?? 0
                let rYear = rhs.month.year ?? 0
                if lYear != rYear { return lYear > rYear }
                return (lhs.month.month ?? 0) > (rhs.month.month ?? 0)
            }
    }

    enum FilterMode: Hashable {
        case all
        case today
        case thisDay(month: Int, day: Int)
        case year(Int)
    }

    func load(baseURL: URL) {
        self.baseURL = baseURL
        dataSource = .folder(baseURL)
        loadAll()
    }

    /// 開発用サンプルを読む。**通常の起動経路からは呼ばない。**
    /// 理由は `DataSource` の地雷の項を参照。
    func loadFallbackFixtures() {
        // SwiftPM生成のBundle.moduleは.app直下を探すため、標準の
        // Contents/Resources配置は明示して解決する。配布.appではビルド先へ
        // フォールバックしない（開発機だけで動く状態を防ぐ）。
        let resourceBundle: Bundle?
        if Bundle.main.bundleURL.pathExtension == "app" {
            resourceBundle = Bundle.main.resourceURL
                .map { $0.appendingPathComponent("DiaryViewer_DiaryViewer.bundle") }
                .flatMap { Bundle(url: $0) }
        } else {
            resourceBundle = Bundle.module
        }
        guard let fixturesURL = resourceBundle?.resourceURL?.appendingPathComponent("Fixtures") else {
            return
        }
        dataSource = .fixtures
        loadAll(from: fixturesURL)
    }

    func loadAll(from url: URL? = nil) {
        let journalURL: URL
        if let url = url {
            journalURL = url
        } else if let base = baseURL {
            journalURL = base
        } else {
            // フォルダ未選択。**サンプルへ勝手に落ちない。**
            entries = []
            journalEntries = []
            captureLoadError = nil
            allTags = []
            dataSource = .notSelected
            return
        }

        let fm = FileManager.default
        // 実データは「ジャーナル」、同梱fixtureは「journal」
        var journalDir = journalURL.appendingPathComponent("ジャーナル")
        if !fm.fileExists(atPath: journalDir.path) {
            journalDir = journalURL.appendingPathComponent("journal")
        }

        var allEntries: [Entry] = []
        journalLoadErrors = []
        // 中断復旧が年別ファイルを書き換える場合があるため、読む順番は復旧が先。
        if case .folder(let root) = dataSource,
           fm.fileExists(atPath: root.appendingPathComponent("日記アプリデータ").path) {
            do { _ = try CaptureLibrary(root: root, allowJournalWrites: Self.allowsJournalWrites(root)) }
            catch { journalLoadErrors.append(error.localizedDescription) }
        }

        // 年を固定しない。将来の日記と、2013年より前の取り込みも読む。
        let yearFiles = (try? fm.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil)) ?? []
        for fileURL in yearFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard fileURL.pathExtension == "md",
                  fileURL.deletingPathExtension().lastPathComponent.count == 4,
                  let year = Int(fileURL.deletingPathExtension().lastPathComponent) else { continue }

            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let result = JournalParser.parse(fileContent: content, year: year)
                if let failure = result.failure { journalLoadErrors.append("\(fileURL.lastPathComponent): \(failure)") }
                // 検算
                JournalParser.validateEntryCount(result: result)
                allEntries.append(contentsOf: result.entries)
            } catch {
                journalLoadErrors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
                print("[エラー] \(fileURL.lastPathComponent) の読み込みに失敗: \(error.localizedDescription)")
            }
        }

        // 画像の探索起点。読み込んだ場所そのものを使う。
        imageResolver = ImageResolver(baseURL: journalURL)

        self.journalEntries = allEntries
        refreshCaptures()
    }

    /// 受け箱を閉じたときに更新。既存日記を再パースせず、選択とIDを維持する。
    func refreshCaptures() {
        var combined = journalEntries
        captureLoadError = journalLoadErrors.isEmpty ? nil : journalLoadErrors.joined(separator: "\n")
        if case .folder(let root) = dataSource,
           FileManager.default.fileExists(atPath: root.appendingPathComponent("日記アプリデータ").path) {
            do {
                let captures = try CaptureLibrary(root: root).captures()
                combined = Entry.merge(journals: journalEntries, captures: captures)
                let journalIDs = Set(journalEntries.map(\.id))
                if captures.contains(where: { $0.adopted && !journalIDs.contains($0.id) }) {
                    captureLoadError = "保存済みの日記が見つかりません。年別ファイルを確認してください。原文は受け箱に残っています。"
                }
            } catch {
                captureLoadError = "受け箱の記録を読み込めませんでした。受け箱を開いて確認してください。\n\(error.localizedDescription)"
            }
        }
        let selectedID = selectedEntry?.id
        entries = combined
        allTags = Set(combined.flatMap(\.tags)).sorted()
        selectedEntry = selectedID.flatMap { id in combined.first { $0.id == id } }
    }

    /// Claude検品と実データの保存検証が済むまでは、専用起動＋架空ライブラリだけ。
    static func allowsJournalWrites(_ root: URL) -> Bool {
        ProcessInfo.processInfo.environment["DIARY_ENABLE_JOURNAL_WRITES"] == "1"
            && (try? String(contentsOf: root.appendingPathComponent(".diary-test-library"), encoding: .utf8)) == "fictional-data-only\n"
    }

    var imageResolver: ImageResolver?

    init() {
        if let path = ProcessInfo.processInfo.environment["DIARY_LIBRARY_PATH"], !path.isEmpty {
            let root = URL(fileURLWithPath: path)
            Task { @MainActor in self.load(baseURL: root) }
            return
        }
        // UserDefaultsから前回のパスを復元
        if let savedPath = UserDefaults.standard.string(forKey: "diaryBaseURL"),
           !savedPath.isEmpty {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: url.path) {
                // 非同期で読み込み
                Task { @MainActor in
                    self.load(baseURL: url)
                }
                return
            }
        }

        // 開発中にサンプルで動かしたいときだけ、明示的に要求する:
        //   DIARY_USE_FIXTURES=1 swift run
        if ProcessInfo.processInfo.environment["DIARY_USE_FIXTURES"] == "1" {
            loadFallbackFixtures()
            return
        }

        // それ以外は何も読まない。画面は「フォルダを選んでください」の案内になる。
        dataSource = .notSelected
    }
}

// MARK: - Image Resolver

struct ImageResolver {
    let baseURL: URL

    func resolve(_ filename: String) -> URL? {
        let media = baseURL.appendingPathComponent("media")
        // 実データは「ジャーナル写真/ジャーナル動画」、同梱fixtureは「photos/videos」
        let dirs = ["ジャーナル写真", "ジャーナル動画", "photos", "videos"].map { media.appendingPathComponent($0) }

        let fm = FileManager.default
        for dir in dirs {
            let url = dir.appendingPathComponent(filename)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func isVideo(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }
}
