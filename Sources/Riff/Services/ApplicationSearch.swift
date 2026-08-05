import Foundation

actor ApplicationSearch {
    private var entries: [SearchCandidate] = []
    private let candidateCache: SearchCandidateCache

    init(
        cacheURL: URL = RiffPaths.applicationSupportDirectory
            .appendingPathComponent("search-candidates.json")
    ) {
        candidateCache = SearchCandidateCache(url: cacheURL)
    }

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
            let cached = candidateCache.fields(
                for: application,
                bundleModificationDate: Self.bundleModificationDate(for: application.url)
            ) {
                SearchCandidateBuilder.cachedFields(for: application)
            }
            return SearchCandidateBuilder.build(
                for: application,
                cachedFields: cached
            )
        }
        candidateCache.persistIfNeeded()
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

    private static func bundleModificationDate(for url: URL) -> TimeInterval? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970
    }
}
