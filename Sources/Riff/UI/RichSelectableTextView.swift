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

/// A lightweight streaming surface. It appends only the newly published
/// suffix instead of reparsing and replacing the entire translated document
/// for every SSE update. Rich Markdown rendering takes over once the stream
/// finishes.
struct StreamingSelectableTextView: NSViewRepresentable {
    let source: String
    let placeholder: String
    var fontSize: CGFloat = 17

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = StreamingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        update(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? StreamingTextView else { return }
        update(textView)
    }

    private func update(_ textView: StreamingTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 7
        paragraph.lineBreakMode = .byWordWrapping

        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let placeholderAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        if source.isEmpty {
            guard !textView.isShowingPlaceholder || textView.string != placeholder else { return }
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: placeholder, attributes: placeholderAttributes)
            )
            textView.streamSource = ""
            textView.isShowingPlaceholder = true
            return
        }

        if !textView.isShowingPlaceholder,
           source.hasPrefix(textView.streamSource),
           source.count > textView.streamSource.count {
            let delta = String(source.dropFirst(textView.streamSource.count))
            textView.textStorage?.append(NSAttributedString(string: delta, attributes: contentAttributes))
        } else if source != textView.streamSource || textView.isShowingPlaceholder {
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: source, attributes: contentAttributes)
            )
        }
        textView.streamSource = source
        textView.isShowingPlaceholder = false
    }
}

private final class StreamingTextView: NSTextView {
    var streamSource = ""
    var isShowingPlaceholder = false
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
        var index = 0

        while index < lines.count {
            let originalLine = lines[index]
            let trimmed = originalLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                isInsideCodeBlock.toggle()
                if index < lines.count - 1, output.length > 0 { output.append(NSAttributedString(string: "\n")) }
                index += 1
                continue
            }

            if !isInsideCodeBlock, looksLikeTableStart(lines, at: index) {
                var blockEnd = index
                var rows: [[String]] = []
                while blockEnd < lines.count, lines[blockEnd].contains("|") {
                    rows.append(tableCells(in: lines[blockEnd]))
                    blockEnd += 1
                }
                if output.length > 0, !output.string.hasSuffix("\n") {
                    output.append(NSAttributedString(string: "\n"))
                }
                output.append(renderTable(
                    rows: rows,
                    fontSize: fontSize,
                    textColor: textColor
                ))
                if blockEnd < lines.count {
                    output.append(NSAttributedString(string: "\n"))
                }
                index = blockEnd
                continue
            }

            var line = originalLine
            var prefix = ""
            var lineFont = NSFont.systemFont(ofSize: fontSize)
            var lineColor = textColor
            var backgroundColor: NSColor?

