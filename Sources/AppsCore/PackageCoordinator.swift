import Foundation
import Observation

public enum SourcePhase: Sendable { case missing, loading, ready, failed }

public struct SourceState: Sendable {
    public var phase: SourcePhase
    public var message: String
    public var managerPath: String?
    public var checkedAt: Date?
    public init(phase: SourcePhase, message: String, managerPath: String? = nil, checkedAt: Date? = nil) {
        self.phase = phase; self.message = message; self.managerPath = managerPath; self.checkedAt = checkedAt
    }
}

public enum PackageAction: Sendable { case upgrade, uninstall }
public struct OperationNotice: Sendable {
    public let message: String
    public let isError: Bool
}

@Observable @MainActor
public final class PackageCoordinator {
    public private(set) var packages: [PackageRecord] = []
    public private(set) var runtimeStates: [String: SourceState] = [:]
    public private(set) var sourceStates: [PackageSource: SourceState] = [:]
    public private(set) var isBusy = false
    public private(set) var activity: String?
    public private(set) var log = ""
    public private(set) var notice: OperationNotice?
    public private(set) var lastLoadedAt: Date?
    @ObservationIgnored private var managers: [any PackageManager]

    public init(managers: [any PackageManager]) {
        var seen = Set<String>()
        self.managers = managers.filter { seen.insert(Self.runtimeKey($0.source, $0.executable.path)).inserted }
        for manager in self.managers { runtimeStates[Self.runtimeKey(manager.source, manager.executable.path)] = .init(phase: .loading, message: L("Waiting to load"), managerPath: manager.executable.path) }
        for source in PackageSource.allCases {
            if let manager = managers.first(where: { $0.source == source }) {
                sourceStates[source] = .init(phase: .loading, message: L("Waiting to load"), managerPath: manager.executable.path)
            } else {
                sourceStates[source] = .init(phase: .missing, message: L("Manager not found. Install \(source.executableName) or check its location."))
            }
        }
    }

    // Change presentation only; checked versions, identities, and manager state stay intact.
    public func relocalize(from: AppLanguage, to: AppLanguage) {
        func translate(_ value: String) -> String { AppLocalization.relocalized(value, from: from, to: to) }
        packages = packages.map { original in
            var row = original
            row.upgradeRestriction = row.upgradeRestriction.map(translate)
            row.removalRestriction = row.removalRestriction.map(translate)
            return row
        }
        sourceStates = sourceStates.mapValues { original in
            var state = original; state.message = translate(state.message); return state
        }
        runtimeStates = runtimeStates.mapValues { original in
            var state = original; state.message = translate(state.message); return state
        }
        if let old = notice { notice = .init(message: translate(old.message), isError: old.isError) }
    }

    public func reload() async { await loadAll(check: false) }
    public func checkUpdates() async { await loadAll(check: true) }

    public static func runtimeKey(_ source: PackageSource, _ path: String) -> String { source.rawValue + "|" + path }

    public func canModify(_ package: PackageRecord) -> Bool {
        !isBusy && runtimeStates[Self.runtimeKey(package.source, package.managerPath)]?.phase == .ready
    }

    @discardableResult public func configureManagers(source: PackageSource, replacements: [any PackageManager]) -> Bool {
        guard !isBusy, replacements.allSatisfy({ $0.source == source }) else { return false }
        var seen = Set<String>()
        let unique = replacements.filter { seen.insert($0.executable.path).inserted }
        let paths = Set(unique.map { $0.executable.path })
        managers.removeAll { $0.source == source }; managers += unique
        packages.removeAll { $0.source == source && !paths.contains($0.managerPath) }
        runtimeStates = runtimeStates.filter { !$0.key.hasPrefix(source.rawValue + "|") || paths.contains($0.value.managerPath ?? "") }
        for manager in unique {
            let key = Self.runtimeKey(source, manager.executable.path)
            if runtimeStates[key] == nil { runtimeStates[key] = .init(phase: .loading, message: L("Waiting to load"), managerPath: manager.executable.path) }
        }
        aggregate(source)
        return true
    }

    @discardableResult public func addManagers(_ candidates: [any PackageManager]) async -> Bool {
        guard !isBusy else { return false }
        var known = Set(managers.map { Self.runtimeKey($0.source, $0.executable.path) })
        let additions = candidates.filter { known.insert(Self.runtimeKey($0.source, $0.executable.path)).inserted }
        guard !additions.isEmpty else { return true }
        isBusy = true; activity = L("Loading new environments…")
        defer { isBusy = false; activity = nil }
        managers += additions
        await withTaskGroup(of: Void.self) { group in
            for manager in additions { group.addTask { await self.refresh(manager, check: false) } }
            await group.waitForAll()
        }
        lastLoadedAt = Date()
        return true
    }

    public func replaceManager(source: PackageSource, manager: (any PackageManager)?) async -> Bool {
        guard configureManagers(source: source, replacements: manager.map { [$0] } ?? []) else { return false }
        isBusy = true; notice = nil; activity = L("Reading source: ") + source.title
        defer { isBusy = false; activity = nil }
        if let manager { await refresh(manager, check: false) }
        lastLoadedAt = Date()
        return true
    }

    private func aggregate(_ source: PackageSource) {
        let states = managers.filter { $0.source == source }.compactMap { runtimeStates[Self.runtimeKey(source, $0.executable.path)] }
        guard !states.isEmpty else {
            sourceStates[source] = .init(phase: .missing, message: L("Manager not found. Add an installation or check its location."))
            return
        }
        let failed = states.filter { $0.phase == .failed }
        let phase: SourcePhase = states.contains { $0.phase == .loading } ? .loading : failed.isEmpty ? .ready : .failed
        let message = failed.isEmpty ? L("\(packages.filter { $0.source == source }.count) packages · \(states.count) environments") : failed.map { ($0.managerPath ?? "") + "\n" + $0.message }.joined(separator: "\n\n")
        sourceStates[source] = .init(phase: phase, message: message, managerPath: states.count == 1 ? states[0].managerPath : nil,
            checkedAt: states.compactMap(\.checkedAt).max())
    }

