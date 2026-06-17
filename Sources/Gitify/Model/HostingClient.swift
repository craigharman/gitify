import Foundation

/// Minimal GitHub/GitLab REST client: validates a personal access token and lists the
/// account's repositories. (OAuth and pull-request browsing are intentionally out of scope.)
enum HostingClient {
    struct ClientError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Verifies the token and returns the authenticated user's login.
    static func validate(provider: HostingAccount.Provider, token: String) async throws -> String {
        let url = URL(string: provider.apiBase + (provider == .github ? "/user" : "/user"))!
        let data = try await get(url, provider: provider, token: token)
        let key = provider == .github ? "login" : "username"
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object[key] as? String else {
            throw ClientError(message: "Couldn't read the account from the response.")
        }
        return login
    }

    /// Lists repositories the account can access.
    static func repositories(provider: HostingAccount.Provider, token: String) async throws -> [HostedRepo] {
        switch provider {
        case .github:
            let url = URL(string: provider.apiBase + "/user/repos?per_page=100&sort=updated")!
            let data = try await get(url, provider: provider, token: token)
            let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            return array.compactMap { item in
                guard let fullName = item["full_name"] as? String,
                      let clone = item["clone_url"] as? String else { return nil }
                return HostedRepo(id: "\(item["id"] ?? fullName)", fullName: fullName,
                                  cloneURL: clone, isPrivate: item["private"] as? Bool ?? false)
            }
        case .gitlab:
            let url = URL(string: provider.apiBase + "/projects?membership=true&per_page=100&order_by=updated_at")!
            let data = try await get(url, provider: provider, token: token)
            let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            return array.compactMap { item in
                guard let fullName = item["path_with_namespace"] as? String,
                      let clone = item["http_url_to_repo"] as? String else { return nil }
                return HostedRepo(id: "\(item["id"] ?? fullName)", fullName: fullName,
                                  cloneURL: clone, isPrivate: (item["visibility"] as? String) != "public")
            }
        }
    }

    private static func get(_ url: URL, provider: HostingAccount.Provider, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        switch provider {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        case .gitlab:
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "No response from \(provider.displayName).")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError(message: "\(provider.displayName) returned HTTP \(http.statusCode). Check the token and its scopes.")
        }
        return data
    }
}
