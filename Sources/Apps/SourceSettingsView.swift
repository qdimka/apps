import SwiftUI
import AppsCore

struct SourceSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Источники пакетов", systemImage: "slider.horizontal.3").font(.title2.bold())
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section {
                    Text("Установок Node.js: \(model.npmChoices.count)")
                    Text("Все установки показаны вместе. Фильтр над списком скрывает ненужные окружения.").font(.caption).foregroundStyle(.secondary)
                    Button("Добавить установку Node.js…") { model.chooseRuntime(.npm) }
                } header: { Text("npm · глобальные пакеты") }
                Section {
                    Text("Python-окружений: \(model.pythonChoices.count)")
                    Button("Добавить Python или venv…") { model.chooseRuntime(.pip) }
                    Text("Основные Python и найденные venv показаны вместе. Добавьте окружение, если оно находится вне стандартных каталогов проектов.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("pip · окружение Python") }
                Section {
                    Text(model.cargoRoot).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button("Выбрать каталог Cargo…") { model.chooseCargoRoot() }
                    Text("Установленные CLI из cargo install. Выберите другой каталог, если используете --root или install.root.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Rust · Cargo") }
            }
            .formStyle(.grouped)
            .disabled(model.coordinator.isBusy)
            Button("Найти окружения и обновить список") { Task { await model.reload() } }.disabled(model.coordinator.isBusy)
            if let error = model.settingsError { Text(error).font(.callout).foregroundStyle(.orange) }
            if model.coordinator.isBusy {
                HStack { ProgressView().controlSize(.small); Text(model.coordinator.activity ?? "Загрузка…").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(24).frame(width: 720, height: 620)
    }

}
