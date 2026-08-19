import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var store: JournalStore

    var body: some View {
        List(selection: $store.filterMode) {
            Section {
                Label("すべて", systemImage: "book")
                    .tag(JournalStore.FilterMode.all)

                Label("今日", systemImage: "calendar.day.timeline.left")
                    .tag(JournalStore.FilterMode.today)
            }

            Section("年別") {
                ForEach(store.entriesByYear, id: \.year) { item in
                    HStack {
                        Text("\(String(item.year))年")
                            .font(.body)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .tag(JournalStore.FilterMode.year(item.year))
                }
            }

            Section("その他") {
                Label("ゴミ箱", systemImage: "trash")
                    .foregroundStyle(.secondary)
                Label("設定", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}
