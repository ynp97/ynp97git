import SwiftUI
import AppKit

extension Color {
    static let todoAccent = Color(red: 0.76, green: 0.25, blue: 0.05)
    static let todoBackground = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let todoCard = Color(red: 1.0, green: 0.99, blue: 0.97)
    static let todoText = Color(red: 0.17, green: 0.16, blue: 0.14)
    static let todoMuted = Color(red: 0.49, green: 0.46, blue: 0.42)
    static let todoBorder = Color(red: 0.90, green: 0.88, blue: 0.84)
    static let routinePurple = Color(red: 0.49, green: 0.23, blue: 0.86)
}

@main
struct ZatsuTodoApp: App {
    @StateObject private var store = TodoStore.shared

    var body: some Scene {
        WindowGroup("TODO") {
            MainView(store: store)
        }
        .defaultSize(width: 780, height: 860)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("TODOを終了") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

enum TodoSize: String, Codable, CaseIterable {
    case large = "大"
    case medium = "中"
    case small = "小"
    case none = ""

    var label: String {
        switch self {
        case .large: "🔥"
        case .medium: "⭐"
        case .small: "🌱"
        case .none: "—"
        }
    }
}

// 3.0（2026-08-17）で TodoPlacement（プール／今日／今週／今月）は廃止した。
// 時間の指定は「期日」と「目処」の2つだけ。移行は TodoItem.init(from:) が行う。

enum TodoRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "繰り返しなし"
        case .daily: "毎日"
        case .weekly: "毎週"
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    /// 期日。日にちを指定したものだけに入る。ここに日付があれば、目処は日付から自動で決まる。
    var date: Date?
    /// 目処。期日を入れていないものが使う。画面の段はこれで決まる。
    var timeframe: String?
    var size: TodoSize
    var done: Bool
    var createdAt: Date
    var genre: String
    var recurrence: TodoRecurrence
    var weeklyDay: Int?
    var weeklyDays: [Int]
    var completedOccurrenceKeys: [String]

    init(
        text: String,
        date: Date? = nil,
        timeframe: String? = nil,
        size: TodoSize = .none,
        genre: String = "未分類",
        recurrence: TodoRecurrence = .none,
        weeklyDays: [Int] = []
    ) {
        id = UUID().uuidString
        self.text = text
        self.date = date
        self.timeframe = timeframe
        self.size = size
        done = false
        createdAt = Date()
        self.genre = genre
        self.recurrence = recurrence
        weeklyDay = weeklyDays.first
        self.weeklyDays = weeklyDays
        completedOccurrenceKeys = []
    }

    enum CodingKeys: String, CodingKey {
        case id, text, date, timeframe, size, done, createdAt
        case genre, recurrence, weeklyDay, weeklyDays, completedOccurrenceKeys
        // 2.x の持ち物。読み込み時の移行にだけ使い、3.0では書き出さない。
        case placement, plannedDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try values.decode(String.self, forKey: .text)
        size = try values.decodeIfPresent(TodoSize.self, forKey: .size) ?? .none
        done = try values.decodeIfPresent(Bool.self, forKey: .done) ?? false
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        genre = try values.decodeIfPresent(String.self, forKey: .genre) ?? "未分類"
        recurrence = try values.decodeIfPresent(TodoRecurrence.self, forKey: .recurrence) ?? .none
        weeklyDay = try values.decodeIfPresent(Int.self, forKey: .weeklyDay)
        weeklyDays = try values.decodeIfPresent([Int].self, forKey: .weeklyDays)
            ?? weeklyDay.map { [$0] }
            ?? []
        completedOccurrenceKeys = try values.decodeIfPresent([String].self, forKey: .completedOccurrenceKeys) ?? []

        // ── 3.0 移行（2026-08-17）──────────────────────────────
        // 2.x は「期日」「目処」「大まかな場所(placement)」「やる日(plannedDate)」の4つで
        // 時間を指定していた。3.0では「期日」「目処」の2つへ畳む。古い値は捨てずに移す。
        // 一度保存すれば placement / plannedDate はファイルから消えるので、この処理は二度目以降は素通りする。
        var migratedDate = try values.decodeIfPresent(Date.self, forKey: .date)
        var migratedTimeframe = try values.decodeIfPresent(String.self, forKey: .timeframe)
        let legacyPlannedDate = try values.decodeIfPresent(Date.self, forKey: .plannedDate)
        let legacyPlacement = try values.decodeIfPresent(String.self, forKey: .placement)

        if let planned = legacyPlannedDate {
            if planned > Calendar.current.startOfDay(for: Date()) {
                // 「明日やる」など先の日付は、そのまま期日にする。
                migratedDate = migratedDate ?? planned
            } else {
                // 過去に「今日へ置いた」ものは日付ではなく目処として畳む。
                // 日付のまま移すと、8月11日に今日へ置いたものが一斉に期限切れへ落ちるため。
                migratedTimeframe = "今日中"
            }
        }
        switch legacyPlacement {
        case "today": migratedTimeframe = "今日中"
        case "week": migratedTimeframe = "今週中"
        case "month": migratedTimeframe = "今月中"
        default: break
        }
        date = migratedDate
        timeframe = migratedTimeframe
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(timeframe, forKey: .timeframe)
        try container.encode(size, forKey: .size)
        try container.encode(done, forKey: .done)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(genre, forKey: .genre)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encodeIfPresent(weeklyDay, forKey: .weeklyDay)
        try container.encode(weeklyDays, forKey: .weeklyDays)
        try container.encode(completedOccurrenceKeys, forKey: .completedOccurrenceKeys)
    }
}

private let defaultGenres = ["仕事", "学校", "教会", "音楽", "ポケカ", "私用", "未分類"]
private let defaultGenreColors = [
    "仕事": "1A6BE0",
    "学校": "00A1C7",
    "教会": "F06614",
    "音楽": "7A40DB",
    "ポケカ": "E02952",
    "私用": "8C5733",
    "未分類": "6B707A"
]
private let defaultTimeframeTags = [
    "今日中", "今週中", "今月中", "来月中", "半年以内", "今年中", "いつか"
]

@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published var todos: [TodoItem] = []
    @Published var genres: [String] = []
    @Published var genreColors: [String: String] = [:]
    @Published var timeframeTags: [String] = []

