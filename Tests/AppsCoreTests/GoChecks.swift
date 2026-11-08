import Foundation
import AppsCore

enum GoChecks {
    static let go = URL(fileURLWithPath: "/tools/go")
    static func info(_ version: String = "v1.0.0", replace: Bool = false) -> String {
        #"{"GoVersion":"go1.25.3","Path":"example.com/tool/cmd/tool","Main":{"Path":"example.com/tool","Version":""# + version + #"""# + (replace ? #", "Replace":{"Path":"../local"}"# : "") + #"},"Deps":[{"Path":"example.com/dep","Version":"v0.2.0"}],"Settings":[{"Key":"GOOS","Value":"darwin"},{"Key":"GOARCH","Value":"arm64"}]}"#
    }
    static func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("apps-go-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try RuntimeChecks.executable(root.appendingPathComponent("tool"))
        return root
    }
    static var all: [Check] { [
        Check(name: "Go check has an overall cancellable deadline") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let manager = GoManager(executable: go, runner: GoFixtureRunner(root: root, slowLatest: true), checkTimeout: .milliseconds(25))
            do { _ = try await manager.checkUpdates(); throw CheckFailure(description: "Deadline ignored") }
            catch { try expectEqual(error as? CommandError, .timedOut) }
        },
        Check(name: "Go old toolchains report unsupported JSON rather than an empty inventory") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "usage: go version [-m] [file ...]")])
            do { _ = try await GoManager(executable: go, runner: runner).list(); throw CheckFailure(description: "Unsupported Go accepted") }
            catch { try expect(error.localizedDescription.contains("1.25")) }
        },
        Check(name: "Go build metadata identifies module command version and binary") {
            let binary = URL(fileURLWithPath: "/home/go/bin/tool")
            let row = try GoManager.parseInfo(info(), binary: binary, executable: go, root: binary.deletingLastPathComponent(), fingerprint: "original", owned: true)
            try expectEqual(row.source, .go)
            try expectEqual(row.modulePath, "example.com/tool")
            try expectEqual(row.packageReference, "example.com/tool/cmd/tool")
            try expectEqual(row.version, "v1.0.0")
            try expectEqual(row.installationPath, binary.path)
            try expectEqual(row.dependencies, ["example.com/dep v0.2.0"])
        },
        Check(name: "Go devel replacements and foreign files cannot be automatically updated") {
            for (text, owned) in [(info("(devel)"), true), (info(replace: true), true), (info(), false)] {
                let row = try GoManager.parseInfo(text, binary: URL(fileURLWithPath: "/bin/tool"), executable: go, root: URL(fileURLWithPath: "/bin"), fingerprint: "x", owned: owned)
                try expect(row.upgradeRestriction != nil)
                if !owned { try expect(row.removalRestriction != nil) }
            }
        },
        Check(name: "Go inventory skips symlinks and unrecognized files") {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("tool"))
            let runner = GoFixtureRunner(root: root)
            let rows = try await GoManager(executable: go, runner: runner).list()
            try expectEqual(rows.map(\.name), ["tool"])
        },
        Check(name: "Go removal revalidates the exact binary then sends it to Trash") {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let trash = FixtureTrash(root: root)
            let manager = GoManager(executable: go, runner: GoFixtureRunner(root: root), trash: trash)
            let row = try await manager.list()[0]
            _ = try await manager.uninstall(row)
            try expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("tool").path))
            try expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("removed-tool").path))
        },
        Check(name: "Go refuses deletion when the binary changed since listing") {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let manager = GoManager(executable: go, runner: GoFixtureRunner(root: root), trash: FixtureTrash(root: root))
            let row = try await manager.list()[0]
            try Data("changed executable".utf8).write(to: root.appendingPathComponent("tool"))
            do { _ = try await manager.uninstall(row); throw CheckFailure(description: "Changed file removed") }
            catch { try expect(error is ManagerError) }
            try expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("tool").path))
        },
        Check(name: "Go stages one verified newer binary and atomically promotes only that target") {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let runner = GoFixtureRunner(root: root)
            let manager = GoManager(executable: go, runner: runner)
            let row = try await manager.list()[0]
            _ = try await manager.upgrade(row)
            try expectEqual(try String(contentsOf: root.appendingPathComponent("tool"), encoding: .utf8), "new binary")
            let arguments = await runner.installArguments
            try expect(arguments.contains("example.com/tool/cmd/tool@v2.0.0"))
            try expect(arguments.contains("GOFLAGS="))
            try expect(!arguments.contains("GOBIN=" + root.path))
        },
        Check(name: "Failed Go staged output leaves the current executable untouched") {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let manager = GoManager(executable: go, runner: GoFixtureRunner(root: root, badBuild: true))
            let row = try await manager.list()[0]
            do { _ = try await manager.upgrade(row); throw CheckFailure(description: "Invalid staged binary promoted") }
            catch { try expect(error is ManagerError) }
            try expectEqual(try String(contentsOf: root.appendingPathComponent("tool"), encoding: .utf8), "#!/bin/sh\nexit 0\n")
        }
    ] }
}

struct FixtureTrash: FileTrashing {
    let root: URL
    func trash(_ url: URL) throws { try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("removed-" + url.lastPathComponent)) }
}

actor GoFixtureRunner: CommandRunning {
    let root: URL
    let badBuild: Bool
    let slowLatest: Bool
    var installArguments: [String] = []
    init(root: URL, badBuild: Bool = false, slowLatest: Bool = false) { self.root = root; self.badBuild = badBuild; self.slowLatest = slowLatest }
    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        if arguments.first == "help" { return .init(exitCode: 0, stdout: "go version [-json]") }
        if arguments.first == "env" {
            let data = try JSONSerialization.data(withJSONObject: ["GOBIN": root.path, "GOPATH": "", "GOFLAGS": ""])
            return .init(exitCode: 0, stdout: String(data: data, encoding: .utf8)!)
        }
        if arguments.first == "version" {
            let staged = arguments.last!.contains(".apps-go-stage-")
            return .init(exitCode: 0, stdout: GoChecks.info(staged ? (badBuild ? "v0.1.0" : "v2.0.0") : "v1.0.0"))
        }
        if arguments.first == "list" { if slowLatest { try await Task.sleep(for: .seconds(2)) }; return .init(exitCode: 0, stdout: #"{"Path":"example.com/tool","Version":"v2.0.0"}"#) }
        if executable.path == "/usr/bin/env" {
            installArguments = arguments
            let path = String(arguments.first { $0.hasPrefix("GOBIN=") }!.dropFirst(6))
            try Data("new binary".utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent("tool"))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path + "/tool")
            return .init(exitCode: 0, stdout: "built")
        }
        throw CheckFailure(description: "Unexpected Go invocation")
    }
}
