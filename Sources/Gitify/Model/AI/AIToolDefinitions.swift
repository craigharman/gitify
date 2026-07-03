import Foundation

/// Tool definitions exposed to the AI assistant, mapping to GitService operations.
enum AIToolDefinitions {

    static let all: [AIToolDefinition] = [
        // MARK: Read-only tools

        AIToolDefinition(
            name: "get_status",
            description: "Get the working tree status: current branch, staged files, unstaged changes, and untracked files.",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
        ),
        AIToolDefinition(
            name: "get_log",
            description: "Get recent commit history. Returns commit SHA, author, date, and message.",
            parameters: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Number of commits to return (default 10, max 50)."],
                ] as [String: Any],
                "required": [] as [String],
            ]
        ),
        AIToolDefinition(
            name: "get_refs",
            description: "List all branches (local and remote) and tags with their current SHAs.",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
        ),
        AIToolDefinition(
            name: "get_diff",
            description: "Get the diff for a specific file. Shows what has changed.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path relative to the repo root."],
                    "staged": ["type": "boolean", "description": "If true, show the staged (index) diff. Default false."],
                ] as [String: Any],
                "required": ["path"],
            ]
        ),
        AIToolDefinition(
            name: "get_commit_detail",
            description: "Get detailed information about a specific commit, including its changed files and line counts.",
            parameters: [
                "type": "object",
                "properties": [
                    "sha": ["type": "string", "description": "The commit SHA (full or abbreviated)."],
                ] as [String: Any],
                "required": ["sha"],
            ]
        ),
        AIToolDefinition(
            name: "get_conflicts",
            description: "List files with unresolved merge conflicts.",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
        ),
        AIToolDefinition(
            name: "get_file_contents",
            description: "Read the contents of a file in the working tree (including any conflict markers).",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path relative to the repo root."],
                ] as [String: Any],
                "required": ["path"],
            ]
        ),
        AIToolDefinition(
            name: "get_stashes",
            description: "List all stash entries.",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
        ),
        AIToolDefinition(
            name: "get_remotes",
            description: "List configured remotes with their fetch and push URLs.",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
        ),

        // MARK: Mutation tools

        AIToolDefinition(
            name: "stage_files",
            description: "Stage files for commit (git add). Use [\".\"] to stage all changes.",
            parameters: [
                "type": "object",
                "properties": [
                    "paths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "File paths to stage. Use [\".\"] to stage all.",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["paths"],
            ]
        ),
        AIToolDefinition(
            name: "commit",
            description: "Create a commit with the staged changes.",
            parameters: [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "The commit message."],
                    "amend": ["type": "boolean", "description": "If true, amend the last commit. Default false."],
                ] as [String: Any],
                "required": ["message"],
            ]
        ),
        AIToolDefinition(
            name: "checkout",
            description: "Check out an existing branch, tag, or commit.",
            parameters: [
                "type": "object",
                "properties": [
                    "revision": ["type": "string", "description": "Branch name, tag, or commit SHA to check out."],
                ] as [String: Any],
                "required": ["revision"],
            ]
        ),
        AIToolDefinition(
            name: "create_branch",
            description: "Create a new branch, optionally checking it out.",
            parameters: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name for the new branch."],
                    "start_point": ["type": "string", "description": "Starting point (branch, tag, or SHA). Default HEAD."],
                    "checkout": ["type": "boolean", "description": "Switch to the new branch. Default true."],
                ] as [String: Any],
                "required": ["name"],
            ]
        ),
        AIToolDefinition(
            name: "merge",
            description: "Merge a branch into the current branch. This is a destructive operation \u{2014} explain to the user what you are about to do before calling this.",
            parameters: [
                "type": "object",
                "properties": [
                    "branch": ["type": "string", "description": "The branch to merge into the current branch."],
                    "squash": ["type": "boolean", "description": "Squash all commits into the index without committing. Default false."],
                    "no_fast_forward": ["type": "boolean", "description": "Always create a merge commit. Default false."],
                    "no_commit": ["type": "boolean", "description": "Perform merge but stop before committing. Default false."],
                ] as [String: Any],
                "required": ["branch"],
            ]
        ),
        AIToolDefinition(
            name: "rebase",
            description: "Rebase the current branch onto another branch. This rewrites history \u{2014} explain to the user what you are about to do before calling this.",
            parameters: [
                "type": "object",
                "properties": [
                    "onto": ["type": "string", "description": "The branch to rebase onto."],
                ] as [String: Any],
                "required": ["onto"],
            ]
        ),
        AIToolDefinition(
            name: "cherry_pick",
            description: "Apply a specific commit onto the current branch.",
            parameters: [
                "type": "object",
                "properties": [
                    "sha": ["type": "string", "description": "The commit SHA to cherry-pick."],
                ] as [String: Any],
                "required": ["sha"],
            ]
        ),
        AIToolDefinition(
            name: "revert",
            description: "Create a new commit that undoes a specific commit.",
            parameters: [
                "type": "object",
                "properties": [
                    "sha": ["type": "string", "description": "The commit SHA to revert."],
                ] as [String: Any],
                "required": ["sha"],
            ]
        ),
        AIToolDefinition(
            name: "resolve_conflict",
            description: "Resolve a merge conflict in a file by choosing ours or theirs.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path of the conflicted file."],
                    "use_ours": ["type": "boolean", "description": "If true, take our version. If false, take theirs."],
                ] as [String: Any],
                "required": ["path", "use_ours"],
            ]
        ),
        AIToolDefinition(
            name: "abort_operation",
            description: "Abort an in-progress merge or rebase.",
            parameters: [
                "type": "object",
                "properties": [
                    "operation": ["type": "string", "enum": ["merge", "rebase"], "description": "Which operation to abort."],
                ] as [String: Any],
                "required": ["operation"],
            ]
        ),
        AIToolDefinition(
            name: "stash_push",
            description: "Stash the current working tree changes.",
            parameters: [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Optional stash message."],
                    "include_untracked": ["type": "boolean", "description": "Include untracked files. Default true."],
                ] as [String: Any],
                "required": [] as [String],
            ]
        ),
        AIToolDefinition(
            name: "stash_pop",
            description: "Apply and remove the most recent stash (or a specified stash).",
            parameters: [
                "type": "object",
                "properties": [
                    "selector": ["type": "string", "description": "Stash selector (e.g. stash@{0}). Default: most recent."],
                ] as [String: Any],
                "required": [] as [String],
            ]
        ),
    ]
}
