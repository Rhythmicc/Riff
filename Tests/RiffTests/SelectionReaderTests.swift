import XCTest
@testable import Riff

final class SelectionReaderTests: XCTestCase {
    func testSelectionNormalizationPreservesInternalParagraphsAndLineBreaks() {
        let source = "  First paragraph.\r\n\r\nSecond line.\rThird line.  \n"

        XCTAssertEqual(
            SelectionReader.normalizedSelection(source),
            "First paragraph.\n\nSecond line.\nThird line."
        )
    }

    func testSelectionNormalizationRejectsWhitespaceOnlyContent() {
        XCTAssertNil(SelectionReader.normalizedSelection(" \n\r\t "))
    }
}
