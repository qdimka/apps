import Foundation

public struct NPMManager: PackageManager {
    public let source = PackageSource.npm
    public let executable: URL
    public let runner: any CommandRunning
    public init(executable: URL, runner: any CommandRunning = CommandRunner()) {
        self.executable = executable; self.runner = runner
    }

    public func list() async throws -> [PackageRecord] {
        let prefix = try await output(["prefix", "--global"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = try await output(["root", "--global", "--prefix", prefix]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.hasPrefix("/"), root.hasPrefix("/") else { throw ManagerError.invalidData("npm") }
        let json = try await output(["ls", "--global", "--prefix", prefix, "--depth=0", "--json", "--long"])
        return try Self.parseList(json, executable: executable, prefix: prefix, root: root)
    }

    public func checkUpdates() async throws -> [PackageRecord] {
        let rows = try await list()
        guard let prefix = rows.first?.environmentPath else { return rows }
        let result = try await runner.run(executable: executable, arguments: ["outdated", "--global", "--prefix", prefix, "--json", "--long"])
        guard result.exitCode == 0 || result.exitCode == 1 else { throw CommandError.failed(result.exitCode, result.log) }
        let outdated = try jsonObject(result.stdout, source: "npm outdated")
        guard outdated["error"] == nil else { throw CommandError.failed(result.exitCode, result.log) }
        for (_, value) in outdated {
            guard let item = value as? [String: Any], let latest = item["latest"] as? String, !latest.isEmpty else { throw ManagerError.invalidData("npm outdated") }
        }
        return rows.map { row in
            var row = row
            if row.upgradeRestriction != nil { row.updateStatus = .unsupported }
            else if let latest = (outdated[row.name] as? [String: Any])?["latest"] as? String {
                if let installed = SemanticVersion(row.version), let candidate = SemanticVersion(latest) {
                    row.latestVersion = candidate > installed ? latest : nil
                    row.updateStatus = candidate > installed ? .available : .current
                } else { row.updateStatus = .unsupported }
            } else { row.updateStatus = .current }
            return row
        }
    }

    public func upgrade(_ package: PackageRecord) async throws -> CommandResult { try await mutate(package, action: .upgrade) }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult { try await mutate(package, action: .uninstall) }

    private func mutate(_ package: PackageRecord, action: PackageAction) async throws -> CommandResult {
        try validate(package)
        guard let fresh = try await list().first(where: { $0.id == package.id }),
              fresh.version == package.version, fresh.environmentPath == package.environmentPath,
              let prefix = fresh.environmentPath else { throw ManagerError.contextChanged }
        if let reason = action == .upgrade ? fresh.upgradeRestriction : fresh.removalRestriction { throw ManagerError.operationRestricted(reason) }
        var target: String?
        if action == .upgrade {
            let json = try await output(["view", "--prefix", prefix, "--json", "--", fresh.name, "version"])
            guard let latest = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) as? String,
                  let candidate = SemanticVersion(latest), let installed = SemanticVersion(fresh.version) else {
                throw ManagerError.invalidData("npm version")
            }
            guard candidate > installed else { return .init(exitCode: 0, stdout: L("No newer version found. The installed version was preserved.")) }
            target = latest
        }
        let arguments = action == .upgrade
            ? ["install", "--global", "--prefix", prefix, "--no-audit", "--no-fund", "--", fresh.name + "@" + target!]
            : ["uninstall", "--global", "--prefix", prefix, "--no-audit", "--no-fund", "--", fresh.name]
        return try await runner.run(executable: executable, arguments: arguments)
    }

    public static func parseList(_ text: String, executable: URL, prefix: String, root: String) throws -> [PackageRecord] {
        let object = try jsonObject(text, source: "npm")
        guard object["error"] == nil else { throw ManagerError.invalidData("npm") }
        guard let dependencies = object["dependencies"] as? [String: Any] else {
            if object["dependencies"] == nil { return [] }
            throw ManagerError.invalidData("npm")
        }
        return try dependencies.keys.sorted().map { name in
            guard let item = dependencies[name] as? [String: Any], let version = item["version"] as? String, !version.isEmpty else { throw ManagerError.invalidData("npm") }
            let linked = item["link"] as? Bool == true || (item["resolved"] as? String)?.hasPrefix("file:") == true
            let alias = (item["name"] as? String).map { $0.lowercased() != name.lowercased() } ?? false
            let origins = ["resolved", "from", "_from"].compactMap { item[$0] as? String }
            let nonRegistry = origins.contains { value in
                value.hasPrefix("git@") || value.contains("@git@") ||
                ["git+", "git://", "ssh://", "github:", "gitlab:", "bitbucket:", "file:", "npm:"].contains { value.contains($0) }
            }
            let restriction: String?
            if linked { restriction = L("Local npm link: update the original project.") }
            else if alias || nonRegistry { restriction = L("This package is an alias or comes from another source. Update the original installation.") }
            else { restriction = nil }
            return PackageRecord(name: name, source: .npm, managerPath: executable.path, version: version, kind: .npmPackage,
                summary: item["description"] as? String ?? L("Global npm package"),
                installationPath: item["path"] as? String ?? root + "/" + name,
                homepage: item["homepage"] as? String, environmentPath: prefix,
                upgradeRestriction: restriction,
                removalRestriction: name == "npm" ? L("Removing npm is disabled to preserve this source.") : nil)
        }
    }
}
