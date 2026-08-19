import SwiftUI

// MARK: - Entry List

struct EntryListView: View {
    @ObservedObject var store: JournalStore
    @State private var searchText: String = ""

    /// Listの選択をいったんローカルで受けるための状態。
    ///
    /// ★踏んではいけない地雷（2026-08-03）
    /// 以前は `List(selection: $store.selectedEntry)` と、ストアの `@Published` を
    /// 直接束縛していた。行を選ぶ → `objectWillChange` が飛ぶ → この body が再評価され
    /// `entriesGroupedByMonth` を読み直す → **NSTableViewのデリゲート実行中に
    /// テーブルが作り直される**。これが
    ///   `WARNING: Application performed a reentrant operation in its NSTableView delegate.`
    /// の正体で、Appleは将来assertになると告知している（＝放置するといずれ落ちる）。
    /// **選択をストアへ直接束縛し直さないこと。**
    @State private var selectedID: Entry.ID?

    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索…", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        store.searchQuery = newValue
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = ""; store.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            // エントリ一覧
            if store.filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("エントリがありません")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(store.entriesGroupedByMonth, id: \.month) { group in
                        Section(header: monthHeader(group.month)) {
                            ForEach(group.entries) { entry in
                                EntryRow(entry: entry, imageResolver: store.imageResolver)
                                    .tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .controlBackgroundColor))
        // 選択 → ストア。
        // Task で「いまのイベント処理が終わってから」書く。
        // ここを同期にすると、上の地雷（NSTableViewの再入）が戻る。
        .onChange(of: selectedID) { _, newID in
            guard store.selectedEntry?.id != newID else { return }
            let entry = newID.flatMap { id in
                store.filteredEntries.first { $0.id == id }
            }
            Task { @MainActor in
                store.selectedEntry = entry
            }
        }
        // ストア → 選択（絞り込みで選択が外れた場合などに追従する）
        .onChange(of: store.selectedEntry) { _, newEntry in
            if newEntry?.id != selectedID {
                selectedID = newEntry?.id
            }
        }
    }

    private func monthHeader(_ dc: DateComponents) -> some View {
        HStack {
            Text("\(dc.year ?? 0)年\(dc.month ?? 0)月")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: Entry
    let imageResolver: ImageResolver?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左: 日付
            VStack(alignment: .center, spacing: 2) {
                Text(entry.displayDateShort)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                Text(entry.weekday)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42)

            // 中央: プレビュー
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview)
                    .font(.callout)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if !entry.time.isEmpty {
                        Text(entry.time)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let loc = entry.location, !loc.isEmpty {
                        Text(loc)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 右: サムネイル
            if let firstAttachment = entry.attachments.first,
               let resolver = imageResolver,
               let imageURL = resolver.resolve(firstAttachment),
               !resolver.isVideo(firstAttachment),
               let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
