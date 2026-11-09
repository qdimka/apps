import Foundation

public struct PipxManager: PackageManager {
    public let source = PackageSource.pipx
    public let executable: URL
    public let runner: any CommandRunning
    public init(executable: URL, runner: any CommandRunning = CommandRunner()) { self.executable = executable; self.runner = runner }
    public func list() async throws -> [PackageRecord] {
        let text = try await output(["list", "--json"])
        // Environment metadata is optional: a failure must not hide the packages.
        let root = try? await output(["environment", "--value", "PIPX_LOCAL_VENVS"])
        return try Self.parse(text, executable: executable, venvRoot: root?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public func checkUpdates() async throws -> [PackageRecord] {
        try await list().map { row in var row = row; row.updateStatus = .unsupported; return row }
    }
    public func upgrade(_ package: PackageRecord) async throws -> CommandResult { try await mutate("upgrade", package) }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult { try await mutate("uninstall", package) }
    private func mutate(_ command: String, _ package: PackageRecord) async throws -> CommandResult {
        try validate(package)
        return try await runner.run(executable: executable, arguments: [command, "--", package.name])
    }

    public static func parse(_ text: String, executable: URL, venvRoot: String? = nil) throws -> [PackageRecord] {
        let root = try jsonObject(text, source: "pipx")
        guard let venvs = root["venvs"] as? [String: Any] else { throw ManagerError.invalidData("pipx") }
        return try venvs.keys.sorted().map { name in
            guard let venv = venvs[name] as? [String: Any], let metadata = venv["metadata"] as? [String: Any],
                  let main = metadata["main_package"] as? [String: Any], let version = main["package_version"] as? String else { throw ManagerError.invalidData("pipx") }
            func path(_ value: Any) -> String? {
                if let string = value as? String { return string }
                return (value as? [String: Any])?["__Path__"] as? String
            }
            let appPaths = (main["app_paths"] as? [Any] ?? []).compactMap(path)
            let apps = main["apps"] as? [String] ?? []
            let resolved = apps.map { name in appPaths.first { URL(fileURLWithPath: $0).lastPathComponent == name } ?? name }
            let location = (metadata["venv_dir"].flatMap(path)) ?? venvRoot.flatMap { $0.isEmpty ? nil : $0 + "/" + name }
            return PackageRecord(name: name, source: .pipx, managerPath: executable.path, version: version,
                summary: L("Python tool in an isolated environment"), installationPath: location,
                executables: resolved, pinned: main["pinned"] as? Bool ?? false)
        }
    }
}
