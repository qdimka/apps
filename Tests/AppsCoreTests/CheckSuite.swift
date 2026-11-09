import Foundation
import AppsCore

let testPythonPath = ProcessInfo.processInfo.environment["APPS_TEST_PYTHON"] ?? "/usr/bin/python3"

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
        if CommandLine.arguments.contains("--inventory") {
            var failures = 0
            for manager in ManagerDiscovery.environmentManagers(npm: RuntimeDiscovery.npmChoices(), python: RuntimeDiscovery.pythonChoices()) {
                do {
                    let rows = try await manager.list()
                    print("\(manager.source.title): \(rows.count) packages; \(manager.executable.path)")
                } catch { failures += 1; print("\(manager.source.title): \(error.localizedDescription)") }
            }
            if failures > 0 { exit(1) }
            return
        }
        let checks = CommandRunnerChecks.all + ManagerChecks.all + CoordinatorChecks.all + NPMChecks.all + PipChecks.all + RuntimeChecks.all + GoChecks.all + CargoChecks.all + EnvironmentChecks.all + LocalizationChecks.all
        var failures = 0
        for check in checks {
            do { try await check.run(); print("PASS \(check.name)") }
            catch { failures += 1; print("FAIL \(check.name): \(error)") }
        }
        print("\(checks.count) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
