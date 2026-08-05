import Foundation

/// Bundle-derived candidate fields that are expensive to regenerate
/// (localized InfoPlist.strings reads and pinyin transforms). Cached on disk
/// keyed by app path, valid while the bundle modification date is unchanged.
struct CachedSearchCandidateFields: Codable, Sendable, Equatable {
    var bundleModificationDate: TimeInterval?
    var localizedNames: [String]
    var pinyinVariants: [String]
}

final class SearchCandidateCache: Sendable {
    private let lock = NSLock()
    private let url: URL
    private var entries: [String: CachedSearchCandidateFields]
    private var isDirty = false

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(
            [String: CachedSearchCandidateFields].self,
            from: data
           ) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func fields(
        for application: ApplicationRecord,
        bundleModificationDate: TimeInterval?,
        build: () -> CachedSearchCandidateFields
    ) -> CachedSearchCandidateFields {
        lock.lock()
        defer { lock.unlock() }
        let key = application.url.path
        if let cached = entries[key],
           cached.bundleModificationDate == bundleModificationDate {
            return cached
        }
        let built = build()
        entries[key] = built
        isDirty = true
        return built
    }

    func persistIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard isDirty else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
        isDirty = false
    }
}
