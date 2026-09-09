import SwiftUI

// MARK: - Markdown Text

/// 日記本文のMarkdownを描画する（行ベースの簡易レンダラ）。
///
/// なぜ行ベースか:
/// 日記の本文は「1行 = 1つのまとまり」で書かれていて、改行がそのまま意味を持つ。
/// 一般的なMarkdownの規則どおりに段落を連結すると、13年分の見た目が全部変わってしまう。
/// そこで **ブロック要素（見出し・箇条書き・引用・区切り線・コード）だけを行単位で解釈し、
/// 行内の装飾（太字・斜体・コード・リンク）は AttributedString に任せる**。
///
/// 対応する記法:
/// - `# ` 〜 `###### ` 見出し
/// - `- ` `* ` `+ ` 箇条書き
/// - `1. ` 番号付き
/// - `> ` 引用
/// - `---` `***` `___` 区切り線
/// - ``` で囲まれたコードブロック
/// - 行内: `**太字**` `*斜体*` `` `コード` `` `[表示](URL)`
/// - `#タグ` はアクセント色で強調する
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.blocks(from: text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Blocks

    enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case numbered(marker: String, text: String)
        case quote(text: String)
        case divider
        case code(text: String)
        case paragraph(text: String)
        case blank
    }

    static func blocks(from text: String) -> [Block] {
        var result: [Block] = []
        let lines = text.components(separatedBy: .newlines)

        var codeBuffer: [String] = []
        var inCode = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // コードブロックの開始・終了
            if trimmed.hasPrefix("```") {
                if inCode {
                    result.append(.code(text: codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(rawLine)
                continue
            }

            // 空行
            if trimmed.isEmpty {
                result.append(.blank)
                continue
            }

            // 区切り線
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.divider)
                continue
            }

            // 見出し（`#` の直後に空白があるものだけ。`#タグ` は見出しにしない）
            if let match = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = trimmed[trimmed.startIndex...].prefix(while: { $0 == "#" }).count
                let content = String(trimmed[match.upperBound...])
                result.append(.heading(level: level, text: content))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                result.append(.quote(text: content))
                continue
            }

            // 箇条書き
            if let match = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                result.append(.bullet(text: String(trimmed[match.upperBound...])))
                continue
            }

            // 番号付き
            if let match = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                let marker = String(trimmed[trimmed.startIndex..<match.upperBound])
                    .trimmingCharacters(in: .whitespaces)
                result.append(.numbered(marker: marker, text: String(trimmed[match.upperBound...])))
                continue
            }

            result.append(.paragraph(text: rawLine))
        }

        // 閉じ忘れたコードブロックも捨てない
        if inCode && !codeBuffer.isEmpty {
            result.append(.code(text: codeBuffer.joined(separator: "\n")))
        }

        return result
    }

    // MARK: Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(Self.headingFont(level))
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 14 : 10)
                .padding(.bottom, 4)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("・")
                    .foregroundStyle(.secondary)
                Text(Self.inline(text))
                    .lineSpacing(Self.lineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.vertical, 1)

        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Self.inline(text))
                    .lineSpacing(Self.lineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.vertical, 1)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                Text(Self.inline(text))
                    .lineSpacing(Self.lineSpacing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)

        case .divider:
            Divider()
                .padding(.vertical, 10)

        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.10))
                )
                .padding(.vertical, 6)

        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.body)
                .lineSpacing(Self.lineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)

        case .blank:
            Spacer().frame(height: 10)
        }
    }

    static let lineSpacing: CGFloat = 7

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .body
        }
    }

    // MARK: Inline

    /// 行内のMarkdownを解釈し、`#タグ` に色を付ける
    static func inline(_ source: String) -> AttributedString {
        var attributed: AttributedString
        if let parsed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            attributed = parsed
        } else {
            attributed = AttributedString(source)
        }

        highlightTags(in: &attributed)
        return attributed
    }

    private static let tagHighlightPattern = try! NSRegularExpression(
        pattern: #"(?:^|\s)(#[\p{L}\p{N}_\-]+)"#,
        options: [.anchorsMatchLines]
    )

    private static func highlightTags(in attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        let ns = plain as NSString
        let matches = tagHighlightPattern.matches(
            in: plain,
            range: NSRange(location: 0, length: ns.length)
        )
        // 長いタグから先に色を付ける。
        // 先に短い方を塗ると、`#音楽` が `#音楽制作` の前半に当たってしまうため。
        let tagTexts = Set(matches.map { ns.substring(with: $0.range(at: 1)) })
            .sorted { $0.count > $1.count }

        for tagText in tagTexts {
            if let range = attributed.range(of: tagText) {
                attributed[range].foregroundColor = .accentColor
            }
        }
    }
}
