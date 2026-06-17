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
  worktrees, stashes, unified diffs, mutations (stage/unstage/discard, commit, amend),
  hunk-level staging, lane-assignment graph layout, branch/tag/stash/worktree management,
  merge (with conflict preview) / rebase / abort, reflog, remotes, and streamed network ops
  (fetch/pull/push/clone). Argument-injection
  hardened (`--` separators, leading-dash rejection, restricted `GIT_ALLOW_PROTOCOL`).
  Covered by a 92-check integration suite.
- App: repository manager with a sidebar repo-switcher (add / **clone-from-URL** with
  progress), overview, a full working-tree/staging view (stage/unstage/discard, **per-hunk
  staging**, unified diff, commit + amend), a **lane-based commit graph** with ref pills and
  inspector, **fetch/pull/push** with a live-progress overlay, branch checkout/create/rename/
  delete, tag create/delete, stash push/apply/pop/drop, worktree add/remove, reflog view,
  **FSEvents auto-refresh**, and a **Check for Updates** menu.
- Packaging: `scripts/package.sh` builds a (optionally signed + notarized) `.dmg`. See
  `docs/RELEASING.md`.

Planned:
- Line-level (intra-hunk) staging
- Sparkle integration for silent signed auto-updates (see `docs/RELEASING.md`)
