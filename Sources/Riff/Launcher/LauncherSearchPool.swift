import Foundation

enum LauncherSearchCategory: String, CaseIterable, Sendable {
    case app
    case quickAction
    case systemOperation

    var title: String {
        switch self {
        case .app: return "应用"
        case .quickAction: return "快捷"
        case .systemOperation: return "操作"
        }
    }
}

struct LauncherSearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let category: LauncherSearchCategory
    let title: String
    let subtitle: String?
    let symbol: String
    let score: Int
    let payload: LauncherSearchPayload
}

enum LauncherSearchPayload: Hashable, Sendable {
    case application(ApplicationRecord)
    case quickAction(LauncherQuickAction)
    case systemOperation(SystemOperation)
}

/// Builds and merges the cross-category launcher candidate pool. All
/// candidates share one quality scale; usage adds a bounded bonus; category
/// caps keep short queries diverse instead of letting one category dominate.
enum LauncherSearchPool {
    static func quickActionItems(
        query: String,
        isEnabled: (LauncherQuickAction) -> Bool
    ) -> [LauncherSearchItem] {
        LauncherQuickAction.matching(query).filter(isEnabled).map { action in
            LauncherSearchItem(
                id: "quick:\(action.rawValue)",
                category: .quickAction,
                title: action.title,
                subtitle: action.detail,
                symbol: action.symbol,
                score: score(query: query, keywords: action.keywords) ?? 6_000,
                payload: .quickAction(action)
            )
        }
    }

    static func systemOperationItems(
        query: String,
        isEnabled: Bool
    ) -> [LauncherSearchItem] {
        guard isEnabled else { return [] }
        return SystemOperation.matching(query).map { operation in
            LauncherSearchItem(
                id: "system:\(operation.rawValue)",
                category: .systemOperation,
                title: operation.title,
                subtitle: operation.detail,
                symbol: operation.symbol,
                score: score(query: query, keywords: operation.keywords) ?? 6_000,
                payload: .systemOperation(operation)
            )
        }
    }

    static func appItems(
        query: String,
        applications: [ApplicationRecord]
    ) -> [LauncherSearchItem] {
        applications.compactMap { application in
            guard let score = SearchScorer.score(
                query: query,
                candidate: SearchCandidateBuilder.build(for: application)
            ) else { return nil }
            return LauncherSearchItem(
                id: "app:\(application.id)",
                category: .app,
                title: application.name,
                subtitle: application.url.deletingLastPathComponent().lastPathComponent,
                symbol: "app",
                score: score,
                payload: .application(application)
            )
        }
    }

    /// Sorts by `score + bounded usage bonus`, applies per-category caps, and
    /// returns the final presentation order.
    @MainActor
    static func merge(
        _ items: [LauncherSearchItem],
        queryLength: Int,
        usageStore: LauncherUsageStore,
        appLimit: Int = 8
    ) -> [LauncherSearchItem] {
        let appCap = queryLength <= 2 ? min(3, appLimit) : appLimit
        let quickCap = 3
        let systemCap = 3

        var counts: [LauncherSearchCategory: Int] = [:]
        let ranked = items
            .sorted { lhs, rhs in
                let lhsFinal = finalScore(lhs, usageStore: usageStore)
                let rhsFinal = finalScore(rhs, usageStore: usageStore)
                if lhsFinal != rhsFinal { return lhsFinal > rhsFinal }
                return lhs.id < rhs.id
            }
            .filter { item in
                let cap: Int
                switch item.category {
                case .app: cap = appCap
                case .quickAction: cap = quickCap
                case .systemOperation: cap = systemCap
                }
                let count = counts[item.category, default: 0]
                guard count < cap else { return false }
                counts[item.category] = count + 1
                return true
            }
        return ranked
    }

    @MainActor
    static func finalScore(
        _ item: LauncherSearchItem,
        usageStore: LauncherUsageStore
    ) -> Int {
        let bonus: Int
        if let position = usageStore.position(of: item.id) {
            bonus = max(0, 250 - position * 25)
        } else {
            bonus = 0
        }
        return item.score + bonus
    }

    private static func score(query: String, keywords: [String]) -> Int? {
        keywords.compactMap {
            FuzzyMatcher.score(query: query, candidate: $0)
        }.max()
    }
}
