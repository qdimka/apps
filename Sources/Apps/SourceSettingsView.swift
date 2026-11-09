import SwiftUI
import AppsCore

struct SourceSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(L("Settings"), systemImage: "slider.horizontal.3").font(.title2.bold())
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section {
                    Picker(L("Language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language) }
                    }
                    Text(L("English is the default. Your language choice is saved."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(L("General")) }
                Section {
                    Text(L("Node.js installations: \(model.npmChoices.count)"))
                    Text(L("All installations are shown together. Use the filter above the list to narrow environments.")).font(.caption).foregroundStyle(.secondary)
                    Button(L("Add Node.js installation…")) { model.chooseRuntime(.npm) }
                } header: { Text(L("npm · global packages")) }
                Section {
                    Text(L("Python environments: \(model.pythonChoices.count)"))
                    Button(L("Add Python or venv…")) { model.chooseRuntime(.pip) }
                    Text(L("Main Python installations and discovered venvs are shown together. Add an environment outside the standard project folders."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(L("pip · Python environments")) }
                Section {
                    Text(model.cargoRoot).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button(L("Choose Cargo directory…")) { model.chooseCargoRoot() }
                    Text(L("CLI tools installed with cargo install. Choose another directory if you use --root or install.root."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Rust · Cargo") }
            }
            .formStyle(.grouped)
            .disabled(model.coordinator.isBusy)
            Button(L("Find environments and refresh")) { Task { await model.reload() } }.disabled(model.coordinator.isBusy)
            if let error = model.settingsError { Text(error).font(.callout).foregroundStyle(.orange) }
            if model.coordinator.isBusy {
                HStack { ProgressView().controlSize(.small); Text(model.coordinator.activity ?? L("Loading…")).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(24).frame(width: 720, height: 700)
    }

}
