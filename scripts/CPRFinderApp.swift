import SwiftUI
import AppKit

struct CPRVersion: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
}

struct CPRGroup: Identifiable, Hashable {
    let id: String
    let name: String
    var versions: [CPRVersion]
}

final class CPRLibrary: ObservableObject {
    @Published var groups: [CPRGroup] = []

    init() {
        reload()
    }

    func reload() {
        let indexPath = "/Users/yoshiakinagumo/Documents/Obsidian Vault/scripts/cubase_cpr_group_index.txt"
        guard let text = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return }

        var order: [String] = []
        var grouped: [String: [CPRVersion]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 3 else { continue }
            let groupName = parts[0]
            let fileName = parts[1]
            let filePath = parts.dropFirst(2).joined(separator: "|||")
            if grouped[groupName] == nil { order.append(groupName) }
            grouped[groupName, default: []].append(
                CPRVersion(id: filePath, name: fileName, path: filePath)
            )
        }
        groups = order.map { CPRGroup(id: $0, name: $0, versions: grouped[$0] ?? []) }
    }
}

struct ContentView: View {
    @StateObject private var library = CPRLibrary()
    @State private var searchText = ""
    @State private var selectedGroupID: String?
    @State private var selectedVersionID: String?
    @State private var diagnosticMessage = ""
    @State private var showingDiagnostic = false

    private var filteredGroups: [CPRGroup] {
        if searchText.isEmpty { return library.groups }
        return library.groups.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText) ||
            group.versions.contains {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.path.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var selectedGroup: CPRGroup? {
        library.groups.first { $0.id == selectedGroupID }
    }

    private var selectedVersion: CPRVersion? {
        selectedGroup?.versions.first { $0.id == selectedVersionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title2)
                Text("CPRを探す")
                    .font(.title2.bold())
                Spacer()
                TextField("名前やフォルダの一部で絞り込み", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                Button("更新") { library.reload() }
            }
            .padding(14)

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("作品・系列（\(filteredGroups.count)）")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    List(filteredGroups, selection: $selectedGroupID) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            if group.versions.count > 1 {
                                Text("\(group.versions.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(group.id)
                    }
                    .onChange(of: selectedGroupID) { _ in selectedVersionID = nil }
                }
                .frame(minWidth: 280, idealWidth: 360)

                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedGroup == nil ? "右側にバージョンが表示されます" : "バージョン")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    List(selectedGroup?.versions ?? [], selection: $selectedVersionID) { version in
                        Text(version.name).tag(version.id)
                    }
                    .onTapGesture(count: 2) {
                        if let version = selectedVersion { NSWorkspace.shared.open(URL(fileURLWithPath: version.path)) }
                    }
                }
                .frame(minWidth: 300, idealWidth: 420)
            }

            Divider()

            HStack {
                Text(selectedVersion?.name ?? "左から系列、右からバージョンを選んでください")
                    .foregroundStyle(selectedVersion == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Button("復旧点検") {
                    guard let version = selectedVersion else { return }
                    diagnosticMessage = diagnose(version)
                    showingDiagnostic = true
                }
                .disabled(selectedVersion == nil)
                Button("Finderで表示") {
                    guard let version = selectedVersion else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: version.path)])
                }
                .disabled(selectedVersion == nil)
                Button("Cubaseで開く") {
                    guard let version = selectedVersion else { return }
                    NSWorkspace.shared.open(URL(fileURLWithPath: version.path))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVersion == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert("CPR復旧点検", isPresented: $showingDiagnostic) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(diagnosticMessage)
        }
    }

    private func diagnose(_ version: CPRVersion) -> String {
        let manager = FileManager.default
        let url = URL(fileURLWithPath: version.path)
        let folder = url.deletingLastPathComponent()
        var lines: [String] = [version.name]

        if let attributes = try? manager.attributesOfItem(atPath: version.path),
           let bytes = attributes[.size] as? NSNumber {
            let size = ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file)
            if bytes.int64Value == 0 {
                lines.append("⚠️ 容量: 0バイト（破損の可能性が高い）")
            } else if bytes.int64Value < 1024 {
                lines.append("⚠️ 容量: \(size)（非常に小さい）")
            } else {
                lines.append("✓ 読み取り可能: \(size)")
            }
        } else {
            lines.append("⚠️ ファイルを読み取れません")
        }

        let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let cprCount = contents.filter { $0.pathExtension.lowercased() == "cpr" }.count
        let backups = contents.filter {
            let name = $0.lastPathComponent.lowercased()
            return name.hasSuffix(".bak") || name.contains("backup")
        }.count
        let hasAudio = ["Audio", "audio", "AUDIO"].contains {
            manager.fileExists(atPath: folder.appendingPathComponent($0).path)
        }

        lines.append("同じ場所のCPR: \(cprCount)件")
        lines.append("バックアップ候補: \(backups)件")
        lines.append("Audioフォルダ: \(hasAudio ? "あり" : "なし")")
        lines.append("")
        lines.append("この点検だけでは内部破損を断定できません。原本は変更していません。")
        return lines.joined(separator: "\n")
    }
}

@main
struct CPRFinderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
