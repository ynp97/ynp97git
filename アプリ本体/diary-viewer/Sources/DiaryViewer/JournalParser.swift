import Foundation

// MARK: - Journal Parser

/// 日記ファイル（Markdown）をパースする
struct JournalParser {

    struct ParseResult {
        let entries: [Entry]
        let entryCountFromFrontmatter: Int?
    }

    /// 1ファイルをパースし、エントリ一覧を返す
    static func parse(fileContent: String, year: Int) -> ParseResult {
        let lines = fileContent.components(separatedBy: .newlines)
        var bodyLines: [String] = []
        var inFrontmatter = false
        var frontmatterLines: [String] = []
        var seenFirstEntry = false  // 最初のエントリ見出しより前は無視

        // frontmatterとヘッダ行を除去した「純粋な全行」を作る
        for (index, line) in lines.enumerated() {
            // Bug 2 fix: frontmatter only if first line is exactly "---"
            if index == 0 {
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    inFrontmatter = true
                    continue
                }
                // No frontmatter; skip header area and go to body
            }

            if inFrontmatter {
                if line.trimmingCharacters(in: .whitespaces) == "---" && index > 0 {
                    inFrontmatter = false
                    // Frontmatter closed; next lines are header/body
                } else {
                    frontmatterLines.append(line)
                }
                continue
            }

            // Bug 4 fix: 最初のエントリ見出し（## YYYY-MM-DD）より前は全部無視
            if !seenFirstEntry {
                if isEntryStart(line) {
                    seenFirstEntry = true
                    bodyLines.append(line)
                }
                // else: # 見出し、空行、[[目次]]など→読み飛ばし
                continue
            }

            bodyLines.append(line)
        }

        // frontmatterからentries数を取得
        let entryCountFromFrontmatter = parseFrontmatterEntryCount(frontmatterLines)

        // エントリに分割
        let entries = parseEntries(from: bodyLines, year: year)

