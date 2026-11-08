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
    public private(set) var sourceStates: [PackageSource: SourceState] = [:]
    public private(set) var isBusy = false
    public private(set) var activity: String?
    public private(set) var log = ""
    public private(set) var notice: OperationNotice?
    public private(set) var lastLoadedAt: Date?
    @ObservationIgnored private let managers: [any PackageManager]

    public init(managers: [any PackageManager]) {
        self.managers = managers
        for source in PackageSource.allCases {
            if let manager = managers.first(where: { $0.source == source }) {
                sourceStates[source] = .init(phase: .loading, message: "Ожидает загрузки", managerPath: manager.executable.path)
            } else {
                sourceStates[source] = .init(phase: .missing, message: "Менеджер не найден. Установите \(source.executableName) или проверьте его расположение.")
            }
        }
    }

    public func reload() async { await loadAll(check: false) }
    public func checkUpdates() async { await loadAll(check: true) }

    private func loadAll(check: Bool) async {
        guard !isBusy else { return }
        isBusy = true; notice = nil
        defer { isBusy = false; activity = nil }
        for manager in managers {
            activity = (check ? "Проверка обновлений: " : "Загрузка: ") + manager.source.title
            await refresh(manager, check: check)
        }
        lastLoadedAt = Date()
        if check {
            notice = .init(message: "Проверка завершена. Для uv и pipx наличие новой версии пока не определяется; их можно обновить вручную.", isError: false)
        }
    }

    private func refresh(_ manager: any PackageManager, check: Bool) async {
        let source = manager.source
        sourceStates[source] = .init(phase: .loading, message: "Загрузка…", managerPath: manager.executable.path)
        do {
            let rows = try await (check ? manager.checkUpdates() : manager.list())
            packages.removeAll { $0.source == source && $0.managerPath == manager.executable.path }
            packages += rows
            packages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sourceStates[source] = .init(phase: .ready, message: "\(rows.count) пакетов", managerPath: manager.executable.path,
                                        checkedAt: check && source == .homebrew ? Date() : nil)
        } catch {
            sourceStates[source] = .init(phase: .failed, message: error.localizedDescription, managerPath: manager.executable.path)
            appendLog("\(source.title): \(error.localizedDescription)")
        }
    }

    public func mutate(_ id: PackageRecord.ID, action: PackageAction) async {
        guard !isBusy else { return }
        guard let package = packages.first(where: { $0.id == id }),
              let manager = managers.first(where: { $0.source == package.source && $0.executable.path == package.managerPath }),
              sourceStates[package.source]?.phase == .ready else {
            notice = .init(message: "Сначала обновите список этого источника.", isError: true)
            return
        }
        if action == .upgrade && package.pinned {
            notice = .init(message: "Версия пакета закреплена в менеджере. Сначала снимите закрепление.", isError: true)
            return
        }
        isBusy = true; notice = nil
        activity = (action == .upgrade ? "Обновление " : "Удаление ") + package.name
        defer { isBusy = false; activity = nil }
        appendLog("\(Date().formatted()) — \(activity!) [\(package.source.title)]\nМенеджер: \(package.managerPath)")
        do {
            let result = try await (action == .upgrade ? manager.upgrade(package) : manager.uninstall(package))
            appendLog(result.log + "\nКод завершения: \(result.exitCode)")
            _ = try result.requireSuccess()
            notice = .init(message: package.name + (action == .upgrade ? ": обновление завершено" : ": удалён"), isError: false)
        } catch {
            notice = .init(message: error.localizedDescription, isError: true)
            appendLog(error.localizedDescription)
        }
        // Even failed operations can partially change the registry.
        await refresh(manager, check: false)
    }

    private func appendLog(_ entry: String) {
        log += (log.isEmpty ? "" : "\n\n") + entry
        if log.count > 300_000 { log = "…Ранние записи скрыты…\n" + log.suffix(250_000) }
    }
}

public enum PackageQuery {
    public static func filter(_ packages: [PackageRecord], source: PackageSource?, search: String, updatesOnly: Bool) -> [PackageRecord] {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return packages.filter { row in
            (source == nil || row.source == source) && (!updatesOnly || row.updateStatus == .available) &&
            (search.isEmpty || row.name.localizedCaseInsensitiveContains(search) || row.summary.localizedCaseInsensitiveContains(search))
        }
    }
}
