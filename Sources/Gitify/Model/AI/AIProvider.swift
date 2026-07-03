import Foundation

/// Supported AI providers for the Git assistant.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    /// Fetches available models from the provider's API.
    func fetchModels(apiKey: String) async throws -> [AIModel] {
        switch self {
        case .anthropic: try await Self.fetchAnthropicModels(apiKey: apiKey)
        case .openAI: try await Self.fetchOpenAIModels(apiKey: apiKey)
        }
    }

    // MARK: - Anthropic

    private static func fetchAnthropicModels(apiKey: String) async throws -> [AIModel] {
        var all: [AIModel] = []
        var afterID: String?

        // Paginate through all models.
        while true {
            var urlString = "https://api.anthropic.com/v1/models?limit=100"
            if let after = afterID { urlString += "&after_id=\(after)" }
            guard let url = URL(string: urlString) else { break }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let http = response as? HTTPURLResponse
                throw AIClientError(message: "Anthropic returned HTTP \(http?.statusCode ?? 0) when listing models.")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else { break }

            for item in items {
                guard let id = item["id"] as? String else { continue }
                let displayName = item["display_name"] as? String ?? id
                all.append(AIModel(id: id, displayName: displayName, provider: .anthropic))
            }

            let hasMore = json["has_more"] as? Bool ?? false
            if hasMore, let lastID = json["last_id"] as? String {
                afterID = lastID
            } else {
                break
            }
        }

        return all
    }

    // MARK: - OpenAI

    /// Prefixes that indicate a chat-capable OpenAI model.
    private static let openAIChatPrefixes = ["gpt-", "o1-", "o3-", "o4-", "chatgpt-"]

    private static func fetchOpenAIModels(apiKey: String) async throws -> [AIModel] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw AIClientError(message: "Invalid OpenAI URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw AIClientError(message: "OpenAI returned HTTP \(http?.statusCode ?? 0) when listing models.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }

        // Filter to chat-capable models and sort alphabetically.
        return items.compactMap { item -> AIModel? in
            guard let id = item["id"] as? String else { return nil }
            let isChatModel = openAIChatPrefixes.contains { id.hasPrefix($0) }
            guard isChatModel else { return nil }
            // Skip fine-tuned models (contain ":ft-" or "::" patterns).
            if id.contains(":ft-") || id.contains("::") { return nil }
            return AIModel(id: id, displayName: id, provider: .openAI)
        }.sorted { $0.id < $1.id }
    }
}

/// An AI model that can be used with the assistant.
struct AIModel: Identifiable, Hashable {
    let id: String          // API model identifier (e.g. "claude-sonnet-4-20250514")
    let displayName: String // Human-readable name
    let provider: AIProvider
}

/// UserDefaults accessors for AI assistant preferences.
enum AIDefaults {
    private static let providerKey = "ai.provider"
    private static let modelKey = "ai.model"

    static var provider: AIProvider {
        get {
            UserDefaults.standard.string(forKey: providerKey)
                .flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
        }
    }

    static var modelID: String {
        get {
            UserDefaults.standard.string(forKey: modelKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
        }
    }

    /// Resolves the selected model. Returns an AIModel with the stored ID,
    /// or nil if no model has been selected yet.
    static var model: AIModel? {
        let id = modelID
        guard !id.isEmpty else { return nil }
        return AIModel(id: id, displayName: id, provider: provider)
    }

    // MARK: - Hide AI features

    private static let hideKey = "ai.hidden"

    static var hideAIFeatures: Bool {
        get { UserDefaults.standard.bool(forKey: hideKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideKey) }
    }

    /// True when an API key is configured for the current provider.
    static var hasAPIKey: Bool {
        apiKey(for: provider) != nil
    }

    // MARK: - Keychain (API keys)

    private static let keychainService = "com.gitify.ai"

    static func apiKey(for provider: AIProvider) -> String? {
        Keychain.get(account: provider.rawValue, service: keychainService)
    }

    static func setAPIKey(_ key: String, for provider: AIProvider) {
        Keychain.set(key, account: provider.rawValue, service: keychainService)
    }

    static func removeAPIKey(for provider: AIProvider) {
        Keychain.delete(account: provider.rawValue, service: keychainService)
    }
}
