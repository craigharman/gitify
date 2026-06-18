import Foundation

/// Centralizes the UserDefaults keys used to persist a repository's sidebar state
/// (selected section, collapsed top-level sections, and collapsed branch-tree folders),
/// so the writers and the removal cleanup stay in sync. Keyed per repository path.
enum SidebarDefaults {
    static func sectionKey(_ repoPath: String) -> String { "sidebar.section.\(repoPath)" }
    static func sectionsKey(_ repoPath: String) -> String { "sidebar.sections.\(repoPath)" }
    static func collapsedKey(_ repoPath: String, isRemote: Bool) -> String {
        "sidebar.collapsed.\(isRemote ? "remote" : "local").\(repoPath)"
    }

    /// Clears every persisted sidebar key for a repository (used when it's removed from Gitify).
    static func removeAll(for repoPath: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: sectionKey(repoPath))
        defaults.removeObject(forKey: sectionsKey(repoPath))
        defaults.removeObject(forKey: collapsedKey(repoPath, isRemote: false))
        defaults.removeObject(forKey: collapsedKey(repoPath, isRemote: true))
    }
}
