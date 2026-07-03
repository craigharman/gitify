import Foundation

/// A tool call requested by the AI.
struct AIToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String  // JSON string
}

/// Events emitted while streaming an AI response.
enum AIStreamEvent: Sendable {
    /// A fragment of assistant text.
    case textDelta(String)
    /// The AI is requesting a tool call. The full arguments JSON is assembled from deltas
    /// before this event fires.
    case toolCall(AIToolCall)
    /// The response is complete (no more events).
    case done
}

/// Role of a message in the conversation.
enum AIRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// A single content block within a message.
enum AIContentBlock: Sendable {
    case text(String)
    case toolCall(AIToolCall)
    case toolResult(toolCallID: String, content: String)
}

/// A message in the conversation history, suitable for sending to either provider.
struct AIMessage: Sendable {
    let role: AIRole
    let content: [AIContentBlock]

    static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)])
    }

    static func assistantToolCalls(_ calls: [AIToolCall], text: String = "") -> AIMessage {
        var blocks: [AIContentBlock] = []
        if !text.isEmpty { blocks.append(.text(text)) }
        blocks.append(contentsOf: calls.map { .toolCall($0) })
        return AIMessage(role: .assistant, content: blocks)
    }

    static func toolResult(callID: String, content: String) -> AIMessage {
        AIMessage(role: .tool, content: [.toolResult(toolCallID: callID, content: content)])
    }
}

/// A tool definition to expose to the AI. Marked `@unchecked Sendable` because the
/// parameters dictionary is set once at init and never mutated.
struct AIToolDefinition: @unchecked Sendable {
    let name: String
    let description: String
    /// JSON Schema object describing the parameters (as a dictionary).
    let parameters: [String: Any]

    /// Converts to the Anthropic tool format.
    func anthropicJSON() -> [String: Any] {
        ["name": name, "description": description, "input_schema": parameters]
    }

    /// Converts to the OpenAI function-calling format.
    func openAIJSON() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ] as [String: Any],
        ]
    }
}

/// Protocol for AI provider clients. Implementations must be `Sendable` for use with
/// Swift 6 strict concurrency.
protocol AIClient: Sendable {
    /// Sends a conversation and streams back events. The caller is responsible for the
    /// tool-use loop (executing tool calls and re-sending with results).
    func stream(
        messages: [AIMessage],
        systemPrompt: String,
        tools: [AIToolDefinition],
        model: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}

// MARK: - SSE line parsing

/// Extracts the payload from a Server-Sent Events `data:` line.
/// Returns nil for comment lines, empty lines, or non-data fields.
enum SSEParser {
    static func dataPayload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5)
        // Trim a single leading space per the SSE spec.
        if payload.hasPrefix(" ") {
            return String(payload.dropFirst())
        }
        return String(payload)
    }
}
