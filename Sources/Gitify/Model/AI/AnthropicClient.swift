import Foundation

/// Anthropic Messages API client with streaming and tool-use support.
struct AnthropicClient: AIClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func stream(
        messages: [AIMessage],
        systemPrompt: String,
        tools: [AIToolDefinition],
        model: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, systemPrompt: systemPrompt,
                                                   tools: tools, model: model)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIClientError(message: "No response from Anthropic.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // Read error body.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIClientError(message: "Anthropic returned HTTP \(http.statusCode): \(body)")
                    }
                    try await parseStream(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private func buildRequest(
        messages: [AIMessage], systemPrompt: String,
        tools: [AIToolDefinition], model: String
    ) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": systemPrompt,
            "messages": messages.map(encodeMessage),
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { $0.anthropicJSON() }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encodeMessage(_ message: AIMessage) -> [String: Any] {
        switch message.role {
        case .user:
            // User messages with tool results use the Anthropic content-array format.
            let hasToolResult = message.content.contains {
                if case .toolResult = $0 { return true }
                return false
            }
            if hasToolResult {
                return [
                    "role": "user",
                    "content": message.content.map(encodeContentBlock),
                ]
            }
            let text = message.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined()
            return ["role": "user", "content": text]

        case .assistant:
            let blocks = message.content.map(encodeContentBlock)
            return ["role": "assistant", "content": blocks]

        case .tool:
            // Tool results are sent as user messages with tool_result content blocks.
            return [
                "role": "user",
                "content": message.content.map(encodeContentBlock),
            ]

        case .system:
            return ["role": "user", "content": ""]
        }
    }

    private func encodeContentBlock(_ block: AIContentBlock) -> [String: Any] {
        switch block {
        case .text(let text):
            return ["type": "text", "text": text]
        case .toolCall(let call):
            let input = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) ?? [:]
            return [
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                "input": input,
            ]
        case .toolResult(let callID, let content):
            return [
                "type": "tool_result",
                "tool_use_id": callID,
                "content": content,
            ]
        }
    }

    // MARK: - Stream parsing

    private func parseStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        // Accumulators for tool calls being built across deltas.
        var currentToolID: String?
        var currentToolName: String?
        var currentToolArgs = ""

        for try await line in bytes.lines {
            guard let data = SSEParser.dataPayload(from: line) else { continue }
            if data == "[DONE]" { break }

            guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any],
                   block["type"] as? String == "tool_use" {
                    currentToolID = block["id"] as? String
                    currentToolName = block["name"] as? String
                    currentToolArgs = ""
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    let deltaType = delta["type"] as? String ?? ""
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        continuation.yield(.textDelta(text))
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        currentToolArgs += partial
                    }
                }

            case "content_block_stop":
                if let id = currentToolID, let name = currentToolName {
                    let call = AIToolCall(id: id, name: name, arguments: currentToolArgs)
                    continuation.yield(.toolCall(call))
                    currentToolID = nil
                    currentToolName = nil
                    currentToolArgs = ""
                }

            case "message_stop":
                continuation.yield(.done)

            case "error":
                if let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    throw AIClientError(message: "Anthropic error: \(msg)")
                }

            default:
                break
            }
        }
    }
}

struct AIClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
