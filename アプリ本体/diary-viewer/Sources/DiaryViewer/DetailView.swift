import SwiftUI
import AVKit
import AVFoundation

// MARK: - Detail View

struct DetailView: View {
    let entry: Entry
    let imageResolver: ImageResolver?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 見出し
                Text(entry.displayDateTime)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 4)

                // メタ情報
                if entry.weather != nil || entry.location != nil {
                    HStack(spacing: 16) {
                        if let weather = entry.weather {
                            Label(weather, systemImage: "cloud.sun")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let loc = entry.location {
                            Label(loc, systemImage: "mappin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 8)
                }

                Divider()
                    .padding(.bottom, 4)

                // タグ
                if !entry.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.bottom, 8)
                }

                // 本文（インライン置換）
                bodyWithAttachments
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Body Rendering

    private var bodyWithAttachments: some View {
        // ★ entry.body ではなく entry.displayBody を使う。
        //   body は元ファイルそのままで `<!-- dayone-uuid: … -->` を含む（本人の言う「頭の変な文字」）。
        let segments = parseBodySegments(entry.displayBody)
        var views: [AnyView] = []

        for segment in segments {
            switch segment {
            case .text(let text):
                views.append(AnyView(
                    MarkdownText(text: text)
                ))
            case .attachment(let filename):
                if let resolver = imageResolver {
                    if resolver.isVideo(filename) {
                        views.append(AnyView(videoView(filename: filename, resolver: resolver)))
                    } else {
                        views.append(AnyView(imageView(filename: filename, resolver: resolver)))
                    }
                } else {
                    views.append(AnyView(
                        Text("（ファイルが見つかりません: \(filename)）")
                            .foregroundStyle(.secondary)
                            .italic()
                    ))
                }
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(views.enumerated()), id: \.offset) { _, view in
                view
            }
        }
    }

    private func imageView(filename: String, resolver: ImageResolver) -> some View {
        Group {
            if let url = resolver.resolve(filename),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 620, maxHeight: 620)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                    }
            } else {
                Text("（ファイルが見つかりません: \(filename)）")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    private func videoView(filename: String, resolver: ImageResolver) -> some View {
        Group {
            if let url = resolver.resolve(filename) {
                let player = AVPlayer(url: url)
                VideoPlayer(player: player)
                    .frame(maxWidth: 620, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    .onAppear {
                        player.play()
                    }
            } else {
                Text("（ファイルが見つかりません: \(filename)）")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: Body Segment Parsing

    enum BodySegment {
        case text(String)
        case attachment(String)
    }

    private func parseBodySegments(_ body: String) -> [BodySegment] {
        var segments: [BodySegment] = []
        // ![[...]] で分割
        // ![[...]] で分割
        // 簡易パーサ: 1行ずつ処理して `![[...]]` で分割
        var remaining = body
        while !remaining.isEmpty {
            if let range = remaining.range(of: #"!\[\[([^\]]+)\]\]"#, options: .regularExpression) {
                // マッチ前のテキスト
                let before = String(remaining[..<range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(before))
                }
                // 添付ファイル名
                let match = String(remaining[range])
                let filenameStart = match.index(match.startIndex, offsetBy: 3)
                let filenameEnd = match.index(match.endIndex, offsetBy: -2)
                let filename = String(match[filenameStart..<filenameEnd])
                segments.append(.attachment(filename))
                remaining = String(remaining[range.upperBound...])
            } else {
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(remaining))
                }
                break
            }
        }
        return segments
    }
}
