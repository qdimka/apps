import Foundation
import AppsCore

enum CommandRunnerChecks {
    static let all: [Check] = [
        Check(name: "Package identities include source and manager path") {
            let brew = PackageRecord(name: "ruff", source: .homebrew, managerPath: "/opt/homebrew/bin/brew", version: "1")
            let uv = PackageRecord(name: "ruff", source: .uv, managerPath: "/usr/bin/uv", version: "1")
            let other = PackageRecord(name: "ruff", source: .homebrew, managerPath: "/usr/local/bin/brew", version: "1")
            try expectEqual(Set([brew.id, uv.id, other.id]).count, 3)
        },
        Check(name: "Arguments remain literal") {
            let value = "a b; $(touch /tmp/should-never-exist) `id`"
            let result = try await CommandRunner().run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", value])
            try expectEqual(result.stdout, value)
            try expectEqual(result.exitCode, 0)
        },
        Check(name: "Large simultaneous stdout and stderr do not deadlock") {
            let result = try await CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 10000 ]; do printf 1234567890; printf abcdefghij >&2; i=$((i+1)); done"])
            try expectEqual(result.stdout.utf8.count, 100000)
            try expectEqual(result.stderr.utf8.count, 100000)
        },
        Check(name: "Failure preserves exit code and stderr") {
            let result = try await CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf denied >&2; exit 7"])
            try expectEqual(result.exitCode, 7)
            try expectEqual(result.stderr, "denied")
        },
        Check(name: "Timeout stops a long running process") {
            do {
                _ = try await CommandRunner(timeout: 0.1).run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
                throw CheckFailure(description: "Expected timeout")
            } catch { try expectEqual(error as? CommandError, .timedOut) }
        },
        Check(name: "Cancellation stops the process") {
            let task = Task { try await CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            do { _ = try await task.value; throw CheckFailure(description: "Expected cancellation") }
            catch { try expect(error is CancellationError) }
        }
    ]
}
