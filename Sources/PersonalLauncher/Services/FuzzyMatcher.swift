import Foundation

enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let needle = normalized(query)
        let haystack = normalized(candidate)
        guard !needle.isEmpty else { return 0 }

        if haystack == needle { return 10_000 }
        if haystack.hasPrefix(needle) { return 8_000 - haystack.count }
        if let range = haystack.range(of: needle) {
            return 6_000 - haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }

        var score = 0
        var searchStart = haystack.startIndex
        var previous: String.Index?

        for character in needle {
            guard let index = haystack[searchStart...].firstIndex(of: character) else { return nil }
            score += 100
            if let previous, haystack.index(after: previous) == index { score += 70 }
            if index == haystack.startIndex || haystack[haystack.index(before: index)].isWhitespace { score += 45 }
            previous = index
            searchStart = haystack.index(after: index)
        }

        return score - haystack.count
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}
