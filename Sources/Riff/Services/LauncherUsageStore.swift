import Foundation

/// Frecency store: combines how often and how recently a candidate was used.
/// Older behavior kept only an insertion-ordered recent list; this keeps the
/// same call surface while decaying older hits so ranking stays responsive.
@MainActor
final class LauncherUsageStore {
    private static let maximumCount = 128
    private static let halfLife: TimeInterval = 7 * 24 * 3_600

    private struct Entry: Codable {
        var hits: Int
        var lastUsedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, key: String = "launcher.frecency") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func record(_ identifier: String) {
        var entry = entries[identifier] ?? Entry(hits: 0, lastUsedAt: .distantPast)
        entry.hits += 1
        entry.lastUsedAt = Date()
        entries[identifier] = entry

        if entries.count > Self.maximumCount {
            let ranked = entries.sorted { Self.frecency($0.value) > Self.frecency($1.value) }
            for (identifier, _) in ranked.dropFirst(Self.maximumCount) {
                entries.removeValue(forKey: identifier)
            }
        }
        persist()
    }

    func frecency(_ identifier: String) -> Double {
        guard let entry = entries[identifier] else { return 0 }
        return Self.frecency(entry)
    }

    /// Rank of an identifier by frecency (0 = most used/recent), or nil when
    /// the identifier was never used.
    func position(of identifier: String) -> Int? {
        entries.keys
            .sorted { Self.frecency(entries[$0]!) > Self.frecency(entries[$1]!) }
            .firstIndex(of: identifier)
    }

    func sorted<Element>(
        _ elements: [Element],
        identifier: (Element) -> String
    ) -> [Element] {
        elements.enumerated().sorted { lhs, rhs in
            let lhsFrecency = frecency(identifier(lhs.element))
            let rhsFrecency = frecency(identifier(rhs.element))
            if lhsFrecency != rhsFrecency { return lhsFrecency > rhsFrecency }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func frecency(_ entry: Entry) -> Double {
        let age = max(0, Date().timeIntervalSince(entry.lastUsedAt))
        return Double(entry.hits) * exp(-age / halfLife)
    }
}
