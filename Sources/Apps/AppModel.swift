import Foundation
import Observation
import AppsCore
import AppKit

@Observable @MainActor
final class AppModel {
    let coordinator: PackageCoordinator
    var selection: PackageRecord.ID?
    var searchText = ""
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLocalization.preferenceKey)
            coordinator.relocalize(from: oldValue, to: language)
            settingsError = settingsError.map { AppLocalization.relocalized($0, from: oldValue, to: language) }
        }
    }
    private(set) var npmChoices: [RuntimeChoice]
    private(set) var pythonChoices: [RuntimeChoice]
    private(set) var isDiscovering = false
    @ObservationIgnored private var projectScan: Task<Void, Never>?
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
        language = AppLocalization.current
        let defaults = UserDefaults.standard
        let cargo = defaults.string(forKey: "cargoInstallRoot") ?? CargoManager.defaultRoot.path
        cargoRoot = cargo
        npmChoices = []; pythonChoices = []
        coordinator = PackageCoordinator(managers: [])
        updatesOnly = UserDefaults.standard.bool(forKey: "updatesOnly")
    }

    nonisolated private static func discovered(_ source: PackageSource, includeProjects: Bool = false) -> [RuntimeChoice] {
        let defaults = UserDefaults.standard
        let key = source == .npm ? "extraNpmExecutables" : "extraPythonExecutables"
        let previous = defaults.string(forKey: source == .npm ? "npmExecutable" : "pythonExecutable")
        let saved = (defaults.stringArray(forKey: key) ?? []) + (previous.map { [$0] } ?? []) + (source == .pip ? defaults.stringArray(forKey: "discoveredPythonExecutables") ?? [] : [])
        return RuntimeDiscovery.includingSaved(source == .npm ? RuntimeDiscovery.npmChoices() : RuntimeDiscovery.pythonChoices(includeProjects: includeProjects), paths: saved, python: source == .pip)
    }

    func chooseRuntime(_ source: PackageSource) {
        guard !coordinator.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = source == .pip
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose")
        panel.message = source == .pip ? L("Choose Python, a venv directory, or a project with .venv.") : L("Choose the npm executable belonging to the desired Node.js installation.")
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let chosen: URL?
        if source == .pip { chosen = RuntimeDiscovery.resolvePythonSelection(selected) }
        else { chosen = selected.lastPathComponent == "npm" && FileManager.default.isExecutableFile(atPath: selected.path) ? selected : nil }
        guard let chosen else { settingsError = source == .pip ? L("No Python was found at the selected location.") : L("Select an npm executable."); return }
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
        panel.message = L("Choose the Cargo installation directory containing bin and .crates2.json.")
        panel.prompt = L("Choose")
        guard panel.runModal() == .OK, let root = panel.url else { return }
        guard let executable = ManagerDiscovery.find(.cargo) else { settingsError = L("Cargo was not found."); return }
        Task {
            guard await coordinator.replaceManager(source: .cargo, manager: CargoManager(executable: executable, root: root)) else { return }
            cargoRoot = root.path; UserDefaults.standard.set(root.path, forKey: "cargoInstallRoot")
            settingsError = nil; reconcileSelection()
        }
    }

    func reload(scanProjects: Bool = true) async {
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
        if scanProjects && projectScan == nil {
            projectScan = Task { [weak self] in
                let choices = await Task.detached(priority: .utility) { Self.discovered(.pip, includeProjects: true) }.value
                guard let self else { return }
                UserDefaults.standard.set(choices.map(\.path), forKey: "discoveredPythonExecutables")
                self.projectScan = nil
                guard !self.coordinator.isBusy else { return }
                let additions = choices.filter { candidate in !self.pythonChoices.contains { $0.path == candidate.path } }
                guard !additions.isEmpty else { return }
                if await self.coordinator.addManagers(additions.map { PipManager(executable: URL(fileURLWithPath: $0.path)) }) {
                    self.pythonChoices = choices
                    self.reconcileSelection()
                }
            }
        }
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
