# AGENTS.md

Context for AI coding assistants working on Gitify.

## Project overview

Gitify is a native macOS Git client (SwiftUI + AppKit, Swift 6, macOS 14+). Its only external dependency is [Sparkle](https://sparkle-project.org) for auto-updates. It builds with the Swift CLI toolchain -- no Xcode project exists.

## Architecture

| Layer | Location | Role |
|-------|----------|------|
| **GitKit** | `Sources/GitKit/` | Headless git engine. Wraps the user's `git` binary via `CLIGitService` (implements `GitService` protocol). `GitRunner` actor serialises all invocations per-repo. |
| **Gitify** | `Sources/Gitify/` | SwiftUI app. MVVM with `@Observable` / `@MainActor`. `AppModel` manages the repo list; `RepositoryViewModel` drives per-repo UI. |
| **Tests** | `Tests/GitKitChecks/` | 138-check integration harness (standalone executable, not XCTest). |

## Key files

- `Sources/GitKit/GitService.swift` -- protocol defining all git operations
- `Sources/GitKit/CLIGitService.swift` -- full implementation (~710 lines)
- `Sources/GitKit/GitRunner.swift` -- actor that runs git processes serially
- `Sources/Gitify/Model/RepositoryViewModel.swift` -- per-repo state & commands
- `Sources/Gitify/Model/AppModel.swift` -- app-level state
- `Sources/Gitify/Views/IntegrationSheets.swift` -- merge/rebase dialogs
- `Sources/Gitify/Views/RepositoryWorkspaceView.swift` -- main workspace layout

## Build, test, run

```bash
swift build                      # Build all targets
swift run GitKitChecks           # Run 138-check integration suite
scripts/build-app.sh debug       # Assemble Gitify.app bundle
scripts/build-app.sh release     # Release build
open build/Gitify.app            # Launch the app
```

Always run `swift run GitKitChecks` after making changes to GitKit.

## Conventions to follow

- **Swift 6 strict concurrency.** View models use `@MainActor`. `GitRunner` is an actor. All public models conform to `Sendable`. No completion handlers -- async/await only.
- **`@Observable`** macro (not `ObservableObject`/`@StateObject`).
- **Naming patterns:** `<Feature>View`, `<Type>Parser`, `<Noun>Service`. Models are singular nouns.
- **Git output parsing** uses control-byte separators (`\u{1f}`, `\u{1e}`) and NUL-delimited (`-z`) output. Never split git output on whitespace or newlines.
- **Argument injection hardening** -- `requireSafe()` rejects leading dashes; file paths are separated with `--`; `GIT_ALLOW_PROTOCOL` restricts transports. Any new git command must follow these patterns.
- **Conventional Commits** for commit messages: `feat:`, `fix:`, `ci:`, etc.
- **No Xcode.** Don't generate or reference `.xcodeproj`/`.xcworkspace`.

## Common pitfalls

1. **Actor serialisation.** `GitRunner` serialises all git calls per-repo. Git operations cannot be parallelised within the same repository -- attempting to do so will cause `index.lock` errors.

2. **Unicode curly quotes.** User-facing strings use `\u{201c}`/`\u{201d}` (smart quotes), not ASCII quotes. Match the existing style when editing strings.

3. **Process I/O deadlocks.** `GitRunner.runRaw()` drains stdout and stderr on separate dispatch queues before calling `waitUntilExit()`. Don't simplify this to synchronous reads.

4. **FSEvents debouncing.** `RepositoryWatcher` coalesces file-system events at 0.5 s. Don't create tight refresh loops in response to changes.

5. **Enum persistence.** `WorkspaceSection` is JSON-encoded into UserDefaults per-repo. Adding, removing, or reordering cases breaks stored state unless you write migration logic.

6. **Keychain coupling.** Tokens are stored under service `"com.gitify.accounts"`. Changing this string requires migration.

7. **No XCTest.** The test suite is a standalone executable (`swift run GitKitChecks`), not XCTest or swift-testing. Tests create throwaway git repos as fixtures.

## Adding a new git command

1. Add the method signature to `GitService.swift` (protocol).
2. Implement it in `CLIGitService.swift`, using `runner.run(...)` or `runner.runStreaming(...)`.
3. Validate all user-supplied arguments with `Self.requireSafe()`.
4. Prefix file-path arguments with `"--"` to prevent flag injection.
5. Add a check in `Tests/GitKitChecks/Checks.swift`.
6. Expose it through `RepositoryViewModel` if needed by the UI.

## Adding a new view

1. Create `Sources/Gitify/Views/<Feature>View.swift`.
2. Follow the `<Feature>View` naming convention.
3. Wire it into the workspace via `RepositoryWorkspaceView` or as a `.sheet()`.
4. Use `@Environment`, `@State`, and the view model -- not ad-hoc state management.
