import Foundation

@MainActor
final class LauncherUsageStore {
    private static let maximumCount = 128

    private let defaults: UserDefaults
    private let key: String
    private var recentIdentifiers: [String]

    init(defaults: UserDefaults = .standard, key: String = "launcher.recentSelections") {
        self.defaults = defaults
        self.key = key
        recentIdentifiers = defaults.stringArray(forKey: key) ?? []
    }

    func record(_ identifier: String) {
        recentIdentifiers.removeAll { $0 == identifier }
        recentIdentifiers.insert(identifier, at: 0)
        if recentIdentifiers.count > Self.maximumCount {
            recentIdentifiers.removeLast(recentIdentifiers.count - Self.maximumCount)
        }
        defaults.set(recentIdentifiers, forKey: key)
    }

    func sorted<Element>(
        _ elements: [Element],
        identifier: (Element) -> String
    ) -> [Element] {
        var positions: [String: Int] = [:]
        for (index, identifier) in recentIdentifiers.enumerated()
        where positions[identifier] == nil {
            positions[identifier] = index
        }
        return elements.enumerated().sorted { lhs, rhs in
            let lhsPosition = positions[identifier(lhs.element)] ?? Int.max
            let rhsPosition = positions[identifier(rhs.element)] ?? Int.max
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
