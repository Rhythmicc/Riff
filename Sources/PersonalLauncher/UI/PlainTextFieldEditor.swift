import AppKit

/// Field editor used by the launcher search box. AppKit shares one field editor
/// per window, so installing it on the launcher panel covers SwiftUI's internal
/// NSTextField without depending on private view implementation details.
final class PlainTextFieldEditor: NSTextView {
    private let transferPasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        transferPasteboard = pasteboard
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        super.init(frame: .zero, textContainer: textContainer)
        isFieldEditor = true
        isRichText = false
        importsGraphics = false
        allowsImageEditing = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func paste(_ sender: Any?) {
        guard let plainText = transferPasteboard.string(forType: .string) else {
            NSSound.beep()
            return
        }
        insertText(plainText, replacementRange: selectedRange())
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        let selectedText = (string as NSString).substring(with: range)
        transferPasteboard.clearContents()
        transferPasteboard.setString(selectedText, forType: .string)
    }

    override func cut(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        copy(sender)
        insertText("", replacementRange: range)
    }
}
