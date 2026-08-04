import XCTest
@testable import Riff

@MainActor
final class ExperienceMetricsTests: XCTestCase {
    func testSessionOutcomeAndFocusSamplesAreRecordedOnce() throws {
        let fixture = try makeFixture()
        var now: TimeInterval = 10
        let metrics = ExperienceMetricsStore(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            clock: { now }
        )

        metrics.beginLauncherSession()
        metrics.beginLauncherSession()
        now = 10.04
        metrics.markLauncherFocusReady()
        metrics.markLauncherFocusReady()
        now = 10.09
        metrics.markFirstInput()
        metrics.completeLauncherSession()
        metrics.completeLauncherSession()
        metrics.abandonLauncherSession()

        XCTAssertEqual(metrics.snapshot.launcherSessions, 1)
        XCTAssertEqual(metrics.snapshot.repeatedPresentationAttempts, 1)
        XCTAssertEqual(metrics.snapshot.successfulSessions, 1)
        XCTAssertEqual(metrics.snapshot.abandonedSessions, 0)
        XCTAssertEqual(metrics.snapshot.focusReady.samples.count, 1)
        XCTAssertEqual(metrics.snapshot.firstInput.samples.count, 1)
        XCTAssertEqual(metrics.snapshot.focusReady.p95 ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(metrics.snapshot.firstInput.p95 ?? -1, 90, accuracy: 0.001)
    }

    func testOnlyLatestQueryCanResolveAndSamplesStayBounded() throws {
        let fixture = try makeFixture()
        var now: TimeInterval = 0
        let metrics = ExperienceMetricsStore(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            clock: { now }
        )

        let stale = metrics.beginQuery()
        now = 0.01
        let latest = metrics.beginQuery()
        now = 0.02
        metrics.resolveQuery(token: stale, producedResults: true)
        XCTAssertTrue(metrics.snapshot.queryResolution.samples.isEmpty)

        now = 0.04
        metrics.resolveQuery(token: latest, producedResults: false)
        XCTAssertEqual(metrics.snapshot.queryResolution.samples.count, 1)
        XCTAssertEqual(metrics.snapshot.queryResolution.p95 ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(metrics.snapshot.zeroResultQueries, 1)

        for _ in 0..<(ExperienceMetricDistribution.sampleLimit + 25) {
            let token = metrics.beginQuery()
            now += 0.001
            metrics.resolveQuery(token: token, producedResults: true)
        }
        XCTAssertEqual(
            metrics.snapshot.queryResolution.samples.count,
            ExperienceMetricDistribution.sampleLimit
        )
    }

    func testPersistedPayloadContainsOnlyAggregateValues() throws {
        let fixture = try makeFixture()
        var now: TimeInterval = 1
        let metrics = ExperienceMetricsStore(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            clock: { now }
        )

        metrics.beginLauncherSession()
        now = 1.05
        metrics.markLauncherFocusReady()
        let token = metrics.beginQuery()
        now = 1.08
        metrics.resolveQuery(token: token, producedResults: true)
        metrics.completeLauncherSession()
        metrics.flush()

        let payload = try XCTUnwrap(fixture.defaults.data(forKey: fixture.storageKey))
        let payloadText = String(decoding: payload, as: UTF8.self)
        XCTAssertFalse(payloadText.localizedCaseInsensitiveContains("query" + "Text"))
        XCTAssertFalse(payloadText.contains("clipboard"))
        XCTAssertFalse(payloadText.contains("note"))

        let restored = ExperienceMetricsStore(
            defaults: fixture.defaults,
            storageKey: fixture.storageKey,
            clock: { now }
        )
        XCTAssertEqual(restored.snapshot, metrics.snapshot)
    }

    private func makeFixture() throws -> (
        defaults: UserDefaults,
        storageKey: String
    ) {
        let suiteName = "RiffTests.ExperienceMetrics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (defaults, "experience.metrics.test")
    }
}