    private let dataURL: URL
    private let backupURL: URL
    private let genresKey = "genres-v2"
    private let genreColorsKey = "genre-colors-v1"
    private let timeframeTagsKey = "timeframeTags"

    private init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZatsuTodo")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataURL = directory.appendingPathComponent("todos.json")
        backupURL = directory.appendingPathComponent("todos.backup.json")
        load()
        loadSettings()
    }

    var activeCount: Int { todos.filter { !$0.done || $0.recurrence != .none }.count }
    var completedItems: [TodoItem] {
        todos.filter { $0.done && $0.recurrence == .none }.sorted { $0.createdAt > $1.createdAt }
    }
    var todayRoutines: [TodoItem] {
        todos.filter { routineOccursToday($0) }.sorted(by: taskSort)
    }
    /// 期日が過ぎたもの。目処に関係なく最上段へ集める。
    var overdueItems: [TodoItem] { grouped.overdue }
    /// 目処タグ1つ分の中身。画面の段はこれをタグの並び順に呼び出して作る。
    func items(forTimeframe tag: String) -> [TodoItem] { grouped.byTag[tag] ?? [] }
    /// 「今日中」の段。ヘッダーの件数表示に使う。
    var todayItems: [TodoItem] { items(forTimeframe: "今日中") }

    var todayCompletedCount: Int {
        (todayRoutines + todayItems).filter { isCompleted($0) }.count
    }
    var todayTotalCount: Int { todayRoutines.count + todayItems.count }

    func add(
        text: String,
        date: Date?,
        timeframe: String?,
        size: TodoSize,
        genre: String,
        recurrence: TodoRecurrence,
        weeklyDays: [Int]
    ) {
        todos.insert(
            TodoItem(
                text: text,
                date: date,
                timeframe: timeframe,
                size: size,
                genre: genre,
                recurrence: recurrence,
                weeklyDays: weeklyDays
            ),
            at: 0
        )
        save()
    }

    func toggle(id: String) {
        guard let index = index(for: id) else { return }
        if todos[index].recurrence == .none {
            todos[index].done.toggle()
        } else {
            let key = occurrenceKey(for: Date())
            if let keyIndex = todos[index].completedOccurrenceKeys.firstIndex(of: key) {
                todos[index].completedOccurrenceKeys.remove(at: keyIndex)
            } else {
                todos[index].completedOccurrenceKeys.append(key)
                todos[index].completedOccurrenceKeys = Array(todos[index].completedOccurrenceKeys.suffix(120))
            }
        }
        save()
    }

    func isCompleted(_ item: TodoItem) -> Bool {
        if item.recurrence == .none { return item.done }
        return item.completedOccurrenceKeys.contains(occurrenceKey(for: Date()))
    }

    func delete(id: String) {
        todos.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        todos.removeAll { $0.done && $0.recurrence == .none }
        save()
    }

    /// 目処を変える。期日が入っていたら外す（期日があると目処は日付から自動で決まり、手で選んだ目処が効かなくなるため）。
    func setTimeframe(id: String, timeframe: String?) {
        guard let index = index(for: id) else { return }
        todos[index].timeframe = timeframe
        todos[index].date = nil
        save()
    }

    /// 期日（日にち）を入れる・外す。期日を入れると、目処は日付から自動で決まる。
    func setDate(id: String, date: Date?) {
        guard let index = index(for: id) else { return }
        todos[index].date = date.map { Calendar.current.startOfDay(for: $0) }
        save()
    }

    func moveToTomorrow(id: String) {
        setDate(id: id, date: Calendar.current.date(byAdding: .day, value: 1, to: startOfToday))
    }

    func setGenre(id: String, genre: String) {
        guard let index = index(for: id) else { return }
        todos[index].genre = genre
        save()
    }

    func update(_ edited: TodoItem) {
        guard let index = index(for: edited.id) else { return }
        todos[index] = edited
        save()
    }

    func addGenre(_ genre: String, color: Color) {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !genres.contains(trimmed) else { return }
        genres.append(trimmed)
        genreColors[trimmed] = color.todoHex
        saveSettings()
    }

    func genreColor(for genre: String) -> Color {
        Color(todoHex: genreColors[genre] ?? fallbackGenreHex(genre))
    }

    func setGenreColor(_ genre: String, color: Color) {
        genreColors[genre] = color.todoHex
        saveSettings()
    }

    func removeGenre(_ genre: String) {
        guard genre != "未分類" else { return }
        genres.removeAll { $0 == genre }
        genreColors.removeValue(forKey: genre)
        for index in todos.indices where todos[index].genre == genre {
            todos[index].genre = "未分類"
        }
        saveSettings()
        save()
    }

    func addTimeframe(_ timeframe: String) {
        guard !timeframe.isEmpty, !timeframeTags.contains(timeframe) else { return }
        timeframeTags.append(timeframe)
        saveSettings()
    }

    func removeTimeframe(_ timeframe: String) {
        timeframeTags.removeAll { $0 == timeframe }
        for index in todos.indices where todos[index].timeframe == timeframe {
            todos[index].timeframe = nil
        }
        saveSettings()
        save()
    }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private var endOfWeek: Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysToSunday = (8 - weekday) % 7
        return calendar.date(byAdding: .day, value: daysToSunday + 1, to: startOfToday)!.addingTimeInterval(-1)
    }
    private var endOfMonth: Date {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: startOfToday)!
        return interval.end.addingTimeInterval(-1)
    }
    private var endOfNextMonth: Date {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday),
              let interval = calendar.dateInterval(of: .month, for: nextMonth) else { return endOfMonth }
        return interval.end.addingTimeInterval(-1)
    }
    private var endOfHalfYear: Date {
        Calendar.current.date(byAdding: .month, value: 6, to: startOfToday) ?? endOfNextMonth
    }
    private var endOfYear: Date {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .year, for: startOfToday) else { return endOfNextMonth }
        return interval.end.addingTimeInterval(-1)
    }

    private func routineOccursToday(_ item: TodoItem) -> Bool {
        guard !item.done else { return false }
        switch item.recurrence {
        case .none: return false
        case .daily: return true
        case .weekly:
            return item.weeklyDays.contains(Calendar.current.component(.weekday, from: Date()))
        }
    }

    // 3.0（2026-08-17）: 未完了の通常TODOを「期限切れ」＋目処タグの段へ、1周で漏れなく振り分ける。
    // 段は timeframeTags の並びそのもの。タグを足せば段が増える。
    private var grouped: (overdue: [TodoItem], byTag: [String: [TodoItem]]) {
        let calendar = Calendar.current
        let todayStart = startOfToday
        var overdue: [TodoItem] = []
        var byTag: [String: [TodoItem]] = [:]

        for item in todos {
            guard !item.done, item.recurrence == .none else { continue }
            if let due = item.date, calendar.startOfDay(for: due) < todayStart {
                overdue.append(item)
            } else {
                byTag[timeframeSlot(for: item), default: []].append(item)
            }
        }

        return (
            overdue: overdue.sorted(by: taskSort),
            byTag: byTag.mapValues { $0.sorted(by: taskSort) }
        )
    }

    /// この項目がどの目処の段に入るか。
    /// 期日が入っていれば日付から自動で決まり、入っていなければ手で選んだ目処に従う。どちらも無ければ最後のタグ（いつか）。
    func timeframeSlot(for item: TodoItem) -> String {
        if let due = item.date { return existingTag(from: automaticTimeframe(for: due)) }
        if let tag = item.timeframe, timeframeTags.contains(tag) { return tag }
        return timeframeTags.last ?? defaultTimeframeTags[defaultTimeframeTags.count - 1]
    }

    /// 期日から目処を決める。判定の順番は既定タグの並び順に合わせてある
    /// （「半年以内」が「今年中」より前にあるので、年内の日付でも半年以内に入る年がある）。
    private func automaticTimeframe(for due: Date) -> String {
        let day = Calendar.current.startOfDay(for: due)
        if day <= startOfToday { return "今日中" }
        if day <= endOfWeek { return "今週中" }
        if day <= endOfMonth { return "今月中" }
        if day <= endOfNextMonth { return "来月中" }
        if day <= endOfHalfYear { return "半年以内" }
        if day <= endOfYear { return "今年中" }
        return "いつか"
    }

    /// 自動で決めたタグを本人が消していた場合に、既定の並びを前から後ろへたどって実在するタグへ寄せる。
    private func existingTag(from tag: String) -> String {
        if timeframeTags.contains(tag) { return tag }
        if let start = defaultTimeframeTags.firstIndex(of: tag) {
            for candidate in defaultTimeframeTags[start...] where timeframeTags.contains(candidate) {
                return candidate
            }
        }
        return timeframeTags.last ?? tag
    }

    private func taskSort(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.date != rhs.date { return (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture) }
        if lhs.size != rhs.size {
            let order: [TodoSize: Int] = [.large: 0, .medium: 1, .small: 2, .none: 3]
            return order[lhs.size, default: 3] < order[rhs.size, default: 3]
        }
        return lhs.createdAt < rhs.createdAt
    }


    private func occurrenceKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func index(for id: String) -> Int? { todos.firstIndex { $0.id == id } }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(todos)
            try data.write(to: dataURL, options: .atomic)
            try data.write(to: backupURL, options: .atomic)
        } catch {
            NSLog("TODO save error: \(error)")
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for candidate in [dataURL, backupURL] {
            guard let data = try? Data(contentsOf: candidate),
                  let decoded = try? decoder.decode([TodoItem].self, from: data) else { continue }
            todos = decoded
            return
        }
    }

    private func loadSettings() {
        genres = UserDefaults.standard.stringArray(forKey: genresKey) ?? defaultGenres
        if !genres.contains("未分類") { genres.append("未分類") }
        genreColors = UserDefaults.standard.dictionary(forKey: genreColorsKey) as? [String: String] ?? [:]
        for genre in genres where genreColors[genre] == nil {
            genreColors[genre] = defaultGenreColors[genre] ?? fallbackGenreHex(genre)
        }
        timeframeTags = UserDefaults.standard.stringArray(forKey: timeframeTagsKey) ?? defaultTimeframeTags
        saveSettings()
    }

    private func saveSettings() {
        UserDefaults.standard.set(genres, forKey: genresKey)
        UserDefaults.standard.set(genreColors, forKey: genreColorsKey)
        UserDefaults.standard.set(timeframeTags, forKey: timeframeTagsKey)
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case dashboard = "TODO"
    case routines = "ルーティーン"

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .dashboard: .todoAccent
        case .routines: .routinePurple
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "sun.max.fill"
        case .routines: "repeat"
        }
    }
}

