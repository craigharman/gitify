import Foundation
import GitKit

/// A single message displayed in the AI assistant chat.
struct ChatMessage: Identifiable {
    enum Role { case user, assistant, toolCall, toolResult }

    let id = UUID()
    let role: Role
    var text: String
    /// For tool-call messages: the tool name.
    var toolName: String?
    /// For tool-result messages: the result content.
    var toolResultContent: String?
    let timestamp = Date()
}

/// Manages the AI assistant conversation, including streaming responses and the tool-use
/// loop. Each instance is scoped to a single repository.
@MainActor
@Observable
final class AIAssistantViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    private(set) var isStreaming = false
    private(set) var error: String?

    private let viewModel: RepositoryViewModel
    private let toolExecutor: AIToolExecutor
    /// The full message history sent to the API (not the same as `messages`, which is for display).
    private var conversationHistory: [AIMessage] = []
    private var streamTask: Task<Void, Never>?

    /// Maximum consecutive tool-call rounds before stopping.
    private static let maxToolRounds = 10

    init(viewModel: RepositoryViewModel) {
        self.viewModel = viewModel
        self.toolExecutor = AIToolExecutor(viewModel: viewModel)
    }

    /// Sends the current input as a user message and streams the AI response.
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        error = nil

        messages.append(ChatMessage(role: .user, text: text))
        conversationHistory.append(.user(text))

        streamTask = Task { await streamResponse() }
    }

    /// Cancels the in-flight stream.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// Clears the conversation.
    func clear() {
        stop()
        messages.removeAll()
        conversationHistory.removeAll()
        error = nil
    }

    // MARK: - Streaming + tool-use loop

    private func streamResponse() async {
        guard let client = makeClient() else {
            error = "No API key configured. Open Settings \u{2192} AI to add one."
            return
        }

        guard let model = AIDefaults.model else {
            error = "No model selected. Open Settings \u{2192} AI to choose one."
            return
        }
        let systemPrompt = buildSystemPrompt()
        let tools = AIToolDefinitions.all

        isStreaming = true
        defer { isStreaming = false }

        var toolRounds = 0

        // Loop: stream a response, execute any tool calls, re-send with results.
        while toolRounds < Self.maxToolRounds {
            // Add a placeholder assistant message for streaming text into.
            let assistantIndex = messages.count
            messages.append(ChatMessage(role: .assistant, text: ""))

            var accumulatedText = ""
            var pendingToolCalls: [AIToolCall] = []

            do {
                let stream = client.stream(
                    messages: conversationHistory,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    model: model.id
                )

                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .textDelta(let delta):
                        accumulatedText += delta
                        messages[assistantIndex].text = accumulatedText
                    case .toolCall(let call):
                        pendingToolCalls.append(call)
                    case .done:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    // Remove empty assistant message if nothing was streamed.
                    if accumulatedText.isEmpty {
                        messages.remove(at: assistantIndex)
                    }
                }
                return
            }

            // If no tool calls, we're done.
            if pendingToolCalls.isEmpty {
                // Record the assistant's text in conversation history.
                if !accumulatedText.isEmpty {
                    conversationHistory.append(.assistant(accumulatedText))
                }
                return
            }

            // Record the assistant's response (text + tool calls) in history.
            conversationHistory.append(.assistantToolCalls(pendingToolCalls, text: accumulatedText))

            // Execute each tool call and send results back.
            for call in pendingToolCalls {
                // Show the tool call in the chat.
                messages.append(ChatMessage(role: .toolCall, text: call.name, toolName: call.name))

                let result = await toolExecutor.execute(name: call.name, arguments: call.arguments)

                // Show the tool result.
                messages.append(ChatMessage(role: .toolResult, text: result,
                                            toolName: call.name, toolResultContent: result))

                // Add to conversation history.
                conversationHistory.append(.toolResult(callID: call.id, content: result))
            }

            toolRounds += 1
        }

        // If we hit the cap, let the user know.
        if toolRounds >= Self.maxToolRounds {
            messages.append(ChatMessage(role: .assistant,
                                        text: "Reached the maximum number of tool calls (\(Self.maxToolRounds)). Please continue the conversation if more steps are needed."))
        }
    }

    // MARK: - Helpers

    private func makeClient() -> (any AIClient)? {
        let provider = AIDefaults.provider
        guard let key = AIDefaults.apiKey(for: provider), !key.isEmpty else { return nil }
        switch provider {
        case .anthropic: return AnthropicClient(apiKey: key)
        case .openAI: return OpenAIClient(apiKey: key)
        }
    }

    private func buildSystemPrompt() -> String {
        var prompt = """
        You are a Git expert assistant integrated into Gitify, a macOS Git client. \
        You help the user with Git operations on their repository.

        You have access to tools that let you read repository state and perform Git operations. \
        Always use the tools to check the current state before making changes. \
        For destructive operations (merge, rebase, reset, force push), explain what you are \
        about to do and why before executing the tool call.

        Keep responses concise and focused on the Git task at hand.
        """

        // Add current repo context if available.
        if let status = viewModel.status {
            prompt += "\n\nCurrent repository context:"
            prompt += "\n- Branch: \(status.branch ?? "(detached HEAD)")"
            if let upstream = status.upstream {
                prompt += "\n- Upstream: \(upstream)"
                if status.ahead > 0 { prompt += " (ahead \(status.ahead))" }
                if status.behind > 0 { prompt += " (behind \(status.behind))" }
            }
            let changeCount = status.files.count
            if changeCount > 0 {
                prompt += "\n- \(changeCount) changed file\(changeCount == 1 ? "" : "s") in working tree"
            } else {
                prompt += "\n- Working tree clean"
            }
        }

        return prompt
    }
}
