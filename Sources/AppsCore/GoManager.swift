import Foundation
import Darwin

public struct GoManager: PackageManager {
    public let source = PackageSource.go
    public let executable: URL
    public let runner: any CommandRunning
    private let trash: any FileTrashing
    public init(executable: URL, runner: any CommandRunning = CommandRunner(), trash: any FileTrashing = SystemTrash()) {
        self.executable = executable; self.runner = runner; self.trash = trash
    }
    private func root() async throws -> URL {
        let env = try jsonObject(try await output(["env", "-json", "GOBIN", "GOPATH", "GOFLAGS"]), source: "Go")
        let bin = env["GOBIN"] as? String ?? ""
        let path = bin.isEmpty ? (env["GOPATH"] as? String ?? "").split(separator: ":").first.map { String($0) + "/bin" } ?? "" : bin
        guard path.hasPrefix("/"), path != "/" else { throw ManagerError.invalidData("Go GOBIN/GOPATH") }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    }
    private func record(_ binary: URL, root: URL) async throws -> PackageRecord {
        let before = try ManagedFiles.fingerprint(binary)
        let text = try await output(["version", "-m", "-json", binary.path])
        guard before == (try ManagedFiles.fingerprint(binary)) else { throw ManagerError.contextChanged }
        return try Self.parseInfo(text, binary: binary, executable: executable, root: root, fingerprint: before, owned: ManagedFiles.owned(binary))
    }
    public func list() async throws -> [PackageRecord] {
        guard try await boundedOutput(["help", "version"]).contains("-json") else { throw ManagerError.invalidData("Go: нужен Go 1.25+ с JSON build-info") }
        let root = try await root()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        var rows: [PackageRecord] = []
        for file in files where !file.lastPathComponent.hasPrefix(".") {
            try Task.checkCancellation()
            guard (try? ManagedFiles.fingerprint(file)) != nil, FileManager.default.isExecutableFile(atPath: file.path) else { continue }
            do { rows.append(try await record(file, root: root)) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Non-Go executables may share GOBIN. */ }
        }
        return rows
    }
    public static func parseInfo(_ text: String, binary: URL, executable: URL, root: URL, fingerprint: String, owned: Bool) throws -> PackageRecord {
        let json = try jsonObject(text, source: "Go (нужен Go 1.25+)")
        guard let path = json["Path"] as? String, let main = json["Main"] as? [String: Any],
              let module = main["Path"] as? String, let version = main["Version"] as? String,
              validPath(path), validPath(module) else { throw ManagerError.invalidData("Go build info") }
        let settings = json["Settings"] as? [[String: String]] ?? []
        var options: [String: String] = [:]
        for setting in settings { if let k = setting["Key"] { options[k] = setting["Value"] ?? "" } }
        let custom = options.contains { key, value in
            if ["GOOS", "GOARCH", "CGO_ENABLED", "GOARM64", "GOAMD64", "DefaultGODEBUG", "-compiler"].contains(key) { return false }
            if key == "-buildmode" { return value != "exe" }
            if key.hasPrefix("CGO_") { return !value.isEmpty }
            return true
        }
        let replaced = main["Replace"] != nil || (json["Deps"] as? [[String: Any]] ?? []).contains { $0["Replace"] != nil }
        let reason: String? = !owned ? "Бинарник принадлежит другому пользователю." :
            (SemanticVersion(version) == nil || replaced || custom ? "Локальная или особая сборка: обновите её исходной командой Go." : nil)
        return PackageRecord(name: binary.lastPathComponent, source: .go, managerPath: executable.path, version: version,
            kind: .goTool, summary: path, installationPath: binary.path, executables: [binary.lastPathComponent],
            dependencies: (json["Deps"] as? [[String: Any]] ?? []).compactMap { d in (d["Path"] as? String).map { $0 + " " + (d["Version"] as? String ?? "") } },
            environmentPath: root.path, upgradeRestriction: reason, removalRestriction: owned ? nil : reason,
            installationKey: fingerprint, identityScope: binary.path, packageReference: path, modulePath: module, buildOptions: options)
    }
    private static func validPath(_ value: String) -> Bool {
        ManagedFiles.matches(value, #"^[A-Za-z0-9][A-Za-z0-9._~+/-]*$"#) && !value.split(separator: "/").contains("..")
    }
    private func fresh(_ package: PackageRecord) async throws -> PackageRecord {
        try validate(package)
        let root = try await root()
        guard let path = package.installationPath, URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path else { throw ManagerError.contextChanged }
        let row = try await record(URL(fileURLWithPath: path), root: root)
        guard row.id == package.id, row.installationKey == package.installationKey, row.version == package.version else { throw ManagerError.contextChanged }
        return row
    }
    private func latest(_ row: PackageRecord) async throws -> String? {
        guard row.upgradeRestriction == nil, let module = row.modulePath else { return nil }
        let data = try jsonObject(try await boundedOutput(["list", "-m", "-json", module + "@latest"]), source: "Go registry")
        guard data["Path"] as? String == module, let version = data["Version"] as? String,
              let new = SemanticVersion(version), let old = SemanticVersion(row.version) else { throw ManagerError.invalidData("Go registry") }
        return new > old ? version : nil
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
        try trash.trash(URL(fileURLWithPath: row.installationPath!))
        return .init(exitCode: 0, stdout: "Перемещён в Корзину: " + row.installationPath!)
    }
    public func upgrade(_ package: PackageRecord) async throws -> CommandResult {
        let row = try await fresh(package)
        if let reason = row.upgradeRestriction { throw ManagerError.operationRestricted(reason) }
        guard let version = try await latest(row) else { return .init(exitCode: 0, stdout: "Более новая версия не найдена.") }
        let target = URL(fileURLWithPath: row.installationPath!), root = URL(fileURLWithPath: row.environmentPath!)
        let stage = root.appendingPathComponent(".apps-go-stage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        var args = ["--", "GOBIN=" + stage.path, "GOFLAGS="]
        for key in ["GOOS", "GOARCH", "CGO_ENABLED", "GOARM64", "GOAMD64"] { if let value = row.buildOptions[key] { args.append(key + "=" + value) } }
        args += [executable.path, "install", row.packageReference! + "@" + version]
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: args)
        _ = try result.requireSuccess()
        let files = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
        guard files.count == 1, let built = files.first, FileManager.default.isExecutableFile(atPath: built.path) else { throw ManagerError.invalidData("Go staged output") }
        let check = try await record(built, root: stage)
        guard check.version == version, check.packageReference == row.packageReference, check.modulePath == row.modulePath else { throw ManagerError.invalidData("Go staged build info") }
        _ = try await fresh(row)
        try Task.checkCancellation()
        guard rename(built.path, target.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return result
    }
}
