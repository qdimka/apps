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
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: "done")])
            _ = try await PipManager(executable: python, runner: runner).upgrade(row)
            let calls = await runner.calls()
            try expectEqual(calls.last?.executable, python)
            try expectEqual(calls.last?.arguments, ["-m", "pip", "--disable-pip-version-check", "install", "--upgrade", "--", "demo_pkg"])
        },
        Check(name: "pip user installs retain their user scope on upgrade") {
            let json = report(isUser: true)
            let row = try PipManager.parseProbe(json, executable: python)[0]
            let runner = RecordingRunner([.init(exitCode: 0, stdout: json), .init(exitCode: 0, stdout: "done")])
            _ = try await PipManager(executable: python, runner: runner).upgrade(row)
            let calls = await runner.calls()
            try expectEqual(calls.last?.arguments, ["-m", "pip", "--disable-pip-version-check", "install", "--upgrade", "--user", "--", "demo_pkg"])
        },
        Check(name: "pip checks match normalized distribution names") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report()),
                .init(exitCode: 0, stdout: #"[{"name":"Demo-Pkg","version":"1.0","latest_version":"2.0","latest_filetype":"wheel"}]"#)])
            let row = try await PipManager(executable: python, runner: runner).checkUpdates()[0]
            try expectEqual(row.updateStatus, .available)
            try expectEqual(row.latestVersion, "2.0")
        },
        Check(name: "pip network warnings never become an up-to-date result") {
            let runner = RecordingRunner([.init(exitCode: 0, stdout: report()), .init(exitCode: 0, stdout: "[]", stderr: "WARNING: Could not fetch URL")])
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
