import Combine
import XCTest
@testable import Riff

final class LauncherArchitectureTests: XCTestCase {
    func testClassifierProducesOneExplicitIntent() {
        if case .calculation(let result) = LauncherQueryClassifier.classify("12 * (8 + 2)") {
            XCTAssertEqual(result, "120")
        } else {
            XCTFail("Expected calculation intent")
        }

        if case .unicode(let query) = LauncherQueryClassifier.classify("emoji 举手") {
            XCTAssertEqual(query.scope, .emoji)
            XCTAssertEqual(query.term, "举手")
        } else {
            XCTFail("Expected Unicode intent")
        }

        if case .applications(let actions) = LauncherQueryClassifier.classify("note") {
            XCTAssertEqual(actions, [.note])
        } else {
            XCTFail("Expected applications intent")
        }

        if case .systemOperations(let operations) = LauncherQueryClassifier.classify("睡眠") {
            XCTAssertEqual(operations, [.sleep])
        } else {
            XCTFail("Expected system operation intent")
        }

        if case .password(let request) = LauncherQueryClassifier.classify("随机密码 24") {
            XCTAssertEqual(request.length, 24)
        } else {
            XCTFail("Expected password intent")
        }
    }

    func testSystemOperationsMatchLocalizedAndEnglishQueries() {
        XCTAssertEqual(SystemOperation.matching("睡眠"), [.sleep])
        XCTAssertEqual(SystemOperation.matching("lock screen"), [.lockScreen])
        XCTAssertEqual(SystemOperation.matching("熄屏"), [.displaySleep])
        XCTAssertEqual(SystemOperation.matching("screensaver"), [.screenSaver])
        XCTAssertTrue(SystemOperation.matching("s").isEmpty)
        XCTAssertTrue(SystemOperation.matching("sys").isEmpty)
        XCTAssertTrue(SystemOperation.matching("Safari").isEmpty)

        if case .applications(let actions) = LauncherQueryClassifier.classify("sys") {
            XCTAssertTrue(actions.isEmpty)
        } else {
            XCTFail("Expected sys to remain an application query")
        }
    }

    func testFallbackGoogleURLPreservesTheEntireQuery() throws {
        let url = try XCTUnwrap(
            LauncherFallbackAction.googleSearch.destinationURL(for: "Swift 中文 空格")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first?.value, "Swift 中文 空格")
    }

    @MainActor
    func testRecentSelectionsSortAheadOfUnusedCandidates() throws {
        let suiteName = "RiffTests.LauncherUsage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LauncherUsageStore(defaults: defaults)

        store.record("item:b")
        XCTAssertEqual(
            store.sorted(["a", "b", "c"]) { "item:\($0)" },
            ["b", "a", "c"]
        )

        store.record("item:a")
        XCTAssertEqual(
            store.sorted(["a", "b", "c"]) { "item:\($0)" },
            ["a", "b", "c"]
        )
    }

    @MainActor
    func testSystemOperationSelectionUsesInjectedHandler() {
        let model = AppModel(clipboard: ClipboardStore())
        var performed: SystemOperation?
        model.onPerformSystemOperation = { performed = $0 }

        model.query = "睡眠"

        XCTAssertTrue(model.isSystemOperationQuery)
        XCTAssertEqual(model.resultCount, 1)
        XCTAssertTrue(model.activateSelection())
        XCTAssertEqual(performed, .sleep)
    }

    func testApplicationSearchUsesPreindexedCandidates() async {
        let search = ApplicationSearch()
        let safari = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            name: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let notes = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Notes.app"),
            name: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        _ = await search.replaceApplications(
            [notes, safari],
            runningBundleIdentifiers: [safari.bundleIdentifier!]
        )

        let results = await search.search("saf")
        XCTAssertEqual(results, [safari])
    }