struct MainView: View {
    @ObservedObject var store: TodoStore

    @State private var currentDate = Date()
    @State private var page: AppPage = .dashboard
    @State private var inputText = ""
    @State private var inputDate: Date?
    @State private var inputTimeframe: String?
    @State private var inputSize: TodoSize = .none
    @State private var inputGenre = "未分類"
    @State private var inputRecurrence: TodoRecurrence = .none
    @State private var inputWeeklyDays: Set<Int> = [Calendar.current.component(.weekday, from: Date())]
    @State private var showInputOptions = false
    @State private var editingTodo: TodoItem?
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool
    private let dateRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            quickInput
            pagePicker
            Divider()
            content
        }
        .frame(minWidth: 650, minHeight: 700)
        .background(Color.todoBackground)
        .onAppear {
            currentDate = Date()
            inputFocused = true
            if !store.genres.contains(inputGenre) { inputGenre = store.genres.first ?? "未分類" }
        }
        .onReceive(dateRefreshTimer) { date in
            currentDate = date
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            currentDate = Date()
        }
        .sheet(item: $editingTodo) { item in
            EditTodoView(store: store, original: item)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayTitle).font(.system(size: 26, weight: .heavy)).foregroundColor(.todoText)
                Text("開けば、今日やることがわかる")
                    .font(.caption).foregroundColor(.todoMuted)
            }
            Spacer()
            if store.todayTotalCount > 0 {
                Text("今日 \(store.todayCompletedCount) / \(store.todayTotalCount)")
                    .font(.callout.bold())
                    .foregroundColor(.todoAccent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.todoAccent.opacity(0.10)))
            }
            Button("ジャンル・目処") { showSettings = true }
            Button("終了") { NSApp.terminate(nil) }.foregroundColor(.red)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    private var quickInput: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("思いついたTODOを、そのまま投げ入れる", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .bold))
                    .focused($inputFocused)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .foregroundColor(canSubmit ? .todoAccent : .todoBorder)
                .disabled(!canSubmit)
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.todoCard))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.todoBorder))

            HStack {
                Text(showInputOptions ? "目処・期日・繰り返しを指定できます" : "そのままEnterで「いつか」へ入ります")
                    .font(.caption).foregroundColor(.todoMuted)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showInputOptions.toggle() }
                } label: {
                    Label(showInputOptions ? "追加設定を閉じる" : "追加設定", systemImage: showInputOptions ? "chevron.up" : "slider.horizontal.3")
                }
                .buttonStyle(.borderless).foregroundColor(.todoAccent)
            }

            if showInputOptions {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        LabeledMenu(title: "目処", value: timeframeMenuValue) {
                            Button("なし（いつか）") { inputTimeframe = nil }
                            Divider()
                            ForEach(store.timeframeTags, id: \.self) { tag in
                                Button(tag) { inputTimeframe = tag }
                            }
                        }
                        .disabled(inputRecurrence != .none || inputDate != nil)

                        LabeledMenu(title: "ジャンル", value: inputGenre) {
                            ForEach(store.genres, id: \.self) { genre in
                                Button(genre) { inputGenre = genre }
                            }
                        }

                        LabeledMenu(title: "期日", value: inputDate.map(shortDate) ?? "なし") {
                            Button("期日なし") { inputDate = nil }
                            Divider()
                            Button("今日") { inputDate = Date() }
                            Button("明日") { inputDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                            Button("1週間後") { inputDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
                            Button("1か月後") { inputDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) }
                        }
                        .disabled(inputRecurrence != .none)

                        LabeledMenu(title: "ルーティーン", value: inputRecurrence.label) {
                            ForEach(TodoRecurrence.allCases) { recurrence in
                                Button(recurrence.label) { inputRecurrence = recurrence }
                            }
                        }
                        Spacer()
                    }

                    if inputRecurrence == .weekly {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("毎週出す曜日（複数選べます）")
                                .font(.caption.bold()).foregroundColor(.routinePurple)
                            WeekdayButtons(selection: $inputWeeklyDays)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.todoCard))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.todoBorder))
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var pagePicker: some View {
        HStack(spacing: 8) {
            ForEach(AppPage.allCases) { target in
                Button {
                    page = target
                } label: {
                    Label(target.rawValue, systemImage: target.symbol)
                        .font(.callout.bold())
                        .foregroundColor(page == target ? .white : target.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(page == target ? target.color : Color.todoCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(target.color.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .dashboard: dashboard
        case .routines: routines
        }
    }

    // 段は「期限切れ」＋目処タグの並び。ここに出ないTODOは無い。
    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !store.overdueItems.isEmpty {
                    DashboardSection(
                        title: "期限切れ",
                        subtitle: "期日が過ぎたもの",
                        accent: .red,
                        emptyMessage: ""
                    ) {
                        ForEach(store.overdueItems) { row(for: $0) }
                    }
                    .overlayEmpty(false)
                }

                ForEach(Array(store.timeframeTags.enumerated()), id: \.element) { pair in
                    let tag = pair.element
                    let items = store.items(forTimeframe: tag)
                    let isToday = tag == "今日中"
                    DashboardSection(
                        title: tag,
                        subtitle: subtitle(for: tag),
                        accent: sectionColor(at: pair.offset),
                        emptyMessage: "\(tag)のTODOはありません"
                    ) {
                        if isToday && !store.todayRoutines.isEmpty {
                            TaskGroupLabel(text: "ルーティーン", color: .routinePurple)
                            ForEach(store.todayRoutines) { row(for: $0) }
                            if !items.isEmpty {
                                TaskGroupLabel(text: "今日中のTODO", color: .todoAccent)
                            }
                        }
                        ForEach(items) { row(for: $0) }
                    }
                    .overlayEmpty(items.isEmpty && !(isToday && !store.todayRoutines.isEmpty))
                }

                if !store.completedItems.isEmpty {
                    VStack(spacing: 10) {
                        HStack {
                            Text("完了済み \(store.completedItems.count)件")
                                .font(.headline).foregroundColor(.todoMuted)
                            Spacer()
                            Button("完了済みを掃除") { store.clearDone() }.foregroundColor(.red)
                        }
                        ForEach(store.completedItems) { row(for: $0) }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(20)
        }
    }

    private func subtitle(for tag: String) -> String {
        if tag == "今日中" { return "ルーティーンと、今日中と決めたもの" }
        if tag == store.timeframeTags.last { return "期日も目処も決めていないものは、ここに入る" }
        return "目処が「\(tag)」のものと、期日がその範囲に入るもの"
    }

    private func sectionColor(at index: Int) -> Color {
        let palette: [Color] = [.todoAccent, .blue, .green, .cyan, .indigo, .routinePurple, .todoMuted]
        return palette[min(index, palette.count - 1)]
    }

    private var timeframeMenuValue: String {
        if inputRecurrence != .none { return "今日のルーティーン" }
        if inputDate != nil { return "期日から自動" }
        return inputTimeframe ?? "なし（いつか）"
    }

    private var routines: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ルーティーン").font(.title2.bold())
                        Text("毎日・毎週のTODO。該当する日にだけ『今日中』の段へ現れます。")
                            .font(.caption).foregroundColor(.todoMuted)
                    }
                    Spacer()
                }
                let routineItems = store.todos.filter { $0.recurrence != .none && !$0.done }
                if routineItems.isEmpty {
                    EmptyState(text: "ルーティーンはまだありません")
                } else {
                    ForEach(routineItems.sorted { $0.createdAt < $1.createdAt }) { row(for: $0) }
                }
            }
            .padding(20)
        }
    }

    private func row(for item: TodoItem) -> some View {
        TodoRow(store: store, item: item) { editingTodo = item }
    }

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var todayTitle: String {
        currentDate.formatted(.dateTime.month().day().weekday(.wide))
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = parseDate(trimmed)
        // 文中の「明日」等から拾った日付 → 追加設定の期日 の順に採る。ルーティーンは期日を持たない。
        let resolvedDate = inputRecurrence == .none ? (parsed.date ?? inputDate) : nil
        store.add(
            text: parsed.text,
            date: resolvedDate.map { Calendar.current.startOfDay(for: $0) },
            // 期日が入っているものは目処が自動で決まるので、手で選んだ目処は持たせない。
            timeframe: (resolvedDate == nil && inputRecurrence == .none) ? inputTimeframe : nil,
            size: inputSize,
            genre: inputGenre,
            recurrence: inputRecurrence,
            weeklyDays: inputRecurrence == .weekly
                ? Array(inputWeeklyDays.isEmpty ? [Calendar.current.component(.weekday, from: Date())] : inputWeeklyDays).sorted()
                : []
        )
        inputText = ""
        inputDate = nil
        inputTimeframe = nil
        inputSize = .none
        inputRecurrence = .none
        inputWeeklyDays = [Calendar.current.component(.weekday, from: Date())]
        showInputOptions = false
        inputFocused = true
    }
}