    private func loadAll(check: Bool) async {
        guard !isBusy else { return }
        isBusy = true; notice = nil
        defer { isBusy = false; activity = nil }
        activity = check ? L("Checking sources…") : L("Loading sources…")
        await withTaskGroup(of: Void.self) { group in
            for manager in managers {
                group.addTask { await self.refresh(manager, check: check) }
            }
            await group.waitForAll()
        }
        lastLoadedAt = Date()
        if check {
            let failed = sourceStates.filter { $0.value.phase == .failed }.map { $0.key.title }.sorted()
            notice = failed.isEmpty
                ? .init(message: L("Detected updates are marked. Unverified versions remain unknown; Homebrew uses its local catalog."), isError: false)
                : .init(message: L("Could not check: \(failed.joined(separator: ", ")). Their update statuses were reset."), isError: true)
        }
    }

    @discardableResult private func refresh(_ manager: any PackageManager, check: Bool) async -> Bool {
        let source = manager.source
        let key = Self.runtimeKey(source, manager.executable.path)
        runtimeStates[key] = .init(phase: .loading, message: L("Loading…"), managerPath: manager.executable.path)
        aggregate(source)
        do {
            let rows = try await (check ? manager.checkUpdates() : manager.list())
            packages.removeAll { $0.source == source && $0.managerPath == manager.executable.path }
            packages += rows
            packages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            runtimeStates[key] = .init(phase: .ready, message: L("\(rows.count) packages"), managerPath: manager.executable.path,
                                        checkedAt: check && source == .homebrew ? Date() : nil)
            aggregate(source)
            return true
        } catch {
            for index in packages.indices where packages[index].source == source && packages[index].managerPath == manager.executable.path {
                packages[index].updateStatus = .notChecked
                packages[index].latestVersion = nil
            }
            let message = shortError(error)
            runtimeStates[key] = .init(phase: .failed, message: message, managerPath: manager.executable.path)
            aggregate(source)
            appendLog("\(source.title): \(message)")
            return false
        }
    }

    public func mutate(_ id: PackageRecord.ID, action: PackageAction) async {
        guard !isBusy else { return }
        guard let package = packages.first(where: { $0.id == id }),
              let manager = managers.first(where: { $0.source == package.source && $0.executable.path == package.managerPath }),
              runtimeStates[Self.runtimeKey(package.source, package.managerPath)]?.phase == .ready else {
            notice = .init(message: L("Refresh this source before trying again."), isError: true)
            return
        }
        if action == .upgrade && package.pinned {
            notice = .init(message: L("This package is pinned. Unpin it in its manager first."), isError: true)
            return
        }
        if let reason = action == .upgrade ? package.upgradeRestriction : package.removalRestriction {
            notice = .init(message: reason, isError: true)
            return
        }
        isBusy = true; notice = nil
        activity = (action == .upgrade ? L("Updating ") : L("Removing ")) + package.name
        defer { isBusy = false; activity = nil }
        appendLog(L("\(Date().formatted()) — \(activity!) [\(package.source.title)]\nManager: \(package.managerPath)"))
        var commandSucceeded = false
        do {
            let result = try await (action == .upgrade ? manager.upgrade(package) : manager.uninstall(package))
            appendLog(result.log + L("\nExit code: \(result.exitCode)"))
            _ = try result.requireSuccess()
            commandSucceeded = true
        } catch {
            let message = shortError(error)
            notice = .init(message: message, isError: true)
            appendLog(message)
        }
        // Even failed operations can partially change the registry.
        let refreshed = await refresh(manager, check: false)
        if commandSucceeded {
            if !refreshed {
                notice = .init(message: L("The command finished, but its result could not be verified. Refresh the source."), isError: true)
            } else if action == .uninstall && packages.contains(where: { row in
                guard row.id == id else { return false }
                if package.source != .pip { return true }
                return row.installationPath == package.installationPath && row.isUserInstall == package.isUserInstall &&
                    row.version == package.version && row.installationKey == package.installationKey
            }) {
                notice = .init(message: L("\(package.name) is still installed. See the log for details."), isError: true)
            } else if action == .uninstall && package.source == .pip && packages.contains(where: { $0.id == id }) {
                notice = .init(message: L("\(package.name): the selected installation was removed. Another copy is now visible."), isError: false)
            } else {
                notice = .init(message: package.name + (action == .upgrade ? L(": update command completed") : L(": removed")), isError: false)
            }
        }
    }

    private func appendLog(_ entry: String) {
        log += (log.isEmpty ? "" : "\n\n") + entry.suffix(80_000)
        if log.count > 300_000 { log = L("…Earlier log entries hidden…\n") + log.suffix(250_000) }
    }

    private func shortError(_ error: Error) -> String {
        let message = error.localizedDescription
        return message.count > 4500 ? "…\n" + message.suffix(4000) : message
    }
}

public enum PackageQuery {
    public static func filter(_ packages: [PackageRecord], source: PackageSource?, search: String, updatesOnly: Bool, managerPath: String? = nil) -> [PackageRecord] {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return packages.filter { row in
            (source == nil || row.source == source) && (managerPath == nil || row.managerPath == managerPath) && (!updatesOnly || row.updateStatus == .available) &&
            (search.isEmpty || row.name.localizedCaseInsensitiveContains(search) || row.summary.localizedCaseInsensitiveContains(search))
        }
    }
}
