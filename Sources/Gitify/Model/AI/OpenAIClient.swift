import Foundation

/// OpenAI Chat Completions API client with streaming and function-calling support.
struct OpenAIClient: AIClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

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
                        throw AIClientError(message: "No response from OpenAI.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIClientError(message: "OpenAI returned HTTP \(http.statusCode): \(body)")
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build the OpenAI messages array with system prompt first.
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
        ]
        for msg in messages {
            apiMessages.append(contentsOf: encodeMessage(msg))
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": apiMessages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { $0.openAIJSON() }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Encodes a message for the OpenAI API. Tool results may produce multiple messages.
    private func encodeMessage(_ message: AIMessage) -> [[String: Any]] {
        switch message.role {
        case .user:
            let text = message.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined()
            return [["role": "user", "content": text]]

        case .assistant:
            var msg: [String: Any] = ["role": "assistant"]
            let texts = message.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }
            if !texts.isEmpty { msg["content"] = texts.joined() }

            let toolCalls = message.content.compactMap { block -> [String: Any]? in
                guard case .toolCall(let call) = block else { return nil }
                return [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments,
                    ] as [String: Any],
                ]
            }
            if !toolCalls.isEmpty { msg["tool_calls"] = toolCalls }
            return [msg]

        case .tool:
            return message.content.compactMap { block -> [String: Any]? in
                guard case .toolResult(let callID, let content) = block else { return nil }
                return [
                    "role": "tool",
                    "tool_call_id": callID,
                    "content": content,
                ]
            }

        case .system:
            return [["role": "system", "content": ""]]
        }
    }

    // MARK: - Stream parsing

    private func parseStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        // OpenAI streams tool calls across multiple deltas; accumulate per index.
        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            guard let data = SSEParser.dataPayload(from: line) else { continue }
            if data == "[DONE]" {
                // Flush any accumulated tool calls.
                for index in toolCallAccumulators.keys.sorted() {
                    if let acc = toolCallAccumulators[index] {
                        let call = AIToolCall(id: acc.id, name: acc.name, arguments: acc.args)
                        continuation.yield(.toolCall(call))
                    }
                }
                toolCallAccumulators.removeAll()
                continuation.yield(.done)
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let delta = choice["delta"] as? [String: Any] else { continue }

            // Text content.
            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }

            // Tool calls (function calling).
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    guard let index = tc["index"] as? Int else { continue }
                    if let id = tc["id"] as? String {
                        // Start of a new tool call.
                        let name = (tc["function"] as? [String: Any])?["name"] as? String ?? ""
                        let args = (tc["function"] as? [String: Any])?["arguments"] as? String ?? ""
                        toolCallAccumulators[index] = (id: id, name: name, args: args)
                    } else if let fn = tc["function"] as? [String: Any] {
                        // Continuation delta — append arguments.
                        if let args = fn["arguments"] as? String {
                            toolCallAccumulators[index]?.args += args
                        }
                        if let name = fn["name"] as? String, !(name.isEmpty) {
                            toolCallAccumulators[index]?.name += name
                        }
                    }
                }
            }

            // Check for finish_reason to flush tool calls.
            if let reason = choice["finish_reason"] as? String, reason == "tool_calls" {
                for index in toolCallAccumulators.keys.sorted() {
                    if let acc = toolCallAccumulators[index] {
                        let call = AIToolCall(id: acc.id, name: acc.name, arguments: acc.args)
                        continuation.yield(.toolCall(call))
                    }
                }
                toolCallAccumulators.removeAll()
            }
        }
    }
}
