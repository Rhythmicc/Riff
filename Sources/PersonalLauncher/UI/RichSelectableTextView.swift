import AppKit
import SwiftUI

enum RichTextSyntax: Equatable {
    case plain
    case markdownAndMath
}

struct RichSelectableTextView: NSViewRepresentable {
    let source: String
    var syntax: RichTextSyntax = .markdownAndMath
    var fontSize: CGFloat = 16
    var textColor: NSColor = .labelColor
    var contentInset = NSSize(width: 0, height: 4)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SourcePreservingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.textContainerInset = contentInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.9),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        scrollView.documentView = textView
        update(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SourcePreservingTextView else { return }
        textView.textContainerInset = contentInset
        update(textView)
    }

    private func update(_ textView: SourcePreservingTextView) {
        let renderKey = "\(syntax)-\(fontSize)-\(textColor.hash)-\(source)"
        guard textView.renderKey != renderKey else { return }
        textView.renderKey = renderKey
        textView.sourceText = source
        textView.textStorage?.setAttributedString(
            RichTextRenderer.render(
                source,
                syntax: syntax,
                fontSize: fontSize,
                textColor: textColor
            )
        )
    }
}

private final class SourcePreservingTextView: NSTextView {
    var sourceText = ""
    var renderKey = ""

    override func copy(_ sender: Any?) {
        guard !sourceText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceText, forType: .string)
    }
}

enum RichTextRenderer {
    static func render(
        _ source: String,
        syntax: RichTextSyntax,
        fontSize: CGFloat,
        textColor: NSColor
    ) -> NSAttributedString {
        guard syntax == .markdownAndMath else {
            return NSAttributedString(
                string: source,
                attributes: baseAttributes(fontSize: fontSize, textColor: textColor)
            )
        }

        let output = NSMutableAttributedString()
        let lines = source.components(separatedBy: .newlines)
        var isInsideCodeBlock = false

        for (index, originalLine) in lines.enumerated() {
            let trimmed = originalLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                isInsideCodeBlock.toggle()
                if index < lines.count - 1, output.length > 0 { output.append(NSAttributedString(string: "\n")) }
                continue
            }

            var line = originalLine
            var prefix = ""
            var lineFont = NSFont.systemFont(ofSize: fontSize)
            var lineColor = textColor
            var backgroundColor: NSColor?

            if isInsideCodeBlock {
                lineFont = NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .regular)
                backgroundColor = NSColor.white.withAlphaComponent(0.045)
            } else if let heading = heading(in: line) {
                line = heading.text
                let sizes: [CGFloat] = [fontSize, fontSize + 8, fontSize + 5, fontSize + 3, fontSize + 1, fontSize]
                lineFont = NSFont.systemFont(ofSize: sizes[min(heading.level, 6) - 1], weight: .semibold)
            } else if line.hasPrefix("> ") {
                line.removeFirst(2)
                prefix = "▎ "
                lineColor = textColor.withAlphaComponent(0.76)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                line.removeFirst(2)
                prefix = "•  "
            } else if let match = line.range(of: #"^\s*\d+[.)]\s+"#, options: .regularExpression) {
                prefix = String(line[match])
                line.removeSubrange(match)
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = max(3, fontSize * 0.22)
            paragraph.paragraphSpacing = trimmed.isEmpty ? fontSize * 0.36 : fontSize * 0.52
            paragraph.lineBreakMode = .byWordWrapping

            let lineStart = output.length
            if !prefix.isEmpty {
                output.append(NSAttributedString(
                    string: prefix,
                    attributes: [.font: lineFont, .foregroundColor: lineColor]
                ))
            }
            if isInsideCodeBlock {
                output.append(NSAttributedString(
                    string: line,
                    attributes: [
                        .font: lineFont,
                        .foregroundColor: lineColor,
                        .backgroundColor: backgroundColor!
                    ]
                ))
            } else {
                output.append(renderInlineMathAndMarkdown(
                    line,
                    font: lineFont,
                    textColor: lineColor
                ))
            }

            if index < lines.count - 1 { output.append(NSAttributedString(string: "\n")) }
            let lineRange = NSRange(location: lineStart, length: output.length - lineStart)
            if lineRange.length > 0 {
                output.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
            }
        }

