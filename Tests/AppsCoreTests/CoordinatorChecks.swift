import Foundation
import AppsCore

actor FakeManager: PackageManager {
    nonisolated let source: PackageSource
    nonisolated let executable: URL
    nonisolated let runner: any CommandRunning = RecordingRunner()
    var rows: [PackageRecord]
    let failList: Bool
    let mutationExit: Int32
    let delay: Duration
    var lists = 0, mutations = 0
    init(source: PackageSource, failList: Bool = false, mutationExit: Int32 = 0, delay: Duration = .zero) {
        self.source = source; executable = URL(fileURLWithPath: "/tools/" + source.executableName)
        self.failList = failList; self.mutationExit = mutationExit; self.delay = delay
        rows = [PackageRecord(name: "ruff", source: source, managerPath: "/tools/" + source.executableName, version: "1")]
    }
    func list() async throws -> [PackageRecord] {
        lists += 1
        if failList { throw CommandError.failed(1, "registry unavailable") }
        return rows
    }
    func checkUpdates() async throws -> [PackageRecord] { try await list() }
    func upgrade(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        try await Task.sleep(for: delay)
        if mutationExit == 0 { rows[0].version = "2" }
        return .init(exitCode: mutationExit, stdout: "upgrade output", stderr: mutationExit == 0 ? "" : "permission denied")
    }
    func uninstall(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        if mutationExit == 0 { rows = [] }
        return .init(exitCode: mutationExit, stdout: "uninstall output")
    }
    func counts() -> (lists: Int, mutations: Int) { (lists, mutations) }
}

enum CoordinatorChecks {
    static let all: [Check] = [
        Check(name: "A failed source does not hide another source") {
            let store = await PackageCoordinator(managers: [FakeManager(source: .homebrew), FakeManager(source: .uv, failList: true)])
            await store.reload()
            let rows = await store.packages
            let states = await store.sourceStates
            try expectEqual(rows.count, 1)
            try expectEqual(rows[0].source, .homebrew)
            try expectEqual(states[.uv]?.phase, .failed)
            try expectEqual(states[.pipx]?.phase, .missing)
        },
        Check(name: "Successful mutation refreshes only its own registry") {
            let brew = FakeManager(source: .homebrew), uv = FakeManager(source: .uv)
            let store = await PackageCoordinator(managers: [brew, uv])
            await store.reload()
            let row = await store.packages.first { $0.source == .uv }!
            await store.mutate(row.id, action: .upgrade)
            let rows = await store.packages
            try expectEqual(rows.first { $0.source == .uv }?.version, "2")
            let brewCounts = await brew.counts(), uvCounts = await uv.counts()
            try expectEqual(brewCounts.lists, 1)
            try expectEqual(uvCounts.lists, 2)
        },
        Check(name: "Repeated mutation is ignored while one is running") {
            let manager = FakeManager(source: .uv, delay: .milliseconds(150))
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            let first = Task { await store.mutate(id, action: .upgrade) }
            try await Task.sleep(for: .milliseconds(30))
            await store.mutate(id, action: .upgrade)
            await first.value
            let counts = await manager.counts()
            try expectEqual(counts.mutations, 1)
            let busy = await store.isBusy
            try expect(!busy)
        },
        Check(name: "A failed mutation never reports success and still refreshes") {
            let manager = FakeManager(source: .uv, mutationExit: 1)
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            await store.mutate(id, action: .upgrade)
            let notice = await store.notice
            let log = await store.log
            try expectEqual(notice?.isError, true)
            try expect(log.contains("permission denied"))
            let counts = await manager.counts()
            try expectEqual(counts.lists, 2)
        },
        Check(name: "Uninstalled packages leave the registry") {
            let store = await PackageCoordinator(managers: [FakeManager(source: .uv)])
            await store.reload()
            let id = await store.packages[0].id
            await store.mutate(id, action: .uninstall)
            let rows = await store.packages
            try expectEqual(rows.count, 0)
        },
        Check(name: "Search combines source and availability filters") {
            let rows = [PackageRecord(name: "ruff", source: .uv, managerPath: "/uv", version: "1"),
                        PackageRecord(name: "ruff", source: .homebrew, managerPath: "/brew", version: "1", summary: "Python linter", updateStatus: .available),
                        PackageRecord(name: "git", source: .homebrew, managerPath: "/brew", version: "2", updateStatus: .current)]
            let result = PackageQuery.filter(rows, source: .homebrew, search: "  PYTHON  ", updatesOnly: true)
            try expectEqual(result.map(\.name), ["ruff"])
            try expectEqual(PackageQuery.filter(rows, source: .uv, search: "", updatesOnly: true).count, 0)
        }
    ]
}
