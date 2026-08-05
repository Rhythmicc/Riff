import AppKit
import Foundation

final class ApplicationIndex {
    private struct RootState: Sendable {
        let url: URL
        let modificationDate: Date?
        let exists: Bool
        let applicationURLs: [URL]
    }

    private struct CachedRoot {
        let modificationDate: Date?
        let exists: Bool
        let applicationURLs: [URL]
        let applications: [ApplicationRecord]
    }

    private let roots: [URL]
    private let fullRescanInterval: TimeInterval
    private var cachedRoots: [URL: CachedRoot] = [:]
    private var lastFullScanAt: Date?

    init(
        roots: [URL]? = nil,
        fullRescanInterval: TimeInterval = 5 * 60
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = roots ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]
        self.fullRescanInterval = fullRescanInterval
    }

    /// Discovers application paths on every call, then reloads bundle metadata
    /// only when that path snapshot or the root metadata changed. A periodic
    /// full pass also catches in-place bundle metadata updates.
    func load(force: Bool = false) async -> [ApplicationRecord] {
        let roots = self.roots
        let now = Date()
        let rootStates = await Task.detached(priority: force ? .userInitiated : .utility) {
            roots.map(Self.state(for:))
        }.value
        let needsFullScan = force
            || lastFullScanAt.map { now.timeIntervalSince($0) >= fullRescanInterval } != false

        let rootsToScan = rootStates.filter { state in
            guard !needsFullScan, let cached = cachedRoots[state.url] else { return true }
            return cached.exists != state.exists
                || cached.modificationDate != state.modificationDate
                || cached.applicationURLs != state.applicationURLs
        }

        if !rootsToScan.isEmpty {
            let scans = await Task.detached(priority: force ? .userInitiated : .utility) {
                rootsToScan.map { state in
                    (state, Self.scanApplications(at: state.applicationURLs))
                }
            }.value
            for (state, applications) in scans {
                cachedRoots[state.url] = CachedRoot(
                    modificationDate: state.modificationDate,
                    exists: state.exists,
                    applicationURLs: state.applicationURLs,
                    applications: applications
                )
            }
        }

        if needsFullScan { lastFullScanAt = now }

        var seen = Set<String>()
        return roots
            .flatMap { cachedRoots[$0]?.applications ?? [] }
            .filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func state(for root: URL) -> RootState {
        let values = try? root.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
        let exists = values?.isDirectory == true
        return RootState(
            url: root,
            modificationDate: values?.contentModificationDate,
            exists: exists,
            applicationURLs: exists ? discoverApplications(at: root) : []
        )
    }

    /// Discovering paths is intentionally separate from reading every bundle.
    /// It is cheap enough to run whenever the launcher opens and reliably catches
    /// installers even when the root directory modification date is unchanged.
    private static func discoverApplications(at root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "app" else { return nil }
            return url.standardizedFileURL
        }.sorted { $0.path < $1.path }
    }

    private static func scanApplications(at applicationURLs: [URL]) -> [ApplicationRecord] {
        applicationURLs.map { url in
            let bundle = Bundle(url: url)
            let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            let fallback = url.deletingPathExtension().lastPathComponent
            let bundleIdentifier = bundle?.bundleIdentifier
            return ApplicationRecord(
                url: url,
                name: displayName ?? bundleName ?? fallback,
                bundleIdentifier: bundleIdentifier,
                aliases: bundleIdentifier.flatMap(AppAliasCatalog.aliases(for:)) ?? []
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func launch(_ application: ApplicationRecord) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
    }
}
