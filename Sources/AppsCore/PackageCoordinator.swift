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
    @ObservationIgnored private var managers: [any PackageManager]

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

    public func replaceManager(source: PackageSource, manager: (any PackageManager)?) async -> Bool {
        guard !isBusy, manager == nil || manager?.source == source else { return false }
        isBusy = true; notice = nil; activity = "Выбор окружения: " + source.title
        defer { isBusy = false; activity = nil }
        managers.removeAll { $0.source == source }
        packages.removeAll { $0.source == source }
        if let manager {
            managers.append(manager)
            await refresh(manager, check: false)
        } else {
            sourceStates[source] = .init(phase: .missing, message: "Выберите установку этого источника.")
        }
        lastLoadedAt = Date()
        return true
    }

    private func loadAll(check: Bool) async {
        guard !isBusy else { return }
        isBusy = true; notice = nil
        defer { isBusy = false; activity = nil }
        activity = check ? "Проверка данных источников…" : "Загрузка источников…"
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
                ? .init(message: "Проверка завершена. npm/pip используют настроенные реестры; Homebrew — локальный каталог. Новые версии uv/pipx не проверяются.", isError: false)
                : .init(message: "Не удалось проверить: \(failed.joined(separator: ", ")). Их статусы обновлений сброшены.", isError: true)
        }
    }

    @discardableResult private func refresh(_ manager: any PackageManager, check: Bool) async -> Bool {
        let source = manager.source
        sourceStates[source] = .init(phase: .loading, message: "Загрузка…", managerPath: manager.executable.path)
        do {
            let rows = try await (check ? manager.checkUpdates() : manager.list())
            packages.removeAll { $0.source == source && $0.managerPath == manager.executable.path }
            packages += rows
            packages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sourceStates[source] = .init(phase: .ready, message: "\(rows.count) пакетов", managerPath: manager.executable.path,
                                        checkedAt: check && source == .homebrew ? Date() : nil)
            return true
        } catch {
            for index in packages.indices where packages[index].source == source {
                packages[index].updateStatus = .notChecked
                packages[index].latestVersion = nil
            }
            let message = shortError(error)
            sourceStates[source] = .init(phase: .failed, message: message, managerPath: manager.executable.path)
            appendLog("\(source.title): \(message)")
            return false
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
        if let reason = action == .upgrade ? package.upgradeRestriction : package.removalRestriction {
            notice = .init(message: reason, isError: true)
            return
        }
        isBusy = true; notice = nil
        activity = (action == .upgrade ? "Обновление " : "Удаление ") + package.name
        defer { isBusy = false; activity = nil }
        appendLog("\(Date().formatted()) — \(activity!) [\(package.source.title)]\nМенеджер: \(package.managerPath)")
        var commandSucceeded = false
        do {
            let result = try await (action == .upgrade ? manager.upgrade(package) : manager.uninstall(package))
            appendLog(result.log + "\nКод завершения: \(result.exitCode)")
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
                notice = .init(message: "Команда завершена, но подтвердить результат не удалось. Перечитайте источник.", isError: true)
            } else if action == .uninstall && packages.contains(where: { $0.id == id }) {
                notice = .init(message: "\(package.name) остался установленным. Подробности — в журнале.", isError: true)
            } else {
                notice = .init(message: package.name + (action == .upgrade ? ": команда обновления выполнена" : ": удалён"), isError: false)
            }
        }
    }

    private func appendLog(_ entry: String) {
        log += (log.isEmpty ? "" : "\n\n") + entry.suffix(80_000)
        if log.count > 300_000 { log = "…Ранние записи скрыты…\n" + log.suffix(250_000) }
    }

    private func shortError(_ error: Error) -> String {
        let message = error.localizedDescription
        return message.count > 4500 ? "…\n" + message.suffix(4000) : message
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
