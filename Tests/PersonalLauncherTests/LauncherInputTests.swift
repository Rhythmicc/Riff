import AppKit
import XCTest
@testable import PersonalLauncher

final class LauncherInputTests: XCTestCase {
    func testMarkedTextDefersLauncherKeyHandlingToInputMethod() {
        let editor = MarkedTextView()
        editor.reportsMarkedText = true

        XCTAssertTrue(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: editor))

        editor.reportsMarkedText = false
        XCTAssertFalse(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: editor))
        XCTAssertFalse(LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: NSView()))
    }

    func testPasteAndCopyUsePlainTextOnly() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("note", forType: .string)
        pasteboard.setData(Data("{\\rtf1 styled}".utf8), forType: .rtf)

        let editor = PlainTextFieldEditor(pasteboard: pasteboard)
        editor.string = "prefix "
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        editor.paste(nil)

        XCTAssertEqual(editor.string, "prefix note")

        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        editor.copy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "prefix note")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))
        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
    }
}

private final class MarkedTextView: NSTextView {
    var reportsMarkedText = false

    override func hasMarkedText() -> Bool {
        reportsMarkedText
    }
}
