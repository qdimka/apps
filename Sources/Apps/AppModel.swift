import Foundation
import Observation
import AppsCore
import AppKit

@Observable @MainActor
final class AppModel {
    let coordinator: PackageCoordinator
    var selection: PackageRecord.ID?
    var searchText = ""
    private(set) var npmPath: String
    private(set) var pythonPath: String
    private(set) var npmChoices: [RuntimeChoice]
    private(set) var pythonChoices: [RuntimeChoice]
    var settingsError: String?
    var sourceKey = "all"
    private(set) var cargoRoot: String
    var updatesOnly: Bool {
        didSet { UserDefaults.standard.set(updatesOnly, forKey: "updatesOnly") }
    }
    var selectedSource: PackageSource? { PackageSource(rawValue: sourceKey) }
    var visiblePackages: [PackageRecord] {
        PackageQuery.filter(coordinator.packages, source: selectedSource, search: searchText, updatesOnly: updatesOnly)
    }
    var selectedPackage: PackageRecord? {
        visiblePackages.first { $0.id == selection }
    }
    init() {
        let defaults = UserDefaults.standard
        let npm = defaults.string(forKey: "npmExecutable") ?? RuntimeDiscovery.npmChoices().first?.path ?? ""
        let python = defaults.string(forKey: "pythonExecutable") ?? RuntimeDiscovery.preferredPython()?.path ?? ""
        npmPath = npm; pythonPath = python
        let cargo = defaults.string(forKey: "cargoInstallRoot") ?? CargoManager.defaultRoot.path
        cargoRoot = cargo
        npmChoices = Self.includingSaved(RuntimeDiscovery.npmChoices(), paths: (defaults.stringArray(forKey: "extraNpmExecutables") ?? []) + [npm])
        pythonChoices = Self.includingSaved(RuntimeDiscovery.pythonChoices(), paths: (defaults.stringArray(forKey: "extraPythonExecutables") ?? []) + [python])
        coordinator = PackageCoordinator(managers: ManagerDiscovery.managers(npmPath: npm.isEmpty ? nil : npm, pythonPath: python.isEmpty ? nil : python, cargoRoot: cargo))
        updatesOnly = UserDefaults.standard.bool(forKey: "updatesOnly")
    }

    func selectRuntime(_ source: PackageSource, path: String) async {
        guard !coordinator.isBusy, path.hasPrefix("/"), source == .npm || source == .pip else { return }
        let url = URL(fileURLWithPath: path)
        let manager: any PackageManager = source == .npm ? NPMManager(executable: url) : PipManager(executable: url)
        guard await coordinator.replaceManager(source: source, manager: manager) else { return }
        if source == .npm { npmPath = path; UserDefaults.standard.set(path, forKey: "npmExecutable") }
        else { pythonPath = path; UserDefaults.standard.set(path, forKey: "pythonExecutable") }
        settingsError = nil
        reconcileSelection()
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
        if source == .npm { npmChoices = Self.includingSaved(npmChoices, paths: [chosen.path]) }
        else { pythonChoices = Self.includingSaved(pythonChoices, paths: [chosen.path]) }
        Task { await selectRuntime(source, path: chosen.path) }
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

    private static func includingSaved(_ choices: [RuntimeChoice], paths: [String]) -> [RuntimeChoice] {
        var choices = choices
        for path in paths where path.hasPrefix("/") && !choices.contains(where: { $0.path == path }) {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            choices.append(RuntimeChoice(path: path, label: path + (exists ? "" : " (недоступен)")))
        }
        return choices
    }
    func reload() async { await coordinator.reload(); reconcileSelection() }
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
