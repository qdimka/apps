import Foundation
import Observation
import AppsCore
import AppKit

@Observable @MainActor
final class AppModel {
    let coordinator: PackageCoordinator
    var selection: PackageRecord.ID?
    var searchText = ""
    private(set) var npmChoices: [RuntimeChoice]
    private(set) var pythonChoices: [RuntimeChoice]
    private(set) var isDiscovering = false
    var settingsError: String?
    var sourceKey = "all"
    var environmentKey = "all"
    var environmentChoices: [RuntimeChoice] {
        switch selectedSource {
        case .npm: npmChoices
        case .pip: pythonChoices
        case nil: npmChoices + pythonChoices
        default: []
        }
    }
    private(set) var cargoRoot: String
    var updatesOnly: Bool {
        didSet { UserDefaults.standard.set(updatesOnly, forKey: "updatesOnly") }
    }
    var selectedSource: PackageSource? { PackageSource(rawValue: sourceKey) }
    var visiblePackages: [PackageRecord] {
        PackageQuery.filter(coordinator.packages, source: selectedSource, search: searchText, updatesOnly: updatesOnly, managerPath: environmentKey == "all" ? nil : environmentKey)
    }
    var selectedPackage: PackageRecord? {
        visiblePackages.first { $0.id == selection }
    }
    init() {
        let defaults = UserDefaults.standard
        let cargo = defaults.string(forKey: "cargoInstallRoot") ?? CargoManager.defaultRoot.path
        cargoRoot = cargo
        npmChoices = []; pythonChoices = []
        coordinator = PackageCoordinator(managers: [])
        updatesOnly = UserDefaults.standard.bool(forKey: "updatesOnly")
    }

    nonisolated private static func discovered(_ source: PackageSource) -> [RuntimeChoice] {
        let defaults = UserDefaults.standard
        let key = source == .npm ? "extraNpmExecutables" : "extraPythonExecutables"
        let previous = defaults.string(forKey: source == .npm ? "npmExecutable" : "pythonExecutable")
        let saved = (defaults.stringArray(forKey: key) ?? []) + (previous.map { [$0] } ?? [])
        return RuntimeDiscovery.includingSaved(source == .npm ? RuntimeDiscovery.npmChoices() : RuntimeDiscovery.pythonChoices(), paths: saved, python: source == .pip)
    }

    func chooseRuntime(_ source: PackageSource) {
        guard !coordinator.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = source == .pip
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = source == .pip ? "Выберите Python, каталог venv или проект с .venv." : "Выберите исполняемый файл npm нужной установки Node.js."
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let chosen: URL?
        if source == .pip { chosen = RuntimeDiscovery.resolvePythonSelection(selected) }
        else { chosen = selected.lastPathComponent == "npm" && FileManager.default.isExecutableFile(atPath: selected.path) ? selected : nil }
        guard let chosen else { settingsError = source == .pip ? "Python в выбранном расположении не найден." : "Нужен исполняемый файл npm."; return }
        let key = source == .npm ? "extraNpmExecutables" : "extraPythonExecutables"
        var saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !saved.contains(chosen.path) { saved.append(chosen.path) }
        UserDefaults.standard.set(saved, forKey: key)
        Task { await reload() }
    }

    func chooseCargoRoot() {
        guard !coordinator.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Выберите каталог установки Cargo, содержащий bin и .crates2.json."
        panel.prompt = "Выбрать"
        guard panel.runModal() == .OK, let root = panel.url else { return }
        guard let executable = ManagerDiscovery.find(.cargo) else { settingsError = "Cargo не найден."; return }
        Task {
            guard await coordinator.replaceManager(source: .cargo, manager: CargoManager(executable: executable, root: root)) else { return }
            cargoRoot = root.path; UserDefaults.standard.set(root.path, forKey: "cargoInstallRoot")
            settingsError = nil; reconcileSelection()
        }
    }

    func reload() async {
        guard !coordinator.isBusy, !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        let cargo = cargoRoot
        let inventory = await Task.detached(priority: .userInitiated) {
            let npm = Self.discovered(.npm), python = Self.discovered(.pip)
            return (npm, python, ManagerDiscovery.environmentManagers(npm: npm, python: python, cargoRoot: cargo))
        }.value
        guard !coordinator.isBusy else { return }
        npmChoices = inventory.0; pythonChoices = inventory.1
        for source in PackageSource.allCases {
            _ = coordinator.configureManagers(source: source, replacements: inventory.2.filter { $0.source == source })
        }
        if environmentKey != "all" && !environmentChoices.contains(where: { $0.path == environmentKey }) { environmentKey = "all" }
        await coordinator.reload(); reconcileSelection()
    }
    func checkUpdates() async { await coordinator.checkUpdates(); reconcileSelection() }
    func mutate(_ id: PackageRecord.ID, action: PackageAction) async {
        await coordinator.mutate(id, action: action)
        if action == .uninstall && coordinator.notice?.isError == false { selection = nil }
        else { reconcileSelection() }
    }
    func reconcileSelection() {
        if !visiblePackages.contains(where: { $0.id == selection }) { selection = nil }
    }
}
