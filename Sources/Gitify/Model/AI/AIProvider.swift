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

    /// The models available for this provider.
    var models: [AIModel] {
        switch self {
        case .anthropic: AIModel.anthropicModels
        case .openAI: AIModel.openAIModels
        }
    }

    /// The default model for a newly-selected provider.
    var defaultModel: AIModel {
        models[0]
    }
}

/// An AI model that can be used with the assistant.
struct AIModel: Identifiable, Hashable {
    let id: String          // API model identifier (e.g. "claude-sonnet-4-20250514")
    let displayName: String // Human-readable name (e.g. "Claude Sonnet 4")
    let provider: AIProvider

    static let anthropicModels: [AIModel] = [
        AIModel(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", provider: .anthropic),
        AIModel(id: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku", provider: .anthropic),
    ]

    static let openAIModels: [AIModel] = [
        AIModel(id: "gpt-4o", displayName: "GPT-4o", provider: .openAI),
        AIModel(id: "gpt-4o-mini", displayName: "GPT-4o mini", provider: .openAI),
        AIModel(id: "o3-mini", displayName: "o3-mini", provider: .openAI),
    ]
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
            UserDefaults.standard.string(forKey: modelKey) ?? AIProvider.anthropic.defaultModel.id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
        }
    }

    /// Resolves the selected model, falling back to the provider's default if the stored ID
    /// doesn't match any known model (e.g. after an app update removes a model).
    static var model: AIModel {
        let id = modelID
        let prov = provider
        return prov.models.first { $0.id == id } ?? prov.defaultModel
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