struct LabeledMenu<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    init(title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.bold()).foregroundColor(.todoMuted)
            Menu { content } label: {
                HStack(spacing: 5) {
                    Text(value).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.todoBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.todoBorder))
            }
            .menuStyle(.borderlessButton)
        }
    }
}

struct WeekdayButtons: View {
    @Binding var selection: Set<Int>
    private let days = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(days, id: \.self) { day in
                Button {
                    if selection.contains(day) {
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(shortWeekdayName(day))
                        .font(.callout.bold())
                        .foregroundColor(selection.contains(day) ? .white : .routinePurple)
                        .frame(width: 34, height: 30)
                        .background(Circle().fill(selection.contains(day) ? Color.routinePurple : Color.todoCard))
                        .overlay(Circle().stroke(Color.routinePurple.opacity(0.55)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let emptyMessage: String
    @ViewBuilder let content: Content
    @Environment(\.dashboardSectionIsEmpty) private var isEmpty

    init(
        title: String,
        subtitle: String,
        accent: Color,
        emptyMessage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.emptyMessage = emptyMessage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold()).foregroundColor(accent)
                Text(subtitle).font(.caption).foregroundColor(.todoMuted)
            }
            if isEmpty { EmptyState(text: emptyMessage) } else { content }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color.todoCard))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.todoBorder))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 5).padding(.vertical, 12)
        }
    }
}

