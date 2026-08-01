import AppKit
import Foundation

final class ApplicationIndex {
    func load() async -> [ApplicationRecord] {
        await Task.detached(priority: .userInitiated) {
            Self.scanApplications()
        }.value
    }

    private static func scanApplications() -> [ApplicationRecord] {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let roots = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                home.appendingPathComponent("Applications")
            ]
            var seen = Set<String>()
            var records: [ApplicationRecord] = []
            let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey, .nameKey]

            for root in roots where FileManager.default.fileExists(atPath: root.path) {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let url as URL in enumerator where url.pathExtension == "app" {
                    let parentComponents = url.deletingLastPathComponent().pathComponents
                    guard !parentComponents.contains(where: { $0.hasSuffix(".app") }) else { continue }
                    let path = url.standardizedFileURL.path
                    guard seen.insert(path).inserted else { continue }
                    let bundle = Bundle(url: url)
                    let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    let fallback = url.deletingPathExtension().lastPathComponent
                    records.append(ApplicationRecord(
                        url: url,
                        name: displayName ?? bundleName ?? fallback,
                        bundleIdentifier: bundle?.bundleIdentifier
                    ))
                }
            }

        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func launch(_ application: ApplicationRecord) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
    }
}
