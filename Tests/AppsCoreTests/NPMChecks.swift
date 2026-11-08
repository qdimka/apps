import Foundation
import AppsCore

enum NPMChecks {
    static let npm = URL(fileURLWithPath: "/Node 22/bin/npm")
    static let prefix = "/Node 22", root = "/Node 22/lib/node_modules"
    static let json = #"{"name":"lib","dependencies":{"@scope/tool":{"version":"1.0","description":"Scoped CLI","path":"/Node 22/lib/node_modules/@scope/tool"},"local":{"version":"2.0","link":true},"npm":{"version":"10.9.3"}}}"#
    static func replies(_ json: String = json) -> [CommandResult] {
        [.init(exitCode: 0, stdout: prefix + "\n"), .init(exitCode: 0, stdout: root + "\n"), .init(exitCode: 0, stdout: json)]
    }
    static var all: [Check] { [
        Check(name: "npm parses scoped globals and protects local links and itself") {
            let rows = try NPMManager.parseList(json, executable: npm, prefix: prefix, root: root)
            try expectEqual(rows.count, 3)
            let scoped = rows.first { $0.name == "@scope/tool" }!
            try expectEqual(scoped.version, "1.0")
            try expectEqual(scoped.environmentPath, prefix)
            try expectEqual(scoped.installationPath, root + "/@scope/tool")
            try expectEqual(scoped.kind, .npmPackage)
            try expect(rows.first { $0.name == "local" }!.upgradeRestriction != nil)
            try expect(rows.first { $0.name == "local" }!.removalRestriction == nil)
            try expect(rows.first { $0.name == "npm" }!.removalRestriction != nil)
        },
        Check(name: "npm outdated code one is a successful check with available versions") {
            let outdated = #"{"@scope/tool":{"current":"1.0","wanted":"1.0","latest":"3.0"}}"#
            let runner = RecordingRunner(replies() + [.init(exitCode: 1, stdout: outdated)])
            let rows = try await NPMManager(executable: npm, runner: runner).checkUpdates()
            let scoped = rows.first { $0.name == "@scope/tool" }!
            try expectEqual(scoped.updateStatus, .available)
            try expectEqual(scoped.latestVersion, "3.0")
            try expectEqual(rows.first { $0.name == "local" }?.updateStatus, .unsupported)
            let calls = await runner.calls()
            try expectEqual(calls.last?.arguments, ["outdated", "--global", "--prefix", prefix, "--json", "--long"])
        },
        Check(name: "npm registry errors are never treated as an empty successful check") {
            for reply in [CommandResult(exitCode: 1, stdout: #"{"error":{"code":"E404"}}"#),
                          CommandResult(exitCode: 1, stdout: #"{"@scope/tool":{"current":"1"}}"#),
                          CommandResult(exitCode: 2, stdout: "{}", stderr: "network error")] {
                let runner = RecordingRunner(replies() + [reply])
                do { _ = try await NPMManager(executable: npm, runner: runner).checkUpdates(); throw CheckFailure(description: "Registry error accepted") }
                catch { try expect(!(error is CheckFailure)) }
            }
        },
        Check(name: "npm global mutations preserve the selected prefix and scoped name") {
            let record = try NPMManager.parseList(json, executable: npm, prefix: prefix, root: root).first { $0.name == "@scope/tool" }!
            let runner = RecordingRunner(replies() + [.init(exitCode: 0, stdout: "done")])
            _ = try await NPMManager(executable: npm, runner: runner).upgrade(record)
            let calls = await runner.calls()
            try expectEqual(calls.last?.executable, npm)
            try expectEqual(calls.last?.arguments, ["install", "--global", "--prefix", prefix, "--no-audit", "--no-fund", "--", "@scope/tool@latest"])
        },
        Check(name: "npm refuses stale contexts before mutation") {
            var record = try NPMManager.parseList(json, executable: npm, prefix: prefix, root: root)[0]
            record.environmentPath = "/other-node"
            let runner = RecordingRunner(replies())
            do { _ = try await NPMManager(executable: npm, runner: runner).uninstall(record); throw CheckFailure(description: "Wrong prefix accepted") }
            catch { try expect(error is ManagerError) }
            let calls = await runner.calls()
            try expectEqual(calls.count, 3)
        },
        Check(name: "npm self-removal and local-link upgrade cannot bypass adapter restrictions") {
            let rows = try NPMManager.parseList(json, executable: npm, prefix: prefix, root: root)
            for (name, action) in [("npm", PackageAction.uninstall), ("local", PackageAction.upgrade)] {
                var row = rows.first { $0.name == name }!
                row.upgradeRestriction = nil; row.removalRestriction = nil
                let manager = NPMManager(executable: npm, runner: RecordingRunner(replies()))
                do {
                    _ = try await (action == .upgrade ? manager.upgrade(row) : manager.uninstall(row))
                    throw CheckFailure(description: "Restriction bypassed")
                } catch { try expect(error is ManagerError) }
            }
        },
        Check(name: "npm accepts an empty global registry but rejects malformed records") {
            try expectEqual(try NPMManager.parseList("{}", executable: npm, prefix: prefix, root: root).count, 0)
            for text in ["broken", #"{"error":{"code":"EACCES"}}"#, #"{"dependencies":{"bad":{"missing":true}}}"#] {
                do { _ = try NPMManager.parseList(text, executable: npm, prefix: prefix, root: root); throw CheckFailure(description: "Malformed npm accepted") }
                catch { try expect(error is ManagerError) }
            }
        }
    ] }
}
