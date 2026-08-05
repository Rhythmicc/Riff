import Foundation

/// Presents an installed script component through the native `RiffComponent`
/// protocol. The launcher and settings never see the process protocol.
struct ScriptComponentAdapter: RiffComponent {
    let installed: InstalledComponent

    var id: String { installed.id }

    var descriptor: ComponentDescriptor {
        installed.manifest.descriptor
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        guard mode == .apps else { return nil }
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        let canUsePrefix = normalized.unicodeScalars.contains {
            $0.properties.isIdeographic
        } || normalized.count >= 2
        for keyword in descriptor.keywords {
            let keyword = keyword.lowercased()
            if normalized == keyword
                || (canUsePrefix && keyword.hasPrefix(normalized))
                || normalized.hasPrefix(keyword + " ")
                || normalized.hasSuffix(" " + keyword) {
                return 30
            }
        }
        return nil
    }

    func results(for query: String) async throws -> ComponentResults {
        try await host.query(query)
    }

    func perform(_ action: ComponentAction) async throws {
        switch action {
        case .callback(let id, let payload):
            _ = try await host.perform(
                actionID: id,
                itemID: payload["item_id"] ?? ""
            )
        case .copy, .openURL, .openPanel:
            break
        }
    }

    private var host: ScriptComponentHost {
        ScriptComponentHost(
            executableURL: installed.executableURL,
            timeout: Double(installed.manifest.timeoutMs) / 1000.0
        )
    }
}
