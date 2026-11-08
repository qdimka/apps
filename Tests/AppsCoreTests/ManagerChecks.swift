import Foundation
import AppsCore

actor RecordingRunner: CommandRunning {
    struct Invocation: Sendable { let executable: URL; let arguments: [String] }
    let replies: [CommandResult]
    private var invocations: [Invocation] = []
    init(_ replies: [CommandResult] = [.init(exitCode: 0, stdout: "")]) { self.replies = replies }
    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        invocations.append(.init(executable: executable, arguments: arguments))
        return replies[min(invocations.count - 1, replies.count - 1)]
    }
    func calls() -> [Invocation] { invocations }
}

enum ManagerChecks {
    static let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    static let uv = URL(fileURLWithPath: "/usr/local/bin/uv")
    static let pipx = URL(fileURLWithPath: "/usr/local/bin/pipx")
    // Reduced fixture from brew info --json=v2 --installed on this Mac.
    static let brewJSON = #"{"formulae":[{"name":"wget","full_name":"wget","desc":"Internet file retriever","homepage":"https://www.gnu.org/software/wget/","versions":{"stable":"1.25.0"},"installed":[{"version":"1.24.5"}],"dependencies":["openssl@3"],"outdated":true,"pinned":false}],"casks":[{"token":"rectangle","installed":"0.92","version":"2.0.4","desc":"Move windows","outdated":true}]}"#
    // pipx list JSON schema: pypa/pipx src/pipx/commands/list_packages.py
    static let pipxJSON = #"{"pipx_spec_version":"0.1","venvs":{"httpie":{"metadata":{"main_package":{"package":"httpie","package_version":"3.2.4","apps":["http","https","httpie"],"app_paths":[{"__Path__":"/tools/httpie/bin/http"}],"pinned":false},"injected_packages":{}}},"black-old":{"metadata":{"main_package":{"package":"black","package_version":"24.0","apps":["black-old"],"suffix":"-old","pinned":true},"injected_packages":{}}}}}"#

