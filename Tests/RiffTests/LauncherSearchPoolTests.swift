import XCTest
@testable import Riff

@MainActor
final class LauncherSearchPoolTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "LauncherSearchPoolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeApplication(name: String, bundle: String) -> ApplicationRecord {
        ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            name: name,
            bundleIdentifier: bundle
        )
    }

    func testSystemOperationAndQuickActionEnterTheSamePool() {
        let usage = LauncherUsageStore(defaults: makeDefaults())

        let sleepItems = LauncherSearchPool.systemOperationItems(
            query: "睡眠",
            isEnabled: true
        )
        XCTAssertEqual(sleepItems.first?.category, .systemOperation)
        XCTAssertEqual(sleepItems.first?.title, "睡眠")

        let noteItems = LauncherSearchPool.quickActionItems(query: "note") { _ in true }
        XCTAssertEqual(noteItems.first?.category, .quickAction)
        XCTAssertEqual(noteItems.first?.payload, .quickAction(.note))

        let merged = LauncherSearchPool.merge(
            sleepItems + noteItems,
            queryLength: 2,
            usageStore: usage
        )
        XCTAssertEqual(
            Set(merged.map(\.category)),
            Set([.systemOperation, .quickAction])
        )
    }

    func testShortQueryCapsAppCategory() {
        let usage = LauncherUsageStore(defaults: makeDefaults())
        let applications = (0..<6).map { index in
            makeApplication(name: "MacApp\(index)", bundle: "com.example.macapp\(index)")
        }
        let appItems = LauncherSearchPool.appItems(query: "ma", applications: applications)

        let merged = LauncherSearchPool.merge(
            appItems,
            queryLength: 2,
            usageStore: usage
        )

        XCTAssertEqual(merged.filter { $0.category == .app }.count, 3)
    }

    func testFrecencyOrdersByHitsAndRecency() {
        let usage = LauncherUsageStore(defaults: makeDefaults())
        usage.record("a")
        usage.record("b")
        usage.record("a")

        XCTAssertEqual(usage.position(of: "a"), 0)
        XCTAssertEqual(usage.position(of: "b"), 1)
        XCTAssertEqual(usage.sorted(["a", "b"]) { $0 }, ["a", "b"])
    }

    func testUsageBonusBreaksNearTies() {
        let usage = LauncherUsageStore(defaults: makeDefaults())
        let first = LauncherSearchItem(
            id: "app:first",
            category: .app,
            title: "First",
            subtitle: nil,
            symbol: "app",
            score: 7_990,
            payload: .application(makeApplication(name: "First", bundle: "com.example.first"))
        )
        let second = LauncherSearchItem(
            id: "app:second",
            category: .app,
            title: "Second",
            subtitle: nil,
            symbol: "app",
            score: 7_995,
            payload: .application(makeApplication(name: "Second", bundle: "com.example.second"))
        )
        usage.record(first.id)

        let merged = LauncherSearchPool.merge(
            [second, first],
            queryLength: 3,
            usageStore: usage
        )

        XCTAssertEqual(merged.first?.id, first.id)
    }
}
