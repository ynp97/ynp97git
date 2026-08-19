import AppKit
import SwiftUI

struct TagShelfView: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("付箋")
                    .font(.title3.bold())
                Text("TODOを選んで貼る")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)

            VStack(spacing: 8) {
                ForEach(store.tags) { tag in
                    TagNoteView(tag: tag)
                }
            }

            Divider()

            Text("付箋を作る")
                .font(.headline)
            TextField("名前", text: $store.newTagName)
                .textFieldStyle(.roundedBorder)
            ColorPicker("色", selection: Binding(
                get: { Color(hex: store.newTagColorHex) },
                set: { color in
                    store.newTagColorHex = color.toHex() ?? store.newTagColorHex
                }
            ))

            Button {
                store.addTag()
            } label: {
                Label("付箋を追加", systemImage: "plus")
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.ynpPack(), forType: .string)
            } label: {
                Label("ynp97用をコピー", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }
}

private struct TagNoteView: View {
    @EnvironmentObject private var store: TodoStore
    let tag: TodoTag

    var body: some View {
        Button {
            if let task = store.selectedTask {
                store.toggleTag(tag, for: task)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name)
                        .font(.headline)
                        .foregroundStyle(.black.opacity(0.78))
                    Text("\(store.tasks(for: tag))件")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.5))
                }
                Spacer()
                if let task = store.selectedTask, store.taskContains(task, tag: tag) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: tag.colorHex), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.black.opacity(0.08))
            }
            .rotationEffect(.degrees(tag.name.count.isMultiple(of: 2) ? 0.5 : -0.4))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("付箋を削除", role: .destructive) {
                store.deleteTag(tag)
            }
        }
    }
}

private extension Color {
    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", red, green, blue)
    }
}
