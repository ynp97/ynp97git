import Foundation
import SQLite3

actor ReadingDictionary {
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

    deinit {
        sqlite3_close(database)
    }

    func findBestReading(in recognizedTexts: [String]) throws -> ReadingResult? {
        var best: (result: ReadingResult, score: Int)?

        for (index, text) in recognizedTexts.enumerated() {
            guard let result = try findReading(in: text) else { continue }
            let ideographCount = result.expression.unicodeScalars.filter(
                \.properties.isIdeographic
            ).count
            let score = ideographCount * 100 + result.expression.count - index
            if best == nil || score > best!.score {
                best = (result, score)
            }
        }

        return best?.result
    }

    func findReading(in recognizedText: String) throws -> ReadingResult? {
        try openIfNeeded()

        let normalized = recognizedText
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        if let compound = compoundReading(for: normalized) {
            return compound
        }

        for candidate in candidates(from: normalized) {
            let readings = lookup(candidate)
            if !readings.isEmpty {
                return ReadingResult(
                    expression: candidate,
                    readings: readings,
                    meanings: lookupMeanings(candidate)
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
            return []
        }

        sqlite3_bind_text(statement, 1, expression, -1, SQLITE_TRANSIENT)
        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                results.append(String(cString: text))
            }
        }
        return results
    }

    private func compoundReading(for expression: String) -> ReadingResult? {
        let characters = Array(expression)
        guard characters.count >= 3,
              characters.count <= 16,
              characters.allSatisfy({
                  $0.unicodeScalars.contains(where: \.properties.isIdeographic)
              }) else {
            return nil
        }

        var memo: [Int: [String]?] = [:]

        func split(from index: Int) -> [String]? {
            if index == characters.count { return [] }
            if let cached = memo[index] { return cached }

            let remaining = characters.count - index
            for length in stride(from: remaining, through: 1, by: -1) {
                let part = String(characters[index..<(index + length)])
                guard let reading = lookup(part).first else { continue }
                if let suffix = split(from: index + length) {
                    let result = [reading] + suffix
                    memo[index] = result
                    return result
                }
            }

            memo[index] = nil
            return nil
        }

        guard let parts = split(from: 0), parts.count >= 2 else {
            return nil
        }

        return ReadingResult(
            expression: expression,
            readings: [parts.joined()],
            meanings: lookupMeanings(expression)
        )
    }

    private func lookupMeanings(_ expression: String) -> [String] {
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
            return []
        }

        sqlite3_bind_text(statement, 1, expression, -1, SQLITE_TRANSIENT)
        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                results.append(String(cString: text))
            }
        }
        return results
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
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
