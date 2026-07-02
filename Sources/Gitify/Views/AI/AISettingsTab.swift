import SwiftUI

/// AI configuration tab for the app settings window. Lets the user choose a provider,
/// enter an API key, and select a model.
struct AISettingsTab: View {
    @State private var provider: AIProvider = AIDefaults.provider
    @State private var apiKey: String = ""
    @State private var modelID: String = AIDefaults.modelID
    @State private var hasKey = false

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
                        }
                        .controlSize(.small)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Picker("Model", selection: $modelID) {
                ForEach(provider.models) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: provider) { _, newValue in
            AIDefaults.provider = newValue
            // Reset model to the new provider's default if the current one doesn't belong.
            if !newValue.models.contains(where: { $0.id == modelID }) {
                modelID = newValue.defaultModel.id
            }
            // Refresh key state for the new provider.
            hasKey = AIDefaults.apiKey(for: newValue) != nil
        }
        .onChange(of: modelID) { _, newValue in
            AIDefaults.modelID = newValue
        }
        .onAppear {
            hasKey = AIDefaults.apiKey(for: provider) != nil
        }
    }
}
