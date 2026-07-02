import Foundation
import GitKit

/// Generates a conventional-commit-style message from the staged diff using the configured
/// AI provider.
enum AICommitMessageGenerator {

    /// Generates a commit message for the currently staged changes.
    @MainActor
    static func generate(viewModel: RepositoryViewModel) async throws -> String {
        let provider = AIDefaults.provider
        guard let key = AIDefaults.apiKey(for: provider), !key.isEmpty else {
            throw AIClientError(message: "No API key configured for \(provider.displayName).")
        }

        guard let service = viewModel.gitService else {
            throw AIClientError(message: "Repository service is not available.")
        }

        let diffText = try await collectStagedDiff(service: service)
        guard !diffText.isEmpty else {
            throw AIClientError(message: "No staged changes to generate a message for.")
        }

        let client: any AIClient = switch provider {
        case .anthropic: AnthropicClient(apiKey: key)
        case .openAI: OpenAIClient(apiKey: key)
        }

        let systemPrompt = """
        Generate a concise conventional commit message for the following staged changes. \
        Use the format: type(optional-scope): description

        Where type is one of: feat, fix, chore, refactor, docs, style, test, perf, ci, build.

        Rules:
        - The first line must be at most 72 characters.
        - Use imperative mood (e.g. "add" not "added").
        - Do not include a body or footer unless the changes are complex enough to warrant it.
        - Return ONLY the commit message text, nothing else.
        """

        let messages: [AIMessage] = [.user(diffText)]
        let model = AIDefaults.model

        let stream = client.stream(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: [],
            model: model.id
        )

        var result = ""
        for try await event in stream {
            if case .textDelta(let delta) = event {
                result += delta
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Collects the staged diff for all staged files, truncated to a reasonable size.
    private static func collectStagedDiff(service: any GitService) async throws -> String {
        let status = try await service.status()
        let staged = status.stagedFiles

        guard !staged.isEmpty else { return "" }

        var parts: [String] = []
        var totalLength = 0
        let maxLength = 8000

        for file in staged {
            guard totalLength < maxLength else { break }
            do {
                let diff = try await service.diff(path: file.path, staged: true)
                let text = diff.hunks.map { hunk in
                    hunk.lines.map { line in
                        let prefix: String
                        switch line.kind {
                        case .addition: prefix = "+"
                        case .deletion: prefix = "-"
                        case .context: prefix = " "
                        }
                        return "\(prefix)\(line.content)"
                    }.joined(separator: "\n")
                }.joined(separator: "\n")

                if !text.isEmpty {
                    let header = "--- \(file.path) ---"
                    parts.append(header + "\n" + text)
                    totalLength += header.count + text.count
                }
            } catch {
                // Skip files whose diff can't be read (e.g. binary).
                continue
            }
        }

        if totalLength > maxLength {
            let joined = parts.joined(separator: "\n\n")
            return String(joined.prefix(maxLength)) + "\n\n[Diff truncated]"
        }

        return parts.joined(separator: "\n\n")
    }
}
