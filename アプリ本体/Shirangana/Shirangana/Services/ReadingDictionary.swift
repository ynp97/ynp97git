import Foundation
import SQLite3

actor ReadingDictionary {
    private struct SupplementalEntry {
        let readings: [String]
        let meanings: [String]
    }

    private static let supplementalEntries: [String: SupplementalEntry] = [
        "一部": SupplementalEntry(
            readings: ["いちぶ"],
            meanings: ["全体の中のある部分"]
        ),
        "部分": SupplementalEntry(
            readings: ["ぶぶん"],
            meanings: ["全体を構成する一つの範囲"]
        ),
        "一部分": SupplementalEntry(
            readings: ["いちぶぶん"],
            meanings: ["全体の中の一部"]
        ),
        "場合": SupplementalEntry(
            readings: ["ばあい"],
            meanings: ["ある状況や条件のもと"]
        ),
        "形": SupplementalEntry(
            readings: ["かたち", "けい"],
            meanings: ["物の外見やまとまり方"]
        ),
        "値": SupplementalEntry(
            readings: ["あたい", "ち"],
            meanings: ["数量や評価を表す数"]
        ),
        "御国": SupplementalEntry(
            readings: ["みくに", "おくに"],
            meanings: ["神の支配、または神の国を指す表現"]
        ),
        "御言葉": SupplementalEntry(
            readings: ["みことば"],
            meanings: ["神の言葉、聖書の言葉を指す表現"]
        ),
        "御心": SupplementalEntry(
            readings: ["みこころ"],
            meanings: ["神の思い、意志を指す表現"]
        ),
        "御霊": SupplementalEntry(
            readings: ["みたま"],
            meanings: ["神の霊、聖霊を指す表現"]
        ),
        "高群逸枝": SupplementalEntry(
            readings: ["たかむれいつえ"],
            meanings: ["日本の女性史研究者・詩人の名"]
        ),
        "学級": SupplementalEntry(
            readings: ["がっきゅう"],
            meanings: ["学校で児童・生徒をまとめた単位"]
        ),
        "新聞": SupplementalEntry(
            readings: ["しんぶん"],
            meanings: ["ニュースや記事を伝える印刷物、またはその媒体"]
        ),
        "学級新聞": SupplementalEntry(
            readings: ["がっきゅうしんぶん"],
            meanings: ["学級内で作る新聞"]
        ),
        "身長": SupplementalEntry(
            readings: ["しんちょう"],
            meanings: ["人や物の背の高さ"]
        ),
        "身体": SupplementalEntry(
            readings: ["しんたい", "からだ"],
            meanings: ["人や動物の体"]
        ),
        "身長と体": SupplementalEntry(
            readings: ["しんちょうとからだ"],
            meanings: ["背の高さと体"]
        ),
        "身長と身体": SupplementalEntry(
            readings: ["しんちょうとしんたい"],
            meanings: ["背の高さと体"]
        ),
        "受動分詞": SupplementalEntry(
            readings: ["じゅどうぶんし"],
            meanings: ["動作を受ける意味を表す分詞"]
        ),
        "強意語": SupplementalEntry(
            readings: ["きょういご"],
            meanings: ["意味を強める語"]
        ),
        "本文": SupplementalEntry(
            readings: ["ほんぶん", "ほんもん"],
            meanings: ["書かれたものの中心となる文章"]
        ),
        "引照個所": SupplementalEntry(
            readings: ["いんしょうかしょ"],
            meanings: ["参照する箇所"]
        ),
        "引照箇所": SupplementalEntry(
            readings: ["いんしょうかしょ"],
            meanings: ["参照する箇所"]
        ),
        "旧約聖書": SupplementalEntry(
            readings: ["きゅうやくせいしょ"],
            meanings: ["キリスト教聖書の旧約部分"]
        ),
        "差別表現以外": SupplementalEntry(
            readings: ["さべつひょうげんいがい"],
            meanings: ["差別的な表現ではないもの"]
        ),
        "池田亮司": SupplementalEntry(
            readings: ["いけだりょうじ"],
            meanings: ["日本の電子音楽家・現代美術家の名"]
        ),
        "池田": SupplementalEntry(
            readings: ["いけだ"],
            meanings: ["日本の姓"]
        ),
    ]

    private static let blockedExpressions: Set<String> = [
        "旧人",
        "受動分",
        "引照個",
        "約聖書",
    ]

    private static let ocrCorrections: [String: String] = [
        "受動分": "受動分詞",
        "引照個": "引照個所",
        "引照箇": "引照箇所",
        "旧日約聖書": "旧約聖書",
    ]

    enum DictionaryError: LocalizedError {
        case databaseMissing
        case databaseOpenFailed

        var errorDescription: String? {
            switch self {
            case .databaseMissing:
                "読み辞書が見つかりません。"
            case .databaseOpenFailed:
                "読み辞書を開けませんでした。"
            }
        }
    }

    private var database: OpaquePointer?

    private struct ReadingMatch {
        let result: ReadingResult
        let normalizedSource: String
        let isExactDictionaryHit: Bool
        let compoundPartLengths: [Int]

        var isCompound: Bool {
            !compoundPartLengths.isEmpty
        }

        var singleCharacterPartCount: Int {
            compoundPartLengths.filter { $0 == 1 }.count
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func findBestReading(in recognizedTexts: [String]) throws -> ReadingResult? {
        var best: (result: ReadingResult, score: Int)?

        for (index, text) in recognizedTexts.enumerated() {
            guard let match = try findMatch(in: text) else { continue }
            let result = match.result
            let ideographCount = result.expression.unicodeScalars.filter(
                \.properties.isIdeographic
            ).count
            let sourceLength = max(match.normalizedSource.count, 1)
            let matchedLength = result.expression.count
            let lengthGap = max(sourceLength - matchedLength, 0)
            let baseScore: Int
            if match.isExactDictionaryHit {
                // Full-length exact matches are the gold standard: the OCR string
                // was found verbatim in the dictionary. Give these the highest
                // base so they always beat speculative compounds.
                baseScore = matchedLength == sourceLength ? 12_000 : 8_500
            } else if match.isCompound {
                // Compounds are speculative decompositions of an OCR hypothesis
                // into known dictionary words. Even when every part is itself a
                // multi-character word, the combined text may be a hallucination.
                // Must never outscore any exact match.
                baseScore = match.singleCharacterPartCount == 0 ? 7_000 : 4_200
            } else {
                baseScore = 7_500
            }
            let score = baseScore
                + ideographCount * 90
                + matchedLength * 12
                - lengthGap * 120
                - match.singleCharacterPartCount * 240
                - index * 70
            if best == nil || score > best!.score {
                best = (result, score)
            }
        }

        return best?.result
    }

    func inspectCandidates(in recognizedTexts: [String]) throws -> [DictionaryCandidateDiagnostic] {
        try openIfNeeded()

        var diagnostics: [DictionaryCandidateDiagnostic] = []
        for text in recognizedTexts.prefix(24) {
            if let result = try findReading(in: text) {
                diagnostics.append(
                    DictionaryCandidateDiagnostic(
                        sourceText: text,
                        matchedExpression: result.expression,
                        readings: result.readings,
                        meanings: result.meanings
                    )
                )
            } else {
                diagnostics.append(
                    DictionaryCandidateDiagnostic(
                        sourceText: text,
                        matchedExpression: nil,
                        readings: [],
                        meanings: []
                    )
                )
            }
        }
        return diagnostics
    }

    func findReading(in recognizedText: String) throws -> ReadingResult? {
        try findMatch(in: recognizedText)?.result
    }

    private func findMatch(in recognizedText: String) throws -> ReadingMatch? {
        try openIfNeeded()

        // Vision frequently surrounds an otherwise correct word with Japanese
        // punctuation. Removing it here prevents a valid phrase such as
        // 「電子音楽」 from being reduced to the shorter dictionary word 「子音楽」.
        let normalized = String(recognizedText.unicodeScalars.filter {
            $0.properties.isIdeographic || Self.isKanaOrJapaneseMark($0)
        }.map(Character.init))

        guard !normalized.isEmpty else { return nil }

        let lookupText = Self.ocrCorrections[normalized] ?? normalized

        let normalizedIdeographCount = lookupText.unicodeScalars.filter(
            \.properties.isIdeographic
        ).count
        let exactReadings = lookup(lookupText)
        if !exactReadings.isEmpty {
            return ReadingMatch(
                result: ReadingResult(
                    expression: lookupText,
                    readings: exactReadings,
                    meanings: lookupMeanings(lookupText)
                ),
                normalizedSource: normalized,
                isExactDictionaryHit: true,
                compoundPartLengths: []
            )
        }

        if let compound = bestCompoundReading(in: lookupText) {
            return ReadingMatch(
                result: compound.result,
                normalizedSource: normalized,
                isExactDictionaryHit: false,
                compoundPartLengths: compound.partLengths
            )
        }

        for candidate in candidates(from: normalized) {
            if normalizedIdeographCount > 1 && candidate.count == 1 {
                continue
            }
            let readings = lookup(candidate)
            if !readings.isEmpty {
                return ReadingMatch(
                    result: ReadingResult(
                        expression: candidate,
                        readings: readings,
                        meanings: lookupMeanings(candidate)
                    ),
                    normalizedSource: normalized,
                    isExactDictionaryHit: true,
                    compoundPartLengths: []
                )
            }
        }
        return nil
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        guard let path = Bundle.main.path(forResource: "JMdict", ofType: "sqlite") else {
            throw DictionaryError.databaseMissing
        }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DictionaryError.databaseOpenFailed
        }
    }

    private func lookup(_ expression: String) -> [String] {
        guard !Self.blockedExpressions.contains(expression) else {
            return []
        }
        var results = Self.supplementalEntries[expression]?.readings ?? []
        let query = """
            SELECT reading
            FROM readings
            WHERE expression = ?
            ORDER BY is_common DESC, length(reading), reading
            LIMIT 4
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return results
        }

        sqlite3_bind_text(statement, 1, expression, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                let reading = String(cString: text)
                if !results.contains(reading) {
                    results.append(reading)
                }
            }
        }
        return Array(results.prefix(4))
    }

    private func bestCompoundReading(in text: String) -> (result: ReadingResult, partLengths: [Int])? {
        var best: (result: ReadingResult, partLengths: [Int], score: Int)?
        for candidate in candidates(from: text) {
            guard let compound = compoundReading(for: candidate) else { continue }
            let lengthGap = text.count - compound.result.expression.count
            let singleCharacterParts = compound.partLengths.filter { $0 == 1 }.count
            let score = compound.result.expression.count * 180
                - lengthGap * 180
                - singleCharacterParts * 520
                + (singleCharacterParts == 0 ? 1_100 : 0)

            if best == nil || score > best!.score {
                best = (
                    result: compound.result,
                    partLengths: compound.partLengths,
                    score: score
                )
            }
        }
        return best.map { (result: $0.result, partLengths: $0.partLengths) }
    }

    private func compoundReading(for expression: String) -> (result: ReadingResult, partLengths: [Int])? {
        let characters = Array(expression)
        guard characters.count >= 3,
              characters.count <= 16,
              characters.allSatisfy({
                  $0.unicodeScalars.contains(where: \.properties.isIdeographic)
              }) else {
            return nil
        }

        var memo: [Int: [(reading: String, length: Int)]?] = [:]

        func split(from index: Int) -> [(reading: String, length: Int)]? {
            if index == characters.count { return [] }
            if let cached = memo[index] { return cached }

            let remaining = characters.count - index
            for length in stride(from: remaining, through: 1, by: -1) {
                let part = String(characters[index..<(index + length)])
                guard let reading = lookup(part).first else { continue }
                if let suffix = split(from: index + length) {
                    let result = [(reading: reading, length: length)] + suffix
                    memo[index] = result
                    return result
                }
            }

            memo[index] = nil
            return nil
        }

        guard let parts = split(from: 0),
              parts.count >= 2,
              parts.contains(where: { $0.length > 1 }) else {
            return nil
        }

        return (
            ReadingResult(
                expression: expression,
                readings: [parts.map { $0.reading }.joined()],
                meanings: lookupMeanings(expression)
            ),
            parts.map { $0.length }
        )
    }

    private func lookupMeanings(_ expression: String) -> [String] {
        guard !Self.blockedExpressions.contains(expression) else {
            return []
        }
        var results = Self.supplementalEntries[expression]?.meanings ?? []
        let query = """
            SELECT definition
            FROM meanings
            WHERE expression = ?
            ORDER BY rank
            LIMIT 2
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return results
        }

        sqlite3_bind_text(statement, 1, expression, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                let meaning = String(cString: text)
                if !results.contains(meaning) {
                    results.append(meaning)
                }
            }
        }
        return Array(results.prefix(2))
    }

    private func candidates(from text: String) -> [String] {
        let characters = Array(text)
        let maximumLength = min(characters.count, 16)
        var values: [String] = []

        for length in stride(from: maximumLength, through: 1, by: -1) {
            for start in 0...(characters.count - length) {
                let candidate = String(characters[start..<(start + length)])
                if candidate.unicodeScalars.contains(where: \.properties.isIdeographic) {
                    values.append(candidate)
                }
            }
        }
        return values
    }

    private static func isKanaOrJapaneseMark(_ scalar: UnicodeScalar) -> Bool {
        (0x3040...0x30FF).contains(Int(scalar.value))
            || scalar.value == 0x3005
            || scalar.value == 0x3006
            || scalar.value == 0x3007
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
