import SwiftUI

/// The AI assistant chat sheet. Presents a scrollable conversation with a text input bar.
struct AIAssistantView: View {
    @State var assistant: AIAssistantViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RepositoryViewModel) {
        _assistant = State(initialValue: AIAssistantViewModel(viewModel: viewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("AI Assistant").font(.headline)
                Spacer()
                Picker("Model", selection: Binding(
                    get: { AIDefaults.modelID },
                    set: { AIDefaults.modelID = $0 }
                )) {
                    ForEach(AIDefaults.provider.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .fixedSize()
                Button { assistant.clear() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
                .disabled(assistant.messages.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(assistant.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: assistant.messages.count) { _, _ in
                    if let last = assistant.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: assistant.messages.last?.text) { _, _ in
                    if let last = assistant.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Error banner
            if let error = assistant.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(8)
                .background(.orange.opacity(0.1))
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Ask about your repository\u{2026}", text: $assistant.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            assistant.send()
                        }
                    }

                if assistant.isStreaming {
                    Button { assistant.stop() } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop generating")
                } else {
                    Button { assistant.send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .disabled(assistant.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send message")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 620, height: 520)
    }
}

/// Renders a single chat message as a styled bubble.
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .padding(10)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }

        case .assistant:
            HStack {
                Text(LocalizedStringKey(message.text))
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
                Spacer(minLength: 60)
            }

        case .toolCall:
            ToolCallCard(name: message.toolName ?? "tool", isResult: false, content: nil)

        case .toolResult:
            ToolCallCard(name: message.toolName ?? "tool", isResult: true,
                         content: message.toolResultContent)
        }
    }
}

/// A collapsible card showing a tool call or its result.
private struct ToolCallCard: View {
    let name: String
    let isResult: Bool
    let content: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if isResult { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isResult ? "checkmark.circle.fill" : "gearshape.fill")
                        .foregroundStyle(isResult ? .green : .secondary)
                        .font(.caption)
                    Text(isResult ? "Result: \(name)" : "Calling: \(name)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if isResult, content != nil {
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let content {
                Text(content)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(20)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 4)
    }
}
