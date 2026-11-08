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
                    .disabled(!canModify || package.pinned)
                    Button(role: .destructive) { confirmDeletion = true } label: {
                        Label("Удалить", systemImage: "trash")
                    }.disabled(!canModify)
                }.controlSize(.large)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Установка").font(.headline)
                    metadata("Источник", package.source.title)
                    metadata("Тип", package.kind.title)
                    metadata("Версия", package.version, mono: true)
                    if let path = package.installationPath { metadata("Расположение", path, mono: true) }
                    metadata("Менеджер", package.managerPath, mono: true)
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
            Text("\(package.name) \(package.version)\nИсточник: \(package.source.title)\n\n" +
                 (package.source == .homebrew ? "Homebrew проверит зависимости перед удалением." : "Будет удалено окружение инструмента вместе с его зависимостями."))
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
            if package.source != .homebrew {
                Text("Проверка новой версии пока недоступна. «Обновить» запустит штатное обновление этого инструмента.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.updateStatus == .notChecked {
                Text("Нажмите «Проверить обновления» на панели инструментов.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if package.updateStatus == .unsupported {
                Text("Свежесть каталога Homebrew не подтверждена. Отсутствие найденного обновления не означает, что версия последняя.")
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

    private func metadata(_ title: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(mono ? .system(size: 12, design: .monospaced) : .callout)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
