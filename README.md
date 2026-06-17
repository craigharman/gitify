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
- Git engine: status (porcelain v2), history (paged log) + per-commit changes/diffs,
  refs (branches/tags + tracking), worktrees, stashes (+ diffs, branch-from-stash), unified
  diffs, mutations (stage/unstage/discard, commit, amend), hunk-level staging, lane-assignment
  graph layout, branch/tag/stash/worktree management, merge (with conflict preview) / rebase /
  cherry-pick / revert / reset / abort, conflict resolution (ours/theirs/mark-resolved),
  reflog, remotes (add/remove, push tags, force-push, delete remote branch), config get/set,
  repository stats (lines-by-language, top committers, README), submodules, per-line
  staging, conflict-marker parsing, and streamed network ops
  (fetch/pull/push/pull-rebase/clone). Argument-injection
  hardened (`--` separators, leading-dash rejection, restricted `GIT_ALLOW_PROTOCOL`).
  Covered by a 138-check integration suite.
- App: repository manager with a sidebar repo-switcher (add / **clone-from-URL** with
  progress), overview (stats + rendered README), a full working-tree/staging view
  (stage/unstage/discard, **per-hunk and per-line staging**, **unified + split diffs with
  syntax highlighting**, commit + amend), a **lane-based commit graph** with an Inspect-Changes
  panel, **commit context menu** (cherry-pick/revert/reset/branch/tag), **fetch/pull/push**
  with a live-progress overlay, branch/tag/stash/worktree management, **merge/rebase dialogs**,
  a **3-way conflict editor**, submodules, reflog, **search/filter** across lists,
  **GitHub/GitLab accounts** (token-based repo browsing + clone), **FSEvents auto-refresh**,
  and a **Check for Updates** menu.
- Packaging: `scripts/package.sh` builds a (optionally signed + notarized) `.dmg`. See
  `docs/RELEASING.md`.

Needs your credentials / external setup (see `docs/RELEASING.md`):
- **Developer-ID notarization** — `package.sh` is ready; supply `SIGN_IDENTITY` + a notary
  profile.
- **Sparkle** silent auto-updates — needs an EdDSA key pair, a hosted appcast, and the
  embedded framework. The in-app GitHub-release **Check for Updates** covers basic updating
  until then.
- **Full OAuth accounts + pull-request review** — the current accounts use personal access
  tokens; OAuth needs a registered app.
