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
    let keepOnUninstall: Bool
    var failChecks = false
    var failAfterMutation = false
    var lists = 0, mutations = 0
    init(source: PackageSource, failList: Bool = false, mutationExit: Int32 = 0, delay: Duration = .zero, keepOnUninstall: Bool = false) {
        self.source = source; executable = URL(fileURLWithPath: "/tools/" + source.executableName)
        self.failList = failList; self.mutationExit = mutationExit; self.delay = delay
        self.keepOnUninstall = keepOnUninstall
        rows = [PackageRecord(name: "ruff", source: source, managerPath: "/tools/" + source.executableName, version: "1")]
    }
    func list() async throws -> [PackageRecord] {
        lists += 1
        if failList || (failAfterMutation && mutations > 0) { throw CommandError.failed(1, "registry unavailable") }
        if mutations == 0 { try await Task.sleep(for: delay) }
        return rows
    }
    func checkUpdates() async throws -> [PackageRecord] {
        if failChecks { throw CommandError.failed(1, "check unavailable") }
        return try await list().map { row in var row = row; row.updateStatus = .current; row.latestVersion = row.version; return row }
    }
    func setCheckFailure() { failChecks = true }
    func setRefreshFailure() { failAfterMutation = true }
    func upgrade(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        try await Task.sleep(for: delay)
        if mutationExit == 0 { rows[0].version = "2" }
        return .init(exitCode: mutationExit, stdout: "upgrade output", stderr: mutationExit == 0 ? "" : "permission denied")
    }
    func uninstall(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        if mutationExit == 0 && !keepOnUninstall { rows = [] }
        return .init(exitCode: mutationExit, stdout: "uninstall output")
    }
    func counts() -> (lists: Int, mutations: Int) { (lists, mutations) }
}

enum CoordinatorChecks {
    static let all: [Check] = [
        Check(name: "Successful exit without actual removal never reports deleted") {
            let store = await PackageCoordinator(managers: [FakeManager(source: .uv, keepOnUninstall: true)])
            await store.reload()
            let id = await store.packages[0].id
            await store.mutate(id, action: .uninstall)
            let notice = await store.notice
            try expectEqual(notice?.isError, true)
        },
        Check(name: "Unverifiable deletion reports uncertainty after refresh failure") {
            let manager = FakeManager(source: .uv)
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            await manager.setRefreshFailure()
            await store.mutate(id, action: .uninstall)
            let notice = await store.notice
            try expectEqual(notice?.isError, true)
        },
        Check(name: "Failed recheck clears old availability and reports a partial failure") {
            let manager = FakeManager(source: .homebrew)
            let store = await PackageCoordinator(managers: [manager])
            await store.checkUpdates()
            let initial = await store.packages[0].updateStatus
            try expectEqual(initial, .current)
            await manager.setCheckFailure()
            await store.checkUpdates()
            let row = await store.packages[0], notice = await store.notice
            try expectEqual(row.updateStatus, .notChecked)
            try expectEqual(row.latestVersion, nil)
            try expectEqual(notice?.isError, true)
        },
        Check(name: "A slow source does not delay publication of healthy sources") {
            let store = await PackageCoordinator(managers: [FakeManager(source: .homebrew, delay: .milliseconds(500)), FakeManager(source: .uv)])
            let loading = Task { await store.reload() }
            try await Task.sleep(for: .milliseconds(150))
            let published = await store.packages
            await loading.value
            try expectEqual(published.map(\.source), [.uv])
        },
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
