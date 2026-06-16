import Foundation

/// A minimal async test harness used in place of XCTest/swift-testing (neither of which
/// ships with the Command Line Tools toolchain). Collects failures and reports a summary;
/// `main` exits non-zero if anything failed.
actor TestReporter {
    private(set) var passed = 0
    private(set) var failed = 0
    private var currentTest = ""
    private var failures: [String] = []

    func begin(_ name: String) { currentTest = name }

    func record(_ condition: Bool, _ message: String, file: String, line: Int) {
        if condition {
            passed += 1
        } else {
            failed += 1
            let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line)"
            failures.append("  ✗ [\(currentTest)] \(message) (\(location))")
        }
    }

    func summary() -> (ok: Bool, text: String) {
        var lines = failures
        lines.append("")
        lines.append("\(passed) checks passed, \(failed) failed")
        return (failed == 0, lines.joined(separator: "\n"))
    }
}

struct CheckError: Error { let message: String }

/// Global reporter for the run.
let reporter = TestReporter()

func expect(
    _ condition: Bool, _ message: @autoclosure () -> String = "expectation failed",
    file: String = #fileID, line: Int = #line
) async {
    await reporter.record(condition, message(), file: file, line: line)
}

func expectEqual<T: Equatable>(
    _ lhs: T, _ rhs: T, _ message: @autoclosure () -> String = "",
    file: String = #fileID, line: Int = #line
) async {
    let ok = lhs == rhs
    let detail = ok ? "" : " — got \(lhs), expected \(rhs)"
    await reporter.record(ok, message() + detail, file: file, line: line)
}

/// Returns the unwrapped value or throws to abort the current test (and records a failure).
func require<T>(
    _ value: T?, _ message: @autoclosure () -> String = "required value was nil",
    file: String = #fileID, line: Int = #line
) async throws -> T {
    if let value { return value }
    await reporter.record(false, message(), file: file, line: line)
    throw CheckError(message: message())
}

/// Records pass if `body` throws, failure otherwise.
func expectThrows(
    _ message: @autoclosure () -> String = "expected an error",
    file: String = #fileID, line: Int = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        await reporter.record(false, message(), file: file, line: line)
    } catch {
        await reporter.record(true, message(), file: file, line: line)
    }
}

/// Runs a single named test, isolating thrown errors so one failure doesn't halt the run.
func test(_ name: String, _ body: () async throws -> Void) async {
    FileHandle.standardError.write(Data("→ \(name)\n".utf8))
    await reporter.begin(name)
    do {
        try await body()
    } catch is CheckError {
        // Already recorded by `require`.
    } catch {
        await reporter.record(false, "threw unexpectedly: \(error)", file: #fileID, line: #line)
    }
}
