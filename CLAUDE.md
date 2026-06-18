# CLAUDE.md

Project context for Claude and Claude Code.

## What is Gitify?

A native macOS Git client built with SwiftUI + AppKit. It wraps the user's installed `git` binary (no libgit2) behind a `GitService` protocol, giving a full-featured GUI with semantics that always match the user's git config.

## Architecture

Two SwiftPM targets, zero external dependencies:

- **GitKit** (`Sources/GitKit/`) -- headless Git engine. `CLIGitService` implements the `GitService` protocol by shelling out to `git`. `GitRunner` is an **actor** that serialises all process invocations per-repo to prevent `index.lock` contention.
- **Gitify** (`Sources/Gitify/`) -- SwiftUI app. MVVM with `@Observable` / `@MainActor`. `AppModel` owns the repo list; `RepositoryViewModel` holds per-repo live state.

## Repository layout

```
Package.swift                  # SwiftPM manifest (Swift 6.0, macOS 14+)
Sources/
  GitKit/
    GitService.swift           # Protocol
    CLIGitService.swift        # Implementation (~710 lines)
    GitRunner.swift            # Actor -- serialises git calls
    GitError.swift
    RepositoryWatcher.swift    # FSEvents auto-refresh
    GraphLayout.swift          # Commit-graph lane assignment
    Models/                    # Commit, Ref, Diff, FileStatus, ...
    Parsers/                   # Git output parsers (porcelain v2, diffs, ...)
  Gitify/
    App/GitifyApp.swift        # @main entry point
    Model/                     # AppModel, RepositoryViewModel, stores
    Views/                     # ~25 SwiftUI views
Resources/Info.plist           # Bundle metadata; version managed by release-please
Tests/GitKitChecks/            # 138-check integration harness (standalone executable)
scripts/
  build-app.sh                 # Assembles .app bundle (debug | release)
  package.sh                   # Builds signed/notarised .dmg
.github/workflows/release.yml  # release-please CI
```

## Commands

```bash
swift build                          # Build everything
swift run GitKitChecks               # Run the 138-check test suite
scripts/build-app.sh debug           # Assemble Gitify.app (debug)
scripts/build-app.sh release         # Assemble Gitify.app (release)
open build/Gitify.app                # Launch
```

There is no XCTest -- tests are a standalone executable harness. Always run `swift run GitKitChecks` to verify changes.

## Conventions

- **Swift 6 strict concurrency.** All view models are `@MainActor`. `GitRunner` is an actor. All public data models are `Sendable`.
- **async/await everywhere.** No completion handlers.
- **`@Observable`** (not `@StateObject`/`ObservableObject`).
- **Naming:** views are `<Feature>View`, parsers are `<Type>Parser`, models are singular nouns.
- **Git output parsing** uses control-byte separators (`\u{1f}` unit, `\u{1e}` record) and `-z` NUL-delimited output where possible -- never split on whitespace or newlines naively.
- **Argument injection hardening:** `requireSafe()` rejects args starting with `-`; file paths are prefixed with `--`; `GIT_ALLOW_PROTOCOL` restricts transports. Preserve these patterns in any new git commands.
- **Commit messages** follow Conventional Commits (`feat:`, `fix:`, `ci:`, ...).

## Gotchas

- **Actor serialisation.** Git operations within the same repo cannot run in parallel -- `GitRunner` enforces this. Don't try to parallelise git calls.
- **Smart/curly quotes.** The codebase uses Unicode curly quotes (\u{201c}/\u{201d}) in user-facing strings. Match them when editing.
- **No Xcode project.** This builds with the Swift CLI toolchain only. Don't generate or reference `.xcodeproj` or `.xcworkspace`.
- **FSEvents debouncing.** `RepositoryWatcher` coalesces at 0.5 s. Don't create tight refresh loops.
- **`WorkspaceSection` persistence.** The enum is JSON-encoded to UserDefaults per-repo. Changing its cases breaks stored state unless you add migration.
- **Keychain service name** is `"com.gitify.accounts"`. Don't rename without migration.
