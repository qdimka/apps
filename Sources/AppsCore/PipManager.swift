import Foundation

public struct PipManager: PackageManager {
    public let source = PackageSource.pip
    public let executable: URL
    public let runner: any CommandRunning
    public let checkTimeout: Duration
    public init(executable: URL, runner: any CommandRunning = CommandRunner(), checkTimeout: Duration = .seconds(60)) {
        self.executable = executable; self.runner = runner; self.checkTimeout = checkTimeout
    }

    public func list() async throws -> [PackageRecord] {
        try Self.parseProbe(await output(["-c", Self.probeScript]), executable: executable)
    }

    public func checkUpdates() async throws -> [PackageRecord] {
        let rows = try await list()
        guard rows.contains(where: { $0.upgradeRestriction == nil }) else {
            return rows.map { var row = $0; row.updateStatus = .unsupported; return row }
        }
        try await validateConfiguration()
        var arguments = ["-m", "pip", "--disable-pip-version-check", "--no-input", "--timeout", "8", "--retries", "0", "list", "--outdated", "--format=json"]
        for row in rows where row.upgradeRestriction != nil { arguments += ["--exclude", row.name] }
        let checkArguments = arguments
        let result = try await withThrowingTaskGroup(of: CommandResult.self) { group in
            group.addTask { try await runner.run(executable: executable, arguments: checkArguments) }
            group.addTask { try await Task.sleep(for: checkTimeout); throw CommandError.timedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        let text = try result.requireSuccess()
        guard result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManagerError.operationRestricted(L("The pip index check returned a warning.\n") + result.stderr.suffix(3500))
        }
        guard let entries = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { throw ManagerError.invalidData("pip outdated") }
        var latest: [String: String] = [:]
        for item in entries {
            guard let name = item["name"] as? String, let version = item["latest_version"] as? String, !version.isEmpty else { throw ManagerError.invalidData("pip outdated") }
            latest[Self.normalized(name)] = version
        }
        return rows.map { item in
            var row = item
            if row.upgradeRestriction != nil { row.updateStatus = .unsupported }
            else if let version = latest[Self.normalized(row.name)] {
                row.latestVersion = version; row.updateStatus = version == row.version ? .current : .available
            } else { row.updateStatus = .unsupported }
            return row
        }
    }

    public func upgrade(_ package: PackageRecord) async throws -> CommandResult { try await mutate(package, action: .upgrade) }
    public func uninstall(_ package: PackageRecord) async throws -> CommandResult { try await mutate(package, action: .uninstall) }
    private func mutate(_ package: PackageRecord, action: PackageAction) async throws -> CommandResult {
        try validate(package)
        let rows = try await list()
        guard let fresh = rows.first(where: { $0.id == package.id }),
              fresh.version == package.version, fresh.environmentPath == package.environmentPath,
              fresh.installationPath == package.installationPath, fresh.isUserInstall == package.isUserInstall,
              fresh.installationKey == package.installationKey else { throw ManagerError.contextChanged }
        if let reason = action == .upgrade ? fresh.upgradeRestriction : fresh.removalRestriction { throw ManagerError.operationRestricted(reason) }
        try await validateConfiguration()
        var constraintDirectory: URL?
        defer { if let constraintDirectory { try? FileManager.default.removeItem(at: constraintDirectory) } }
        var arguments = ["-m", "pip", "--disable-pip-version-check"]
        if action == .upgrade {
            arguments += ["install", "--upgrade"]
            if fresh.isUserInstall { arguments.append("--user") }
            let protected = rows.filter { $0.id != fresh.id && $0.upgradeRestriction != nil }
            if !protected.isEmpty {
                var lines: [String] = []
                for row in protected {
                    guard row.name.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil,
                          row.version.range(of: #"^[A-Za-z0-9.!+_-]+$"#, options: .regularExpression) != nil else {
                        throw ManagerError.operationRestricted(L("Could not pin protected dependency versions. Update this package with its original manager."))
                    }
                    lines.append(Self.normalized(row.name) + "===" + row.version)
                }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("apps-pip-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                constraintDirectory = directory
                let file = directory.appendingPathComponent("constraints.txt")
                try Data((lines.sorted().joined(separator: "\n") + "\n").utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                arguments += ["--constraint", file.path]
            }
        } else { arguments += ["uninstall", "--yes"] }
        return try await runner.run(executable: executable, arguments: arguments + ["--", Self.normalized(fresh.name)])
    }

    private func validateConfiguration() async throws {
        let text = try await output(["-c", Self.configurationGuardScript])
        guard let keys = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String] else { throw ManagerError.invalidData("pip configuration") }
        if !keys.isEmpty {
            throw ManagerError.operationRestricted(L("Pip settings change the operation target or scope: ") + keys.joined(separator: ", ") + L(". Use the original configuration in Terminal or remove these options."))
        }
    }

    public static func normalized(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: #"[-_.]+"#, with: "-", options: .regularExpression)
    }

    public static func parseProbe(_ text: String, executable: URL) throws -> [PackageRecord] {
        let object = try jsonObject(text, source: "Python")
        guard object["version"] as? Int == 1, let prefix = object["prefix"] as? String, prefix.hasPrefix("/"),
              let base = object["basePrefix"] as? String, let pip = object["pipAvailable"] as? Bool,
              let external = object["externallyManaged"] as? Bool, let system = object["isSystem"] as? Bool,
              let entries = object["packages"] as? [[String: Any]], (object["warnings"] as? [String] ?? []).isEmpty else {
            throw ManagerError.invalidData("Python metadata")
        }
        var seen = Set<String>()
        var rows: [PackageRecord] = []
        for item in entries {
            guard let name = item["name"] as? String, !name.isEmpty, let version = item["version"] as? String,
                  let location = item["location"] as? String, location.hasPrefix("/") else { throw ManagerError.invalidData("Python metadata") }
            guard seen.insert(normalized(name)).inserted else { continue }
            let installer = item["installer"] as? String ?? ""
            let user = item["isUser"] as? Bool ?? false
            let direct = item["directURL"] as? Bool ?? false
            let local = within(location, prefix)
            let restriction: String?
            if !pip { restriction = L("This Python has no pip. Packages are available for inspection only.") }
            else if external { restriction = L("An external manager owns this environment (EXTERNALLY-MANAGED).") }
            else if prefix != base && !local { restriction = L("This package comes from another environment. Use its original Python to modify it.") }
            else if system && !user { restriction = L("System Python package. Changes through apps are disabled.") }
            else if !local && !user { restriction = L("This package is outside the selected environment.") }
            else if !["pip", "uv"].contains(installer) {
                restriction = installer == "conda" ? L("Conda owns this package. Manage it with conda.") : L("Installation ownership could not be confirmed as pip or uv.")
            } else { restriction = nil }
            rows.append(PackageRecord(name: name, source: .pip, managerPath: executable.path, version: version,
                kind: .pythonPackage, summary: String((item["summary"] as? String ?? "").prefix(1000)), installationPath: location,
                executables: item["commands"] as? [String] ?? [], dependencies: item["dependencies"] as? [String] ?? [],
                homepage: item["homepage"] as? String, environmentPath: prefix,
                upgradeRestriction: restriction ?? (direct ? L("This package was installed from a URL or local project. Update the original installation.") : nil),
                removalRestriction: restriction ?? (normalized(name) == "pip" ? L("Removing pip is disabled to preserve environment management.") : nil), isUserInstall: user,
                installationKey: item["metadataLocation"] as? String ?? "\(location)|\(normalized(name))|\(version)|\(user)"))
        }
        return rows
    }

    // Read effective option names only: never return registry URLs or credentials.
    // Reject settings that redirect to another interpreter/location or add targets.
    public static let configurationGuardScript = #"""
import json
from pip._internal.configuration import Configuration
config = Configuration(isolated=False)
config.load()
dangerous = {'python', 'requirement', 'editable', 'target', 'prefix', 'root', 'user',
             'force-reinstall', 'ignore-installed', 'no-deps', 'constraint', 'build-constraint',
             'global-option', 'install-option', 'break-system-packages'}
booleans = {'user', 'force-reinstall', 'ignore-installed', 'no-deps', 'break-system-packages'}
blocked = []
# pip 26.3 groups options by source file; older versions expose flat option pairs.
# Reject unknown shapes rather than silently skipping safety-relevant options.
def option_items():
    for key, value in config.items():
        pairs = value.items() if isinstance(value, dict) else [(key, value)]
        for option, setting in pairs:
            if not isinstance(option, str) or '.' not in option or not isinstance(setting, (str, bool, int, float, type(None))):
                raise RuntimeError('Unsupported pip configuration format')
            yield option, setting
for key, value in option_items():
    option = key.split('.')[-1]
    if option == 'upgrade-strategy' and str(value).strip() != 'only-if-needed':
        blocked.append(key)
    elif option in dangerous and str(value).strip():
        if option in booleans and str(value).lower() in ('0', 'false', 'no', 'off'):
            continue
        blocked.append(key)
print(json.dumps(sorted(set(blocked))))
"""#

    private static func within(_ path: String, _ root: String) -> Bool {
        let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
        let root = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardized.path
        return path == root || path.hasPrefix(root + "/")
    }

    // Python 3.8+ standard library only; no import of installed application code.
    public static let probeScript = #"""
import importlib.metadata as md
import importlib.util
import json, os, re, site, sys, sysconfig

def inside(path, root):
    try:
        return os.path.commonpath([os.path.realpath(path), os.path.realpath(root)]) == os.path.realpath(root)
    except (ValueError, OSError):
        return False

prefix, base = sys.prefix, getattr(sys, 'base_prefix', sys.prefix)
stdlib = sysconfig.get_path('stdlib')
user_site = site.getusersitepackages()
rows, warnings, seen = [], [], set()
for dist in md.distributions():
    try:
        name = dist.metadata.get('Name')
        if not name:
            continue
        key = re.sub(r'[-_.]+', '-', name).lower()
        if key in seen:
            continue
        seen.add(key)
        location = os.path.abspath(str(dist.locate_file('')))
        rows.append(dict(name=name, version=dist.version,
            summary=dist.metadata.get('Summary', ''), homepage=dist.metadata.get('Home-page', ''),
            location=location, metadataLocation=os.path.abspath(str(getattr(dist, '_path', location))),
            installer=(dist.read_text('INSTALLER') or '').strip().lower(),
            commands=[entry.name for entry in dist.entry_points if entry.group == 'console_scripts'],
            dependencies=dist.requires or [], directURL=bool(dist.read_text('direct_url.json')),
            isUser=inside(location, user_site)))
    except Exception as error:
        warnings.append(str(error)[:200])
system = prefix == base and (prefix.startswith(('/System/', '/Library/Developer/')) or sys.executable.startswith('/usr/bin/'))
print(json.dumps(dict(version=1, prefix=prefix, basePrefix=base,
    pipAvailable=importlib.util.find_spec('pip') is not None,
    externallyManaged=prefix == base and os.path.isfile(os.path.join(stdlib, 'EXTERNALLY-MANAGED')),
    isSystem=system, packages=rows, warnings=warnings)))
"""#
}
