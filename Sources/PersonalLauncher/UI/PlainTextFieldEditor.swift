import AppKit

enum PlainTextFieldEditing {
    /// Keep AppKit's own field editor instance: SwiftUI's system text field
    /// expects that private concrete type on recent macOS versions. Plain-text
    /// mode makes paste/copy use unstyled strings without replacing the editor.
    static func configure(_ editor: NSTextView) {
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsImageEditing = false
    }
}
