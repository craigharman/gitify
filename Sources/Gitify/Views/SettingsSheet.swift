import SwiftUI
import GitKit

/// Repository settings: the committer identity (git user.name / user.email), editable for
/// this repository or globally.
struct SettingsSheet: View {
    let viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var global = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "gearshape.fill").font(.system(size: 30)).foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository Settings").font(.title2.bold())
                    Text("The identity used for new commits.").foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                Picker("Apply to", selection: $global) {
                    Text("This Repository").tag(false)
                    Text("Global (all repositories)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
            .formStyle(.grouped)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if !name.isEmpty { await viewModel.setConfigValue("user.name", name, global: global) }
                        if !email.isEmpty { await viewModel.setConfigValue("user.email", email, global: global) }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 360)
        .task {
            guard !loaded else { return }
            loaded = true
            name = await viewModel.configValue("user.name") ?? ""
            email = await viewModel.configValue("user.email") ?? ""
        }
    }
}
