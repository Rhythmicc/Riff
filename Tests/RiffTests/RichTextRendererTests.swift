import AppKit
import XCTest
@testable import Riff

final class RichTextRendererTests: XCTestCase {
    func testRendersCommonLatexAsReadableTypography() {
        let source = #"After \(2\times2\times128\), \(512\to256\), \(\tanh\), and \(d=\mathrm{nnz}/256\)."#

        let rendered = RichTextRenderer.render(
            source,
            syntax: .markdownAndMath,
            fontSize: 17,
            textColor: .labelColor
        ).string

        XCTAssertTrue(rendered.contains("2 × 2 × 128"))
        XCTAssertTrue(rendered.contains("512 → 256"))
        XCTAssertTrue(rendered.contains("tanh"))
        XCTAssertTrue(rendered.contains("d = nnz / 256"))
        XCTAssertFalse(rendered.contains(#"\times"#))
        XCTAssertFalse(rendered.contains(#"\mathrm"#))
    }

    func testRendersMarkdownWithoutLosingReadableText() {
        let source = "# Heading\n\nA **bold** value and `inline code`."

        let rendered = RichTextRenderer.render(
            source,
            syntax: .markdownAndMath,
            fontSize: 17,
            textColor: .labelColor
        ).string

        XCTAssertTrue(rendered.contains("Heading"))
        XCTAssertTrue(rendered.contains("A bold value and inline code."))
        XCTAssertFalse(rendered.contains("**"))
        XCTAssertFalse(rendered.contains("`"))
    }

    func testPlainModeLeavesSourceUntouched() {
        let source = #"Keep **Markdown** and \(x\times y\)."#

        let rendered = RichTextRenderer.render(
            source,
            syntax: .plain,
            fontSize: 17,
            textColor: .labelColor
        ).string

        XCTAssertEqual(rendered, source)
    }
}
