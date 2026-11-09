import Foundation
import AppsCore

enum EnvironmentChecks {
    static var all: [Check] { [
        Check(name: "Same-source runtimes stay distinct and mutations target one environment") {
            let a = FakeManager(source: .pip, runtimeSuffix: "a/"), b = FakeManager(source: .pip, runtimeSuffix: "b/")
            let store = await PackageCoordinator(managers: [a, b])
            await store.reload()
            let rows = await store.packages
            try expectEqual(rows.count, 2)
            let target = rows.first { $0.managerPath == b.executable.path }!
            await store.mutate(target.id, action: .uninstall)
            try expectEqual(await a.counts().mutations, 0)
            try expectEqual(await b.counts().mutations, 1)
            try expectEqual(await store.packages.count, 1)
        },
        Check(name: "Failed runtime cannot erase healthy runtime status or block its actions") {
            let a = FakeManager(source: .npm, runtimeSuffix: "a/"), b = FakeManager(source: .npm, runtimeSuffix: "b/")
            let store = await PackageCoordinator(managers: [a, b]); await store.reload()
            await b.setCheckFailure(); await store.checkUpdates()
            let rows = await store.packages
            let healthy = rows.first { $0.managerPath == a.executable.path }!, failed = rows.first { $0.managerPath == b.executable.path }!
            try expectEqual(healthy.updateStatus, .current)
            try expectEqual(failed.updateStatus, .notChecked)
            let healthyAllowed = await store.canModify(healthy), failedAllowed = await store.canModify(failed)
            try expect(healthyAllowed)
            try expect(!failedAllowed)
            await store.mutate(healthy.id, action: .upgrade)
            try expectEqual(await a.counts().mutations, 1)
            try expectEqual(await store.sourceStates[.npm]?.phase, .failed)
        },
        Check(name: "Environment filter changes the view without removing other installations") {
            let rows = [PackageRecord(name: "ruff", source: .pip, managerPath: "/a/python", version: "1"), PackageRecord(name: "ruff", source: .pip, managerPath: "/b/python", version: "2")]
            try expectEqual(PackageQuery.filter(rows, source: .pip, search: "", updatesOnly: false, managerPath: nil).count, 2)
            try expectEqual(PackageQuery.filter(rows, source: .pip, search: "", updatesOnly: false, managerPath: "/b/python").map(\.version), ["2"])
        },
        Check(name: "Runtime discovery finds project venvs and preserves distinct symlink interpreters") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let base = home.appendingPathComponent("base/bin/python")
            try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RuntimeChecks.executable(base)
            for name in ["a", "b"] {
                let env = home.appendingPathComponent("Projects/\(name)/.venv")
                try FileManager.default.createDirectory(at: env.appendingPathComponent("bin"), withIntermediateDirectories: true)
                try Data("home = /base".utf8).write(to: env.appendingPathComponent("pyvenv.cfg"))
                try FileManager.default.createSymbolicLink(at: env.appendingPathComponent("bin/python"), withDestinationURL: base)
            }
            try expectEqual(RuntimeDiscovery.pythonChoices(searchPaths: [], home: home, includeProjects: false).count, 0)
            let choices = RuntimeDiscovery.pythonChoices(searchPaths: [], home: home)
            try expectEqual(choices.count, 2)
            try expect(choices.contains { $0.path.contains("/a/.venv/") })
        }
    ] }
}