            if isInsideCodeBlock {
                lineFont = NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .regular)
                backgroundColor = NSColor.quaternarySystemFill
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
            index += 1
        }

        return output
    }

    // MARK: - Markdown tables

    private static func looksLikeTableStart(_ lines: [String], at index: Int) -> Bool {
        guard lines[index].contains("|"), index + 1 < lines.count else { return false }
        return isTableSeparatorRow(lines[index + 1])
    }

    private static func isTableSeparatorRow(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty
                && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func renderTable(
        rows: [[String]],
        fontSize: CGFloat,
        textColor: NSColor
    ) -> NSAttributedString {
        guard !rows.isEmpty else { return NSAttributedString() }
        let columnCount = max(rows.map(\.count).max() ?? 1, 1)
        let cellFont = NSFont.systemFont(ofSize: fontSize - 0.5)
        let headerFont = NSFont.systemFont(ofSize: fontSize - 0.5, weight: .semibold)
        let secondaryColor = textColor.withAlphaComponent(0.72)
        let cellPadding: CGFloat = 14

        var widths = [CGFloat](repeating: 0, count: columnCount)
        for (rowIndex, row) in rows.enumerated() {
            let isHeader = rowIndex == 0
            for (column, cell) in row.enumerated() where column < columnCount {
                let font = isHeader ? headerFont : cellFont
                let attributed = renderInlineMarkdown(cell, font: font, textColor: textColor)
                widths[column] = max(widths[column], attributed.size().width)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(2, fontSize * 0.18)
        paragraph.paragraphSpacing = 2
        var tabStops: [NSTextTab] = []
        var offset: CGFloat = 0
        for column in 0..<max(0, columnCount - 1) {
            offset += widths[column] + cellPadding
            tabStops.append(NSTextTab(textAlignment: .left, location: offset))
        }
        paragraph.tabStops = tabStops

        let output = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex == 1 { continue } // separator row becomes the divider below
            let isHeader = rowIndex == 0
            let cells = (0..<columnCount).map { column in
                column < row.count ? row[column] : ""
            }
            let font = isHeader ? headerFont : cellFont
            let color = isHeader ? textColor : textColor.withAlphaComponent(0.94)

            // Wrap each cell independently, then emit one tab-aligned text line
            // per wrapped row so long content stays inside the bubble.
            let wrapped = cells.enumerated().map { column, cell in
                wrappedLines(cell, font: font, width: widths[column])
            }
            let lineCount = wrapped.map(\.count).max() ?? 1
            for lineIndex in 0..<lineCount {
                let line = NSMutableAttributedString()
                for column in 0..<columnCount {
                    if column > 0 { line.append(NSAttributedString(string: "\t")) }
                    let cellText = lineIndex < wrapped[column].count
                        ? wrapped[column][lineIndex]
                        : ""
                    line.append(renderInlineMarkdown(cellText, font: font, textColor: color))
                }
                let fullRange = NSRange(location: 0, length: line.length)
                line.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
                output.append(line)
                output.append(NSAttributedString(string: "\n"))
            }

            if isHeader {
                let totalWidth = widths.reduce(0, +) + cellPadding * CGFloat(max(0, columnCount - 1))
                let dashWidth = (("─" as NSString).size(withAttributes: [.font: cellFont]).width)
                let dashCount = max(1, Int(totalWidth / max(dashWidth, 1)))
                let divider = String(repeating: "─", count: dashCount)
                let dividerAttributes: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: paragraph
                ]
                output.append(NSAttributedString(string: divider, attributes: dividerAttributes))
                output.append(NSAttributedString(string: "\n"))
            }
        }
        if output.length > 0, output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        return output
    }

    private static func wrappedLines(
        _ text: String,
        font: NSFont,
        width: CGFloat
    ) -> [String] {
        guard !text.isEmpty else { return [""] }
        guard width > 10 else { return [text] }

        // Prefer word boundaries so Latin words are not split mid-word.
        let words = text.split(omittingEmptySubsequences: false) { $0.isWhitespace }
        var lines: [String] = []
        var current = ""
        var currentWidth: CGFloat = 0
        for word in words {
            let wordString = String(word)
            let wordWidth = (wordString as NSString)
                .size(withAttributes: [.font: font])
                .width
            let separatorWidth = current.isEmpty
                ? 0
                : (" " as NSString).size(withAttributes: [.font: font]).width
            if currentWidth + separatorWidth + wordWidth > width, !current.isEmpty {
                lines.append(current)
                current = wordString
                currentWidth = wordWidth
            } else {
                current += (current.isEmpty ? "" : " ") + wordString
                currentWidth += separatorWidth + wordWidth
            }
        }
        if !current.isEmpty { lines.append(current) }

        // A single overlong word (for example a URL) still needs char wrapping.
        var result: [String] = []
        for line in lines {
            let lineWidth = (line as NSString).size(withAttributes: [.font: font]).width
            if lineWidth <= width || !line.contains(" ") {
                result.append(line)
            } else {
                result.append(contentsOf: charWrapped(line, font: font, width: width))
            }
        }
        return result.isEmpty ? [text] : result
    }

    private static func charWrapped(
        _ text: String,
        font: NSFont,
        width: CGFloat
    ) -> [String] {
        var lines: [String] = []
        var current = ""
        var currentWidth: CGFloat = 0
        for character in text {
            let characterString = String(character)
            let characterWidth = (characterString as NSString)
                .size(withAttributes: [.font: font])
                .width
            if currentWidth + characterWidth > width, !current.isEmpty {
                lines.append(current)
                current = characterString
                currentWidth = characterWidth
            } else {
                current += characterString
                currentWidth += characterWidth
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
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
                styled.addAttribute(.backgroundColor, value: NSColor.quaternarySystemFill, range: range)
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
