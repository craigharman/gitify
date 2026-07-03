import SwiftUI

/// AI configuration tab for the app settings window. Lets the user choose a provider,
/// enter an API key, and select a model (fetched dynamically from the provider's API).
struct AISettingsTab: View {
    @State private var provider: AIProvider = AIDefaults.provider
    @State private var apiKey: String = ""
    @State private var modelID: String = AIDefaults.modelID
    @State private var hasKey = false
    @State private var hideAI: Bool = AIDefaults.hideAIFeatures
    @State private var availableModels: [AIModel] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Section {
                if hasKey {
                    HStack {
                        Label("API key is saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            AIDefaults.removeAPIKey(for: provider)
                            apiKey = ""
                            hasKey = false
                            availableModels = []
                            modelID = ""
                            AIDefaults.modelID = ""
                        }
                        .controlSize(.small)
                    }
                } else {
                    SecureField("API Key", text: $apiKey)
                    HStack {
                        Text("Enter your \(provider.displayName) API key. It will be stored in your Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") {
                            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            AIDefaults.setAPIKey(trimmed, for: provider)
                            hasKey = true
                            apiKey = ""
                            Task { await loadModels() }
                        }
                        .controlSize(.small)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Section {
                if isLoadingModels {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading models\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                } else if availableModels.isEmpty {
                    if let error = modelError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if hasKey {
                        Text("No models available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add an API key to see available models.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Model", selection: $modelID) {
                        ForEach(availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
            }

            Toggle("Hide AI features", isOn: $hideAI)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: provider) { _, newValue in
            AIDefaults.provider = newValue
            hasKey = AIDefaults.apiKey(for: newValue) != nil
            availableModels = []
            modelError = nil
            if hasKey {
                Task { await loadModels() }
            } else {
                modelID = ""
                AIDefaults.modelID = ""
            }
        }
        .onChange(of: modelID) { _, newValue in
            AIDefaults.modelID = newValue
        }
        .onChange(of: hideAI) { _, newValue in
            AIDefaults.hideAIFeatures = newValue
        }
        .onAppear {
            hasKey = AIDefaults.apiKey(for: provider) != nil
            if hasKey {
                Task { await loadModels() }
            }
        }
    }

    private func loadModels() async {
        guard let key = AIDefaults.apiKey(for: provider) else { return }
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }

        do {
            let models = try await provider.fetchModels(apiKey: key)
            availableModels = models

            // If the currently selected model isn't in the list, pick the first.
            if !models.contains(where: { $0.id == modelID }) {
                modelID = models.first?.id ?? ""
                AIDefaults.modelID = modelID
            }
        } catch {
            modelError = error.localizedDescription
            availableModels = []
        }
    }
}
