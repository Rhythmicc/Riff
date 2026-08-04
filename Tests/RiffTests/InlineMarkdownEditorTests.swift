import AppKit
import MarkdownEngine
import SwiftUI
import XCTest
@testable import Riff

@MainActor
final class InlineMarkdownEditorTests: XCTestCase {
    func testHeadingScaleKeepsEveryHeadingDistinctFromBodyText() {
        let headings = InlineMarkdownEditor.configuration.headings

        XCTAssertGreaterThan(headings.fontMultiplier(for: 1), headings.fontMultiplier(for: 2))
        XCTAssertGreaterThan(headings.fontMultiplier(for: 2), headings.fontMultiplier(for: 3))
        XCTAssertGreaterThan(headings.fontMultiplier(for: 3), headings.fontMultiplier(for: 4))
        XCTAssertGreaterThan(headings.fontMultiplier(for: 4), 1)
        XCTAssertEqual(headings.fontMultiplier(for: 6), 1)
    }

    func testEditorSnapshotCoversHeadingRuleListAndTable() throws {
        let source = """
        ## Hello

        正文应该明显小于二级标题，并保持舒适的行高。

        ---

        1. Alpha
        2. Beta
        3. Gamma

        | Name | Count |
        |:---|---:|
        | Alpha | 12 |
        | Beta | 8 |
        """
        let host = NSHostingView(rootView: ZStack {
            Color(red: 0.075, green: 0.082, blue: 0.095)
            InlineMarkdownEditor(
                text: .constant(source),
                documentID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            )
        }.environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 620)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let textView = try XCTUnwrap(firstTextView(in: host))
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        if let snapshotPath = ProcessInfo.processInfo.environment["RIFF_NOTE_SNAPSHOT_PATH"] {
            try data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }
        XCTAssertGreaterThan(data.count, 1_000)
    }

    func testEditorKeepsMarkedTextVisibleAndCommitsItToTheBinding() throws {
        var source = ""
        let controller = MaterialPanelController(size: NSSize(width: 640, height: 420))
        controller.install(InlineMarkdownEditor(
            text: Binding(
                get: { source },
                set: { source = $0 }
            ),
            documentID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF")!
        ))
        defer { controller.panel.orderOut(nil) }

        controller.showCentered()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let textView = try XCTUnwrap(firstTextView(in: controller.panel.contentView!))
        XCTAssertTrue(controller.panel.makeFirstResponder(textView))

        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "ni")

        textView.insertText("你", replacementRange: textView.markedRange())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "你")
        XCTAssertEqual(source, "你")
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) { return textView }
        }
        return nil
    }
}
