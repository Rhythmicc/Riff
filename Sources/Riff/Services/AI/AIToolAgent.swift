import Foundation

/// Provider-agnostic tool loop: streams a round, executes requested local
/// tools, feeds results back, and repeats up to `maxRounds`.
struct AIToolAgent: Sendable {
    let transport: any AITransport
    let tools: [RiffTool]
    let maxRounds: Int

    init(
        transport: any AITransport,
        tools: [RiffTool],
        maxRounds: Int = 4
    ) {
        self.transport = transport
        self.tools = tools
        self.maxRounds = maxRounds
    }

    func run(
        model: String,
        initialMessages: [ConversationMessage],
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var messages = initialMessages
        var finalText = ""

        for _ in 0..<maxRounds {
            try Task.checkCancellation()
            let request = AIRequest(
                model: model,
                messages: messages,
                tools: tools,
                temperature: 0.2,
                maxOutputTokens: 1024
            )
            let result = try await transport.stream(request) { event in
                if case .text(let delta) = event {
                    await onDelta(delta)
                }
            }
            finalText += result.text
            guard !result.toolCalls.isEmpty else {
                return finalText.isEmpty ? result.text : finalText
            }

            var outputs: [String] = []
            for call in result.toolCalls {
                try Task.checkCancellation()
                if let tool = tools.first(where: { $0.name == call.name }) {
                    let arguments = (try? JSONSerialization.jsonObject(
                        with: Data(call.arguments.utf8)
                    )) as? [String: Any] ?? [:]
                    do {
                        outputs.append(try await tool.execute(arguments))
                    } catch {
                        outputs.append("工具执行失败：\(error.localizedDescription)")
                    }
                } else {
                    outputs.append("没有名为 \(call.name) 的本地工具")
                }
            }
            messages = transport.format.appendingToolRound(
                to: messages,
                calls: result.toolCalls,
                outputs: outputs
            )
        }
        throw AIServiceError.server("工具调用轮次过多，已停止")
    }
}
