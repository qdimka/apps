import Foundation

public struct HomebrewManager: PackageManager {
    public let source = PackageSource.homebrew
    public let executable: URL
    public let runner: any CommandRunning
    public init(executable: URL, runner: any CommandRunning = CommandRunner()) {
        self.executable = executable; self.runner = runner
    }
    public func list() async throws -> [PackageRecord] {
        try Self.parse(await output(["info", "--json=v2", "--installed"]), executable: executable)
    }
    public func checkUpdates() async throws -> [PackageRecord] {
        // brew update may migrate installed formulae/casks. Inspect the local
        // catalog instead and never claim its freshness has been confirmed.
        return try Self.parse(await output(["info", "--json=v2", "--installed"]), executable: executable, checked: true)
    }
    public func upgrade(_ package: PackageRecord) async throws -> CommandResult { try await mutate("upgrade", package) }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult { try await mutate("uninstall", package) }
    private func mutate(_ command: String, _ package: PackageRecord) async throws -> CommandResult {
        try validate(package)
        guard package.kind == .formula || package.kind == .cask else { throw ManagerError.invalidTarget }
        var arguments = [command, package.kind == .cask ? "--cask" : "--formula"]
        if command == "upgrade" && package.kind == .cask { arguments.append("--greedy") }
        return try await runner.run(executable: executable, arguments: arguments + ["--", package.name])
    }

    public static func parse(_ text: String, executable: URL, checked: Bool = false) throws -> [PackageRecord] {
        let root = try jsonObject(text, source: "Homebrew")
        guard let formulae = root["formulae"] as? [[String: Any]], let casks = root["casks"] as? [[String: Any]] else { throw ManagerError.invalidData("Homebrew") }
        let prefix = executable.deletingLastPathComponent().deletingLastPathComponent().path
        var packages: [PackageRecord] = []
        for item in formulae {
            guard let name = item["name"] as? String, !name.isEmpty,
                  let installed = item["installed"] as? [[String: Any]] else { throw ManagerError.invalidData("Homebrew") }
            let versions = installed.compactMap { $0["version"] as? String }
            guard !versions.isEmpty else { throw ManagerError.invalidData("Homebrew") }
            let latest = (item["versions"] as? [String: Any])?["stable"] as? String
            let status: UpdateStatus = !checked ? .notChecked : (item["outdated"] as? Bool == true ? .available : .unsupported)
            packages.append(PackageRecord(name: item["full_name"] as? String ?? name, source: .homebrew, managerPath: executable.path,
                version: versions.joined(separator: ", "), kind: .formula, summary: item["desc"] as? String ?? "",
                installationPath: prefix + "/Cellar/" + name, dependencies: item["dependencies"] as? [String] ?? [],
                latestVersion: checked ? latest : nil, updateStatus: status, pinned: item["pinned"] as? Bool ?? false, homepage: item["homepage"] as? String))
        }
        for item in casks {
            guard let token = item["token"] as? String, !token.isEmpty else { throw ManagerError.invalidData("Homebrew") }
            let version: String
            if let value = item["installed"] as? String { version = value }
            else if let values = item["installed"] as? [String], !values.isEmpty { version = values.joined(separator: ", ") }
            else { throw ManagerError.invalidData("Homebrew") }
            let latest = item["version"] as? String
            let status: UpdateStatus = !checked ? .notChecked : latest == "latest" ? .unsupported :
                (item["outdated"] as? Bool == true ? .available : .unsupported)
            packages.append(PackageRecord(name: item["full_token"] as? String ?? token, source: .homebrew, managerPath: executable.path,
                version: version, kind: .cask, summary: item["desc"] as? String ?? "",
                installationPath: prefix + "/Caskroom/" + token, latestVersion: checked ? latest : nil,
                updateStatus: status, pinned: item["pinned"] as? Bool ?? false, homepage: item["homepage"] as? String))
        }
        return packages
    }
}
