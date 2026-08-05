import AppKit
import CryptoKit
import Foundation

struct RiffUpdateRelease: Equatable, Sendable {
    let tagName: String

    var zipURL: URL {
        URL(
            string: "https://github.com/Rhythmicc/Riff/releases/download/\(tagName)/Riff-\(tagName)-macOS-universal.zip"
        )!
    }

    var checksumURL: URL {
        URL(string: zipURL.absoluteString + ".sha256")!
    }
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case releaseUnavailable
    case checksumMissing
    case checksumMismatch
    case downloadFailed
    case extractionFailed(String)
    case invalidBundle
    case versionMismatch(expected: String, found: String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无法访问 GitHub Releases（网络或响应异常）"
        case .releaseUnavailable:
            return "没有找到可用的发布版本"
        case .checksumMissing:
            return "发布缺少 SHA-256 校验文件，已停止更新"
        case .checksumMismatch:
            return "下载文件校验失败，已丢弃并停止更新"
        case .downloadFailed:
            return "下载安装包失败"
        case .extractionFailed(let detail):
            return "解压安装包失败：\(detail)"
        case .invalidBundle:
            return "下载的 App 无法验证（Bundle 或签名异常）"
        case .versionMismatch(let expected, let found):
            return "下载的版本 \(found) 与发布 \(expected) 不一致"
        case .installFailed(let detail):
            return "安装失败：\(detail)"
        }
    }
}

/// Checks GitHub Releases for a newer Riff build, downloads the Universal 2
/// zip, verifies its SHA-256 and bundle signature, then replaces the running
/// app bundle and relaunches it.
///
/// The latest tag is discovered through GitHub's `/releases/latest` redirect
/// and assets are downloaded from plain release URLs, so the updater never
/// depends on the rate-limited REST API.
@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case available(release: RiffUpdateRelease)
        case downloading(release: RiffUpdateRelease)
        case installing(release: RiffUpdateRelease)
        case failed(message: String)
    }

    static let latestRedirectURL = URL(
        string: "https://github.com/Rhythmicc/Riff/releases/latest"
    )!

    @Published private(set) var state: State = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func checkForUpdates() async {
        guard state != .checking else { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            if Self.isNewer(release.tagName, than: currentVersion) {
                state = .available(release: release)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func downloadAndInstall(_ release: RiffUpdateRelease) async {
        guard state == .available(release: release) else { return }
        state = .downloading(release: release)
        do {
            let stagedApp = try await downloadAndValidate(release)
            state = .installing(release: release)
            try installAndRelaunch(from: stagedApp, release: release)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Version comparison

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = versionComponents(candidate)
        let currentComponents = versionComponents(current)
        let count = max(candidateComponents.count, currentComponents.count)
        for index in 0..<count {
            let candidateValue = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    nonisolated static func versionComponents(_ version: String) -> [Int] {
        let trimmed = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        return trimmed
            .split(separator: ".")
            .prefix(3)
            .compactMap { component in
                Int(component.prefix(while: \.isNumber))
            }
    }

    nonisolated static func tagName(fromLatestRedirectURL url: URL) -> String? {
        let path = url.path
        guard path.contains("/releases/tag/") else { return nil }
        return url.lastPathComponent
    }

    nonisolated static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Update pipeline

    private func fetchLatestRelease() async throws -> RiffUpdateRelease {
        var request = URLRequest(url: Self.latestRedirectURL)
        request.setValue("Riff-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard http.statusCode == 200,
              let finalURL = http.url,
              let tag = Self.tagName(fromLatestRedirectURL: finalURL) else {
            throw AppUpdateError.releaseUnavailable
        }
        return RiffUpdateRelease(tagName: tag)
    }

    private func downloadAndValidate(_ release: RiffUpdateRelease) async throws -> URL {
        let updatesDirectory = try updatesDirectory()
        try? FileManager.default.removeItem(at: updatesDirectory)
        try FileManager.default.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true
        )

        let expectedChecksum = try await downloadString(from: release.checksumURL)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        guard !expectedChecksum.isEmpty else { throw AppUpdateError.checksumMismatch }

        let zipURL = updatesDirectory.appendingPathComponent("Riff-\(release.tagName)-macOS-universal.zip")
        let (zipData, zipResponse) = try await URLSession.shared.data(from: release.zipURL)
        guard let http = zipResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.downloadFailed
        }
        try zipData.write(to: zipURL, options: .atomic)

        let actualChecksum = Self.sha256Hex(of: zipData)
        guard actualChecksum.lowercased() == expectedChecksum.lowercased() else {
            throw AppUpdateError.checksumMismatch
        }

        let stagedDirectory = updatesDirectory.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagedDirectory,
            withIntermediateDirectories: true
        )
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, stagedDirectory.path])

        let stagedApp = stagedDirectory.appendingPathComponent("Riff.app")
        try validate(stagedApp: stagedApp, release: release)
        return stagedApp
    }

    private func downloadString(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.downloadFailed
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func validate(stagedApp: URL, release: RiffUpdateRelease) throws {
        guard let bundle = Bundle(url: stagedApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw AppUpdateError.invalidBundle
        }
        let stagedVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        let expectedVersion = release.tagName.replacingOccurrences(
            of: "^[vV]",
            with: "",
            options: .regularExpression
        )
        guard stagedVersion == expectedVersion else {
            throw AppUpdateError.versionMismatch(expected: expectedVersion, found: stagedVersion)
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedApp.path])
    }

    private func installAndRelaunch(from stagedApp: URL, release: RiffUpdateRelease) throws {
        let updatesDirectory = try updatesDirectory()
        let scriptURL = updatesDirectory.appendingPathComponent("install-\(release.tagName).sh")
        let target = Bundle.main.bundleURL.path
        let escapedStaged = stagedApp.path.replacingOccurrences(of: "'", with: "'\\''")
        let backupName = "Riff-\(release.tagName)-old.app"
        let script = """
        #!/bin/zsh
        set -e
        TARGET="\(target)"
        STAGED='\(escapedStaged)'
        for _ in {1..75}; do
          if ! pgrep -x Riff >/dev/null 2>&1; then break; fi
          sleep 0.2
        done
        pkill -x Riff 2>/dev/null || true
        sleep 0.3
        if [[ -d "$TARGET" ]]; then
          mv "$TARGET" "$HOME/.Trash/\(backupName)" 2>/dev/null || rm -rf "$TARGET"
        fi
        cp -R "$STAGED" "$TARGET"
        open "$TARGET"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private func updatesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let riff = base.appendingPathComponent("Riff", isDirectory: true)
        let updates = riff.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
        return updates
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: output, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.extractionFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
