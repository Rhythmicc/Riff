import Foundation

actor ApplicationSearch {
    private struct Entry: Sendable {
        let application: ApplicationRecord
        let normalizedName: String
        let normalizedBundleIdentifier: String?
    }

    private var entries: [Entry] = []

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
        entries = sorted.map { application in
            Entry(
                application: application,
                normalizedName: FuzzyMatcher.normalized(application.name),
                normalizedBundleIdentifier: application.bundleIdentifier.map(FuzzyMatcher.normalized)
            )
        }
        return sorted
    }

    func search(_ query: String) -> [ApplicationRecord] {
        let needle = FuzzyMatcher.normalized(query)
        guard !needle.isEmpty else { return entries.map(\.application) }

        var matches: [(application: ApplicationRecord, matchedName: Bool, score: Int)] = []
        matches.reserveCapacity(64)
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 16), Task.isCancelled { return [] }
            let nameScore = FuzzyMatcher.score(
                normalizedQuery: needle,
                normalizedCandidate: entry.normalizedName
            )
            if let nameScore {
                matches.append((entry.application, true, nameScore))
                continue
            }
            guard let bundleScore = entry.normalizedBundleIdentifier.flatMap({
                FuzzyMatcher.contiguousScore(
                    normalizedQuery: needle,
                    normalizedCandidate: $0
                )
            }) else { continue }
            // Bundle identifiers remain useful for expert queries such as
            // `vscode`, but any display-name match belongs ahead of a
            // bundle-only match regardless of the raw fuzzy score.
            matches.append((entry.application, false, bundleScore))
        }
        matches.sort { lhs, rhs in
            if lhs.matchedName != rhs.matchedName { return lhs.matchedName }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.application.name.localizedCaseInsensitiveCompare(rhs.application.name) == .orderedAscending
        }
        return matches.map(\.application)
    }
}
