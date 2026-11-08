import SwiftUI
import AppsCore

extension PackageSource {
    var symbol: String {
        switch self { case .homebrew: "shippingbox"; case .uv: "bolt.fill"; case .pipx: "cube.transparent" }
    }
    var color: Color {
        switch self { case .homebrew: .orange; case .uv: .purple; case .pipx: .teal }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showLog = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 175, ideal: 200, max: 260)
        } content: {
            packageList
                .navigationSplitViewColumnWidth(min: 320, ideal: 430, max: 600)
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
                if model.coordinator.isBusy {
                    ProgressView().controlSize(.small).help(model.coordinator.activity ?? "Загрузка")
                }
                Button { Task { await model.reload() } } label: {
                    Label("Обновить список", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.coordinator.isBusy)
                .help("Перечитать установленные пакеты")
                Button { Task { await model.checkUpdates() } } label: {
                    Label("Проверить обновления", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.coordinator.isBusy)
                .help("Проверить локальный каталог Homebrew без изменения установок")
                Button { showLog = true } label: { Label("Журнал", systemImage: "terminal") }
                    .help("Журнал операций")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(isPresented: $showLog) { LogView(log: model.coordinator.log) }
        .task { await model.reload() }
        .onChange(of: model.sourceKey) { model.reconcileSelection() }
        .onChange(of: model.searchText) { model.reconcileSelection() }
        .onChange(of: model.updatesOnly) { model.reconcileSelection() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.sourceKey) {
                Section {
                    HStack {
                        Label("Все инструменты", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text("\(model.coordinator.packages.count)").foregroundStyle(.secondary).monospacedDigit()
                    }.tag("all")
                }
                Section("Источники") {
                    ForEach(PackageSource.allCases) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.symbol).foregroundStyle(source.color).frame(width: 16)
                            Text(source.title)
                            Spacer(minLength: 0)
                            sourceAccessory(source)
                        }
                        .tag(source.rawValue)
                        .help(model.coordinator.sourceStates[source]?.managerPath ?? "Менеджер не найден")
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text("apps").font(.system(size: 16, weight: .semibold))
                Text("Ваши инструменты на Mac")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
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
                    Text(model.selectedSource?.title ?? "Инструменты")
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
            }.padding(20)
            Divider()
            if let source = model.selectedSource, let state = model.coordinator.sourceStates[source], state.phase == .failed || state.phase == .missing {
                sourceMessage(source, state)
            } else if model.visiblePackages.isEmpty && !model.coordinator.isBusy {
                ContentUnavailableView {
                    Label(model.searchText.isEmpty ? "Пакетов нет" : "Ничего не найдено", systemImage: "magnifyingglass")
                } description: {
                    Text(model.updatesOnly ? "Обновления ещё не найдены. Отключите фильтр или запустите проверку." : "Измените поиск или выберите другой источник.")
                }
            } else {
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
            if state.phase == .failed {
                Button("Повторить") { Task { await model.reload() } }.disabled(model.coordinator.isBusy)
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
                    Text(failures > 0 ? "Источников с ошибкой: \(failures). Выберите источник для подробностей." : "\(model.coordinator.packages.count) пакетов")
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
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: package.kind == .cask ? "app.dashed" : package.source.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(package.source.color)
                .frame(width: 32, height: 32)
                .background(package.source.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
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
                } else {
                    Text(package.source.title).font(.system(size: 10)).foregroundStyle(.secondary)
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