    func testApplicationNameMatchesAlwaysRankAheadOfBundleOnlyMatches() async {
        let search = ApplicationSearch()
        let nameMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Cool Draft Xylophone.app"),
            name: "Cool Draft Xylophone",
            bundleIdentifier: "dev.example.editor"
        )
        let bundleOnlyMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Utility.app"),
            name: "Utility",
            bundleIdentifier: "cdx"
        )
        _ = await search.replaceApplications(
            [bundleOnlyMatch, nameMatch],
            runningBundleIdentifiers: []
        )

        let results = await search.search("cdx")

        XCTAssertEqual(results, [nameMatch, bundleOnlyMatch])
    }

    @MainActor
    func testRecentBundleMatchCannotLeapfrogAnApplicationNameMatch() throws {
        let suiteName = "RiffTests.LauncherUsage.AppNames.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LauncherUsageStore(defaults: defaults)
        let nameMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Cool Draft Xylophone.app"),
            name: "Cool Draft Xylophone",
            bundleIdentifier: "dev.example.editor"
        )
        let bundleOnlyMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Utility.app"),
            name: "Utility",
            bundleIdentifier: "cdx"
        )
        store.record("app:\(bundleOnlyMatch.id)")

        let ranked = AppModel.rankApplicationsForPresentation(
            query: "cdx",
            searchedResults: [nameMatch, bundleOnlyMatch],
            usageStore: store
        )

        XCTAssertEqual(ranked, [nameMatch, bundleOnlyMatch])
    }

    func testApplicationIndexRefreshesAChangedRoot() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("riff-application-index-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try makeApplication(named: "First", bundleIdentifier: "test.first", in: root)
        let index = ApplicationIndex(roots: [root], fullRescanInterval: 60 * 60)
        let initial = await index.load(force: true)
        XCTAssertEqual(initial.map(\.name), ["First"])
        let originalModificationDate = try root.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate

        try makeApplication(named: "Second", bundleIdentifier: "test.second", in: root)
        if let originalModificationDate {
            try fileManager.setAttributes(
                [.modificationDate: originalModificationDate],
                ofItemAtPath: root.path
            )
        }
        let refreshed = await index.load()

        XCTAssertEqual(refreshed.map(\.name), ["First", "Second"])
    }

    @MainActor
    func testSynchronousQueryTransitionPublishesOneCoherentSnapshot() {
        let model = AppModel(clipboard: ClipboardStore())
        var publicationCount = 0
        let cancellable = model.$state.dropFirst().sink { _ in publicationCount += 1 }

        model.query = "12 * (8 + 2)"

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(model.calculation, "120")
        XCTAssertTrue(model.hasInferredContent)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testQueryTypedDuringInitialIndexingIsReplayedAfterIndexingCompletes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-initial-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeApplication(named: "Safari", bundleIdentifier: "test.safari", in: root)

        let model = AppModel(
            clipboard: ClipboardStore(),
            applicationIndex: ApplicationIndex(roots: [root])
        )

        model.query = "safari"
        if case .applications(_, _, _, let isSearching) = model.state.content {
            XCTAssertTrue(isSearching)
        } else {
            XCTFail("Expected a pending application search")
        }

        for _ in 0..<200 {
            if !model.isIndexing, model.state.content.isSettledForExperienceMetrics { break }
            try await Task.sleep(for: .milliseconds(15))
        }

        XCTAssertFalse(model.isIndexing)
        XCTAssertTrue(model.state.content.isSettledForExperienceMetrics)
        XCTAssertTrue(model.filteredApplications.contains {
            $0.name.localizedCaseInsensitiveContains("safari")
        })
    }

    @MainActor
    func testStaleAsynchronousResultCannotReplaceTheLatestImmediateQuery() async throws {
        let model = AppModel(clipboard: ClipboardStore())

        model.query = "unicode arrow"
        model.query = "12 + 2"
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(model.calculation, "14")
        XCTAssertEqual(model.state.query, "12 + 2")
        XCTAssertEqual(model.contentKind, .calculation)
    }

    func testFunctionPlotIsComputedOutsideTheView() async throws {
        let expression = try XCTUnwrap(MathExpression("y=sinx"))
        let generated = await FunctionPlotter.plot(expression)
        let plot = try XCTUnwrap(generated)

        XCTAssertGreaterThan(plot.samples.count, 100)
        XCTAssertLessThan(plot.minimumY, 0)
        XCTAssertGreaterThan(plot.maximumY, 0)
    }

    private func makeApplication(
        named name: String,
        bundleIdentifier: String,
        in root: URL
    ) throws {
        let contents = root
            .appendingPathComponent("\(name).app")
            .appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