private struct DashboardSectionEmptyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dashboardSectionIsEmpty: Bool {
        get { self[DashboardSectionEmptyKey.self] }
        set { self[DashboardSectionEmptyKey.self] = newValue }
    }
}

extension View {
    func overlayEmpty(_ isEmpty: Bool) -> some View {
        environment(\.dashboardSectionIsEmpty, isEmpty)
    }
}

struct TaskGroupLabel: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold()).foregroundColor(color)
            .padding(.top, 3)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundColor(.todoMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

struct TodoRow: View {
    @ObservedObject var store: TodoStore
    let item: TodoItem
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button { store.toggle(id: item.id) } label: {
                Image(systemName: store.isCompleted(item) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(store.isCompleted(item) ? .green : .todoMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(store.isCompleted(item) ? .todoMuted : .todoText)
                    .strikethrough(store.isCompleted(item))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    GenreChip(text: item.genre, color: store.genreColor(for: item.genre))
                    if item.recurrence != .none {
                        MetaChip(text: recurrenceLabel(item), color: .routinePurple)
                    }
                    if item.size != .none { Text(item.size.label) }
                    if let date = item.date {
                        MetaChip(text: "期日 \(shortDate(date))", color: dueColor(date))
                    } else if item.recurrence == .none {
                        MetaChip(text: "目処 \(store.timeframeSlot(for: item))", color: .todoMuted)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            if item.recurrence == .none && !item.done {
                Menu {
                    Section("目処へ移す（期日は外れます）") {
                        ForEach(store.timeframeTags, id: \.self) { tag in
                            Button(tag) { store.setTimeframe(id: item.id, timeframe: tag) }
                        }
                    }
                    Section("期日を入れる") {
                        Button("今日") { store.setDate(id: item.id, date: Date()) }
                        Button("明日") { store.moveToTomorrow(id: item.id) }
                        Button("1週間後") {
                            store.setDate(id: item.id, date: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
                        }
                        if item.date != nil {
                            Button("期日を外す") { store.setDate(id: item.id, date: nil) }
                        }
                    }
                } label: {
                    Image(systemName: item.date == nil ? "tray.full" : "calendar.badge.clock")
                }
                .help("目処を変える・期日を入れる")
            }

            Menu {
                ForEach(store.genres, id: \.self) { genre in
                    Button(genre) { store.setGenre(id: item.id, genre: genre) }
                }
            } label: { Image(systemName: "tag") }

            Button(action: edit) { Image(systemName: "pencil") }
                .help("内容・期日・目処・繰り返しを編集")
            Button { store.delete(id: item.id) } label: { Image(systemName: "trash") }
                .foregroundColor(.red.opacity(0.75))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.todoBackground.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.todoBorder.opacity(0.8)))
    }
}

struct GenreChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color))
    }
}

