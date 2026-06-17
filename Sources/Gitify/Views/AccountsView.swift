import SwiftUI

/// Manage GitHub/GitLab accounts (token-based) and clone their repositories.
struct AccountsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: HostingAccount.ID?
    @State private var repos: [HostedRepo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var addingAccount = false

    private var selectedAccount: HostingAccount? {
        model.accounts.first { $0.id == selection }
    }
    private var filteredRepos: [HostedRepo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? repos : repos.filter { $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Accounts") {
                    ForEach(model.accounts) { account in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.login)
                                Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: account.provider == .github ? "cat.fill" : "hexagon.fill")
                        }
                        .tag(account.id)
                        .contextMenu {
                            Button("Remove Account", role: .destructive) { model.removeAccount(account) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { addingAccount = true } label: { Label("Add Account", systemImage: "plus") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(8).background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .frame(width: 760, height: 520)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $addingAccount) { AddAccountSheet(model: model) }
        .onChange(of: selection) { _, _ in Task { await loadRepos() } }
    }

    @ViewBuilder
    private var detail: some View {
        if let account = selectedAccount {
            VStack(spacing: 0) {
                SearchField(text: $search, prompt: "Filter repositories")
                if loading {
                    ProgressView("Loading repositories…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("Couldn’t Load Repositories", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    List(filteredRepos) { repo in
                        HStack {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe").foregroundStyle(.secondary)
                            Text(repo.fullName)
                            Spacer()
                            Button("Clone") {
                                Task { await model.clone(repo, account: account); dismiss() }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        } else {
            ContentUnavailableView("No Account Selected", systemImage: "person.crop.circle",
                                   description: Text("Add or select an account to browse its repositories."))
        }
    }

    private func loadRepos() async {
        guard let account = selectedAccount else { return }
        loading = true; error = nil; repos = []
        defer { loading = false }
        do { repos = try await model.repositories(for: account) }
        catch { self.error = error.localizedDescription }
    }
}

/// Sheet to add an account by pasting a personal access token.
private struct AddAccountSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var provider: HostingAccount.Provider = .github
    @State private var token = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account").font(.title2.bold())
            Picker("Provider", selection: $provider) {
                ForEach(HostingAccount.Provider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            SecureField("Personal Access Token", text: $token)
            Text("Create a token with repo read scope in your \(provider.displayName) settings. It's stored in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "Adding…" : "Add") {
                    Task {
                        working = true; error = nil
                        do { try await model.addAccount(provider: provider, token: token); dismiss() }
                        catch { self.error = error.localizedDescription }
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || working)
            }
        }
        .padding(24)
        .frame(width: 460, height: 280)
    }
}