        return output
    }

    private static func renderInlineMathAndMarkdown(
        _ source: String,
        font: NSFont,
        textColor: NSColor
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let nsSource = source as NSString
        let pattern = #"\\\((.+?)\\\)|\\\[(.+?)\\\]|\$\$(.+?)\$\$|(?<!\\)\$(?!\s)(.+?)(?<!\s)\$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let matches = regex?.matches(
            in: source,
            range: NSRange(location: 0, length: nsSource.length)
        ) ?? []
        var location = 0

        for match in matches {
            if match.range.location > location {
                output.append(renderInlineMarkdown(
                    nsSource.substring(with: NSRange(location: location, length: match.range.location - location)),
                    font: font,
                    textColor: textColor
                ))
            }
            let contentRange = (1..<match.numberOfRanges)
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound }
            if let contentRange {
                let math = readableMath(nsSource.substring(with: contentRange))
                let mathFont = NSFont(name: "STIX Two Math", size: font.pointSize + 0.5)
                    ?? NSFont.systemFont(ofSize: font.pointSize, weight: .medium)
                output.append(NSAttributedString(
                    string: math,
                    attributes: [
                        .font: mathFont,
                        .foregroundColor: textColor.withAlphaComponent(0.96),
                        .baselineOffset: 0.5
                    ]
                ))
            }
            location = NSMaxRange(match.range)
        }

        if location < nsSource.length {
            output.append(renderInlineMarkdown(
                nsSource.substring(from: location),
                font: font,
                textColor: textColor
            ))
        }
        return output
    }

    private static func renderInlineMarkdown(
        _ source: String,
        font: NSFont,
        textColor: NSColor
    ) -> NSAttributedString {
        guard !source.isEmpty else { return NSAttributedString() }
        let parsed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )).map(NSAttributedString.init) ?? NSAttributedString(string: source)
        let styled = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: styled.length)
        styled.addAttributes([.font: font, .foregroundColor: textColor], range: fullRange)

        let intentKey = NSAttributedString.Key("NSInlinePresentationIntent")
        styled.enumerateAttribute(intentKey, in: fullRange) { value, range, _ in
            guard let rawValue = (value as? NSNumber)?.intValue else { return }
            var resolvedFont = font
            var traits: NSFontTraitMask = []
            if rawValue & 1 != 0 { traits.insert(.italicFontMask) }
            if rawValue & 2 != 0 { traits.insert(.boldFontMask) }
            if !traits.isEmpty {
                resolvedFont = NSFontManager.shared.convert(font, toHaveTrait: traits)
            }
            if rawValue & 4 != 0 {
                resolvedFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 0.5, weight: .regular)
                styled.addAttribute(.backgroundColor, value: NSColor.white.withAlphaComponent(0.07), range: range)
            }
            if rawValue & 8 != 0 {
                styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            styled.addAttribute(.font, value: resolvedFont, range: range)
        }
        return styled
    }

    private static func readableMath(_ source: String) -> String {
        var value = source
        let wrapperPattern = #"\\(?:mathrm|mathbf|mathit|text|operatorname)\{([^{}]*)\}"#
        while let regex = try? NSRegularExpression(pattern: wrapperPattern),
              regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
            value = regex.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: "$1"
            )
        }

        let fractionPattern = #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: fractionPattern) {
            value = regex.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: "$1⁄$2"
            )
        }
        let sqrtPattern = #"\\sqrt\{([^{}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: sqrtPattern) {
            value = regex.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: "√($1)"
            )
        }

        let replacements = [
            "\\leftrightarrow": " ↔ ", "\\rightarrow": " → ", "\\leftarrow": " ← ",
            "\\Rightarrow": " ⇒ ", "\\Leftarrow": " ⇐ ", "\\times": " × ",
            "\\cdot": " · ", "\\approx": " ≈ ", "\\neq": " ≠ ", "\\leq": " ≤ ",
            "\\geq": " ≥ ", "\\pm": " ± ", "\\div": " ÷ ", "\\to": " → ",
            "\\infty": "∞", "\\sum": "∑", "\\prod": "∏", "\\partial": "∂",
            "\\nabla": "∇", "\\alpha": "α", "\\beta": "β", "\\gamma": "γ",
            "\\delta": "δ", "\\theta": "θ", "\\lambda": "λ", "\\mu": "μ",
            "\\pi": "π", "\\sigma": "σ", "\\phi": "φ", "\\omega": "ω",
            "\\tanh": "tanh", "\\sin": "sin", "\\cos": "cos", "\\log": "log",
            "\\exp": "exp", "\\left": "", "\\right": "", "\\,": " ", "\\;": " "
        ]
        for (command, replacement) in replacements {
            value = value.replacingOccurrences(of: command, with: replacement)
        }
        value = value.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s*([=/+−])\s*"#, with: " $1 ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        guard let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) else { return nil }
        let hashes = line[match].prefix { $0 == "#" }.count
        return (hashes, String(line[match.upperBound...]))
    }

    private static func baseAttributes(fontSize: CGFloat, textColor: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(3, fontSize * 0.22)
        paragraph.paragraphSpacing = fontSize * 0.5
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
    }
}
