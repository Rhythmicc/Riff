import AppKit
import XCTest
@testable import PersonalLauncher

@MainActor
final class LauncherInputTests: XCTestCase {
    func testMarkedTextDefersLauncherKeyHandlingToInputMethod() {
        let editor = MarkedTextView()
        editor.reportsMarkedText = true

        XCTAssertTrue(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: editor))

        editor.reportsMarkedText = false
        XCTAssertFalse(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: editor))
        XCTAssertFalse(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: NSView()))
    }

    func testLauncherConfiguresSystemFieldEditorForPlainText() throws {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.usesPlainTextFieldEditor = true
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        panel.contentView?.addSubview(field)

        let editor = try XCTUnwrap(panel.fieldEditor(true, for: field) as? NSTextView)

        XCTAssertFalse(editor.isRichText)
        XCTAssertFalse(editor.importsGraphics)
        XCTAssertFalse(editor.allowsImageEditing)

        editor.string = "plain text"
        editor.setSelectedRange(NSRange(location: 0, length: 10))
        XCTAssertEqual(editor.writablePasteboardTypes.count, 1)
        XCTAssertFalse(editor.writablePasteboardTypes.contains(.rtf))
        XCTAssertFalse(editor.writablePasteboardTypes.contains(.html))
    }
}

private final class MarkedTextView: NSTextView {
    var reportsMarkedText = false

    override func hasMarkedText() -> Bool {
        reportsMarkedText
    }
}
