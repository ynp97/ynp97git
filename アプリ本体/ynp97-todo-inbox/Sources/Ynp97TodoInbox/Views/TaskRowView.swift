import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject private var store: TodoStore
    let task: TodoTask
    let addToCalendar: () -> Void

    private var isSelected: Bool {
        store.selectedTaskID == task.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.toggleDone(task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone)
                        .fixedSize(horizontal: false, vertical: true)

                    if let dueText {
                        Label(dueText, systemImage: "calendar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(dueColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(dueColor.opacity(0.12), in: Capsule())
                    }

                    Spacer()
                }

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(task.tagIDs.compactMap(store.tag)) { tag in
                        Text(tag.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.78))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: tag.colorHex), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            VStack(spacing: 8) {
                Button {
                    addToCalendar()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .help("カレンダーに追加")
                .disabled(task.dueDate == nil)

                Button(role: .destructive) {
                    store.delete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .help("削除")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(task)
        }
    }

    private var dueText: String? {
        guard let dueDate = task.dueDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) { return "今日まで" }
        if calendar.isDateInTomorrow(dueDate) { return "明日まで" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/dまで"
        return formatter.string(from: dueDate)
    }

    private var dueColor: Color {
        guard let dueDate = task.dueDate else { return .secondary }
        let today = Date().startOfDay
        if dueDate.startOfDay < today { return .red }
        if Calendar.current.isDateInToday(dueDate) { return .orange }
        return .blue
    }
}
