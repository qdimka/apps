import Foundation

public struct UVManager: PackageManager {
    public let source = PackageSource.uv
    public let executable: URL
    public let runner: any CommandRunning
    public init(executable: URL, runner: any CommandRunning = CommandRunner()) { self.executable = executable; self.runner = runner }
    public func list() async throws -> [PackageRecord] {
        try Self.parse(await output(["tool", "list", "--show-paths", "--color", "never"]), executable: executable)
    }
    public func checkUpdates() async throws -> [PackageRecord] {
        try await list().map { row in var row = row; row.updateStatus = .unsupported; return row }
    }
    public func upgrade(_ package: PackageRecord) async throws -> CommandResult { try await mutate("upgrade", package) }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult { try await mutate("uninstall", package) }
    private func mutate(_ command: String, _ package: PackageRecord) async throws -> CommandResult {
        try validate(package)
        return try await runner.run(executable: executable, arguments: ["tool", command, "--", package.name])
    }

    public static func parse(_ text: String, executable: URL) throws -> [PackageRecord] {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty || content == "No tools installed" { return [] }
        let header = try NSRegularExpression(pattern: #"^([A-Za-z0-9][A-Za-z0-9._-]*) v([^\s]+)(?: \((.+)\))?$"#)
        let command = try NSRegularExpression(pattern: #"^- ([^\s]+)(?: \((.+)\))?$"#)
        var rows: [PackageRecord] = []
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            let range = NSRange(line.startIndex..., in: line)
            func capture(_ match: NSTextCheckingResult, _ index: Int) -> String? {
                Range(match.range(at: index), in: line).map { String(line[$0]) }
            }
            if let match = header.firstMatch(in: line, range: range), let name = capture(match, 1), let version = capture(match, 2) {
                rows.append(PackageRecord(name: name, source: .uv, managerPath: executable.path, version: version,
                                          summary: L("Python tool in an isolated environment"), installationPath: capture(match, 3)))
            } else if let match = command.firstMatch(in: line, range: range), !rows.isEmpty, let name = capture(match, 1) {
                rows[rows.count - 1].executables.append(capture(match, 2) ?? name)
            } else { throw ManagerError.invalidData("uv tools") }
        }
        return rows
    }
}
