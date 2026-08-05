import Foundation

actor ApplicationSearch {
    private var entries: [SearchCandidate] = []

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
        entries = sorted.map(SearchCandidateBuilder.build)
        return sorted
    }

    func search(_ query: String) -> [ApplicationRecord] {
        let needle = FuzzyMatcher.normalized(query)
        guard !needle.isEmpty else { return entries.map(\.application) }

        var matches: [(application: ApplicationRecord, score: Int)] = []
        matches.reserveCapacity(64)
        for (index, candidate) in entries.enumerated() {
            if index.isMultiple(of: 16), Task.isCancelled { return [] }
            guard let score = SearchScorer.score(query: query, candidate: candidate) else {
                continue
            }
            matches.append((candidate.application, score))
        }
        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.application.name.localizedCaseInsensitiveCompare(rhs.application.name)
                == .orderedAscending
        }
        return matches.map(\.application)
    }
}
