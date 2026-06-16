import Foundation

/// Parses `git worktree list --porcelain` output. Worktrees are separated by blank lines;
/// the first block is always the main worktree.
enum WorktreeParser {
    static func parse(_ output: String) -> [Worktree] {
        let blocks = output.components(separatedBy: "\n\n")
        var result: [Worktree] = []

        for (index, block) in blocks.enumerated() {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
            guard !lines.isEmpty else { continue }

            var path: String?
            var head: String?
            var branch: String?
            var isBare = false
            var isDetached = false
            var isLocked = false

            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else if line == "bare" {
                    isBare = true
                } else if line == "detached" {
                    isDetached = true
                } else if line == "locked" || line.hasPrefix("locked ") {
                    isLocked = true
                }
            }

            guard let path else { continue }
            result.append(Worktree(
                path: path, head: head, branch: branch,
                isBare: isBare, isDetached: isDetached, isLocked: isLocked,
                isMain: index == 0
            ))
        }
        return result
    }
}
