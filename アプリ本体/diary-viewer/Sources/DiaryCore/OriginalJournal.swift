import Foundation
import CryptoKit

public enum DiaryError: LocalizedError {
    case invalid(String)
    case conflict
    case storage(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .conflict: return "保存後に内容が変わっています。上書きせず、読み込み直してください。"
        case .storage(let reason): return "保存処理を完了できませんでした: \(reason)"
        }
    }
}

public func contentHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// 閲覧用Entryから再構成しない。コメント・空白・改行を含む生バイトを保持する。
/// ここでの差替えはメモリ内だけ。既存ファイルへ保存するAPIはまだ公開しない。
public struct OriginalJournal {
    public struct Block {
        public let range: Range<Int>
        public let data: Data
        public let explicitID: UUID?
    }
    public let data: Data
    public let blocks: [Block]
    public let expectedCount: Int?

    public init(data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw DiaryError.invalid("日記がUTF-8ではありません。原本を変更しません。")
        }
        self.data = data
        let bytes = Array(data)
        var offset = 0
        var starts: [Int] = []
        var count: Int?
        var inFrontmatter = false
        var fence: (Character, Int)?
        let heading = try NSRegularExpression(pattern: #"^## \d{4}-\d{2}-\d{2}（[月火水木金土日]）(?:\d{1,2}:\d{2}:\d{2})?\s*$"#)
        while offset < bytes.count {
            let start = offset
            while offset < bytes.count && bytes[offset] != 10 { offset += 1 }
            let end = offset
            if offset < bytes.count { offset += 1 }
            var line = String(decoding: bytes[start..<end], as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if start == 0 && trimmed == "---" { inFrontmatter = true; continue }
            if inFrontmatter {
                if trimmed == "---" { inFrontmatter = false }
                else if trimmed.hasPrefix("entries:") {
                    guard count == nil, let value = Int(trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)), value >= 0 else {
                        throw DiaryError.invalid("entriesの形式が不明です。原本を変更しません。")
                    }
                    count = value
                }
                continue
            }
            // コードブロック内の例示日付をエントリ境界と誤認しない。
            if let current = fence {
                if trimmed.prefix(while: { $0 == current.0 }).count >= current.1,
                   trimmed.drop(while: { $0 == current.0 }).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                continue
            }
            if let first = trimmed.first, first == "`" || first == "~" {
                let length = trimmed.prefix(while: { $0 == first }).count
                if length >= 3 { fence = (first, length); continue }
            }
            if heading.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil { starts.append(start) }
        }
        guard !inFrontmatter else { throw DiaryError.invalid("frontmatterが閉じていません。") }
        expectedCount = count
        var result: [Block] = []
        var ids = Set<UUID>()
        for (index, start) in starts.enumerated() {
            let range = start..<(index + 1 < starts.count ? starts[index + 1] : bytes.count)
            let original = data.subdata(in: range)
            let lines = String(decoding: original, as: UTF8.self).components(separatedBy: .newlines)
            var id: UUID?
            // IDは見出し直後の空行・コメント領域だけから読む。本文の例示コードは対象外。
            for line in lines.dropFirst() {
                let value = line.trimmingCharacters(in: .whitespaces)
                if value.isEmpty { continue }
                guard value.hasPrefix("<!--"), value.hasSuffix("-->") else { break }
                if value.hasPrefix("<!-- diary-entry-id:") {
                    let raw = value.dropFirst("<!-- diary-entry-id:".count).dropLast(3).trimmingCharacters(in: .whitespaces)
                    guard id == nil, let parsed = UUID(uuidString: raw), ids.insert(parsed).inserted else {
                        throw DiaryError.invalid("日記IDが重複または不正です。")
                    }
                    id = parsed
                }
            }
            result.append(Block(range: range, data: original, explicitID: id))
        }
        blocks = result
    }

    public func validateForWriting() throws {
        guard let count = expectedCount, count == blocks.count else {
            throw DiaryError.invalid("日記の件数が一致しないため、書き込めません。")
        }
    }

    /// 先頭に追加すれば既存の最終行が改行なしでも、そのブロックを変更しない。
    /// 件数の数字以外のfrontmatterと、既存ブロック全てをバイト比較する。
    public func prepending(_ block: Data) throws -> Data {
        try validateForWriting()
        let boundary = blocks.first?.range.lowerBound ?? data.count
        let prefix = String(decoding: data.prefix(boundary), as: UTF8.self)
        let pattern = try NSRegularExpression(pattern: #"(?m)^(\s*entries:[ \t]*)([0-9]+)([ \t]*\r?)$"#)
        let matches = pattern.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix))
        guard matches.count == 1, let range = Range(matches[0].range(at: 2), in: prefix) else {
            throw DiaryError.invalid("件数欄を一意に更新できません。")
        }
        var header = prefix
        header.replaceSubrange(range, with: String(blocks.count + 1))
        if !header.hasSuffix("\n") { header += "\n" }
        var output = Data(header.utf8)
        output.append(block)
        output.append(data.dropFirst(boundary))
        let next = try OriginalJournal(data: output)
        try next.validateForWriting()
        guard next.blocks.count == blocks.count + 1,
              next.blocks.first?.data == block,
              zip(next.blocks.dropFirst(), blocks).allSatisfy({ $0.data == $1.data }) else {
            throw DiaryError.invalid("別の日記に変更が及ぶため保存しません。")
        }
        return output
    }

    public func replacingBlock(at index: Int, with replacement: Data, expectedHash: String) throws -> Data {
        try validateForWriting()
        guard contentHash(data) == expectedHash else { throw DiaryError.conflict }
        guard blocks.indices.contains(index) else { throw DiaryError.invalid("対象の日記がありません。") }
        var output = data
        output.replaceSubrange(blocks[index].range, with: replacement)
        let next = try OriginalJournal(data: output)
        try next.validateForWriting()
        guard next.blocks.count == blocks.count else { throw DiaryError.invalid("日記の件数が変わる編集です。") }
        if let id = blocks[index].explicitID, next.blocks[index].explicitID != id {
            throw DiaryError.invalid("日記のIDを変更する編集は保存しません。")
        }
        for other in blocks.indices where other != index {
            guard blocks[other].data == next.blocks[other].data else { throw DiaryError.invalid("別の日記に変更が及ぶため保存しません。") }
        }
        return output
    }
}
