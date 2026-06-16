import Foundation
import AppKit
import GitKit

/// Top-level application state: the list of repositories and the current selection.
@MainActor
@Observable
final class AppModel {
    private(set) var repositories: [RepositoryRef]
    var selectedRepositoryID: RepositoryRef.ID?

    private let store = RepositoryStore()

    init() {
        repositories = store.load()
        selectedRepositoryID = repositories.first?.id
    }

    var selectedRepository: RepositoryRef? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    /// Presents an open panel and adds the chosen directory if it is a git repository.
    func promptToAddRepository() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Repository"
        panel.message = "Choose a Git repository folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await add(directory: url)
    }

    /// Adds a directory, resolving it to the repository root first.
    func add(directory: URL) async {
        guard let root = await CLIGitService.repositoryRoot(for: directory) else {
            presentError("\(url: directory) is not a Git repository.")
            return
        }
        guard !repositories.contains(where: { $0.path == root.path }) else {
            selectedRepositoryID = repositories.first { $0.path == root.path }?.id
            return
        }
        let ref = RepositoryRef(path: root.path)
        repositories.append(ref)
        store.save(repositories)
        selectedRepositoryID = ref.id
    }

    func remove(_ ref: RepositoryRef) {
        repositories.removeAll { $0.id == ref.id }
        store.save(repositories)
        if selectedRepositoryID == ref.id {
            selectedRepositoryID = repositories.first?.id
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t add repository"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension String.StringInterpolation {
    mutating func appendInterpolation(url: URL) {
        appendLiteral(url.lastPathComponent)
    }
}
