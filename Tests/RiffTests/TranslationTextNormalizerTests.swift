import XCTest
@testable import Riff

final class TranslationTextNormalizerTests: XCTestCase {
    func testJoinsSoftWrappedProseAndPreservesBlankLineParagraphs() {
        let source = "First line\r\ncontinues here.\r\n\r\nSecond paragraph."

        XCTAssertEqual(
            TranslationTextNormalizer.normalize(source),
            "First line continues here.\n\nSecond paragraph."
        )
    }

    func testJoinsCJKLinesWithoutInventingSpaces() {
        XCTAssertEqual(
            TranslationTextNormalizer.normalize("第一行文字\n继续同一个段落。"),
            "第一行文字继续同一个段落。"
        )
    }

    func testKeepsMarkdownBlockStructure() {
        let source = """
        # Heading
        - first
        - second

        | A | B |
        |---|---|

        ```swift
        let a = 1
        let b = 2
        ```
        """

        XCTAssertEqual(TranslationTextNormalizer.normalize(source), source)
    }

    func testCollapsesRepeatedBlankLinesToOneParagraphBoundary() {
        XCTAssertEqual(
            TranslationTextNormalizer.normalize("one\n\n\n\ntwo"),
            "one\n\ntwo"
        )
    }
}
