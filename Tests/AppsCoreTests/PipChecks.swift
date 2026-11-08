import Foundation
import AppsCore

enum PipChecks {
    static let python = URL(fileURLWithPath: "/Project With Spaces/.venv/bin/python")
    static let prefix = "/Project With Spaces/.venv"
    static func report(installer: String = "pip", location: String? = nil, external: Bool = false,
                       system: Bool = false, pipAvailable: Bool = true, directURL: Bool = false,
                       name: String = "demo_pkg", isUser: Bool = false) -> String {
        let row: [String: Any] = ["name": name, "version": "1.0", "summary": "Example package",
            "location": location ?? prefix + "/lib/python3.12/site-packages", "installer": installer,
            "commands": ["demo"], "dependencies": ["requests>=2"], "directURL": directURL, "isUser": isUser]
        let object: [String: Any] = ["version": 1, "prefix": prefix, "basePrefix": "/Python",
            "pipAvailable": pipAvailable, "externallyManaged": external, "isSystem": system, "packages": [row]]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    static var all: [Check] { [
        Check(name: "pip rejects requirement expressions and canonicalizes archive-like names") {
            let invalid = try PipManager.parseProbe(report(name: "requests@bad"), executable: python)[0]
            do { _ = try await PipManager(executable: python, runner: RecordingRunner()).uninstall(invalid); throw CheckFailure(description: "Requirement expression accepted") }
            catch { try expect(error is ManagerError) }
            let json = report(name: "demo.tar.gz")
            let row = try PipManager.parseProbe(json, executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: "[]"), .init(exitCode: 0, stdout: "done")])
            _ = try await PipManager(executable: python, runner: runner).uninstall(row)
            let calls = await runner.calls()
            try expectEqual(calls.last?.arguments, ["-m", "pip", "--disable-pip-version-check", "uninstall", "--yes", "--", "demo-tar-gz"])
        },
        Check(name: "pip refuses configuration that redirects or adds mutation targets") {
            let json = report(), row = try PipManager.parseProbe(json, executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: #"["global.python","uninstall.requirement",":env:.target"]"#)])
            do { _ = try await PipManager(executable: python, runner: runner).uninstall(row); throw CheckFailure(description: "Unsafe pip config accepted") }
            catch { try expect(error is ManagerError) }
            let calls = await runner.calls()
            try expectEqual(calls.count, 2)
            try expect(calls.allSatisfy { $0.arguments.first == "-c" })
        },
        Check(name: "pip preserves protected dependency versions through resolver constraints") {
            var object = try JSONSerialization.jsonObject(with: Data(report().utf8)) as! [String: Any]
            var protected = (object["packages"] as! [[String: Any]])[0]
            protected["name"] = "protected_dep"; protected["installer"] = "conda"
            object["packages"] = (object["packages"] as! [[String: Any]]) + [protected]
            let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
            let row = try PipManager.parseProbe(json, executable: python).first { $0.name == "demo_pkg" }!
            let runner = ConstraintRunner(report: json)
            _ = try await PipManager(executable: python, runner: runner).upgrade(row)
            let captured = await runner.constraint
            try expectEqual(captured, "protected-dep===1.0\n")
            let path = await runner.constraintPath
            try expect(path != nil)
            try expect(!FileManager.default.fileExists(atPath: path!))
        },
        Check(name: "pip empty index results do not prove that packages are current") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report()), .init(exitCode: 0, stdout: "[]"), .init(exitCode: 0, stdout: "[]")])
            let rows = try await PipManager(executable: python, runner: runner).checkUpdates()
            try expectEqual(rows[0].updateStatus, .unsupported)
        },
        Check(name: "pip update checks have an overall cancellable deadline") {
            let runner = SlowPipRunner(report: report())
            do { _ = try await PipManager(executable: python, runner: runner, checkTimeout: .milliseconds(30)).checkUpdates(); throw CheckFailure(description: "Check did not time out") }
            catch { try expectEqual(error as? CommandError, .timedOut) }
        },
        Check(name: "pip config guard reads dangerous file and environment keys without leaking registry secrets") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("pip.conf")
            try Data("[global]\nindex-url=https://user:secret@example.invalid/simple\npython=/wrong/python\n[uninstall]\nrequirement=/extra.txt\n".utf8).write(to: file)
            let result = try await CommandRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["PIP_CONFIG_FILE=" + file.path, "PIP_TARGET=/other", "PIP_PYTHON=/different/python", "PIP_REQUIREMENT=/another.txt", "/usr/bin/python3", "-c", PipManager.configurationGuardScript])
            let text = try result.requireSuccess()
            let keys = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String]
            try expect(keys.contains("global.python") && keys.contains("uninstall.requirement") && keys.contains(":env:.target"))
            try expect(keys.contains(":env:.python") && keys.contains(":env:.requirement"))
            try expect(!text.contains("secret") && !text.contains("example.invalid"))
        },
        Check(name: "pip metadata belongs to the exact selected interpreter") {
            let rows = try PipManager.parseProbe(report(), executable: python)
            let row = rows[0]
            try expectEqual(row.source, .pip)
            try expectEqual(row.kind, .pythonPackage)
            try expectEqual(row.environmentPath, prefix)
            try expectEqual(row.managerPath, python.path)
            try expectEqual(row.executables, ["demo"])
            try expectEqual(row.dependencies, ["requests>=2"])
            try expect(row.upgradeRestriction == nil && row.removalRestriction == nil)
        },
        Check(name: "pip protects conda system externally managed and foreign packages") {
            for json in [report(installer: "conda"), report(external: true), report(system: true),
                         report(pipAvailable: false), report(location: "/other-env/lib/site-packages"), report(installer: "")] {
                let row = try PipManager.parseProbe(json, executable: python)[0]
                try expect(row.upgradeRestriction != nil)
                try expect(row.removalRestriction != nil)
            }
        },
        Check(name: "pip editable origins are not silently replaced by registry packages") {
            let row = try PipManager.parseProbe(report(directURL: true), executable: python)[0]
            try expect(row.upgradeRestriction != nil)
            try expect(row.removalRestriction == nil)
            let pip = try PipManager.parseProbe(report(name: "pip"), executable: python)[0]
            try expect(pip.removalRestriction != nil)
        },
        Check(name: "pip upgrades use python module arguments without shell activation") {
            let json = report()
            let row = try PipManager.parseProbe(json, executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: "[]"), .init(exitCode: 0, stdout: "done")])
            _ = try await PipManager(executable: python, runner: runner).upgrade(row)
            let calls = await runner.calls()
            try expectEqual(calls.last?.executable, python)
            try expectEqual(calls.last?.arguments, ["-m", "pip", "--disable-pip-version-check", "install", "--upgrade", "--", "demo-pkg"])
        },
        Check(name: "pip user installs retain their user scope on upgrade") {
            let json = report(isUser: true)
            let row = try PipManager.parseProbe(json, executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: "[]"), .init(exitCode: 0, stdout: "done")])
            _ = try await PipManager(executable: python, runner: runner).upgrade(row)
            let calls = await runner.calls()
            try expectEqual(calls.last?.arguments, ["-m", "pip", "--disable-pip-version-check", "install", "--upgrade", "--user", "--", "demo-pkg"])
        },
        Check(name: "pip checks match normalized distribution names") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report()), .init(exitCode: 0, stdout: "[]"),
                .init(exitCode: 0, stdout: #"[{"name":"Demo-Pkg","version":"1.0","latest_version":"2.0","latest_filetype":"wheel"}]"#)])
            let row = try await PipManager(executable: python, runner: runner).checkUpdates()[0]
            try expectEqual(row.updateStatus, .available)
            try expectEqual(row.latestVersion, "2.0")
        },
        Check(name: "pip network warnings never become an up-to-date result") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report()), .init(exitCode: 0, stdout: "[]"), .init(exitCode: 0, stdout: "[]", stderr: "WARNING: Could not fetch URL")])
            do { _ = try await PipManager(executable: python, runner: runner).checkUpdates(); throw CheckFailure(description: "Incomplete index check accepted") }
            catch { try expect(!(error is CheckFailure)) }
        },
        Check(name: "pip mutation rechecks ownership rather than trusting UI state") {
            let row = try PipManager.parseProbe(report(), executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report(installer: "conda"))])
            do { _ = try await PipManager(executable: python, runner: runner).uninstall(row); throw CheckFailure(description: "Changed owner accepted") }
            catch { try expect(error is ManagerError) }
            let calls = await runner.calls()
            try expectEqual(calls.count, 1)
        },
        Check(name: "pip rejects unsupported probe schema and malformed metadata") {
            for text in ["[]", "{}", #"{"version":2,"packages":[]}"#] {
                do { _ = try PipManager.parseProbe(text, executable: python); throw CheckFailure(description: "Invalid probe accepted") }
                catch { try expect(error is ManagerError) }
            }
        }
    ] }
}

actor ConstraintRunner: CommandRunning {
    let report: String
    var constraint: String?
    var constraintPath: String?
    init(report: String) { self.report = report }
    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        if arguments == ["-c", PipManager.probeScript] { return .init(exitCode: 0, stdout: report) }
        if arguments.first == "-c" { return .init(exitCode: 0, stdout: "[]") }
        if let index = arguments.firstIndex(of: "--constraint"), arguments.indices.contains(index + 1) {
            constraintPath = arguments[index + 1]
            constraint = try String(contentsOfFile: arguments[index + 1], encoding: .utf8)
        }
        return .init(exitCode: 0, stdout: "done")
    }
}

struct SlowPipRunner: CommandRunning {
    let report: String
    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        if arguments == ["-c", PipManager.probeScript] { return .init(exitCode: 0, stdout: report) }
        if arguments.first == "-c" { return .init(exitCode: 0, stdout: "[]") }
        try await Task.sleep(for: .seconds(2))
        return .init(exitCode: 0, stdout: "[]")
    }
}