struct MetaChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.10)))
    }
}

struct EditTodoView: View {
    @ObservedObject var store: TodoStore
    let original: TodoItem
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var hasDate: Bool

    init(store: TodoStore, original: TodoItem) {
        self.store = store
        self.original = original
        _draft = State(initialValue: original)
        _hasDate = State(initialValue: original.date != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TODOを編集").font(.title2.bold())
            TextField("内容", text: $draft.text).textFieldStyle(.roundedBorder)

            Form {
                Picker("ジャンル", selection: $draft.genre) {
                    ForEach(store.genres, id: \.self) { Text($0).tag($0) }
                }

                Toggle("期日を入れる（日にち指定）", isOn: $hasDate)
                    .disabled(draft.recurrence != .none)
                if hasDate && draft.recurrence == .none {
                    DatePicker("期日", selection: Binding(
                        get: { draft.date ?? Date() },
                        set: { draft.date = $0 }
                    ), displayedComponents: .date)
                    Text("期日を入れると、目処は日付から自動で決まります。")
                        .font(.caption).foregroundColor(.todoMuted)
                }

                Picker("目処", selection: Binding(
                    get: { draft.timeframe ?? "" },
                    set: { draft.timeframe = $0.isEmpty ? nil : $0 }
                )) {
                    Text("なし（いつか）").tag("")
                    ForEach(store.timeframeTags, id: \.self) { Text($0).tag($0) }
                }
                .disabled(hasDate || draft.recurrence != .none)

                Picker("大きさ", selection: $draft.size) {
                    ForEach(TodoSize.allCases, id: \.self) { size in
                        Text(size == .none ? "指定なし" : "\(size.label) \(size.rawValue)").tag(size)
                    }
                }

                Picker("ルーティーン", selection: $draft.recurrence) {
                    ForEach(TodoRecurrence.allCases) { Text($0.label).tag($0) }
                }
                if draft.recurrence == .weekly {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("曜日（複数選べます）").font(.caption.bold()).foregroundColor(.routinePurple)
                        WeekdayButtons(selection: Binding(
                            get: { Set(draft.weeklyDays) },
                            set: { draft.weeklyDays = Array($0).sorted() }
                        ))
                    }
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    draft.text = trimmed
                    if !hasDate || draft.recurrence != .none {
                        draft.date = nil
                    } else if draft.date == nil {
                        draft.date = Date()
                    }
                    draft.date = draft.date.map { Calendar.current.startOfDay(for: $0) }
                    // 期日が入っているものは目処が自動で決まるので、手で選んだ目処は残さない。
                    if draft.date != nil { draft.timeframe = nil }
                    if draft.recurrence == .none {
                        draft.weeklyDay = nil
                        draft.weeklyDays = []
                    } else {
                        draft.timeframe = nil
                    }
                    if draft.recurrence == .weekly && draft.weeklyDays.isEmpty {
                        draft.weeklyDays = [Calendar.current.component(.weekday, from: Date())]
                    }
                    draft.weeklyDay = draft.weeklyDays.first
                    store.update(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 500)
    }
}

struct SettingsView: View {
    @ObservedObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var newGenre = ""
    @State private var newGenreColor = Color.indigo
    @State private var newTimeframe = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ジャンル・目処").font(.title2.bold())
                Spacer()
                Button("閉じる") { dismiss() }
            }
            HStack(alignment: .top, spacing: 18) {
                genreSettingsColumn
                settingsColumn(
                    title: "目処",
                    items: store.timeframeTags,
                    text: $newTimeframe,
                    placeholder: "新しい目処",
                    add: { store.addTimeframe(newTimeframe); newTimeframe = "" },
                    remove: store.removeTimeframe
                )
            }
        }
        .buttonStyle(.borderless).padding(22).frame(width: 620, height: 520)
        .background(Color.todoBackground)
    }

    private var genreSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ジャンル").font(.headline)
            Text("色の丸を押すと、あとから変更できます")
                .font(.caption).foregroundColor(.todoMuted)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.genres, id: \.self) { genre in
                        HStack {
                            GenreChip(text: genre, color: store.genreColor(for: genre))
                            Spacer()
                            ColorPicker(
                                "\(genre)の色",
                                selection: Binding(
                                    get: { store.genreColor(for: genre) },
                                    set: { store.setGenreColor(genre, color: $0) }
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .frame(width: 28)
                            if genre != "未分類" {
                                Button { store.removeGenre(genre) } label: { Image(systemName: "trash") }
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.todoCard))
                    }
                }
            }
            HStack {
                TextField("新しいジャンル", text: $newGenre)
                ColorPicker("新しいジャンルの色", selection: $newGenreColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28)
                Button("追加") {
                    store.addGenre(newGenre, color: newGenreColor)
                    newGenre = ""
                    newGenreColor = .indigo
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsColumn(
        title: String,
        items: [String],
        text: Binding<String>,
        placeholder: String,
        add: @escaping () -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Text(item)
                            Spacer()
                            if item != "未分類" {
                                Button { remove(item) } label: { Image(systemName: "trash") }
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.todoCard))
                    }
                }
            }
            HStack {
                TextField(placeholder, text: text)
                Button("追加", action: add)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private func shortDate(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "今日" }
    if calendar.isDateInTomorrow(date) { return "明日" }
    return date.formatted(.dateTime.month().day())
}

