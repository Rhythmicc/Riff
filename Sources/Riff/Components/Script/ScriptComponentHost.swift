import Foundation

enum ScriptComponentHostError: LocalizedError {
    case launchFailed
    case timeout
    case invalidResponse
    case outputTooLarge
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "无法启动组件进程"
        case .timeout:
            return "组件响应超时"
        case .invalidResponse:
            return "组件返回了无法识别的内容"
        case .outputTooLarge:
            return "组件输出超过大小限制"
        case .actionFailed(let message):
            return message.isEmpty ? "组件动作执行失败" : message
        }
    }
}

/// Runs one script component process per request. The protocol is JSONL over
/// stdio: one request line in, one response JSON object out.
struct ScriptComponentHost: Sendable {
    let executableURL: URL
    let timeout: TimeInterval
    var maxOutputBytes = 1_048_576

    func query(_ text: String) async throws -> ComponentResults {
        let json = try await run(request: ["request": "query", "query": text])
        guard let rawItems = json["results"] as? [[String: Any]] else {
            throw ScriptComponentHostError.invalidResponse
        }
        var items: [ComponentResultItem] = []
        for (index, raw) in rawItems.enumerated() {
            guard let title = raw["title"] as? String else { continue }
            let copy = raw["copy"] as? String
            var actions: [ComponentAction] = []
            if let rawActions = raw["actions"] as? [[String: Any]] {
                for rawAction in rawActions {
                    let kind = rawAction["kind"] as? String ?? "callback"
                    let actionID = rawAction["id"] as? String ?? String(index)
                    switch kind {
                    case "copy":
                        actions.append(.copy(copy ?? title))
                    case "open":
                        if let urlString = rawAction["url"] as? String,
                           let url = URL(string: urlString) {
                            actions.append(.openURL(url))
                        }
                    default:
                        actions.append(.callback(
                            id: actionID,
                            payload: rawAction["payload"] as? [String: String] ?? [:]
                        ))
                    }
                }
            }
            items.append(ComponentResultItem(
                id: raw["id"] as? String ?? String(index),
                title: title,
                subtitle: raw["subtitle"] as? String,
                icon: (raw["icon"] as? String).map { ComponentIcon(systemName: $0) },
                actions: actions
            ))
        }
        return ComponentResults(
            items: items,
            isComplete: json["isComplete"] as? Bool ?? true
        )
    }

    func perform(actionID: String, itemID: String) async throws -> String? {
        let json = try await run(request: [
            "request": "action",
            "action_id": actionID,
            "item": ["id": itemID]
        ])
        guard json["result"] as? String == "ok" else {
            throw ScriptComponentHostError.actionFailed(
                json["error"] as? String ?? ""
            )
        }
        return json["payload"] as? String
    }

    private enum Outcome: Sendable {
        case success([String: Any])
        case failure(ScriptComponentHostError)
    }

    private func run(request: [String: Any]) async throws -> [String: Any] {
        let process = Process()
        process.executableURL = executableURL
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["RIFF_COMPONENT_ROOT"] = executableURL.deletingLastPathComponent().path
        environment["RIFF_COMPONENT_TIMEOUT"] = String(Int(timeout * 1000))
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw ScriptComponentHostError.launchFailed
        }

        if let payload = try? JSONSerialization.data(withJSONObject: request) {
            inputPipe.fileHandleForWriting.write(payload)
        }
        inputPipe.fileHandleForWriting.write(Data("\n".utf8))
        try? inputPipe.fileHandleForWriting.close()

        return try await withThrowingTaskGroup(of: Outcome.self) { group in
            group.addTask {
                var byteCount = 0
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    byteCount += line.utf8.count + 1
                    if byteCount > maxOutputBytes {
                        process.terminate()
                        return .failure(.outputTooLarge)
                    }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard let data = trimmed.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          json["results"] != nil || json["result"] != nil
                    else { continue }
                    process.terminate()
                    return .success(json)
                }
                process.terminate()
                return .failure(.invalidResponse)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                process.terminate()
                return .failure(.timeout)
            }
            guard let first = try await group.next() else {
                throw ScriptComponentHostError.invalidResponse
            }
            group.cancelAll()
            switch first {
            case .success(let json):
                return json
            case .failure(let error):
                throw error
            }
        }
    }
}
