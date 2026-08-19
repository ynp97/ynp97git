import Foundation

struct TodoTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var note: String
    var dueDate: Date?
    var tagIDs: [UUID]
    var isDone: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        dueDate: Date? = nil,
        tagIDs: [UUID] = [],
        isDone: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.tagIDs = tagIDs
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct TodoTag: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

struct TodoData: Codable {
    var tasks: [TodoTask]
    var tags: [TodoTag]
}

enum TodoFilter: String, CaseIterable, Identifiable {
    case open
    case all
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "未完了"
        case .all: return "全部"
        case .done: return "完了"
        }
    }
}
