import SwiftUI

// MARK: - ContentView (3ペイン)

struct ContentView: View {
    @StateObject var store = JournalStore()
    @State private var showFolderPicker = false
    @State private var showTagFilter = false

    var body: some View {
        Group {
            if store.dataSource == .notSelected {
                // ★フォルダ未選択のときは一覧を出さない。
                //   以前はここで同梱サンプルを黙って表示しており、本物の日記と
                //   見分けがつかなかった（2026-08-03）。JournalStore.DataSource を参照。
                WelcomeView { showFolderPicker = true }
            } else {
                mainSplitView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showFolderPicker = true }) {
                    Image(systemName: "folder")
                }
                .help("フォルダを選択")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showTagFilter.toggle() }) {
                    Image(systemName: "tag")
                }
                .help("タグで絞り込み")
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(store: store)
        }
        .sheet(isPresented: $showTagFilter) {
            TagFilterView(store: store)
        }
        // ★ .preferredColorScheme(.dark) を外した（2026-07-31）。
        //   ダークを強制していたため、システムがライトでも画面が真っ黒だった（本人評「黒すぎる」）。
        //   いまはmacOSの外観設定に従う。ダークで使いたいときはシステム側で切り替える。
    }

    private var mainSplitView: some View {
        VStack(spacing: 0) {
            if store.dataSource == .fixtures {
                fixturesBanner
            }
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
            } content: {
                // ★詳細ペインを広く取るため、一覧の ideal を 360 → 300 に下げた（2026-07-31）
                EntryListView(store: store)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            } detail: {
                if let entry = store.selectedEntry {
                    DetailView(entry: entry, imageResolver: store.imageResolver)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("エントリを選んでください")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// サンプル表示中であることを、隠しようがない形で出す
    private var fixturesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("開発用のサンプルデータを表示しています。あなたの日記ではありません。")
                .fontWeight(.medium)
            Spacer()
            Button("日記フォルダを選ぶ…") { showFolderPicker = true }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.22))
    }
}

// MARK: - Welcome（フォルダ未選択）

struct WelcomeView: View {
    var onChoose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("日記フォルダを選んでください")
                .font(.title2)
                .fontWeight(.semibold)
            Text("「ジャーナル/」と「media/」を含むフォルダを選びます。\n一度選べば次回から自動で開きます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("フォルダを選択…", action: onChoose)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Folder Picker

struct FolderPickerView: View {
    @ObservedObject var store: JournalStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("日記フォルダを選択")
                .font(.title2)
            Text("「ジャーナル/」と「media/」を含むフォルダを選んでください")
                .foregroundStyle(.secondary)
            Button("フォルダを選択…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "「ジャーナル/」と「media/」を含むフォルダを選んでください"
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        // 非サンドボックスでは startAccessing… が false を返すため、戻り値で分岐せず必ず読み込む
                        let accessed = url.startAccessingSecurityScopedResource()
                        store.load(baseURL: url)
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            Button("キャンセル") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 400)
    }
}

// MARK: - Tag Filter

struct TagFilterView: View {
    @ObservedObject var store: JournalStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("タグで絞り込み")
                .font(.title2)
            if store.allTags.isEmpty {
                Text("タグがありません")
                    .foregroundStyle(.secondary)
            } else {
                List(store.allTags, id: \.self) { tag in
                    HStack {
                        Text(tag)
                            .font(.body)
                        Spacer()
                        if store.selectedTags.contains(tag) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.selectedTags.contains(tag) {
                            store.selectedTags.remove(tag)
                        } else {
                            store.selectedTags.insert(tag)
                        }
                    }
                }
                .listStyle(.plain)

                HStack {
                    Button("すべて解除") {
                        store.selectedTags.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("閉じる") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 300, height: 400)
    }
}
