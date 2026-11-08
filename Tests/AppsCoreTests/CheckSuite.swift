import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Condition failed", file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition() { throw CheckFailure(description: "\(file):\(line): \(message)") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(actual == expected, "Expected \(expected), received \(actual)", file: file, line: line)
}

struct Check {
    let name: String
    let run: @Sendable () async throws -> Void
}

@main struct CheckSuite {
    static func main() async {
        let checks = CommandRunnerChecks.all
        var failures = 0
        for check in checks {
            do { try await check.run(); print("PASS \(check.name)") }
            catch { failures += 1; print("FAIL \(check.name): \(error)") }
        }
        print("\(checks.count) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
