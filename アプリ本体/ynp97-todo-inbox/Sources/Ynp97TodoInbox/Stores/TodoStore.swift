import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = []
    @Published private(set) var tags: [TodoTag] = []
    @Published var selectedTaskID: UUID?
    @Published var filter: TodoFilter = .open
    @Published var searchText = ""
    @Published var newTagName = ""
    @Published var newTagColorHex = "#ffe08a"
    @Published var statusMessage = "保存済み"

    private let appSupportURL: URL
    private let dataURL: URL
    private let legacyDataURL: URL
    private let vaultMarkdownURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("ynp97 TODOインボックス", isDirectory: true)
        self.appSupportURL = appSupport
        self.dataURL = appSupport.appendingPathComponent("todo-data.json")
        self.legacyDataURL = home
            .appendingPathComponent("Documents/Obsidian Vault/アプリ/ynp97 TODOインボックス.data.json")
        self.vaultMarkdownURL = home
            .appendingPathComponent("Documents/Obsidian Vault/TODOインボックス.md")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        load()
        save()
    }

    var filteredTasks: [TodoTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            switch filter {
            case .open where task.isDone:
                return false
            case .done where !task.isDone:
                return false
            default:
                break
            }

            guard !query.isEmpty else { return true }
            let tagNames = task.tagIDs.compactMap(tagName).joined(separator: " ")
            return "\(task.title) \(task.note) \(tagNames)".lowercased().contains(query)
        }
        .sorted { first, second in
            if first.isDone != second.isDone { return !first.isDone }
            switch (first.dueDate, second.dueDate) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return first.createdAt > second.createdAt
            }
        }
    }

    var openCount: Int {
        tasks.filter { !$0.isDone }.count
    }

    var selectedTask: TodoTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    func addTask(from rawText: String, dueDate: Date?) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = lines.first ?? trimmed
        let note = lines.dropFirst().joined(separator: "\n")
        let task = TodoTask(title: title, note: note, dueDate: dueDate)
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        filter = .open
        save()
    }

    func addStarterTasks() {
        let starters = [
            ("Pastor DennisへWise送金用の口座情報を聞く", "口座名義、銀行名、口座番号、口座通貨、個人口座かプロジェクト/ビジネス用口座か。"),
            ("Pastor Dennisへ孤児院用地候補を見たいことを伝える", "海と夕陽が見える山側、土地価格、所有関係、道路、水道電気、整地費、地元案内役。"),
            ("家庭ゲートの説明要点を4行にする", "教会、KG・教育事業、150万円を超えるビジョン、最大リスクと資金見通し。"),
            ("航空券の予約内容とターミナルを確定する", "9/1朝MNL→DGT、9/4夜DGT→MNLを軸に確認。")
        ]
        let existingTitles = Set(tasks.map(\.title))
        var inserted = 0
        for item in starters where !existingTitles.contains(item.0) {
            tasks.insert(TodoTask(title: item.0, note: item.1, tagIDs: [defaultWeekTagID].compactMap { $0 }), at: 0)
            inserted += 1
        }
        statusMessage = inserted == 0 ? "現在地TODOは登録済み" : "\(inserted)件追加"
        save()
    }

    func toggleDone(_ task: TodoTask) {
        updateTask(task.id) { item in
            item.isDone.toggle()
        }
    }

    func delete(_ task: TodoTask) {
        tasks.removeAll { $0.id == task.id }
        if selectedTaskID == task.id { selectedTaskID = nil }
        save()
    }

    func clearDone() {
        tasks.removeAll { $0.isDone }
        save()
    }

    func toggleTag(_ tag: TodoTag, for task: TodoTask) {
        updateTask(task.id) { item in
            if item.tagIDs.contains(tag.id) {
                item.tagIDs.removeAll { $0 == tag.id }
            } else {
                item.tagIDs.append(tag.id)
            }
        }
    }

    func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !tags.contains(where: { $0.name == name }) else {
            statusMessage = "同じ付箋があります"
            return
        }
        tags.append(TodoTag(name: name, colorHex: newTagColorHex))
        newTagName = ""
        save()
    }

    func deleteTag(_ tag: TodoTag) {
        tags.removeAll { $0.id == tag.id }
        for index in tasks.indices {
            tasks[index].tagIDs.removeAll { $0 == tag.id }
        }
        save()
    }

    func tagName(for id: UUID) -> String? {
        tags.first { $0.id == id }?.name
    }

    func tag(for id: UUID) -> TodoTag? {
        tags.first { $0.id == id }
    }

    func tasks(for tag: TodoTag) -> Int {
        tasks.filter { !$0.isDone && $0.tagIDs.contains(tag.id) }.count
    }

    func select(_ task: TodoTask) {
        selectedTaskID = task.id
    }

    func taskContains(_ task: TodoTask, tag: TodoTag) -> Bool {
        task.tagIDs.contains(tag.id)
    }

    func markdown() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = [
            "# TODOインボックス",
            "",
            "最終更新: \(formatter.string(from: Date()))",
            "",
            "## 未完了"
        ]
        lines.append(contentsOf: markdownLines(tasks.filter { !$0.isDone }))
        lines.append("")
        lines.append("## 完了")
        lines.append(contentsOf: markdownLines(tasks.filter(\.isDone)))
        return lines.joined(separator: "\n")
    }

    func ynpPack() -> String {
        let groups = [
            ("今日中", tasks(withTagNamed: "今日中")),
            ("急ぎ", tasks(withTagNamed: "急ぎ")),
            ("今週中", tasks(withTagNamed: "今週中")),
            ("待機", tasks(withTagNamed: "待機")),
            ("未分類", tasks.filter { !$0.isDone && $0.tagIDs.isEmpty })
        ]
        var lines = ["ynp97", "", "## TODO相談パック"]
        for group in groups {
            lines.append("")
            lines.append("### \(group.0)")
            lines.append(contentsOf: group.1.prefix(8).map { "- \($0.title)" })
            if group.1.isEmpty { lines.append("- なし") }
        }
        lines.append("")
        lines.append("### 相談したいこと")
        lines.append("- この中から、今日の主成果物1つと、短く触れるもの2つまでに絞ってください。")
        return lines.joined(separator: "\n")
    }

    private var defaultWeekTagID: UUID? {
        tags.first { $0.name == "今週中" }?.id
    }

    private func updateTask(_ id: UUID, mutate: (inout TodoTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
        tasks[index].updatedAt = Date()
        save()
    }

    private func load() {
        do {
            let sourceURL = FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : legacyDataURL
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let data = try Data(contentsOf: sourceURL)
                let decoded = try decoder.decode(TodoData.self, from: data)
                tasks = decoded.tasks
                tags = decoded.tags.isEmpty ? Self.defaultTags : decoded.tags
            } else {
                tasks = []
                tags = Self.defaultTags
            }
        } catch {
            tasks = []
            tags = Self.defaultTags
            statusMessage = "読み込みに失敗"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let data = try encoder.encode(TodoData(tasks: tasks, tags: tags))
            try data.write(to: dataURL, options: .atomic)
            try markdown().write(to: vaultMarkdownURL, atomically: true, encoding: .utf8)
            statusMessage = "Obsidianへ保存済み"
        } catch {
            statusMessage = "保存できませんでした"
        }
    }

    private func markdownLines(_ input: [TodoTask]) -> [String] {
        guard !input.isEmpty else { return ["- なし"] }
        let dueFormatter = DateFormatter()
        dueFormatter.locale = Locale(identifier: "ja_JP")
        dueFormatter.dateFormat = "yyyy-MM-dd"
        return input.map { task in
            let tagsText = task.tagIDs.compactMap(tagName).map { "#\($0)" }.joined(separator: " ")
            let dueText = task.dueDate.map { " 期限:\(dueFormatter.string(from: $0))" } ?? ""
            let line = "- [\(task.isDone ? "x" : " ")] \(task.title)\(tagsText.isEmpty ? "" : " \(tagsText)")\(dueText)"
            if task.note.isEmpty { return line }
            return line + "\n  - " + task.note.replacingOccurrences(of: "\n", with: "\n  - ")
        }
    }

    private func tasks(withTagNamed name: String) -> [TodoTask] {
        guard let tag = tags.first(where: { $0.name == name }) else { return [] }
        return tasks.filter { !$0.isDone && $0.tagIDs.contains(tag.id) }
    }

    private static let defaultTags: [TodoTag] = [
        TodoTag(name: "今日中", colorHex: "#ffe08a"),
        TodoTag(name: "今週中", colorHex: "#c9f2d2"),
        TodoTag(name: "急ぎ", colorHex: "#ffc6bd"),
        TodoTag(name: "待機", colorHex: "#cfe1ff")
    ]
}
