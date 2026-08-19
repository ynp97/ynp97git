import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var draft = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var calendarMessage = ""
    @State private var showingDeleteDoneAlert = false
    private let calendarService = CalendarService()

    var body: some View {
        HStack(spacing: 0) {
            TagShelfView()
                .frame(width: 245)
                .background(.regularMaterial)

            VStack(spacing: 14) {
                composer
                listHeader
                taskList
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("完了TODOを消しますか?", isPresented: $showingDeleteDoneAlert) {
            Button("消す", role: .destructive) {
                store.clearDone()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("完了したTODOだけを一覧から削除します。")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("書く")
                .font(.headline)
            TextEditor(text: $draft)
                .font(.system(size: 18))
                .frame(minHeight: 112, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack(spacing: 10) {
                Toggle("期限", isOn: $hasDueDate)
                    .toggleStyle(.checkbox)
                if hasDueDate {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }

                Spacer()

                Text("⌘ + Return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    addDraft()
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var listHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("並んでいるTODO")
                    .font(.title3.bold())
                Text("\(store.openCount)件の未完了  /  \(store.statusMessage)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $store.filter) {
                ForEach(TodoFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            TextField("検索", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button {
                store.addStarterTasks()
            } label: {
                Label("現在地", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                showingDeleteDoneAlert = true
            } label: {
                Label("完了整理", systemImage: "trash")
            }
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.filteredTasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("TODOは空です")
                            .font(.title3.bold())
                        Text("思いついたことを上に書いて追加します。")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                } else {
                    ForEach(store.filteredTasks) { task in
                        TaskRowView(task: task) {
                            Task {
                                await addCalendarEvent(for: task)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay(alignment: .bottomLeading) {
            if !calendarMessage.isEmpty {
                Text(calendarMessage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thickMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    private func addDraft() {
        store.addTask(from: draft, dueDate: hasDueDate ? dueDate : nil)
        draft = ""
        hasDueDate = false
    }

    private func addCalendarEvent(for task: TodoTask) async {
        do {
            try await calendarService.addEvent(for: task)
            calendarMessage = "カレンダーに追加しました"
        } catch {
            calendarMessage = error.localizedDescription
        }

        try? await Task.sleep(nanoseconds: 2_500_000_000)
        calendarMessage = ""
    }
}
