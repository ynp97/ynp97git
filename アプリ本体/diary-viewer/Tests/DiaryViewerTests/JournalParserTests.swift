import XCTest
@testable import DiaryViewer

final class JournalParserTests: XCTestCase {

    // MARK: - Basic Parsing

    func testParseBasicEntry() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-01-06（火）6:45:26

        > 🌤 1°C ほぼ快晴 ｜ 📍 学研教室, 八千代市, 千葉県, 日本

        こんにちは。今日はいい天気。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.year, 2026)
        XCTAssertEqual(entry.weekday, "火")
        XCTAssertEqual(entry.time, "6:45:26")
        XCTAssertEqual(entry.weather, "🌤 1°C ほぼ快晴")
        XCTAssertEqual(entry.location, "📍 学研教室, 八千代市, 千葉県, 日本")
        XCTAssertTrue(entry.body.contains("こんにちは"))
    }

    func testParseZeroPaddedTime() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2025
        entries: 1
        ---

        # Test

        ## 2025-03-03（月）14:14:27

        テスト本文
        """
        let result = JournalParser.parse(fileContent: content, year: 2025)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.time, "14:14:27")
        XCTAssertEqual(entry.weekday, "月")
    }

    func testParseEntryWithoutMetadata() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-04-01（水）10:30:00

        引用行がないエントリ。これだけで成立する。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertNil(entry.weather)
        XCTAssertNil(entry.location)
        XCTAssertTrue(entry.body.contains("引用行がない"))
    }

    // MARK: - Attachments

    func testParseAttachments() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2024
        entries: 1
        ---

        # Test

        ## 2024-02-03（土）7:30:15

        本文です。

        ![[snowman_2024.png]]

        写真の後にも文章。
        """
        let result = JournalParser.parse(fileContent: content, year: 2024)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.attachments, ["snowman_2024.png"])
        // 本文中に添付の記法が含まれていることを確認
        XCTAssertTrue(entry.body.contains("![[snowman_2024.png]]"))
    }

    func testParseMultipleAttachments() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2024
        entries: 1
        ---

        # Test

        ## 2024-03-20（水）6:45:26

        最初の文。

        ![[plum_blossom_2024.png]]

        間の文。

        ![[castle_wall_2024.png]]

        最後の文。
        """
        let result = JournalParser.parse(fileContent: content, year: 2024)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.attachments, ["plum_blossom_2024.png", "castle_wall_2024.png"])
    }

    // MARK: - Tags

    func testParseTags() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2024
        entries: 1
        ---

        # Test

        ## 2024-01-05（金）14:30:00

        今日はいい日だった。 #カフェ #日常
        さらに #買い物 もした。
        """
        let result = JournalParser.parse(fileContent: content, year: 2024)
        let entry = result.entries[0]
        XCTAssertTrue(entry.tags.contains("#カフェ"))
        XCTAssertTrue(entry.tags.contains("#日常"))
        XCTAssertTrue(entry.tags.contains("#買い物"))
    }

    // MARK: - Multiple entries on same day

    func testSameDayMultipleEntries() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2025
        entries: 2
        ---

        # Test

        ## 2025-05-15（木）18:00:00

        昼のエントリ。

        ## 2025-05-15（木）21:30:00

        夜のエントリ。
        """
        let result = JournalParser.parse(fileContent: content, year: 2025)
        XCTAssertEqual(result.entries.count, 2)
        // 時系列順
        if result.entries.count == 2 {
            // 時間順はファイル内の出現順のまま
            XCTAssertTrue(result.entries[0].body.contains("昼"))
            XCTAssertTrue(result.entries[1].body.contains("夜"))
        }
    }

    // MARK: - Entry Count Validation

    func testEntryCountValidation() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 3
        ---

        # Test

        ## 2026-01-01（木）10:00:00

        1つ目。

        ## 2026-01-02（金）10:00:00

        2つ目。

        ## 2026-01-03（土）10:00:00

        3つ目。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entryCountFromFrontmatter, 3)
        // 検算
        JournalParser.validateEntryCount(result: result)
    }

    func testEntryCountMismatch() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 5
        ---

        # Test

        ## 2026-01-01（木）10:00:00

        1つ目。

        ## 2026-01-02（金）10:00:00

        2つ目。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entryCountFromFrontmatter, 5)
        // Should output a warning but not crash
        JournalParser.validateEntryCount(result: result)
    }

    // MARK: - Fixtures Integration

    func testFixture2024() throws {
        let url = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/journal/2024.md"))
        let content = try String(contentsOf: url, encoding: .utf8)
        let result = JournalParser.parse(fileContent: content, year: 2024)
        XCTAssertEqual(result.entries.count, 15)
        JournalParser.validateEntryCount(result: result)
    }

    func testFixture2025() throws {
        let url = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/journal/2025.md"))
        let content = try String(contentsOf: url, encoding: .utf8)
        let result = JournalParser.parse(fileContent: content, year: 2025)
        XCTAssertEqual(result.entries.count, 13)
        JournalParser.validateEntryCount(result: result)
    }

    func testFixture2026() throws {
        let url = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/journal/2026.md"))
        let content = try String(contentsOf: url, encoding: .utf8)
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 12)
        JournalParser.validateEntryCount(result: result)
    }

    // MARK: - Edge Cases

    func testEmptyFile() throws {
        let content = ""
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 0)
        JournalParser.validateEntryCount(result: result)
    }

    func testOnlyFrontmatter() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 0
        ---
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 0)
    }

    func testNonDateHeadingInBody() throws {
        // Bug 1 fix: `## ` 非日付見出しは本文として扱われ、エントリを壊さない
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-01-06（火）10:00:00

        これは有効なエントリの本文です。

        ## 今日のまとめ

        ここは上のエントリの本文の続き。
        ---
        さらに別の行。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1, "非日付##見出しでエントリが分割されないこと")
        let entry = result.entries[0]
        XCTAssertTrue(entry.body.contains("今日のまとめ"), "非日付見出しが本文に含まれること")
        XCTAssertTrue(entry.body.contains("さらに別の行"), "## 以降の本文も含まれること")
        XCTAssertTrue(entry.body.contains("---"), "body内の---も含まれること")
    }

    func testMalformedHeading() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 0
        ---

        # Test

        ## 不正な見出し

        これはエントリとして認識されない。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 0)
    }

    func testDashDashDashInBody() throws {
        // Bug 2 fix: 本文中の --- で以降が消えない
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-01-06（火）10:00:00

        最初の行。

        ---

        区切りの後も本文に含まれる。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertTrue(entry.body.contains("最初の行"))
        XCTAssertTrue(entry.body.contains("---"), "---が本文に含まれること")
        XCTAssertTrue(entry.body.contains("区切りの後"), "---以降も本文として保持されること")
    }

    func testTagWithPunctuation() throws {
        // Bug 3 fix: 句読点付きタグは記号を除去
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-01-06（火）10:00:00

        今日は映画を見た #映画。そのあと買い物 #買い物、疲れた。 #散歩…
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        let entry = result.entries[0]
        XCTAssertTrue(entry.tags.contains("#映画"), "句点が除去されたタグ")
        XCTAssertTrue(entry.tags.contains("#買い物"), "読点が除去されたタグ")
        XCTAssertTrue(entry.tags.contains("#散歩"), "三点リーダが除去されたタグ")
        XCTAssertEqual(entry.tags.count, 3, "句読点除去後のタグ数が正しい")
    }

    func testFrontmatterWithoutEntries() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        ---

        # Test

        ## 2026-01-01（木）10:00:00

        エントリ
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertNil(result.entryCountFromFrontmatter)
    }

    // MARK: - 2026-07-31 修正分

    /// ①実データ形式: 見出し → `<!-- dayone-uuid: … -->` → `> 天気｜場所` → 本文
    ///
    /// 修正前はコメント行を見た時点で打ち切っていたため、
    /// 天気・場所が nil になり、`>` 行が本文の先頭に残っていた。
    func testUUIDCommentBeforeMetadataLine() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2020
        entries: 1
        ---

        # Test

        ## 2020-02-14（金）13:43:58

        <!-- dayone-uuid: 638B52D58BE34E48B611CC5E24A6B0A1 | journal: ジャーナル -->

        > 🌤 8°C 所により霧 ｜ 📍 八千代台北5丁目8-16, 八千代市, 千葉県, 日本

        ここにタイトルなんだ。
        """
        let result = JournalParser.parse(fileContent: content, year: 2020)
        XCTAssertEqual(result.entries.count, 1)
        let entry = result.entries[0]
        XCTAssertEqual(entry.weather, "🌤 8°C 所により霧", "コメント行の先にあるメタ情報を取れること")
        XCTAssertEqual(entry.location, "📍 八千代台北5丁目8-16, 八千代市, 千葉県, 日本")
        XCTAssertFalse(entry.body.contains("dayone-uuid"), "uuidコメントが本文に残らないこと")
        XCTAssertFalse(entry.body.contains("🌤"), "メタ情報行が本文に残らないこと")
        XCTAssertTrue(entry.body.hasPrefix("ここにタイトルなんだ"))
    }

    /// ①メタ情報行が無く、uuidコメントだけがある形
    func testUUIDCommentWithoutMetadataLine() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2021
        entries: 1
        ---

        # Test

        ## 2021-05-05（水）9:00:00

        <!-- dayone-uuid: AAAA | journal: Journal -->

        本文だけ。
        """
        let result = JournalParser.parse(fileContent: content, year: 2021)
        let entry = result.entries[0]
        XCTAssertNil(entry.weather)
        XCTAssertFalse(entry.body.contains("dayone-uuid"), "uuidコメントが本文に残らないこと")
        XCTAssertEqual(entry.body, "本文だけ。")
    }

    /// ①displayBody は本文中に紛れ込んだコメントも落とす
    func testDisplayBodyStripsInlineComment() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2022
        entries: 1
        ---

        # Test

        ## 2022-03-03（木）8:00:00

        前の行。
        <!-- dayone-uuid: BBBB | journal: Journal -->
        後の行。
        """
        let result = JournalParser.parse(fileContent: content, year: 2022)
        let entry = result.entries[0]
        XCTAssertTrue(entry.body.contains("dayone-uuid"), "body は元ファイルどおり保持すること")
        XCTAssertFalse(entry.displayBody.contains("dayone-uuid"), "displayBody では消えること")
        XCTAssertTrue(entry.displayBody.contains("前の行"))
        XCTAssertTrue(entry.displayBody.contains("後の行"))
        XCTAssertFalse(entry.preview.contains("dayone-uuid"), "一覧のプレビューにも出ないこと")
    }

    /// ⑤行頭のタグが検出されること（旧 `(?<!\A|^)` で落ちていた）
    func testTagAtLineStart() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-02-02（月）10:00:00

        #早天 きょうの記録。
        #音楽制作 も少し進んだ。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        let entry = result.entries[0]
        XCTAssertTrue(entry.tags.contains("#早天"), "本文1行目・行頭のタグが取れること")
        XCTAssertTrue(entry.tags.contains("#音楽制作"), "2行目の行頭タグも取れること")
        XCTAssertEqual(entry.tags.count, 2)
    }

    /// ⑤Markdownの見出しをタグと取り違えないこと
    func testHeadingIsNotATag() throws {
        let content = """
        ---
        title: Test
        type: journal
        year: 2026
        entries: 1
        ---

        # Test

        ## 2026-02-03（火）10:00:00

        # 見出し
        ### 小見出し
        本文 #タグ あり。
        """
        let result = JournalParser.parse(fileContent: content, year: 2026)
        let entry = result.entries[0]
        XCTAssertEqual(entry.tags, ["#タグ"], "`# 見出し` はタグにしないこと")
    }

    // MARK: - Markdown 描画（②）

    func testMarkdownBlockParsing() throws {
        let source = """
        # 見出し1
        本文の行。
        - 箇条書き
        1. 番号付き
        > 引用
        ---
        末尾。
        """
        let blocks = MarkdownText.blocks(from: source)
        XCTAssertEqual(blocks.count, 7)

        guard case .heading(let level, let headingText) = blocks[0] else {
            return XCTFail("1つめは見出しのはず")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(headingText, "見出し1")

        guard case .paragraph = blocks[1] else { return XCTFail("2つめは段落のはず") }
        guard case .bullet(let bulletText) = blocks[2] else { return XCTFail("3つめは箇条書きのはず") }
        XCTAssertEqual(bulletText, "箇条書き")
        guard case .numbered(let marker, _) = blocks[3] else { return XCTFail("4つめは番号付きのはず") }
        XCTAssertEqual(marker, "1.")
        guard case .quote(let quoteText) = blocks[4] else { return XCTFail("5つめは引用のはず") }
        XCTAssertEqual(quoteText, "引用")
        guard case .divider = blocks[5] else { return XCTFail("6つめは区切り線のはず") }
        guard case .paragraph = blocks[6] else { return XCTFail("7つめは段落のはず") }
    }

    /// `#タグ` を見出しとして解釈しないこと
    func testMarkdownTagIsNotHeading() throws {
        let blocks = MarkdownText.blocks(from: "#早天 の記録")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph = blocks[0] else {
            return XCTFail("`#タグ` は見出しではなく段落のはず")
        }
    }

    func testMarkdownCodeFence() throws {
        let source = """
        前。
        ```
        let x = 1
        ```
        後。
        """
        let blocks = MarkdownText.blocks(from: source)
        XCTAssertEqual(blocks.count, 3)
        guard case .code(let code) = blocks[1] else { return XCTFail("2つめはコードのはず") }
        XCTAssertEqual(code, "let x = 1")
    }
}
