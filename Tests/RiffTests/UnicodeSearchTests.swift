import XCTest
@testable import Riff

final class UnicodeSearchTests: XCTestCase {
    func testParsesUnicodeAndEmojiIntents() {
        XCTAssertEqual(
            UnicodeSearchQuery.parse("unicode arrow"),
            UnicodeSearchQuery(scope: .unicode, term: "arrow")
        )
        XCTAssertEqual(
            UnicodeSearchQuery.parse("表情：微笑"),
            UnicodeSearchQuery(scope: .emoji, term: "微笑")
        )
        XCTAssertEqual(
            UnicodeSearchQuery.parse("U+2192"),
            UnicodeSearchQuery(scope: .unicode, term: "U+2192")
        )
        XCTAssertEqual(
            UnicodeSearchQuery.parse("絵文字 笑顔"),
            UnicodeSearchQuery(scope: .emoji, term: "笑顔")
        )
        XCTAssertEqual(
            UnicodeSearchQuery.parse("symbole coeur"),
            UnicodeSearchQuery(scope: .unicode, term: "coeur")
        )
        XCTAssertNil(UnicodeSearchQuery.parse("Safari"))
    }

    func testFindsUnicodeByCodePoint() async throws {
        let query = try XCTUnwrap(UnicodeSearchQuery.parse("U+2192"))
        let results = await UnicodeSearchIndex.shared.search(query)

        XCTAssertEqual(results.first?.symbol, "→")
        XCTAssertEqual(results.first?.codePointLabel, "U+2192")
    }

    func testFindsEmojiAndChineseAliases() async throws {
        let emojiQuery = try XCTUnwrap(UnicodeSearchQuery.parse("emoji grin"))
        let emojiResults = await UnicodeSearchIndex.shared.search(emojiQuery)
        XCTAssertTrue(emojiResults.contains { $0.symbol.contains("😀") })
        XCTAssertTrue(emojiResults.allSatisfy(\.isEmoji))

        let faceQuery = try XCTUnwrap(UnicodeSearchQuery.parse("emoji face"))
        let faceResults = await UnicodeSearchIndex.shared.search(faceQuery)
        XCTAssertFalse(faceResults.isEmpty)

        let arrowQuery = try XCTUnwrap(UnicodeSearchQuery.parse("符号 箭头"))
        let arrowResults = await UnicodeSearchIndex.shared.search(arrowQuery)
        XCTAssertTrue(arrowResults.contains { $0.name.localizedCaseInsensitiveContains("arrow") })
    }

    func testFindsCountryFlagSequences() async throws {
        let query = try XCTUnwrap(UnicodeSearchQuery.parse("emoji flag china"))
        let results = await UnicodeSearchIndex.shared.search(query)

        XCTAssertEqual(results.first?.symbol, "🇨🇳")
    }

    func testRepeatedSearchUsesTheSameResults() async {
        let query = UnicodeSearchQuery(scope: .emoji, term: "heart")
        let first = await UnicodeSearchIndex.shared.search(query, limit: 32)
        let second = await UnicodeSearchIndex.shared.search(query, limit: 32)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    func testSearchesUsingTheConfiguredNativeLanguage() async {
        let japanese = await UnicodeSearchIndex.shared.search(
            UnicodeSearchQuery(scope: .emoji, term: "笑顔"),
            nativeLanguage: .japanese,
            limit: 16
        )
        let french = await UnicodeSearchIndex.shared.search(
            UnicodeSearchQuery(scope: .emoji, term: "coeur"),
            nativeLanguage: .french,
            limit: 16
        )
        let japaneseFlag = await UnicodeSearchIndex.shared.search(
            UnicodeSearchQuery(scope: .emoji, term: "日本"),
            nativeLanguage: .japanese,
            limit: 16
        )

        XCTAssertTrue(japanese.contains { $0.name.localizedCaseInsensitiveContains("smiling face") })
        XCTAssertTrue(french.contains { $0.name.localizedCaseInsensitiveContains("heart") })
        XCTAssertTrue(japaneseFlag.contains { $0.symbol == "🇯🇵" })
    }

    func testChineseRaisingHandQueryFindsRaisingHandEmoji() async {
        let results = await UnicodeSearchIndex.shared.search(
            UnicodeSearchQuery(scope: .emoji, term: "举手"),
            nativeLanguage: .simplifiedChinese,
            limit: 16
        )

        XCTAssertTrue(results.contains {
            $0.name.localizedCaseInsensitiveContains("raising")
                && $0.name.localizedCaseInsensitiveContains("hand")
        })
    }
}
