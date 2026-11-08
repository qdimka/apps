import Foundation
import AppsCore

enum CargoChecks {
    static let cargo = URL(fileURLWithPath: "/tools/cargo")
    static func fixture(source: String = "registry+https://github.com/rust-lang/crates.io-index") throws -> URL {
        let root = try GoChecks.fixture()
        try FileManager.default.removeItem(at: root.appendingPathComponent("tool"))
        let json: [String: Any] = ["installs": ["tool 1.0.0 (\(source))": ["version_req": "*", "bins": ["tool"], "features": ["fast"], "all_features": false, "no_default_features": true, "profile": "release", "target": "aarch64-apple-darwin"]]]
        try JSONSerialization.data(withJSONObject: json).write(to: root.appendingPathComponent(".crates2.json"))
        return root
    }
    static var all: [Check] { [
        Check(name: "Cargo legacy inventory stays visible with restricted operations") {
            let root = try GoChecks.fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try Data("[v1]".utf8).write(to: root.appendingPathComponent(".crates.toml"))
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "tool v1.0.0:\n    tool\n")])
            let rows = try await CargoManager(executable: cargo, root: root, runner: runner).list()
            try expectEqual(rows.count, 1)
            try expect(rows[0].upgradeRestriction != nil && rows[0].removalRestriction != nil)
        },
        Check(name: "Unified query preserves equal names from all sources and Cargo roots") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            var rows = try await CargoManager(executable: cargo, root: root).list()
            var second = rows[0]; second.identityScope = "/another/root"; rows.append(second)
            rows.append(PackageRecord(name: "tool", source: .go, managerPath: "/go", version: "1"))
            rows.append(PackageRecord(name: "tool", source: .npm, managerPath: "/npm", version: "1"))
            try expectEqual(Set(rows.map(\.id)).count, 4)
            try expectEqual(PackageQuery.filter(rows, source: nil, search: "tool", updatesOnly: false).count, 4)
            try expectEqual(PackageQuery.filter(rows, source: .cargo, search: "", updatesOnly: false).count, 2)
        },
        Check(name: "Cargo empty tracking files describe an empty installation") {
            let root = try GoChecks.fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try Data().write(to: root.appendingPathComponent(".crates2.json"))
            try expectEqual(try await CargoManager(executable: cargo, root: root).list().count, 0)
        },
        Check(name: "Cargo metadata preserves root source and build configuration") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let rows = try await CargoManager(executable: cargo, root: root).list()
            try expectEqual(rows.count, 1)
            try expectEqual(rows[0].source, .cargo)
            try expectEqual(rows[0].environmentPath, root.path)
            try expectEqual(rows[0].executables, ["tool"])
            try expectEqual(rows[0].buildOptions["features"], "fast")
            try expect(rows[0].packageReference!.contains("#tool@1.0.0"))
        },
        Check(name: "Cargo uninstall uses qualified package ID and explicit root") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "")])
            let manager = CargoManager(executable: cargo, root: root, runner: runner)
            _ = try await manager.uninstall(try await manager.list()[0])
            let calls = await runner.calls()
            try expect(calls[0].arguments.contains(root.path))
            try expect(calls[0].arguments.contains("registry+https://github.com/rust-lang/crates.io-index#tool@1.0.0"))
        },
        Check(name: "Cargo newer install preserves bins features target and registry") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "tool = \"2.0.0\" # Tool\nother = \"9.0.0\""), .init(exitCode: 0, stdout: "")])
            let manager = CargoManager(executable: cargo, root: root, runner: runner)
            _ = try await manager.upgrade(try await manager.list()[0])
            let args = await runner.calls().last!.arguments
            for value in ["--root", root.path, "--bin", "tool", "--features", "fast", "--no-default-features", "--target", "aarch64-apple-darwin", "--version", "=2.0.0", "--registry", "crates-io"] { try expect(args.contains(value)) }
            try expect(!args.contains("--force"))
        },
        Check(name: "Cargo Git and path origins cannot silently become crates.io") {
            for source in ["git+https://example.com/tool#abcdef", "path+file:///tmp/tool"] {
                let root = try fixture(source: source); defer { try? FileManager.default.removeItem(at: root) }
                let rows = try await CargoManager(executable: cargo, root: root).list()
                try expect(rows[0].upgradeRestriction != nil)
            }
        },
        Check(name: "Cargo refuses changed install metadata and malformed tracking JSON") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let manager = CargoManager(executable: cargo, root: root, runner: RecordingRunner([.init(exitCode: 0, stdout: "")]))
            let row = try await manager.list()[0]
            try Data("{}".utf8).write(to: root.appendingPathComponent(".crates2.json"))
            do { _ = try await manager.uninstall(row); throw CheckFailure(description: "Stale metadata accepted") } catch { try expect(error is ManagerError) }
            try Data("bad".utf8).write(to: root.appendingPathComponent(".crates2.json"))
            do { _ = try await manager.list(); throw CheckFailure(description: "Malformed metadata accepted") } catch { try expect(error is ManagerError) }
        },
        Check(name: "Cargo search cannot downgrade or substitute a similarly named crate") {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let runner = RecordingRunner([.init(exitCode: 0, stdout: "tool = \"0.9.0\"\ntool-other = \"9.0.0\"")])
            let manager = CargoManager(executable: cargo, root: root, runner: runner)
            let row = try await manager.list()[0]
            _ = try await manager.upgrade(row)
            try expectEqual(await runner.calls().count, 1)
        }
    ] }
}
