import Foundation
import Observation
import AppsCore

@Observable @MainActor
final class AppModel {
    let coordinator: PackageCoordinator
    var selection: PackageRecord.ID?
    var searchText = ""
    var sourceKey: String {
        didSet { UserDefaults.standard.set(sourceKey, forKey: "selectedSource") }
    }
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
        coordinator = PackageCoordinator(managers: ManagerDiscovery.managers())
        sourceKey = UserDefaults.standard.string(forKey: "selectedSource") ?? "all"
        updatesOnly = UserDefaults.standard.bool(forKey: "updatesOnly")
    }
    func reload() async { await coordinator.reload(); reconcileSelection() }
    func checkUpdates() async { await coordinator.checkUpdates(); reconcileSelection() }
    func mutate(_ id: PackageRecord.ID, action: PackageAction) async {
        await coordinator.mutate(id, action: action)
        reconcileSelection()
    }
    func reconcileSelection() {
        if !visiblePackages.contains(where: { $0.id == selection }) { selection = nil }
    }
}
