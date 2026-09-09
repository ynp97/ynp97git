import Foundation

/// 貼付原文をMarkdownの可変長フェンスに収める。本文内の日付見出しや引用を
/// エントリ境界・天気と誤認しない。原文のUTF-8（CRLF、末尾空白も含む）を保持。
/// 日付のみの見出しを使い、分からない執筆時刻を作らない。
public struct PlainJournalRecord {
    public let id: UUID
    public let day: String
    public let text: String

    public init(id: UUID, day: String, text: String) {
        self.id = id; self.day = day; self.text = text
    }

    public func encoded() throws -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else {
            throw DiaryError.invalid("保存する日付が不正です。")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = ["日", "月", "火", "水", "木", "金", "土"][calendar.component(.weekday, from: date) - 1]
        var longest = 0, run = 0
        for byte in text.utf8 {
            run = byte == 96 ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return Data(("## \(day)（\(weekday)）\n<!-- diary-entry-id: \(id.uuidString) -->\n<!-- diary-plain-text: 1 -->\n\(fence)text\n" + text + "\n\(fence)\n\n").utf8)
    }

    public static func decode(_ data: Data) throws -> PlainJournalRecord? {
        guard String(data: data, encoding: .utf8) != nil else { throw DiaryError.invalid("原文がUTF-8ではありません。") }
        // Characterによる改行分割はCRLFを変えるため、生バイトのLFだけでヘッダを読む。
        let bytes = Array(data)
        var cursor = 0
        func line() -> String {
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 10 { cursor += 1 }
            let value = String(decoding: bytes[start..<cursor], as: UTF8.self)
            if cursor < bytes.count { cursor += 1 }
            return value
        }
        let heading = line(), identity = line(), marker = line()
        guard marker == "<!-- diary-plain-text: 1 -->" else { return nil }
        let opening = line()
        let idPrefix = "<!-- diary-entry-id: "
        guard identity.hasPrefix(idPrefix), identity.hasSuffix(" -->"),
              let id = UUID(uuidString: String(identity.dropFirst(idPrefix.count).dropLast(4))),
              heading.range(of: #"^## \d{4}-\d{2}-\d{2}（[月火水木金土日]）$"#, options: .regularExpression) != nil,
              opening.hasSuffix("text") else { throw DiaryError.invalid("保存済み日記の形式が不正です。") }
        let fence = String(opening.dropLast(4))
        guard fence.count >= 3, fence.allSatisfy({ $0 == "`" }) else { throw DiaryError.invalid("原文の囲みが不正です。") }
        let ending = Data("\n\(fence)\n\n".utf8)
        guard data.count >= cursor + ending.count, data.suffix(ending.count) == ending else {
            throw DiaryError.invalid("原文の末尾を確認できません。")
        }
        let text = String(decoding: data[cursor..<(data.count - ending.count)], as: UTF8.self)
        return PlainJournalRecord(id: id, day: String(heading.dropFirst(3).prefix(10)), text: text)
    }
}