private func dueColor(_ date: Date) -> Color {
    Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()) ? .red : .todoAccent
}

private func weekdayName(_ weekday: Int) -> String {
    ["", "日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][max(1, min(7, weekday))]
}

private func shortWeekdayName(_ weekday: Int) -> String {
    weekdayName(weekday).replacingOccurrences(of: "曜日", with: "")
}

private func recurrenceLabel(_ item: TodoItem) -> String {
    switch item.recurrence {
    case .none: return ""
    case .daily: return "毎日"
    case .weekly:
        let labels = item.weeklyDays.sorted(by: weekdayDisplayOrder).map(shortWeekdayName).joined(separator: "・")
        return labels.isEmpty ? "毎週" : "毎週 \(labels)"
    }
}

private func weekdayDisplayOrder(_ lhs: Int, _ rhs: Int) -> Bool {
    let order = [2, 3, 4, 5, 6, 7, 1]
    return (order.firstIndex(of: lhs) ?? 7) < (order.firstIndex(of: rhs) ?? 7)
}

private func fallbackGenreHex(_ genre: String) -> String {
    let palette = ["D9468F", "4F46E5", "0F8B8D", "7C3AED", "B45309", "0369A1", "BE185D"]
    let value = genre.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[value % palette.count]
}

private extension Color {
    init(todoHex: String) {
        let cleaned = todoHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x6B707A
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var todoHex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return String(
            format: "%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}

private func parseDate(_ text: String) -> (text: String, date: Date?) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2 else { return (trimmed, nil) }

    let prefix = String(parts[0])
    let remainder = String(parts[1])
    let relative = ["今日": 0, "本日": 0, "明日": 1, "あした": 1, "明後日": 2, "あさって": 2]
    if let offset = relative[prefix] {
        return (remainder, Calendar.current.date(byAdding: .day, value: offset, to: Date()))
    }

    let dateParts = prefix.split { $0 == "/" || $0 == "-" }
    if dateParts.count == 2, let month = Int(dateParts[0]), let day = Int(dateParts[1]) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.month = month
        components.day = day
        if let candidate = calendar.date(from: components) {
            if candidate < calendar.startOfDay(for: Date()) {
                components.year = (components.year ?? 2026) + 1
            }
            return (remainder, calendar.date(from: components))
        }
    }
    return (trimmed, nil)
}
