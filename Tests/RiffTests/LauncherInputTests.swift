import AppKit
import XCTest
@testable import Riff

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

    func testCommandCommaRoutesToSettings() {
        XCTAssertTrue(LauncherKeyRouting.isSettingsShortcut(keyCode: 43, modifiers: .command))
        XCTAssertFalse(LauncherKeyRouting.isSettingsShortcut(keyCode: 43, modifiers: [.command, .shift]))
        XCTAssertFalse(LauncherKeyRouting.isSettingsShortcut(keyCode: 42, modifiers: .command))
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

    func testLauncherKeepsSearchFocusedWhenResultsUnfold() {
        let model = AppModel(clipboard: ClipboardStore())
        let controller = LauncherPanelController(
            model: model,
            showNote: {},
            showSettings: {}
        )
        defer { controller.panel.orderOut(nil) }

        controller.show(mode: .apps)

        XCTAssertTrue(controller.panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(controller.panel.hasShadow)
        XCTAssertTrue(waitForSearchFocus(on: controller.panel))

        model.query = "r"

        XCTAssertTrue(model.shouldShowResults)
        XCTAssertTrue(waitForSearchFocus(on: controller.panel))
    }

    /// Focus is established through an AppKit field editor after the panel
    /// becomes key, which is timing-sensitive on CI. Poll instead of sleeping
    /// a fixed amount so slower runners don't produce false failures.
    private func waitForSearchFocus(
        on panel: KeyablePanel,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.isKeyWindow, panel.firstResponder is NSTextView {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    func testLauncherCanDismissImmediatelyWithoutLeavingTransparentPanelVisible() {
        let controller = LauncherPanelController(
            model: AppModel(clipboard: ClipboardStore()),
            showNote: {},
            showSettings: {}
        )

        controller.show(mode: .apps)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(controller.panel.isVisible)

        controller.dismiss(animated: false)

        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertEqual(controller.panel.alphaValue, 1)
    }

    func testTypingThenDeletingKeepsTheSearchBarAtOneScreenPosition() throws {
        let model = AppModel(clipboard: ClipboardStore())
        let controller = LauncherPanelController(
            model: model,
            showNote: {},
            showSettings: {}
        )
        defer { controller.dismiss(animated: false) }

        controller.show(mode: .apps)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))

        let textField = try XCTUnwrap(firstTextField(in: controller.panel.contentView))
        let initialTop = controller.panel.frame.maxY
        let initialFieldMidY = screenMidY(of: textField, in: controller.panel)

        model.query = "r"
        assertStableGeometry(
            panel: controller.panel,
            textField: textField,
            expectedTop: initialTop,
            expectedFieldMidY: initialFieldMidY,
            duration: 0.22
        )

        model.query = ""
        assertStableGeometry(
            panel: controller.panel,
            textField: textField,
            expectedTop: initialTop,
            expectedFieldMidY: initialFieldMidY,
            duration: 0.22
        )
    }

    private func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap(firstTextField(in:)).first
    }

    private func screenMidY(of view: NSView, in panel: NSWindow) -> CGFloat {
        let windowRect = view.convert(view.bounds, to: nil)
        return panel.convertToScreen(windowRect).midY
    }

    private func assertStableGeometry(
        panel: NSWindow,
        textField: NSTextField,
        expectedTop: CGFloat,
        expectedFieldMidY: CGFloat,
        duration: TimeInterval
    ) {
        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            XCTAssertEqual(panel.frame.maxY, expectedTop, accuracy: 1)
            XCTAssertGreaterThan(panel.contentView?.layer?.cornerRadius ?? 0, 20)
            XCTAssertEqual(
                screenMidY(of: textField, in: panel),
                expectedFieldMidY,
                accuracy: 1
            )
        }
    }
}

private final class MarkedTextView: NSTextView {
    var reportsMarkedText = false

    override func hasMarkedText() -> Bool {
        reportsMarkedText
    }
}
