import Foundation

enum TranslationTextNormalizer {
    /// Applies Markdown paragraph semantics to text copied from browsers, PDFs,
    /// and editors. Soft-wrapped prose lines are joined; blank lines and actual
    /// Markdown block structure remain meaningful.
    static func normalize(_ text: String) -> String {
        let source = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        var paragraph: [String] = []
        var fenceMarker: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append(joinProseLines(paragraph))
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker {
                output.append(line)
                if trimmed.hasPrefix(marker) { fenceMarker = nil }
                continue
            }

            if let marker = openingFence(in: trimmed) {
                flushParagraph()
                output.append(trimmed)
                fenceMarker = marker
            } else if trimmed.isEmpty {
                flushParagraph()
                if !output.isEmpty, output.last != "" { output.append("") }
            } else if isMarkdownBlockLine(line, trimmed: trimmed) {
                flushParagraph()
                output.append(line)
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()

        while output.first == "" { output.removeFirst() }
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    private static func joinProseLines(_ lines: [String]) -> String {
        lines.reduce(into: "") { result, line in
            guard !result.isEmpty else {
                result = line
                return
            }
            guard let left = result.unicodeScalars.last,
                  let right = line.unicodeScalars.first else { return }
            if shouldJoinWithoutSpace(left: left, right: right) {
                result.append(line)
            } else {
                result.append(" ")
                result.append(line)
            }
        }
    }

    private static func shouldJoinWithoutSpace(
        left: Unicode.Scalar,
        right: Unicode.Scalar
    ) -> Bool {
        if isCJK(left), isCJK(right) { return true }
        if "，。！？；：、,.!?;:)]}〉》」』】".unicodeScalars.contains(right) { return true }
        if "([{〈《「『【".unicodeScalars.contains(left) { return true }
        if left == "-", CharacterSet.letters.contains(right) { return true }
        return false
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static func openingFence(in line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func isMarkdownBlockLine(_ line: String, trimmed: String) -> Bool {
        if line.hasPrefix("    ") || line.hasPrefix("\t") { return true }
        if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") { return true }
        if trimmed.hasPrefix("> ") || trimmed == ">" { return true }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return true }
        if trimmed.hasPrefix("|") || trimmed.hasSuffix("|") { return true }
        if isOrderedListItem(trimmed) || isHorizontalRule(trimmed) { return true }
        return false
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.endIndex < line.endIndex else { return false }
        let suffix = line[digits.endIndex...]
        return suffix.hasPrefix(". ") || suffix.hasPrefix(") ")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first,
              marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }
}
