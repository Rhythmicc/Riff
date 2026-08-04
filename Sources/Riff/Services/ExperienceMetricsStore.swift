import Combine
import Foundation

struct ExperienceMetricDistribution: Codable, Equatable, Sendable {
    static let sampleLimit = 200

    private(set) var samples: [Double] = []

    mutating func append(milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        samples.append(min(milliseconds, 60_000))
        if samples.count > Self.sampleLimit {
            samples.removeFirst(samples.count - Self.sampleLimit)
        }
    }

    var p95: Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }
}

struct ExperienceMetricsSnapshot: Codable, Equatable, Sendable {
    var launcherSessions = 0
    var successfulSessions = 0
    var abandonedSessions = 0
    var repeatedPresentationAttempts = 0
    var queriesStarted = 0
    var zeroResultQueries = 0
    var focusReady = ExperienceMetricDistribution()
    var firstInput = ExperienceMetricDistribution()
    var queryResolution = ExperienceMetricDistribution()

    var completionRate: Double? {
        let finished = successfulSessions + abandonedSessions
        guard finished > 0 else { return nil }
        return Double(successfulSessions) / Double(finished)
    }
}

/// Stores only bounded numeric aggregates in UserDefaults. Query text, selected
/// application names, clipboard contents, and note/translation text never cross
/// this boundary.
@MainActor
final class ExperienceMetricsStore: ObservableObject {
    typealias Clock = () -> TimeInterval

    @Published private(set) var snapshot: ExperienceMetricsSnapshot

    private let defaults: UserDefaults
    private let storageKey: String
    private let clock: Clock
    private var activeSessionStartedAt: TimeInterval?
    private var didRecordFocus = false
    private var didRecordFirstInput = false
    private var querySequence: UInt64 = 0
    private var activeQuery: (token: UInt64, startedAt: TimeInterval)?
    private var persistenceTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "experience.metrics.v1",
        clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.clock = clock
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ExperienceMetricsSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = ExperienceMetricsSnapshot()
        }
    }

    deinit {
        persistenceTask?.cancel()
    }

    func beginLauncherSession() {
        guard activeSessionStartedAt == nil else {
            snapshot.repeatedPresentationAttempts += 1
            schedulePersistence()
            return
        }
        activeSessionStartedAt = clock()
        didRecordFocus = false
        didRecordFirstInput = false
        activeQuery = nil
        snapshot.launcherSessions += 1
        schedulePersistence()
    }

    func markLauncherFocusReady() {
        guard let startedAt = activeSessionStartedAt, !didRecordFocus else { return }
        didRecordFocus = true
        snapshot.focusReady.append(milliseconds: elapsedMilliseconds(since: startedAt))
        schedulePersistence()
    }

    func markFirstInput() {
        guard let startedAt = activeSessionStartedAt, !didRecordFirstInput else { return }
        didRecordFirstInput = true
        snapshot.firstInput.append(milliseconds: elapsedMilliseconds(since: startedAt))
        schedulePersistence()
    }

    func beginQuery() -> UInt64 {
        querySequence &+= 1
        let token = querySequence
        activeQuery = (token, clock())
        snapshot.queriesStarted += 1
        schedulePersistence()
        return token
    }

    func cancelActiveQuery() {
        activeQuery = nil
    }

    func resolveQuery(token: UInt64, producedResults: Bool) {
        guard let activeQuery, activeQuery.token == token else { return }
        snapshot.queryResolution.append(
            milliseconds: elapsedMilliseconds(since: activeQuery.startedAt)
        )
        if !producedResults { snapshot.zeroResultQueries += 1 }
        self.activeQuery = nil
        schedulePersistence()
    }

    func completeLauncherSession() {
        guard activeSessionStartedAt != nil else { return }
        snapshot.successfulSessions += 1
        endSession()
    }

    func abandonLauncherSession() {
        guard activeSessionStartedAt != nil else { return }
        snapshot.abandonedSessions += 1
        endSession()
    }

    func reset() {
        snapshot = ExperienceMetricsSnapshot()
        activeSessionStartedAt = nil
        activeQuery = nil
        didRecordFocus = false
        didRecordFirstInput = false
        persistenceTask?.cancel()
        defaults.removeObject(forKey: storageKey)
    }

    func flush() {
        persistenceTask?.cancel()
        persist()
    }

    var diagnosticSummary: String {
        let completion = snapshot.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        return [
            "Riff 本地体验指标",
            "启动器会话：\(snapshot.launcherSessions)",
            "成功 / 放弃：\(snapshot.successfulSessions) / \(snapshot.abandonedSessions)",
            "完成率：\(completion)",
            "焦点就绪 P95：\(Self.formatted(snapshot.focusReady.p95))",
            "首次输入 P95：\(Self.formatted(snapshot.firstInput.p95))",
            "查询响应 P95：\(Self.formatted(snapshot.queryResolution.p95))",
            "零结果查询：\(snapshot.zeroResultQueries) / \(snapshot.queriesStarted)",
            "重复展示尝试：\(snapshot.repeatedPresentationAttempts)",
            "仅包含本机聚合数值，不包含查询或用户内容。"
        ].joined(separator: "\n")
    }

    static func formatted(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "尚无数据" }
        if milliseconds < 1_000 { return "\(Int(milliseconds.rounded())) ms" }
        return String(format: "%.2f s", milliseconds / 1_000)
    }

    private func endSession() {
        activeSessionStartedAt = nil
        activeQuery = nil
        didRecordFocus = false
        didRecordFirstInput = false
        schedulePersistence()
    }

    private func elapsedMilliseconds(since startedAt: TimeInterval) -> Double {
        max(0, clock() - startedAt) * 1_000
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
