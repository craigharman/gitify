import SwiftUI

/// Browse SSH servers, discover repositories, and clone them.
/// Layout follows the same `NavigationSplitView` pattern as `AccountsView`.
struct SSHServersView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: SSHServer.ID?
    @State private var repos: [SSHRepo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var addingServer = false

    private var selectedServer: SSHServer? {
        model.sshServers.first { $0.id == selection }
    }
    private var filteredRepos: [SSHRepo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? repos : repos.filter {
            $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("SSH Servers") {
                    ForEach(model.sshServers) { server in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.label)
                                Text("\(server.user)@\(server.host)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "server.rack")
                        }
                        .tag(server.id)
                        .contextMenu {
                            Button("Remove Server", role: .destructive) {
                                model.removeSSHServer(server)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { addingServer = true } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .frame(width: 760, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $addingServer) { AddSSHServerSheet(model: model) }
        .onChange(of: selection) { _, _ in Task { await loadRepos() } }
    }

    @ViewBuilder
    private var detail: some View {
        if let server = selectedServer {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    SearchField(text: $search, prompt: "Filter repositories")
                    Button { Task { await loadRepos() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Rescan for repositories")
                    .disabled(loading)
                    .padding(.trailing, 8)
                }
                if loading {
                    ProgressView("Scanning for repositories\u{2026}")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 40)
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Couldn\u{2019}t Scan Server")
                            .font(.title3).foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repos.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 40)
                        Image(systemName: "shippingbox")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Repositories Found")
                            .font(.title3).foregroundStyle(.secondary)
                        Text("No git repositories were found under \u{201c}\(server.basePath)\u{201d}.")
                            .font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredRepos) { repo in
                        HStack {
                            Image(systemName: "shippingbox").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.name)
                                Text(repo.path)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("Open") {
                                Task { await model.openRemote(repo, server: server); dismiss() }
                            }
                            Button("Clone") {
                                Task { await model.clone(repo); dismiss() }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        } else {
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Add or select an SSH server to browse its repositories.")
            )
        }
    }

    private func loadRepos() async {
        guard let server = selectedServer else { return }
        loading = true; error = nil; repos = []
        defer { loading = false }
        do {
            repos = try await SSHScanner.discoverRepositories(server)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
