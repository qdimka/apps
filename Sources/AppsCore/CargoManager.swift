import Foundation

public struct CargoManager: PackageManager {
    public let source = PackageSource.cargo
    public let executable: URL
    public let runner: any CommandRunning
    public let root: URL
    public static var defaultRoot: URL {
        let env = ProcessInfo.processInfo.environment
        return URL(fileURLWithPath: env["CARGO_INSTALL_ROOT"] ?? env["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo").path)
    }
    public init(executable: URL, root: URL? = nil, runner: any CommandRunning = CommandRunner()) {
        self.executable = executable; self.root = (root ?? Self.defaultRoot).standardizedFileURL; self.runner = runner
    }
    public func list() async throws -> [PackageRecord] {
        let file = root.appendingPathComponent(".crates2.json")
        let text = try read(file)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let legacy = try read(root.appendingPathComponent(".crates.toml"))
            guard !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let output = try await output(["install", "--list", "--root", root.path, "--color", "never"])
            var rows: [PackageRecord] = []
            for line in output.split(separator: "\n") where !line.hasPrefix(" ") {
                let parts = line.split(separator: " ")
                guard parts.count >= 2, Self.validName(String(parts[0])) else { continue }
                rows.append(PackageRecord(name: String(parts[0]), source: .cargo, managerPath: executable.path, version: String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "v:")), kind: .cargoPackage,
                    environmentPath: root.path, upgradeRestriction: "Старая запись Cargo: параметры установки неизвестны.", removalRestriction: "Старая запись Cargo: точный источник неизвестен.", identityScope: root.path + "|" + String(line)))
            }
            return rows
        }
        let object = try jsonObject(text, source: "Cargo")
        guard let installs = object["installs"] as? [String: [String: Any]] else { throw ManagerError.invalidData("Cargo tracking registry") }
        var rows: [PackageRecord] = []
        for (id, entry) in installs {
            guard let start = id.range(of: " ("), id.hasSuffix(")") else { throw ManagerError.invalidData("Cargo package ID") }
            let parts = id[..<start.lowerBound].split(separator: " ")
            let origin = String(id[start.upperBound..<id.index(before: id.endIndex)])
            guard parts.count == 2, Self.validName(String(parts[0])), SemanticVersion(String(parts[1])) != nil,
                  let bins = entry["bins"] as? [String], !bins.isEmpty, bins.allSatisfy({ Self.validName($0) }),
                  let features = entry["features"] as? [String], features.allSatisfy({ ManagedFiles.matches($0, #"^[A-Za-z0-9_][A-Za-z0-9_+./?-]*$"#) }),
                  let all = entry["all_features"] as? Bool, let noDefault = entry["no_default_features"] as? Bool,
                  let profile = entry["profile"] as? String, Self.validName(profile),
                  let target = entry["target"] as? String, Self.validName(target),
                  origin.hasPrefix("registry+") || origin.hasPrefix("git+") || origin.hasPrefix("path+") else { throw ManagerError.invalidData("Cargo install entry") }
            let name = String(parts[0]), version = String(parts[1])
            // Cargo pkgid URL syntax: source kind plus URL, with name@version fragment.
            let spec = origin.components(separatedBy: "#")[0] + "#" + name + "@" + version
            let canonical = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            let registry = origin == "registry+https://github.com/rust-lang/crates.io-index" || origin == "registry+sparse+https://index.crates.io/"
            let options = ["features": features.joined(separator: ","), "all_features": String(all), "no_default_features": String(noDefault), "profile": profile, "target": target]
            rows.append(PackageRecord(name: name, source: .cargo, managerPath: executable.path, version: version, kind: .cargoPackage,
                summary: origin, installationPath: root.appendingPathComponent("bin").path, executables: bins.sorted(), environmentPath: root.path,
                upgradeRestriction: registry ? nil : "Git, локальные и сторонние registry требуют исходной команды установки Cargo.",
                installationKey: String(data: canonical, encoding: .utf8), identityScope: root.path + "|" + id, packageReference: spec, buildOptions: options))
        }
        let counts = Dictionary(grouping: rows, by: { $0.packageReference! }).mapValues(\.count)
        for i in rows.indices where counts[rows[i].packageReference!]! > 1 {
            rows[i].removalRestriction = "Несколько установок соответствуют одному Cargo package ID. Удалите их через Cargo вручную."
            rows[i].upgradeRestriction = rows[i].removalRestriction
        }
        return rows.sorted { $0.name < $1.name }
    }
    private func read(_ file: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return "" }
        return try String(contentsOf: file, encoding: .utf8)
    }
    private static func validName(_ text: String) -> Bool { ManagedFiles.matches(text, #"^[A-Za-z0-9_][A-Za-z0-9_.-]*$"#) && text != "." && text != ".." }
    private func fresh(_ package: PackageRecord) async throws -> PackageRecord {
        try validate(package)
        guard let row = try await list().first(where: { $0.id == package.id }), row.installationKey == package.installationKey,
              row.version == package.version else { throw ManagerError.contextChanged }
        return row
    }
    private func latest(_ row: PackageRecord) async throws -> String? {
        let text = try await boundedOutput(["search", "--registry", "crates-io", "--limit", "100", "--color", "never", "--", row.name])
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == row.name else { continue }
            let values = parts[1].split(separator: "\"")
            guard values.count >= 2, let new = SemanticVersion(String(values[1])), let old = SemanticVersion(row.version) else { throw ManagerError.invalidData("Cargo search") }
            return new > old ? String(values[1]) : nil
        }
        throw ManagerError.invalidData("Cargo search: точный пакет не найден")
    }
    public func checkUpdates() async throws -> [PackageRecord] {
        var rows = try await list()
        for i in rows.indices {
            if rows[i].upgradeRestriction != nil { rows[i].updateStatus = .unsupported; continue }
            rows[i].latestVersion = try await latest(rows[i]); rows[i].updateStatus = rows[i].latestVersion == nil ? .current : .available
        }
        return rows
    }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult {
        let row = try await fresh(package)
        if let reason = row.removalRestriction { throw ManagerError.operationRestricted(reason) }
        guard let spec = row.packageReference else { throw ManagerError.invalidTarget }
        let result = try await runner.run(executable: executable, arguments: ["uninstall", "--root", root.path, "--color", "never", "--package", spec])
        _ = try result.requireSuccess(); return result
    }
    public func upgrade(_ package: PackageRecord) async throws -> CommandResult {
        let row = try await fresh(package)
        if let reason = row.upgradeRestriction { throw ManagerError.operationRestricted(reason) }
        guard let version = try await latest(row) else { return .init(exitCode: 0, stdout: "Более новая версия не найдена.") }
        _ = try await fresh(row)
        var args = ["install", "--root", root.path, "--registry", "crates-io", "--locked", "--version", "=" + version, "--color", "never"]
        for bin in row.executables { args += ["--bin", bin] }
        for (key, flag) in [("features", "--features"), ("profile", "--profile"), ("target", "--target")] {
            if let value = row.buildOptions[key], !value.isEmpty { args += [flag, value] }
        }
        if row.buildOptions["all_features"] == "true" { args.append("--all-features") }
        if row.buildOptions["no_default_features"] == "true" { args.append("--no-default-features") }
        args += ["--", row.name]
        let result = try await runner.run(executable: executable, arguments: args)
        _ = try result.requireSuccess(); return result
    }
}
