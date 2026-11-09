import SwiftUI
import AppsCore

struct PackageDetailView: View {
    let package: PackageRecord
    @Bindable var model: AppModel
    @State private var confirmDeletion = false
    @State private var showLog = false
    private var canModify: Bool {
        model.coordinator.canModify(package)
    }

    var body: some View {
        let _ = model.language
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                updateSection
                HStack(spacing: 10) {
                    Button { Task { await model.mutate(package.id, action: .upgrade) } } label: {
                        Label(L("Update"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canModify || package.pinned || package.upgradeRestriction != nil)
                    Button(role: .destructive) { confirmDeletion = true } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }.disabled(!canModify || package.removalRestriction != nil)
                }.controlSize(.large)
                ForEach(Array(Set([package.upgradeRestriction, package.removalRestriction].compactMap { $0 })).sorted(), id: \.self) { reason in
                    Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Installation")).font(.headline)
                    metadata(L("Source"), package.source.title)
                    metadata(L("Type"), package.kind.title)
                    metadata(L("Version"), package.version, mono: true)
                    if let reference = package.packageReference { metadata(L("Package"), reference, mono: true) }
                    if let path = package.installationPath { metadata(L("Location"), path, mono: true) }
                    if let environment = package.environmentPath { metadata(L("Environment"), environment, mono: true) }
                    metadata(package.source == .pip ? L("Interpreter") : L("Manager"), package.managerPath, mono: true)
                }
                if !package.executables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Commands")).font(.headline)
                        ForEach(package.executables, id: \.self) { command in
                            Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                if !package.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Dependencies · \(package.dependencies.count)")).font(.headline)
                        Text(package.dependencies.joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if let notice = model.coordinator.notice {
                    Label {
                        Text(notice.message).textSelection(.enabled)
                    } icon: {
                        Image(systemName: notice.isError ? "exclamationmark.circle" : "checkmark.circle")
                    }.font(.callout).foregroundStyle(notice.isError ? Color.orange : Color.secondary)
                }
                Button { showLog = true } label: { Label(L("Open log"), systemImage: "terminal") }
                    .buttonStyle(.link)
            }
            .padding(30).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .sheet(isPresented: $showLog) { LogView(log: model.coordinator.log, language: model.language) }
        .alert(L("Remove \(package.name)?"), isPresented: $confirmDeletion) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Remove"), role: .destructive) {
                Task { await model.mutate(package.id, action: .uninstall) }
            }
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        let identity = L("\(package.name) \(package.version)\nSource: \(package.source.title)\n")
        let environment = package.environmentPath.map { L("Environment: \($0)\n") } ?? ""
        let location = package.source == .pip ? package.installationPath.map { L("Location: \($0)\n") } ?? "" : ""
        return identity + environment + location + "\n" + removalExplanation
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: package.kind == .cask ? "app.dashed" : package.source.symbol)
                .font(.system(size: 28, weight: .medium)).foregroundStyle(package.source.color)
                .frame(width: 62, height: 62)
                .background(package.source.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
            Text(package.name).font(.system(size: 30, weight: .bold)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !package.summary.isEmpty {
                Text(package.summary).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let homepage = package.homepage, let url = URL(string: homepage), ["https", "http"].contains(url.scheme) {
                Link(destination: url) { Label(L("Project website"), systemImage: "arrow.up.right.square") }.font(.caption)
            }
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(package.updateStatus.title, systemImage: package.updateStatus == .available ? "arrow.down.circle.fill" : "info.circle")
                .font(.callout.weight(.medium))
                .foregroundStyle(package.updateStatus == .available ? Color.blue : Color.secondary)
            if package.updateStatus == .available, let latest = package.latestVersion {
                Text("\(package.version) → \(latest)").font(.system(size: 12, design: .monospaced))
            }
            if package.source == .uv || package.source == .pipx {
                Text(L("A separate version check is not available yet. Update runs the tool's native upgrade command."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.updateStatus == .notChecked {
                Text(L("Click Check updates in the toolbar."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.source == .homebrew && package.updateStatus == .unsupported {
                Text(L("Homebrew catalog freshness is unverified. No detected update does not mean the installed version is latest."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.source == .pip && package.updateStatus == .unsupported && package.upgradeRestriction == nil {
                Text(L("The index response did not confirm this version is current."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if package.source == .homebrew && package.updateStatus == .available {
                Text(L("Based on the local Homebrew catalog. A newer version may exist if the catalog is stale."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if package.pinned {
                Label(L("Pinned in the package manager"), systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var removalExplanation: String {
        switch package.source {
        case .homebrew: L("Homebrew will check dependencies before removal.")
        case .uv, .pipx: L("The tool environment and its dependencies will be removed.")
        case .npm: L("This global npm package will be removed from its Node.js installation.")
        case .go: L("The selected binary will move to Trash. Go and its module cache remain.")
        case .cargo: L("Cargo will remove this crate's commands from the specified installation root. Rust and rustup remain.")
        case .pip: L("Only this Python distribution will be removed. The environment and other dependencies remain.")
        }
    }

    private func metadata(_ title: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(mono ? .system(size: 12, design: .monospaced) : .callout)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
