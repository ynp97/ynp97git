import Foundation
#if canImport(DiaryCore)
import DiaryCore
#endif

// MARK: - Entry Model

struct Entry: Identifiable, Hashable {
    var id: UUID = UUID()
    let date: Date
    let time: String
    let weekday: String
    let weather: String?
    let location: String?
    let body: String
    let attachments: [String]
    let tags: [String]
    let year: Int
    var isCapture: Bool = false
    var isPlainText: Bool = false

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Entry, rhs: Entry) -> Bool {
        // 永続IDが同じでも日付・本文の訂正は別の表示値。IDだけで等値にすると
        // SwiftUIが詳細の再描画を省き、一覧と詳細の日付が食い違う。
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.time == rhs.time
            && lhs.weekday == rhs.weekday && lhs.weather == rhs.weather
            && lhs.location == rhs.location && lhs.body == rhs.body
            && lhs.attachments == rhs.attachments && lhs.tags == rhs.tags
            && lhs.year == rhs.year && lhs.isCapture == rhs.isCapture && lhs.isPlainText == rhs.isPlainText
    }
}

extension Entry {
    static func merge(journals: [Entry], captures: [Capture]) -> [Entry] {
        let ids = Set(journals.map(\.id))
        return journals + captures.filter { !$0.adopted && !ids.contains($0.id) }.compactMap(Entry.fromCapture)
    }



    /// HTMLコメント（`<!-- dayone-uuid: … -->` など）を落とした、表示用の本文。
    ///
    /// `body` は閲覧用パーサーの出力であり、原本そのままではない。
    /// 先頭コメントや空白を落とすため、保存時の原文復元に使わない。
    /// 保存用の生バイト保持はDiaryCore.OriginalJournalが担当する。
    /// **画面に出すときは必ずこちらを使う。**
    var displayBody: String {
        (isCapture || isPlainText) ? body : Entry.stripHTMLComments(body)
    }

    /// 日付が決まった受け箱原文の表示専用投影。年別Markdownへは書かない。
    /// 原文を日記パーサーへ通すと見出し・コメントが欠けるため、そのまま使う。
    static func fromCapture(_ capture: Capture) -> Entry? {
        guard let day = capture.journalDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let weekday = ["日", "月", "火", "水", "木", "金", "土"][calendar.component(.weekday, from: date) - 1]
        return Entry(id: capture.id, date: date, time: "", weekday: weekday,
                     weather: nil, location: nil, body: capture.text, attachments: [],
                     tags: JournalParser.extractTags(from: capture.text),
                     year: calendar.component(.year, from: date), isCapture: true)
    }

    static func stripHTMLComments(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<!--[\s\S]*?-->[ \t]*\n?"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 表示用の日時文字列
    var displayDateTime: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy年M月d日"
        return "\(df.string(from: date))（\(weekday)）\(time)"
    }

    /// 表示用の日付のみ
    var displayDateShort: String {
        let cal = Calendar(identifier: .gregorian)
        let dc = cal.dateComponents([.year, .month, .day], from: date)
        return "\(dc.month!).\(dc.day!)"
    }

    /// 冒頭のプレビュー文（最大3行）
    var preview: String {
        let lines = displayBody
            .replacingOccurrences(of: #"!\[\[.*?\]\]"#, with: "", options: .regularExpression)
            // 見出し記号・箇条書き記号は一覧では邪魔なので落とす
            .components(separatedBy: .newlines)
            .map { line -> String in
                line.replacingOccurrences(
                    of: #"^\s*(#{1,6}\s+|[-*+]\s+|>\s*)"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let previewLines = lines.prefix(3)
        if previewLines.isEmpty {
            return "（本文なし）"
        }
        return previewLines.joined(separator: "\n")
    }
}
