import AppKit
import MarkdownEngine
import SwiftUI

struct InlineMarkdownEditor: View {
    @Binding var text: String
    let documentID: UUID

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: Self.configuration,
            fontName: "SF Pro Text",
            fontSize: 17,
            documentId: documentID.uuidString,
            placeholder: NSAttributedString(
                string: "开始写点什么…",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 17),
                    .foregroundColor: NSColor.placeholderTextColor
                ]
            )
        )
    }

    static var configuration: MarkdownEditorConfiguration {
        var theme = MarkdownEditorTheme.default
        theme.bodyText = .labelColor
        theme.mutedText = .secondaryLabelColor
        theme.disabledText = .disabledControlTextColor
        theme.headingMarker = .tertiaryLabelColor
        theme.link = .linkColor
        theme.incompleteLink = theme.link.withAlphaComponent(0.68)
        theme.strikethroughColor = .secondaryLabelColor

        var configuration = MarkdownEditorConfiguration.default
        configuration.theme = theme
        configuration.textInsets = TextInsets(horizontal: 30, vertical: 24)
        configuration.readingWidth = 680
        configuration.headings = HeadingStyle(
            fontMultipliers: [2.15, 1.72, 1.42, 1.22, 1.08, 1.0],
            topSpacingEm: [0.48, 0.42, 0.34, 0.28, 0.22, 0.18]
        )
        configuration.paragraph = ParagraphStyle(
            spacingFactor: 0.42,
            lineHeightExtraSpacing: 3
        )
        configuration.spellChecking = SpellCheckingPolicy(
            continuousSpellChecking: true,
            grammarChecking: true,
            automaticSpellingCorrection: false
        )
        configuration.extensions = [StrikethroughExtension()]
        return configuration
    }
}
