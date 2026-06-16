import Foundation

/// Parses `git remote -v`, which lists a (fetch) and (push) URL line per remote:
/// `origin\tgit@host:repo.git (fetch)`.
enum RemoteParser {
    static func parse(_ output: String) -> [GitRemote] {
        var fetchURLs: [String: String] = [:]
        var pushURLs: [String: String] = [:]
        var order: [String] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            let url = parts[1]
            let kind = parts.count >= 3 ? parts[2] : "(fetch)"
            if !order.contains(name) { order.append(name) }
            if kind == "(push)" { pushURLs[name] = url } else { fetchURLs[name] = url }
        }

        return order.map { name in
            let fetch = fetchURLs[name] ?? pushURLs[name] ?? ""
            return GitRemote(name: name, fetchURL: fetch, pushURL: pushURLs[name] ?? fetch)
        }
    }
}
