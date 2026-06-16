# Gitify

A fast, lightweight, native macOS Git client — built with SwiftUI + AppKit, modeled on
the Gitfox interface concept.

## Architecture

- **`GitKit`** (`Sources/GitKit`) — a headless, testable Swift package that is the Git
  engine. It shells out to the user's installed `git` binary via plumbing/porcelain
  commands (behind the `GitService` protocol), which gives full coverage of advanced
  features — worktrees, stashes, branches, tags — with semantics that always match the
  user's `git`. (libgit2 was rejected because it breaks on modern worktrees.)
- **`Gitify`** (`Sources/Gitify`) — the SwiftUI app: repository manager, overview,
  working-tree/staging, commit history + inspector, and branch/stash/worktree views,
  all driven by `GitKit`.

## Requirements

- macOS 14+
- Swift 6 toolchain (Command Line Tools is sufficient — full Xcode is **not** required)
- `git` on `PATH`

## Build & run

```sh
# Build the engine and app
swift build

# Run the engine verification suite (XCTest/swift-testing aren't bundled with the
# Command Line Tools toolchain, so checks run as a standalone executable harness)
swift run GitKitChecks

# Assemble a runnable Gitify.app bundle (handed-rolled since there is no Xcode project)
scripts/build-app.sh debug      # or: release
open build/Gitify.app
```

## Status

Implemented:
- Git engine: status (porcelain v2), history (paged log), refs (branches/tags + tracking),
  worktrees, stashes, unified diffs, and mutations (stage/unstage/discard, commit, amend)
  — with a 49-check integration suite.
- App: repository manager (add/remove/persist), repository overview, commit history +
  inspector, branch/remote/tag/stash/worktree browsing, and a full working-tree/staging
  view: staged/unstaged file lists, per-file stage/unstage/discard, a unified diff pane,
  and a commit box with amend support.

Planned (see `plans/`):
- Hunk- and line-level staging
- Lane-based commit graph canvas
- Clone-from-URL, fetch/pull/push with progress
- FSEvents auto-refresh, Sparkle auto-update, Developer-ID notarization