    static let all: [Check] = [
        Check(name: "Update check never runs brew update or package migrations") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: brewJSON)])
            let rows = try await HomebrewManager(executable: brew, runner: runner).checkUpdates()
            let calls = await runner.calls()
            try expectEqual(calls.count, 1)
            try expectEqual(calls[0].arguments, ["info", "--json=v2", "--installed"])
            try expectEqual(rows[0].updateStatus, .available)
        },
        Check(name: "Skipped cask checks and unconfirmed catalog freshness stay unknown") {
            let json = #"{"formulae":[{"name":"git","installed":[{"version":"2"}],"outdated":false}],"casks":[{"token":"app","installed":"1","version":"2","auto_updates":true,"outdated":false}]}"#
            let rows = try HomebrewManager.parse(json, executable: brew, checked: true)
            try expectEqual(rows[0].updateStatus, .unsupported)
            try expectEqual(rows[1].updateStatus, .unsupported)
        },
        Check(name: "Brew parses formulae and casks independently") {
            let rows = try HomebrewManager.parse(brewJSON, executable: brew)
            try expectEqual(rows.count, 2)
            try expectEqual(rows[0].name, "wget")
            try expectEqual(rows[0].version, "1.24.5")
            try expectEqual(rows[0].dependencies, ["openssl@3"])
            try expectEqual(rows[0].installationPath, "/opt/homebrew/Cellar/wget")
            try expectEqual(rows[1].kind, .cask)
            try expectEqual(rows[1].version, "0.92")
            try expectEqual(rows[0].updateStatus, .notChecked)
        },
        Check(name: "Brew update status requires an explicit check") {
            let rows = try HomebrewManager.parse(brewJSON, executable: brew, checked: true)
            try expectEqual(rows[0].updateStatus, .available)
            try expectEqual(rows[0].latestVersion, "1.25.0")
        },
        Check(name: "Empty manager registries parse without invented packages") {
            try expectEqual(try HomebrewManager.parse(#"{"formulae":[],"casks":[]}"#, executable: brew).count, 0)
            try expectEqual(try PipxManager.parse(#"{"venvs":{}}"#, executable: pipx).count, 0)
            try expectEqual(try UVManager.parse("No tools installed\n", executable: uv).count, 0)
            try expectEqual(try UVManager.parse("", executable: uv).count, 0)
        },
        Check(name: "Missing optional metadata is tolerated") {
            let rows = try HomebrewManager.parse(#"{"formulae":[{"name":"git","installed":[{"version":"2"}]}],"casks":[]}"#, executable: brew)
            try expectEqual(rows[0].summary, "")
            try expectEqual(rows[0].dependencies, [])
        },
        Check(name: "Malformed schemas are errors rather than empty success") {
            for value in ["not json", "{}", #"{"formulae":{},"casks":[]}"#] {
                do { _ = try HomebrewManager.parse(value, executable: brew); throw CheckFailure(description: "Malformed brew accepted") }
                catch { try expect(error is ManagerError) }
            }
            do { _ = try UVManager.parse("unexpected new output", executable: uv); throw CheckFailure(description: "Malformed uv accepted") }
            catch { try expect(error is ManagerError) }
        },
        Check(name: "uv list preserves environment and command paths with spaces") {
            let rows = try UVManager.parse("ruff v0.9.0 (/Users/test/Tool Envs/ruff)\n- ruff (/Users/test/Tool Bin/ruff)\nhttpie v3.2.4\n- http\n- https\n", executable: uv)
            try expectEqual(rows.count, 2)
            try expectEqual(rows[0].version, "0.9.0")
            try expectEqual(rows[0].installationPath, "/Users/test/Tool Envs/ruff")
            try expectEqual(rows[0].executables, ["/Users/test/Tool Bin/ruff"])
            try expectEqual(rows[1].executables, ["http", "https"])
        },
        Check(name: "pipx groups multiple commands and preserves suffixed venv identity") {
            let rows = try PipxManager.parse(pipxJSON, executable: pipx, venvRoot: "/Tools/pipx/venvs")
            let httpie = rows.first { $0.name == "httpie" }!
            let black = rows.first { $0.name == "black-old" }!
            try expectEqual(rows.count, 2)
            try expectEqual(httpie.executables, ["/tools/httpie/bin/http", "https", "httpie"])
            try expectEqual(httpie.installationPath, "/Tools/pipx/venvs/httpie")
            try expect(black.pinned)
        },
        Check(name: "Python checks keep update availability unknown") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "ruff v0.9.0\n- ruff\n")])
            let rows = try await UVManager(executable: uv, runner: runner).checkUpdates()
            try expectEqual(rows[0].updateStatus, .unsupported)
            let calls = await runner.calls()
            try expectEqual(calls.count, 1)
            try expectEqual(calls[0].arguments, ["tool", "list", "--show-paths", "--color", "never"])
        },
        Check(name: "Mutations use the right manager and package kind") {
            let runner = RecordingRunner()
            let manager = HomebrewManager(executable: brew, runner: runner)
            let package = PackageRecord(name: "rectangle", source: .homebrew, managerPath: brew.path, version: "0.92", kind: .cask)
            _ = try await manager.uninstall(package)
            _ = try await manager.upgrade(package)
            let calls = await runner.calls()
            try expectEqual(calls[0].executable, brew)
            try expectEqual(calls[0].arguments, ["uninstall", "--cask", "--", "rectangle"])
            try expectEqual(calls[1].arguments, ["upgrade", "--cask", "--greedy", "--", "rectangle"])
        },
        Check(name: "Python mutation commands preserve uv and pipx semantics") {
            let runner = RecordingRunner()
            _ = try await UVManager(executable: uv, runner: runner).upgrade(.init(name: "ruff", source: .uv, managerPath: uv.path, version: "1"))
            _ = try await PipxManager(executable: pipx, runner: runner).uninstall(.init(name: "black-old", source: .pipx, managerPath: pipx.path, version: "1"))
            let calls = await runner.calls()
            try expectEqual(calls[0].arguments, ["tool", "upgrade", "--", "ruff"])
            try expectEqual(calls[1].arguments, ["uninstall", "--", "black-old"])
        },
        Check(name: "Wrong source and option-like names cannot be mutated") {
            let manager = UVManager(executable: uv, runner: RecordingRunner())
            for package in [PackageRecord(name: "ruff", source: .pipx, managerPath: uv.path, version: "1"), PackageRecord(name: "--all", source: .uv, managerPath: uv.path, version: "1")] {
                do { _ = try await manager.uninstall(package); throw CheckFailure(description: "Invalid target accepted") }
                catch { try expect(error is ManagerError) }
            }
        },
        Check(name: "Discovery finds custom and standard executables without requiring a shell") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let tool = root.appendingPathComponent("uv")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
            let found = ManagerDiscovery.find(.uv, searchPaths: [root.path])
            try expectEqual(found?.path, tool.path)
            try expectEqual(ManagerDiscovery.find(.pipx, searchPaths: [root.path]), nil)
        }
    ]
}
