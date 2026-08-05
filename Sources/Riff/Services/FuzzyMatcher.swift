import Foundation

enum FuzzyMatcher {
    static func score(
        query: String,
        candidate: String,
        requireBoundaryForShortQueries: Bool = false
    ) -> Int? {
        guard let base = score(
            normalizedQuery: normalized(query),
            normalizedCandidate: normalized(candidate)
        ) else { return nil }
        if requireBoundaryForShortQueries,
           query.count < 3,
           isShortQueryInteriorMatch(query: query, candidate: candidate) {
            return nil
        }
        return base
    }

    static func score(normalizedQuery needle: String, normalizedCandidate haystack: String) -> Int? {
        guard !needle.isEmpty else { return 0 }

        if haystack == needle { return 10_000 }
        if haystack.hasPrefix(needle) { return 8_000 - haystack.count }
        if let range = haystack.range(of: needle) {
            return 6_000 - haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }

        var score = 0
        var searchStart = haystack.startIndex
        var previous: String.Index?
        var firstMatch: String.Index?
        var lastMatch: String.Index?
        var everyMatchStartsAWord = true

        for character in needle {
            guard let index = haystack[searchStart...].firstIndex(of: character) else { return nil }
            score += 100
            if let previous, haystack.index(after: previous) == index { score += 70 }
            let startsAWord = isWordBoundary(in: haystack, at: index)
            if startsAWord { score += 45 }
            everyMatchStartsAWord = everyMatchStartsAWord && startsAWord
            firstMatch = firstMatch ?? index
            lastMatch = index
            previous = index
            searchStart = haystack.index(after: index)
        }

        // Loose subsequences are useful for acronyms (`saf` → Super App Finder),
        // but otherwise the characters must stay close together. This prevents
        // semantic commands such as `note` from matching an unrelated long name
        // merely because the four letters happen to appear in order.
        if !everyMatchStartsAWord, let firstMatch, let lastMatch {
            let span = haystack.distance(from: firstMatch, to: haystack.index(after: lastMatch))
            let compactLimit = needle.count + max(2, needle.count / 2)
            guard span <= compactLimit else { return nil }
            score -= (span - needle.count) * 35
        }

        return score - haystack.count
    }

    static func contiguousScore(
        query: String,
        candidate: String,
        requireBoundaryForShortQueries: Bool = false
    ) -> Int? {
        guard let base = contiguousScore(
            normalizedQuery: normalized(query),
            normalizedCandidate: normalized(candidate)
        ) else { return nil }
        if requireBoundaryForShortQueries,
           query.count < 3,
           isShortQueryInteriorMatch(query: query, candidate: candidate) {
            return nil
        }
        return base
    }

    static func contiguousScore(
        normalizedQuery needle: String,
        normalizedCandidate haystack: String
    ) -> Int? {
        guard !needle.isEmpty else { return 0 }
        if haystack == needle { return 10_000 }
        if haystack.hasPrefix(needle) { return 8_000 - haystack.count }
        guard let range = haystack.range(of: needle) else { return nil }
        return 6_000 - haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private static func isWordBoundary(in value: String, at index: String.Index) -> Bool {
        guard index != value.startIndex else { return true }
        let previous = value[value.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    /// Component boundaries include separators, camelCase transitions, and
    /// digit-to-letter transitions (`xinWeChat`, `macOS`, `A12B`).
    private static func isComponentBoundary(in value: String, at index: String.Index) -> Bool {
        guard index != value.startIndex else { return true }
        let previous = value[value.index(before: index)]
        let current = value[index]
        if !previous.isLetter && !previous.isNumber { return true }
        if previous.isLetter, current.isLetter, previous.isLowercase, current.isUppercase {
            return true
        }
        if previous.isNumber, current.isLetter { return true }
        return false
    }

    /// Short queries only match at component boundaries. This rejects both
    /// contiguous substrings buried inside a word (`we` in `PowerPoint` or
    /// `pl.maketheweb.cleanshotx`) and loose subsequences whose first character
    /// starts inside a word (`we` in `Dowine 4`), while keeping prefix matches
    /// (`we` → `Welly`, `wechat`) and camelCase boundaries (`xinWeChat`).
    private static func isShortQueryInteriorMatch(
        query: String,
        candidate: String
    ) -> Bool {
        let needle = normalized(query)
        let options: String.CompareOptions = [
            .caseInsensitive, .diacriticInsensitive, .widthInsensitive
        ]
        if let range = candidate.range(of: needle, options: options),
           !isComponentBoundary(in: candidate, at: range.lowerBound) {
            return true
        }
        guard let first = needle.first else { return false }
        if let firstRange = candidate.range(of: String(first), options: options),
           !isComponentBoundary(in: candidate, at: firstRange.lowerBound) {
            return true
        }
        return false
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}
