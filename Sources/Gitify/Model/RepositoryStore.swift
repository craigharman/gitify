import Foundation

/// Persists the list of added repositories to Application Support as JSON.
struct RepositoryStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gitify", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("repositories.json")
    }

    func load() -> [RepositoryRef] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RepositoryRef].self, from: data)) ?? []
    }

    func save(_ repositories: [RepositoryRef]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(repositories) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
