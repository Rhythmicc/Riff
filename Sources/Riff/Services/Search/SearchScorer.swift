import Foundation

/// Unified feature scorer. Every candidate field competes on the same base
/// quality scale; field-type bonuses only nudge ties (aliases/pinyin above
/// display name, initials above loose subsequences, bundle identifiers last).
enum SearchScorer {
    static let minimumScore = 1_200

    static func score(query: String, candidate: SearchCandidate) -> Int? {
        let needle = FuzzyMatcher.normalized(query)
        guard !needle.isEmpty else { return 0 }

        var best: Int?

        func consider(_ field: String, bonus: Int = 0, contiguousOnly: Bool = false) {
            let score: Int?
            if contiguousOnly {
                score = FuzzyMatcher.contiguousScore(
                    query: query,
                    candidate: field,
                    requireBoundaryForShortQueries: true
                )
            } else {
                score = FuzzyMatcher.score(
                    query: query,
                    candidate: field,
                    requireBoundaryForShortQueries: true
                )
            }
            if let score {
                best = max(best ?? Int.min, score + bonus)
            }
        }

        consider(candidate.application.name)
        for name in candidate.localizedNames where name != candidate.application.name {
            consider(name, bonus: 50)
        }
        for component in candidate.components {
            consider(component, bonus: 30)
        }
        consider(candidate.initials, bonus: 40)
        for variant in candidate.pinyinVariants {
            consider(variant, bonus: 50)
        }
        for alias in candidate.aliases {
            consider(alias, bonus: 50)
        }
        if let bundleIdentifier = candidate.application.bundleIdentifier {
            consider(bundleIdentifier, bonus: -500, contiguousOnly: true)
        }

        guard let best, best >= minimumScore else { return nil }
        return best
    }
}
