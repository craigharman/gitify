import Foundation

// Standalone verification runner for the GitKit engine.
// Usage: `swift run GitKitChecks` (exits non-zero on any failure).

await Checks.runAll()
let (ok, text) = await reporter.summary()
print(text)
exit(ok ? 0 : 1)
