import SwiftUI
import AppsCore

struct PackageDetailView: View {
    let package: PackageRecord
    @Bindable var model: AppModel
    @State private var confirmDeletion = false
    @State private var showLog = false
    private var canModify: Bool {
        !model.coordinator.isBusy && model.coordinator.sourceStates[package.source]?.phase == .ready
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                updateSection
                HStack(spacing: 10) {
                    Button { Task { await model.mutate(package.id, action: .upgrade) } } label: {
                        Label("Обновить", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canModify || package.pinned || package.upgradeRestriction != nil)
                    Button(role: .destructive) { confirmDeletion = true } label: {
                        Label("Удалить", systemImage: "trash")
                    }.disabled(!canModify || package.removalRestriction != nil)
                }.controlSize(.large)
                ForEach(Array(Set([package.upgradeRestriction, package.removalRestriction].compactMap { $0 })).sorted(), id: \.self) { reason in
                    Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Установка").font(.headline)
                    metadata("Источник", package.source.title)
                    metadata("Тип", package.kind.title)
                    metadata("Версия", package.version, mono: true)
                    if let reference = package.packageReference { metadata("Пакет", reference, mono: true) }
                    if let path = package.installationPath { metadata("Расположение", path, mono: true) }
                    if let environment = package.environmentPath { metadata("Окружение", environment, mono: true) }
                    metadata(package.source == .pip ? "Интерпретатор" : "Менеджер", package.managerPath, mono: true)
                }
                if !package.executables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Команды").font(.headline)
                        ForEach(package.executables, id: \.self) { command in
                            Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                if !package.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Зависимости · \(package.dependencies.count)").font(.headline)
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
                Button { showLog = true } label: { Label("Открыть журнал", systemImage: "terminal") }
                    .buttonStyle(.link)
            }
            .padding(30).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .sheet(isPresented: $showLog) { LogView(log: model.coordinator.log) }
        .alert("Удалить \(package.name)?", isPresented: $confirmDeletion) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task { await model.mutate(package.id, action: .uninstall) }
            }
        } message: {
            Text("\(package.name) \(package.version)\nИсточник: \(package.source.title)\n" +
                 (package.environmentPath.map { "Окружение: \($0)\n" } ?? "") +
                 (package.source == .pip ? package.installationPath.map { "Расположение: \($0)\n" } ?? "" : "") + "\n" + removalExplanation)
        }
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
                Link(destination: url) { Label("Сайт проекта", systemImage: "arrow.up.right.square") }.font(.caption)
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
                Text("Проверка новой версии пока недоступна. «Обновить» запустит штатное обновление этого инструмента.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.updateStatus == .notChecked {
                Text("Нажмите «Проверить обновления» на панели инструментов.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.source == .homebrew && package.updateStatus == .unsupported {
                Text("Свежесть каталога Homebrew не подтверждена. Отсутствие найденного обновления не означает, что версия последняя.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.source == .pip && package.updateStatus == .unsupported && package.upgradeRestriction == nil {
                Text("Ответ индекса не подтвердил актуальность этой версии.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if package.source == .homebrew && package.updateStatus == .available {
                Text("По локальному каталогу Homebrew. Если он устарел, доступная версия может быть новее указанной.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if package.pinned {
                Label("Версия закреплена в менеджере", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var removalExplanation: String {
        switch package.source {
        case .homebrew: "Homebrew проверит зависимости перед удалением."
        case .uv, .pipx: "Будет удалено окружение инструмента вместе с его зависимостями."
        case .npm: "Будет удалена глобальная установка этого npm-пакета в выбранной установке Node.js."
        case .go: "Один выбранный бинарник будет перемещён в Корзину. Go и кеш модулей останутся."
        case .cargo: "Cargo удалит команды выбранного crate из указанного каталога установки. Rust и rustup останутся."
        case .pip: "Будет удалён только этот Python-пакет. Окружение и остальные зависимости останутся."
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
