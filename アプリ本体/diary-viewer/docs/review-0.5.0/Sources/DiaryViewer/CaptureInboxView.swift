import SwiftUI
import DiaryCore

/// 原文を保持し、日付確定後に明示操作で年別日記へ採用する。
struct CaptureInboxView: View {
    let root: URL
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Capture] = []
    @State private var selectedID: UUID?
    @State private var text = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var composing = false
    @State private var error: String?
    @State private var message: String?
    @State private var library: CaptureLibrary?
    @State private var draftID = UUID()

    private var selected: Capture? { items.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("受け箱").font(.title2.bold())
                Text("\(items.count)件").foregroundStyle(.secondary)
                Spacer()
                Button("文章を追加", systemImage: "plus") { newDraft() }
                    .disabled(library == nil)
                Button("バックアップを作成", systemImage: "externaldrive") { backup() }
                    .disabled(library == nil)
                Button("閉じる") { dismiss() }
            }.padding(20)
            Text("書いたまま保存できます。日付を決めた文章は、日記のその日に表示されます。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text((item.journalDate ?? "日付未定") + (item.adopted ? " ・ 日記へ保存済み" : ""))
                                .font(.caption).foregroundStyle(item.journalDate == nil ? Color.orange : .secondary)
                            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                .lineLimit(3)
                        }.padding(.vertical, 6).tag(item.id)
                    }
                }.frame(minWidth: 220, idealWidth: 270, maxWidth: 330)

                VStack(alignment: .leading, spacing: 14) {
                    if composing {
                        Text("新しい雑感").font(.headline)
                        TextEditor(text: $text)
                            .font(.body).padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            .accessibilityLabel("雑感の本文")
                        dateControls
                        HStack {
                            Text("原文をそのまま保存します。AI処理は行いません。")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("保存せず戻る") { composing = false }
                            Button("受け箱に保存") { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library == nil)
                        }
                    } else if let selected {
                        Text(selected.journalDate ?? "日付はまだ決めていません").font(.headline)
                        ScrollView {
                            Text(selected.text).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }.frame(maxHeight: .infinity)
                        Divider()
                        dateControls.disabled(selected.adopted && !JournalStore.allowsJournalWrites(root))
                        HStack {
                            Button("日付を更新") { updateDate(selected) }.disabled(selected.adopted && !JournalStore.allowsJournalWrites(root))
                            Spacer()
                            if selected.adopted {
                                Text("日記へ保存済み（原文も保持しています）").foregroundStyle(.secondary)
                            } else if JournalStore.allowsJournalWrites(root) {
                                Button("日記へ保存") { adopt(selected) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(selected.journalDate == nil || dateChanged(selected))
                            } else {
                                Text("日記への保存は検証中です").foregroundStyle(.secondary)
                            }
                        }
                        if selected.adopted && JournalStore.allowsJournalWrites(root) {
                            Text("日付を直すと日記も移動します。指定を外すと受け箱だけに戻ります。").font(.caption).foregroundStyle(.secondary)
                        } else if selected.adopted {
                            Text("保存済みの日記の日付変更は検証中です。").font(.caption).foregroundStyle(.secondary)
                        } else if dateChanged(selected) {
                            Text("先に「日付を更新」で書いた日を確定してください。").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Spacer()
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 40)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Text("雑感を貼り付けて、まず残しておきましょう。")
                            .frame(maxWidth: .infinity).foregroundStyle(.secondary)
                        Button("文章を追加") { newDraft() }.buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity).disabled(library == nil)
                        Spacer()
                    }
                }.padding(20).frame(minWidth: 480)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("日付未定の文章は受け箱に残ります。Wordファイル・レシートの取り込みは準備中です。")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { load() }
        .onChange(of: selectedID) { _, _ in
            if let selected {
                composing = false
                hasDate = selected.journalDate != nil
                if let raw = selected.journalDate, let parsed = dateFormatter.date(from: raw) { date = parsed }
            }
        }
    }

    private var dateControls: some View {
        HStack(spacing: 16) {
            Toggle("書いた日を指定する", isOn: $hasDate)
            DatePicker("書いた日", selection: $date, displayedComponents: .date)
                .labelsHidden().disabled(!hasDate)
            Spacer()
        }
    }
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    private func load() {
        do {
            let opened = try CaptureLibrary(root: root, allowJournalWrites: JournalStore.allowsJournalWrites(root))
            let loaded = try opened.captures()
            library = opened; items = loaded; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func newDraft() {
        selectedID = nil; text = ""; hasDate = false; date = Date(); draftID = UUID()
        composing = true; error = nil; message = nil
    }
    private func save() {
        guard let library else { return }
        do {
            let item = try library.capture(text: text, date: hasDate ? dateFormatter.string(from: date) : nil, id: draftID)
            items = try library.captures(); composing = false; selectedID = item.id
            message = "原文を受け箱に保存しました。"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func updateDate(_ item: Capture) {
        guard let library else { return }
        do {
            try library.setDate(hasDate ? dateFormatter.string(from: date) : nil, for: item.id, expectedRevision: item.revision)
            items = try library.captures(); message = "日付を更新しました。原文はそのままです。"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func dateChanged(_ item: Capture) -> Bool {
        item.journalDate != (hasDate ? dateFormatter.string(from: date) : nil)
    }
    private func adopt(_ item: Capture) {
        guard let library else { return }
        do {
            try library.adopt(item.id, expectedRevision: item.revision)
            items = try library.captures()
            message = "日記へ保存しました。受け箱の原文も残しています。"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func backup() {
        guard let library else { return }
        let destination = root.appendingPathComponent("バックアップ/日記受け箱/\(UUID().uuidString)")
        do {
            try library.backup(to: destination)
            message = "受け箱と年別日記のバックアップを作成しました（写真・動画は対象外）。\n\(destination.path)"; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
