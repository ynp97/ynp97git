import Foundation

// MARK: - Entry Model

struct Entry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let time: String
    let weekday: String
    let weather: String?
    let location: String?
    let body: String
    let attachments: [String]
    let tags: [String]
    let year: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Entry, rhs: Entry) -> Bool {
        lhs.id == rhs.id
    }
}

extension Entry {

    /// HTMLコメント（`<!-- dayone-uuid: … -->` など）を落とした、表示用の本文。
    ///
    /// `body` は元ファイルの文字列をそのまま保持する（フェーズ3の編集で書き戻すときに
    /// uuidを失わないため）。**画面に出すときは必ずこちらを使う。**
    var displayBody: String {
        Entry.stripHTMLComments(body)
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
