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
                    Label("Выберите инструмент", systemImage: "shippingbox")
                } description: {
                    Text("Версии, расположение и действия\nпоявятся здесь.")
                }
            }
        }
        .navigationTitle("apps")
        .toolbar {
            ToolbarItemGroup {
                if model.coordinator.isBusy || model.isDiscovering {
                    ProgressView().controlSize(.small).help(model.coordinator.activity ?? "Загрузка")
                }
                Button { Task { await model.reload() } } label: {
                    Label("Обновить список", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.coordinator.isBusy || model.isDiscovering)
                .help("Перечитать установленные пакеты")
                Button { Task { await model.checkUpdates() } } label: {
                    Label("Проверить обновления", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.coordinator.isBusy || model.isDiscovering)
                .help("Проверить новые версии пакетов без установки")
                Button { showLog = true } label: { Label("Журнал", systemImage: "terminal") }
                    .help("Журнал операций")
                Button { showSettings = true } label: { Label("Источники", systemImage: "slider.horizontal.3") }
                    .help("Настроить окружения и каталог Cargo").disabled(model.coordinator.isBusy || model.isDiscovering)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(isPresented: $showLog) { LogView(log: model.coordinator.log) }
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
                Label("Все пакеты", systemImage: "square.stack.3d.up").tag("all")
                Section("Источники") {
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
                Text("Ваши инструменты на Mac").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
    }

    private var sourceStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Состояние источников").font(.headline)
            ForEach(PackageSource.allCases) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(source.title, systemImage: source.symbol).foregroundStyle(source.color)
                        Spacer()
                        sourceAccessory(source)
                    }
                    if let state = model.coordinator.sourceStates[source] {
                        Text(state.managerPath ?? (state.phase == .missing ? "Менеджер не найден" : "Несколько окружений")).font(.system(size: 10, design: .monospaced))
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
                    Text(model.selectedSource?.title ?? "Пакеты")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(model.visiblePackages.count)").font(.title3).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Text("Установлено на этом Mac").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $model.updatesOnly) { Image(systemName: "arrow.down.circle") }
                        .toggleStyle(.button).controlSize(.small)
                        .help("Только пакеты с найденным обновлением")
                        .accessibilityLabel("Только с обновлениями")
                }
                HStack(spacing: 12) {
                    if !model.environmentChoices.isEmpty {
                        Picker("Окружение", selection: $model.environmentKey) {
                            Text(model.selectedSource == .npm ? "Все установки Node.js" : model.selectedSource == .pip ? "Все Python-окружения" : "Все окружения").tag("all")
                            ForEach(model.environmentChoices) { choice in
                                Text(choice.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).tag(choice.path)
                            }
                        }.labelsHidden().accessibilityLabel("Фильтр по окружению")
                    }
                    Button { showSources.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.plain).help("Состояние источников")
                        .popover(isPresented: $showSources) { sourceStatus }
                }

            }.padding(20)
            Divider()
            if let source = model.selectedSource, let state = model.coordinator.sourceStates[source], (state.phase == .failed || state.phase == .missing) && model.visiblePackages.isEmpty {
                sourceMessage(source, state)
            } else if model.visiblePackages.isEmpty && !model.coordinator.isBusy {
                ContentUnavailableView {
                    Label(model.searchText.isEmpty ? "Пакетов нет" : "Ничего не найдено", systemImage: "magnifyingglass")
                } description: {
                    Text(model.updatesOnly ? "Обновления ещё не найдены. Отключите фильтр или запустите проверку." : "Измените поиск или выберите другой источник.")
                }
            } else {
                if let source = model.selectedSource, model.coordinator.sourceStates[source]?.phase == .failed {
                    Label("Некоторые окружения недоступны. Подробности — в состоянии источников.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(12)
                }
                List(selection: $model.selection) {
                    ForEach(model.visiblePackages) { package in
                        PackageRow(package: package).tag(package.id)
                    }
                }.listStyle(.inset)
            }
        }
        .searchable(text: $model.searchText, prompt: "Найти инструмент")
    }

    private func sourceMessage(_ source: PackageSource, _ state: SourceState) -> some View {
        ContentUnavailableView {
            Label(state.phase == .missing ? "\(source.title) не найден" : "Не удалось прочитать \(source.title)",
                  systemImage: state.phase == .missing ? "shippingbox" : "exclamationmark.triangle")
        } description: {
            Text(state.message).textSelection(.enabled)
        } actions: {
            if source == .npm || source == .pip {
                Button("Выбрать установку…") { showSettings = true }.disabled(model.coordinator.isBusy || model.isDiscovering)
            }
            if state.phase == .failed {
                Button("Повторить") { Task { await model.reload() } }.disabled(model.coordinator.isBusy || model.isDiscovering)
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
                    Text(failures > 0 ? "Источников с ошибкой: \(failures). Откройте состояние источников над списком." : "\(model.coordinator.packages.count) пакетов")
                }
                Spacer()
                if let date = model.coordinator.lastLoadedAt {
                    Text("Список: \(date.formatted(date: .omitted, time: .shortened))")
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
                    Label("Обновление", systemImage: "arrow.down.circle.fill").font(.system(size: 10)).foregroundStyle(.blue)
                } else if package.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                } else if package.upgradeRestriction != nil || package.removalRestriction != nil {
                    Image(systemName: "lock").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Операции ограничены")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct LogView: View {
    let log: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Журнал операций", systemImage: "terminal").font(.title2.bold())
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(log.isEmpty ? "Операций пока не было." : log)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }.padding(24).frame(width: 760, height: 520)
    }
}