        return ParseResult(
            entries: entries,
            entryCountFromFrontmatter: entryCountFromFrontmatter
        )
    }

    // MARK: - Validation

    /// frontmatterのentries数と実際のエントリ数を比較。不一致なら警告を出力
    static func validateEntryCount(result: ParseResult) {
        guard let expected = result.entryCountFromFrontmatter else {
            print("[警告] frontmatterにentries: がありません。件数検証をスキップします。")
            return
        }
        let actual = result.entries.count
        if expected != actual {
            print("[警告] entry数が一致しません。frontmatter: \(expected), 実際: \(actual)")
        } else {
            print("[OK] entry数一致: \(actual)")
        }
    }

    // MARK: - Private

    private static func parseFrontmatterEntryCount(_ lines: [String]) -> Int? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("entries:") {
                let value = trimmed.dropFirst("entries:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    private static func parseEntries(from lines: [String], year: Int) -> [Entry] {
        // エントリ境界で分割
        var entryBlocks: [[String]] = []
        var currentBlock: [String] = []
        var foundFirstEntry = false

        for line in lines {
            if isEntryStart(line) {
                if foundFirstEntry {
                    if !currentBlock.isEmpty {
                        entryBlocks.append(currentBlock)
                    }
                }
                foundFirstEntry = true
                currentBlock = [line]
            } else if foundFirstEntry {
                currentBlock.append(line)
            }
        }
        // 最後のブロック
        if !currentBlock.isEmpty {
            entryBlocks.append(currentBlock)
        }

        // 各ブロックをパース
        return entryBlocks.compactMap { block in
            parseEntryBlock(block, year: year)
        }
    }

    /// `## ` で始まり、日付フォーマットに合致する行がエントリ開始
    private static func isEntryStart(_ line: String) -> Bool {
        // Bug 1 fix: 日付形式まで確認する
        guard line.hasPrefix("## ") else { return false }
        // 「###」は冗長なので削除
        let range = NSRange(line.startIndex..., in: line)
        return entryHeadingPattern.firstMatch(in: line, range: range) != nil
    }

    /// エントリ見出しのパース
    /// 形式: `## YYYY-MM-DD（曜）H:MM:SS`
    /// 時刻のHは1桁または2桁
    private static let entryHeadingPattern = try! NSRegularExpression(
        pattern: "^## (\\d{4})-(\\d{2})-(\\d{2})（([月火水木金土日])）(\\d{1,2}):(\\d{2}):(\\d{2})"
    )

    /// 引用行（メタ情報）のパース
    /// 形式: `> 🌤 …｜📍…`
    /// または `> （何らかの天気情報）｜（何らかの場所情報）`
    private static let metadataLinePattern = try! NSRegularExpression(
        pattern: "^>\\s*(.*?)(?:｜[\\s]*(.*))?$"
    )

    /// 1ブロックのエントリをパース
    private static func parseEntryBlock(_ block: [String], year: Int) -> Entry? {
        guard !block.isEmpty else { return nil }

        let headingLine = block[0]
        guard let headingMatch = entryHeadingPattern.firstMatch(
            in: headingLine,
            range: NSRange(headingLine.startIndex..., in: headingLine)
        ) else {
            print("[パース警告] エントリ見出しの形式が異常です: \(headingLine.prefix(40))")
            return nil
        }

        let yStr = (headingLine as NSString).substring(with: headingMatch.range(at: 1))
        let mStr = (headingLine as NSString).substring(with: headingMatch.range(at: 2))
        let dStr = (headingLine as NSString).substring(with: headingMatch.range(at: 3))
        let weekday = (headingLine as NSString).substring(with: headingMatch.range(at: 4))
        let hStr = (headingLine as NSString).substring(with: headingMatch.range(at: 5))
        let minStr = (headingLine as NSString).substring(with: headingMatch.range(at: 6))
        let secStr = (headingLine as NSString).substring(with: headingMatch.range(at: 7))
        let timeStr = "\(hStr):\(minStr):\(secStr)"

        // Date の構築
        let calendar = Calendar(identifier: .gregorian)
        var dateComponents = DateComponents()
        dateComponents.year = Int(yStr) ?? year
        dateComponents.month = Int(mStr) ?? 1
        dateComponents.day = Int(dStr) ?? 1
        dateComponents.hour = Int(hStr) ?? 0
        dateComponents.minute = Int(minStr) ?? 0
        dateComponents.second = Int(secStr) ?? 0
        let date = calendar.date(from: dateComponents) ?? Date()

        // 残りの行を処理
        var weather: String? = nil
        var location: String? = nil
        var bodyStartIndex = 1

        // 空行と HTMLコメント行（<!-- dayone-uuid: … -->）をスキップしてメタ情報行を探す
        //
        // ★踏んではいけない地雷（2026-07-31 Claude確認）
        // 実データでは見出しの直後に `<!-- dayone-uuid: … -->` が入る形が189件ある。
        // 以前はコメント行を見た時点で break していたため、その189件では
        //   ・天気と場所が取れない
        //   ・`> 🌤 …｜📍 …` 行が本文の先頭に残る
        //   ・uuidコメントが一覧のプレビューに出る（本人の言う「頭の変な文字」）
        // という3つが同時に起きていた。コメント行の読み飛ばしを消さないこと。
        var i = 1
        while i < block.count {
            let candidate = block[i].trimmingCharacters(in: .whitespaces)
            if candidate.isEmpty {
                i += 1
                continue
            }
            if isHTMLCommentLine(candidate) {
                i += 1
                bodyStartIndex = i   // コメント行は本文に含めない
                continue
            }
            if candidate.hasPrefix(">") {
                // メタ情報行
                (weather, location) = parseMetadataLine(block[i])
                bodyStartIndex = i + 1
            }
            break  // 最初の（コメントでも空行でもない）行が `>` でなければそれ以上探さない
        }

        // 本文を結合（見出しとメタ情報を除いた行）
        let bodyLines = Array(block[bodyStartIndex...])
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // 添付ファイルを抽出
        let attachments = extractAttachments(from: body)

        // タグを抽出
        let tags = extractTags(from: body)

        return Entry(
            date: date,
            time: timeStr,
            weekday: weekday,
            weather: weather,
            location: location,
            body: body,
            attachments: attachments,
            tags: tags,
            year: year
        )
    }

    /// その行が HTMLコメントだけの行か（`<!-- … -->`）
    private static func isHTMLCommentLine(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("<!--") && trimmedLine.hasSuffix("-->")
    }

    /// 引用行から天気と場所を抽出
    /// 想定形式: `> 🌤 1°C ほぼ快晴 ｜ 📍 学研教室, 八千代市, 千葉県, 日本`
    /// 実際は `>` で始まる行全体。`｜` の左が天気情報、右が場所情報。
    private static func parseMetadataLine(_ line: String) -> (String?, String?) {
        // `｜` または `|` で分割
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return (nil, nil) }

        let afterGT = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)

        // 区切り文字を探す: 全角｜ or 半角| のどちらか
        let separators: [Character] = ["｜", "|"]
        var weatherPart: String = afterGT
        var locationPart: String? = nil

        for sep in separators {
            if let idx = afterGT.firstIndex(of: sep) {
                weatherPart = String(afterGT[..<idx]).trimmingCharacters(in: .whitespaces)
                locationPart = String(afterGT[afterGT.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        let weather: String? = weatherPart.isEmpty ? nil : weatherPart
        let location: String? = locationPart?.isEmpty == true ? nil : locationPart

        return (weather, location)
    }

    /// 本文から `![[ファイル名]]` を抽出
    private static let attachmentPattern = try! NSRegularExpression(
        pattern: #"!\[\[([^\]]+)\]\]"#
    )

    private static func extractAttachments(from body: String) -> [String] {
        let nsBody = body as NSString
        let matches = attachmentPattern.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        return matches.map { nsBody.substring(with: $0.range(at: 1)) }
    }

    /// 本文から `#タグ` を抽出
    ///
    /// - タグ名に使える文字は 日本語などの文字・数字・アンダースコア・ハイフン だけ。
    /// - Markdownの見出し `# 見出し` は `#` の直後が空白なので、この式には一致しない。
    /// - `## …` も `#` の直後が `#` なので一致しない。
    /// - URL中の `…#fragment` は直前が空白でないので一致しない。
    ///
    /// ★2026-07-31修正: もとは先頭に `(?<!\A|^)` が付いていて、
    /// 本文の1行目・行頭に置かれたタグが検出できなかった。これを外し、
    /// 代わりに `.anchorsMatchLines` で `^` を各行頭に効かせている。
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"(?:^|\s)#([\p{L}\p{N}_\-]+)"#,
        options: [.anchorsMatchLines]
    )

    private static func extractTags(from body: String) -> [String] {
        let nsBody = body as NSString
        let matches = tagPattern.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        var tags: [String] = []
        for match in matches {
            let tag = nsBody.substring(with: match.range(at: 1))
            if !tag.isEmpty {
                tags.append("#\(tag)")
            }
        }
        // 重複除去、出現順を保持
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}
