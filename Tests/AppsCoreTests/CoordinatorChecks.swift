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
    var exposeUnderlyingCopy = false
    var lists = 0, mutations = 0
    init(source: PackageSource, failList: Bool = false, mutationExit: Int32 = 0, delay: Duration = .zero, keepOnUninstall: Bool = false, runtimeSuffix: String = "") {
        self.source = source; executable = URL(fileURLWithPath: "/tools/" + runtimeSuffix + source.executableName)
        self.failList = failList; self.mutationExit = mutationExit; self.delay = delay
        self.keepOnUninstall = keepOnUninstall
        rows = [PackageRecord(name: "ruff", source: source, managerPath: executable.path, version: "1")]
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
    func setRestrictions() { rows[0].upgradeRestriction = "Another manager owns this package"; rows[0].removalRestriction = "Another manager owns this package" }
    func setUnderlyingCopyScenario() { rows[0].installationPath = "/user/site-packages"; rows[0].isUserInstall = true; exposeUnderlyingCopy = true }
    func upgrade(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        try await Task.sleep(for: delay)
        if mutationExit == 0 { rows[0].version = "2" }
        return .init(exitCode: mutationExit, stdout: "upgrade output", stderr: mutationExit == 0 ? "" : "permission denied")
    }
    func uninstall(_ package: PackageRecord) async throws -> CommandResult {
        mutations += 1
        if mutationExit == 0 && exposeUnderlyingCopy { rows[0].installationPath = "/base/site-packages"; rows[0].isUserInstall = false }
        else if mutationExit == 0 && !keepOnUninstall { rows = [] }
        return .init(exitCode: mutationExit, stdout: "uninstall output")
    }
    func counts() -> (lists: Int, mutations: Int) { (lists, mutations) }
}

enum CoordinatorChecks {
    static let all: [Check] = [
        Check(name: "Deleting a user copy succeeds even when an underlying copy becomes visible") {
            let manager = FakeManager(source: .pip)
            await manager.setUnderlyingCopyScenario()
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            await store.mutate(id, action: .uninstall)
            let notice = await store.notice, rows = await store.packages
            try expectEqual(notice?.isError, false)
            try expectEqual(rows.count, 1)
            try expectEqual(rows[0].installationPath, "/base/site-packages")
        },
        Check(name: "Runtime switch replaces only its own source and invalidates old identities") {
            let brew = FakeManager(source: .homebrew), old = FakeManager(source: .pip)
            let store = await PackageCoordinator(managers: [brew, old])
            await store.reload()
            let oldID = await store.packages.first { $0.source == .pip }!.id
            let next = FakeManager(source: .pip, runtimeSuffix: "venv/")
            let accepted = await store.replaceManager(source: .pip, manager: next)
            try expect(accepted)
            let rows = await store.packages
            try expectEqual(rows.count, 2)
            try expect(!rows.contains { $0.id == oldID })
            try expectEqual(rows.first { $0.source == .pip }?.managerPath, "/tools/venv/python3")
            let counts = await brew.counts()
            try expectEqual(counts.lists, 1)
        },
        Check(name: "Runtime cannot change while a package mutation is active") {
            let manager = FakeManager(source: .pip, delay: .milliseconds(150))
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            let mutation = Task { await store.mutate(id, action: .upgrade) }
            try await Task.sleep(for: .milliseconds(30))
            let accepted = await store.replaceManager(source: .pip, manager: FakeManager(source: .pip, runtimeSuffix: "other/"))
            await mutation.value
            try expect(!accepted)
            let rows = await store.packages
            try expectEqual(rows[0].managerPath, "/tools/python3")
        },
        Check(name: "Coordinator enforces package restrictions before calling adapters") {
            let manager = FakeManager(source: .pip)
            await manager.setRestrictions()
            let store = await PackageCoordinator(managers: [manager])
            await store.reload()
            let id = await store.packages[0].id
            await store.mutate(id, action: .upgrade)
            await store.mutate(id, action: .uninstall)
            let counts = await manager.counts(), notice = await store.notice
            try expectEqual(counts.mutations, 0)
            try expectEqual(notice?.isError, true)
        },
        Check(name: "Saved missing Python is not silently replaced by another interpreter") {
            let path = "/nonexistent/apps-test/.venv/bin/python"
            let manager = ManagerDiscovery.managers(pythonPath: path).first { $0.source == .pip }
            try expectEqual(manager?.executable.path, path)
        },
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
