import SwiftUI
import AppsCore

extension PackageSource {
    var symbol: String {
        switch self { case .homebrew: "shippingbox"; case .uv: "bolt.fill"; case .pipx: "cube.transparent"; case .npm: "curlybraces.square"; case .pip: "cube.box"; case .go: "terminal"; case .cargo: "shippingbox.fill" }
    }
    var color: Color {
        switch self { case .homebrew: .orange; case .uv: .purple; case .pipx: .teal; case .npm: .red; case .pip: .blue; case .go: .cyan; case .cargo: .brown }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showLog = false
    @State private var showSettings = false
    @State private var showSources = false

    var body: some View {
        let _ = model.language
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } content: {
            packageList
                .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 650)
        } detail: {
            if let package = model.selectedPackage {
                PackageDetailView(package: package, model: model)
            } else {
                ContentUnavailableView {
                    Label(L("Select a tool"), systemImage: "shippingbox")
                } description: {
                    Text(L("Versions, locations, and actions\nwill appear here."))
                }
            }
        }
        .navigationTitle("apps")
        .toolbar {
            ToolbarItemGroup {
                if model.coordinator.isBusy || model.isDiscovering {
                    ProgressView().controlSize(.small).help(model.coordinator.activity ?? L("Loading"))
                }
                Button { Task { await model.reload() } } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.coordinator.isBusy || model.isDiscovering)
                .help(L("Reread installed packages"))
                Button { Task { await model.checkUpdates() } } label: {
                    Label(L("Check updates"), systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.coordinator.isBusy || model.isDiscovering)
                .help(L("Check for newer versions without installing packages"))
                Button { showLog = true } label: { Label(L("Log"), systemImage: "terminal") }
                    .help(L("Operation log"))
                Button { showSettings = true } label: { Label(L("Settings"), systemImage: "slider.horizontal.3") }
                    .help(L("Configure environments and the Cargo directory")).disabled(model.coordinator.isBusy)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(isPresented: $showLog) { LogView(log: model.coordinator.log, language: model.language) }
        .sheet(isPresented: $showSettings) { SourceSettingsView(model: model) }
        .task { await model.reload() }
        .onChange(of: model.sourceKey) { model.environmentKey = "all"; model.reconcileSelection() }
        .onChange(of: model.environmentKey) { model.reconcileSelection() }
        .onChange(of: model.searchText) { model.reconcileSelection() }
        .onChange(of: model.updatesOnly) { model.reconcileSelection() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.sourceKey) {
                Label(L("All packages"), systemImage: "square.stack.3d.up").tag("all")
                Section(L("Sources")) {
                    ForEach(PackageSource.allCases) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.symbol).foregroundStyle(source.color).frame(width: 16)
                            Text(source.title)
                            Spacer(minLength: 0)
                            sourceAccessory(source)
                        }.tag(source.rawValue)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("apps").font(.system(size: 16, weight: .semibold))
                Text(L("Your tools on this Mac")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
    }

    private var sourceStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Source status")).font(.headline)
            ForEach(PackageSource.allCases) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(source.title, systemImage: source.symbol).foregroundStyle(source.color)
                        Spacer()
                        sourceAccessory(source)
                    }
                    if let state = model.coordinator.sourceStates[source] {
                        Text(state.managerPath ?? (state.phase == .missing ? L("Manager not found") : L("Multiple environments"))).font(.system(size: 10, design: .monospaced))
                        if state.phase == .failed || state.phase == .missing {
                            Text(state.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(20).frame(width: 400)
    }

    @ViewBuilder private func sourceAccessory(_ source: PackageSource) -> some View {
        let state = model.coordinator.sourceStates[source]
        switch state?.phase {
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .missing: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        case .loading: ProgressView().controlSize(.mini)
        default:
            Text("\(model.coordinator.packages.filter { $0.source == source }.count)")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var packageList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.selectedSource?.title ?? L("Packages"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(model.visiblePackages.count)").font(.title3).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Text(L("Installed on this Mac")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $model.updatesOnly) { Image(systemName: "arrow.down.circle") }
                        .toggleStyle(.button).controlSize(.small)
                        .help(L("Only packages with a detected update"))
                        .accessibilityLabel(L("Updates only"))
                }
                HStack(spacing: 12) {
                    if !model.environmentChoices.isEmpty {
                        Picker(L("Environment"), selection: $model.environmentKey) {
                            Text(model.selectedSource == .npm ? L("All Node.js installations") : model.selectedSource == .pip ? L("All Python environments") : L("All environments")).tag("all")
                            ForEach(model.environmentChoices) { choice in
                                Text(choice.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).tag(choice.path)
                            }
                        }.labelsHidden().accessibilityLabel(L("Filter by environment"))
                    }
                    Button { showSources.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.plain).help(L("Source status"))
                        .popover(isPresented: $showSources) { sourceStatus }
                }

            }.padding(20)
            Divider()
            if let source = model.selectedSource, let state = model.coordinator.sourceStates[source], (state.phase == .failed || state.phase == .missing) && model.visiblePackages.isEmpty {
                sourceMessage(source, state)
            } else if model.visiblePackages.isEmpty && !model.coordinator.isBusy {
                ContentUnavailableView {
                    Label(model.searchText.isEmpty ? L("No packages") : L("No results"), systemImage: "magnifyingglass")
                } description: {
                    Text(model.updatesOnly ? L("No updates have been found yet. Disable this filter or run a check.") : L("Change the search or choose another source."))
                }
            } else {
                if let source = model.selectedSource, model.coordinator.sourceStates[source]?.phase == .failed {
                    Label(L("Some environments are unavailable. See Source status for details."), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(12)
                }
                List(selection: $model.selection) {
                    ForEach(model.visiblePackages) { package in
                        PackageRow(package: package, language: model.language).tag(package.id)
                    }
                }.listStyle(.inset)
            }
        }
        .searchable(text: $model.searchText, prompt: L("Find a tool"))
    }

    private func sourceMessage(_ source: PackageSource, _ state: SourceState) -> some View {
        ContentUnavailableView {
            Label(state.phase == .missing ? L("\(source.title) not found") : L("Could not read \(source.title)"),
                  systemImage: state.phase == .missing ? "shippingbox" : "exclamationmark.triangle")
        } description: {
            Text(state.message).textSelection(.enabled)
        } actions: {
            if source == .npm || source == .pip {
                Button(L("Choose installation…")) { showSettings = true }.disabled(model.coordinator.isBusy || model.isDiscovering)
            }
            if state.phase == .failed {
                Button(L("Try again")) { Task { await model.reload() } }.disabled(model.coordinator.isBusy || model.isDiscovering)
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if let activity = model.coordinator.activity {
                    Text(activity).lineLimit(1)
                } else if let notice = model.coordinator.notice {
                    Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(notice.isError ? Color.orange : Color.green)
                    Text(notice.message).lineLimit(1).help(notice.message)
                } else {
                    let failures = model.coordinator.sourceStates.values.filter { $0.phase == .failed }.count
                    Image(systemName: failures > 0 ? "exclamationmark.circle" : "internaldrive")
                    Text(failures > 0 ? L("Sources with errors: \(failures). Open Source status above the list.") : L("\(model.coordinator.packages.count) packages"))
                }
                Spacer()
                if let date = model.coordinator.lastLoadedAt {
                    Text(L("Listed: \(date.formatted(date: .omitted, time: .shortened))"))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 32)
            .background(.bar)
        }
    }
}

private struct PackageRow: View {
    let package: PackageRecord
    let language: AppLanguage
    private var environmentLabel: String {
        let runtimeRoot = URL(fileURLWithPath: package.managerPath).deletingLastPathComponent().deletingLastPathComponent().path
        let path = package.source == .npm ? runtimeRoot : package.environmentPath ?? runtimeRoot
        let abbreviated = path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        return (package.source == .npm ? "Node.js · " : "Python · ") + abbreviated
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: package.kind == .cask ? "app.dashed" : package.source.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(package.source.color)
                .frame(width: 32, height: 32)
                .background(package.source.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(package.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(package.source.title).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(package.source.color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(package.source.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
                if package.source == .npm || package.source == .pip {
                    Text(environmentLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(package.managerPath + "\n" + (package.environmentPath ?? ""))
                }
                Text(package.summary.isEmpty ? package.kind.title : package.summary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(package.version).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                if package.updateStatus == .available {
                    Label(L("Available"), systemImage: "arrow.down.circle.fill").font(.system(size: 10)).foregroundStyle(.blue)
                } else if package.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                } else if package.upgradeRestriction != nil || package.removalRestriction != nil {
                    Image(systemName: "lock").font(.caption2).foregroundStyle(.secondary).accessibilityLabel(L("Operations restricted"))
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct LogView: View {
    let log: String
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Operation log"), systemImage: "terminal").font(.title2.bold())
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(log.isEmpty ? L("No operations yet.") : log)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }.padding(24).frame(width: 760, height: 520)
    }
}
