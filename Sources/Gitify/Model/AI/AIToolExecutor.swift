import Foundation
import GitKit

/// Executes AI tool calls against a repository's GitService, formatting results as strings
/// for the AI to consume. Errors are returned as descriptive strings rather than thrown,
/// so the AI can reason about failures.
@MainActor
final class AIToolExecutor {
    private let viewModel: RepositoryViewModel

    init(viewModel: RepositoryViewModel) {
        self.viewModel = viewModel
    }

    /// Dispatches a tool call by name and returns a string result for the AI.
    func execute(name: String, arguments: String) async -> String {
        let args = parseArgs(arguments)
        do {
            guard let service = viewModel.gitService else {
                return "Error: Repository service is not available."
            }

            switch name {
            // MARK: Read-only
            case "get_status":
                return try await executeGetStatus(service)
            case "get_log":
                return try await executeGetLog(service, args: args)
            case "get_refs":
                return try await executeGetRefs(service)
            case "get_diff":
                return try await executeGetDiff(service, args: args)
            case "get_commit_detail":
                return try await executeGetCommitDetail(service, args: args)
            case "get_conflicts":
                return try await executeGetConflicts(service)
            case "get_file_contents":
                return try await executeGetFileContents(service, args: args)
            case "get_stashes":
                return try await executeGetStashes(service)
            case "get_remotes":
                return try await executeGetRemotes(service)

            // MARK: Mutations
            case "stage_files":
                return try await executeStageFiles(service, args: args)
            case "commit":
                return try await executeCommit(service, args: args)
            case "checkout":
                return try await executeCheckout(service, args: args)
            case "create_branch":
                return try await executeCreateBranch(service, args: args)
            case "merge":
                return try await executeMerge(service, args: args)
            case "rebase":
                return try await executeRebase(service, args: args)
            case "cherry_pick":
                return try await executeCherryPick(service, args: args)
            case "revert":
                return try await executeRevert(service, args: args)
            case "resolve_conflict":
                return try await executeResolveConflict(service, args: args)
            case "abort_operation":
                return try await executeAbortOperation(service, args: args)
            case "stash_push":
                return try await executeStashPush(service, args: args)
            case "stash_pop":
                return try await executeStashPop(service, args: args)
            default:
                return "Error: Unknown tool \u{201C}\(name)\u{201D}."
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Read-only implementations

    private func executeGetStatus(_ service: any GitService) async throws -> String {
        let status = try await service.status()
        var lines: [String] = []
        lines.append("Branch: \(status.branch ?? "(detached HEAD)")")
        if let upstream = status.upstream {
            var tracking = "Upstream: \(upstream)"
            if status.ahead > 0 { tracking += " [ahead \(status.ahead)]" }
            if status.behind > 0 { tracking += " [behind \(status.behind)]" }
            lines.append(tracking)
        }
        if status.files.isEmpty {
            lines.append("Working tree clean.")
        } else {
            for file in status.files {
                let idx = file.indexState == .unmodified ? "." : String(file.indexState.rawValue)
                let wt = file.worktreeState == .unmodified ? "." : String(file.worktreeState.rawValue)
                lines.append("\(idx)\(wt) \(file.path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func executeGetLog(_ service: any GitService, args: [String: Any]) async throws -> String {
        let limit = min(args["limit"] as? Int ?? 10, 50)
        let page = try await service.log(skip: 0, limit: limit, revisions: ["HEAD"])
        if page.commits.isEmpty { return "No commits found." }
        return page.commits.map { c in
            "\(c.shortID) \(c.authorName) \(c.authorDate) \(c.summary)"
        }.joined(separator: "\n")
    }

    private func executeGetRefs(_ service: any GitService) async throws -> String {
        let refs = try await service.refs()
        if refs.isEmpty { return "No refs found." }
        var sections: [String] = []
        let local = refs.filter { $0.kind == .localBranch }
        if !local.isEmpty {
            sections.append("Local branches:\n" + local.map {
                "  \($0.isHead ? "* " : "  ")\($0.name) \($0.targetSHA.prefix(7))"
            }.joined(separator: "\n"))
        }
        let remote = refs.filter { $0.kind == .remoteBranch }
        if !remote.isEmpty {
            sections.append("Remote branches:\n" + remote.map {
                "  \($0.name) \($0.targetSHA.prefix(7))"
            }.joined(separator: "\n"))
        }
        let tags = refs.filter { $0.kind == .tag }
        if !tags.isEmpty {
            sections.append("Tags:\n" + tags.map {
                "  \($0.name) \($0.targetSHA.prefix(7))"
            }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func executeGetDiff(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else { return "Error: Missing required parameter \u{201C}path\u{201D}." }
        let staged = args["staged"] as? Bool ?? false
        let diff = try await service.diff(path: path, staged: staged)
        if diff.hunks.isEmpty { return "No differences found for \(path)." }
        return diff.hunks.map { hunk in
            hunk.lines.map { line in
                let prefix: String
                switch line.kind {
                case .addition: prefix = "+"
                case .deletion: prefix = "-"
                case .context: prefix = " "
                }
                return "\(prefix)\(line.content)"
            }.joined(separator: "\n")
        }.joined(separator: "\n---\n")
    }

    private func executeGetCommitDetail(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let sha = args["sha"] as? String else { return "Error: Missing required parameter \u{201C}sha\u{201D}." }
        let changes = try await service.commitChanges(sha: sha)
        if changes.isEmpty { return "No changes found for commit \(sha)." }
        return changes.map { c in
            "\(c.status.rawValue) \(c.path) (+\(c.additions) -\(c.deletions))"
        }.joined(separator: "\n")
    }

    private func executeGetConflicts(_ service: any GitService) async throws -> String {
        let files = try await service.conflictedFiles()
        if files.isEmpty { return "No conflicted files." }
        return "Conflicted files:\n" + files.map { "  \($0)" }.joined(separator: "\n")
    }

    private func executeGetFileContents(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else { return "Error: Missing required parameter \u{201C}path\u{201D}." }
        guard let contents = await service.fileContents(path: path) else {
            return "Error: Could not read file \u{201C}\(path)\u{201D}."
        }
        // Truncate very large files to avoid blowing up the context.
        if contents.count > 50_000 {
            return String(contents.prefix(50_000)) + "\n\n[Truncated \u{2014} file is \(contents.count) characters.]"
        }
        return contents
    }

    private func executeGetStashes(_ service: any GitService) async throws -> String {
        let stashes = try await service.stashes()
        if stashes.isEmpty { return "No stashes." }
        return stashes.map { "\($0.id): \($0.message)" }.joined(separator: "\n")
    }

    private func executeGetRemotes(_ service: any GitService) async throws -> String {
        let remotes = try await service.remotes()
        if remotes.isEmpty { return "No remotes configured." }
        return remotes.map { "\($0.name) fetch=\($0.fetchURL) push=\($0.pushURL)" }.joined(separator: "\n")
    }

    // MARK: - Mutation implementations

    private func executeStageFiles(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let paths = args["paths"] as? [String], !paths.isEmpty else {
            return "Error: Missing required parameter \u{201C}paths\u{201D}."
        }
        if paths == ["."] {
            try await service.stageAll()
        } else {
            try await service.stage(paths: paths)
        }
        await viewModel.refreshStatus()
        return "Staged \(paths == ["."] ? "all changes" : paths.joined(separator: ", "))."
    }

    private func executeCommit(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let message = args["message"] as? String, !message.isEmpty else {
            return "Error: Missing required parameter \u{201C}message\u{201D}."
        }
        let amend = args["amend"] as? Bool ?? false
        try await service.commit(message: message, amend: amend)
        await viewModel.refreshStatus()
        return amend ? "Amended the last commit." : "Committed with message: \(message)"
    }

    private func executeCheckout(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let revision = args["revision"] as? String else {
            return "Error: Missing required parameter \u{201C}revision\u{201D}."
        }
        try await service.checkout(revision)
        await viewModel.refreshStatus()
        return "Checked out \u{201C}\(revision)\u{201D}."
    }

    private func executeCreateBranch(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let name = args["name"] as? String else {
            return "Error: Missing required parameter \u{201C}name\u{201D}."
        }
        let startPoint = args["start_point"] as? String
        let checkout = args["checkout"] as? Bool ?? true
        try await service.createBranch(name: name, startPoint: startPoint, checkout: checkout)
        await viewModel.refreshStatus()
        return "Created branch \u{201C}\(name)\u{201D}\(checkout ? " and checked it out" : "")."
    }

    private func executeMerge(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let branch = args["branch"] as? String else {
            return "Error: Missing required parameter \u{201C}branch\u{201D}."
        }
        let squash = args["squash"] as? Bool ?? false
        let noFF = args["no_fast_forward"] as? Bool ?? false
        let noCommit = args["no_commit"] as? Bool ?? false
        try await service.merge(branch: branch, squash: squash, noFastForward: noFF,
                                noCommit: noCommit, skipHooks: false)
        await viewModel.refreshStatus()
        let conflicts = try await service.conflictedFiles()
        if !conflicts.isEmpty {
            return "Merge of \u{201C}\(branch)\u{201D} resulted in conflicts in: \(conflicts.joined(separator: ", ")). Resolve them and commit."
        }
        return "Merged \u{201C}\(branch)\u{201D} into the current branch."
    }

    private func executeRebase(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let onto = args["onto"] as? String else {
            return "Error: Missing required parameter \u{201C}onto\u{201D}."
        }
        try await service.rebase(onto: onto)
        await viewModel.refreshStatus()
        return "Rebased current branch onto \u{201C}\(onto)\u{201D}."
    }

    private func executeCherryPick(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let sha = args["sha"] as? String else {
            return "Error: Missing required parameter \u{201C}sha\u{201D}."
        }
        try await service.cherryPick(sha: sha)
        await viewModel.refreshStatus()
        return "Cherry-picked commit \(sha)."
    }

    private func executeRevert(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let sha = args["sha"] as? String else {
            return "Error: Missing required parameter \u{201C}sha\u{201D}."
        }
        try await service.revert(sha: sha)
        await viewModel.refreshStatus()
        return "Reverted commit \(sha)."
    }

    private func executeResolveConflict(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else {
            return "Error: Missing required parameter \u{201C}path\u{201D}."
        }
        guard let useOurs = args["use_ours"] as? Bool else {
            return "Error: Missing required parameter \u{201C}use_ours\u{201D}."
        }
        try await service.resolveConflict(path: path, useOurs: useOurs)
        await viewModel.refreshStatus()
        return "Resolved \u{201C}\(path)\u{201D} using \(useOurs ? "ours" : "theirs")."
    }

    private func executeAbortOperation(_ service: any GitService, args: [String: Any]) async throws -> String {
        guard let op = args["operation"] as? String else {
            return "Error: Missing required parameter \u{201C}operation\u{201D}."
        }
        switch op {
        case "merge":
            try await service.abortMerge()
            await viewModel.refreshStatus()
            return "Aborted the in-progress merge."
        case "rebase":
            try await service.abortRebase()
            await viewModel.refreshStatus()
            return "Aborted the in-progress rebase."
        default:
            return "Error: Unknown operation \u{201C}\(op)\u{201D}. Use \u{201C}merge\u{201D} or \u{201C}rebase\u{201D}."
        }
    }

    private func executeStashPush(_ service: any GitService, args: [String: Any]) async throws -> String {
        let message = args["message"] as? String
        let includeUntracked = args["include_untracked"] as? Bool ?? true
        try await service.stashPush(message: message, includeUntracked: includeUntracked)
        await viewModel.refreshStatus()
        return "Stashed working tree changes\(message.map { ": \($0)" } ?? "")."
    }

    private func executeStashPop(_ service: any GitService, args: [String: Any]) async throws -> String {
        let selector = args["selector"] as? String ?? "stash@{0}"
        try await service.stashPop(selector)
        await viewModel.refreshStatus()
        return "Applied and removed stash \(selector)."
    }

    // MARK: - Helpers

    private func parseArgs(_ json: String) -> [String: Any] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}
