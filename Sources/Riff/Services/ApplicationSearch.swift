import Foundation

actor ApplicationSearch {
    private var entries: [ApplicationRecord] = []

    func replaceApplications(
        _ applications: [ApplicationRecord],
        runningBundleIdentifiers: Set<String>
    ) -> [ApplicationRecord] {
        let sorted = applications.sorted { lhs, rhs in
            let lhsRunning = lhs.bundleIdentifier.map(runningBundleIdentifiers.contains) ?? false
            let rhsRunning = rhs.bundleIdentifier.map(runningBundleIdentifiers.contains) ?? false
            if lhsRunning != rhsRunning { return lhsRunning }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        entries = sorted
        return sorted
    }

    func search(_ query: String) -> [ApplicationRecord] {
        let needle = FuzzyMatcher.normalized(query)
        guard !needle.isEmpty else { return entries }
        let requireBoundary = needle.count < 3

        var matches: [(application: ApplicationRecord, matchedName: Bool, score: Int)] = []
        matches.reserveCapacity(64)
        for (index, application) in entries.enumerated() {
            if index.isMultiple(of: 16), Task.isCancelled { return [] }
            let nameScore = FuzzyMatcher.score(
                query: query,
                candidate: application.name,
                requireBoundaryForShortQueries: requireBoundary
            )
            var bestScore = nameScore
            var matchedName = nameScore != nil
            for alias in application.aliases {
                guard let aliasScore = FuzzyMatcher.score(
                    query: query,
                    candidate: alias,
                    requireBoundaryForShortQueries: requireBoundary
                ) else { continue }
                let adjusted = aliasScore - 100
                if !matchedName || adjusted > (bestScore ?? Int.min) {
                    bestScore = adjusted
                    matchedName = true
                }
            }
            if matchedName, let bestScore {
                matches.append((application, true, bestScore))
                continue
            }
            guard let bundleIdentifier = application.bundleIdentifier,
                  let bundleScore = FuzzyMatcher.contiguousScore(
                    query: query,
                    candidate: bundleIdentifier,
                    requireBoundaryForShortQueries: requireBoundary
                  )
            else { continue }
            // Bundle identifiers remain useful for expert queries such as
            // `vscode`, but any display-name match belongs ahead of a
            // bundle-only match regardless of the raw fuzzy score.
            matches.append((application, false, bundleScore))
        }
        matches.sort { lhs, rhs in
            if lhs.matchedName != rhs.matchedName { return lhs.matchedName }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.application.name.localizedCaseInsensitiveCompare(rhs.application.name) == .orderedAscending
        }
        return matches.map(\.application)
    }
}
