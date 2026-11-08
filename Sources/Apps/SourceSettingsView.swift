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
                    runtimePicker(.npm, choices: model.npmChoices, selected: model.npmPath)
                    Button("Выбрать другой npm…") { model.chooseRuntime(.npm) }
                } header: { Text("npm · глобальные пакеты") }
                Section {
                    runtimePicker(.pip, choices: model.pythonChoices, selected: model.pythonPath)
                    Button("Добавить Python или venv…") { model.chooseRuntime(.pip) }
                    Text("Выберите основную установку Python или окружение проекта. Список pip относится к выбранному интерпретатору.")
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
            if let error = model.settingsError { Text(error).font(.callout).foregroundStyle(.orange) }
            if model.coordinator.isBusy {
                HStack { ProgressView().controlSize(.small); Text(model.coordinator.activity ?? "Загрузка…").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(24).frame(width: 720, height: 620)
    }

    @ViewBuilder private func runtimePicker(_ source: PackageSource, choices: [RuntimeChoice], selected: String) -> some View {
        if choices.isEmpty {
            Text("Установка не найдена. Выберите её вручную.").foregroundStyle(.secondary)
        } else {
            Picker("Установка", selection: Binding(get: { selected }, set: { path in Task { await model.selectRuntime(source, path: path) } })) {
                ForEach(choices) { choice in Text(choice.label).tag(choice.path) }
            }
            .labelsHidden()
            Text(selected).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
