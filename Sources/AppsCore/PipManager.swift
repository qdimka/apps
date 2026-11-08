import Foundation

public struct PipManager: PackageManager {
    public let source = PackageSource.pip
    public let executable: URL
    public let runner: any CommandRunning
    public init(executable: URL, runner: any CommandRunning = CommandRunner()) { self.executable = executable; self.runner = runner }

    public func list() async throws -> [PackageRecord] {
        try Self.parseProbe(await output(["-c", Self.probeScript]), executable: executable)
    }

    public func checkUpdates() async throws -> [PackageRecord] {
        let rows = try await list()
        guard rows.contains(where: { $0.upgradeRestriction == nil }) else {
            return rows.map { var row = $0; row.updateStatus = .unsupported; return row }
        }
        var arguments = ["-m", "pip", "--disable-pip-version-check", "--no-input", "--timeout", "8", "--retries", "0", "list", "--outdated", "--format=json"]
        for row in rows where row.upgradeRestriction != nil { arguments += ["--exclude", row.name] }
        let result = try await runner.run(executable: executable, arguments: arguments)
        let text = try result.requireSuccess()
        guard result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManagerError.operationRestricted("Проверка индекса pip завершилась с предупреждением.\n" + result.stderr.suffix(3500))
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
              fresh.installationPath == package.installationPath, fresh.isUserInstall == package.isUserInstall else { throw ManagerError.contextChanged }
        if let reason = action == .upgrade ? fresh.upgradeRestriction : fresh.removalRestriction { throw ManagerError.operationRestricted(reason) }
        var arguments = ["-m", "pip", "--disable-pip-version-check"]
        if action == .upgrade {
            arguments += ["install", "--upgrade"]
            if fresh.isUserInstall { arguments.append("--user") }
        } else { arguments += ["uninstall", "--yes"] }
        return try await runner.run(executable: executable, arguments: arguments + ["--", fresh.name])
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
            if !pip { restriction = "В выбранном Python нет pip. Пакеты доступны для просмотра." }
            else if external { restriction = "Окружением управляет внешний менеджер (EXTERNALLY-MANAGED)." }
            else if prefix != base && !local { restriction = "Пакет доступен из другого окружения. Выберите исходный Python для его изменения." }
            else if system && !user { restriction = "Пакет системного Python. Изменение через apps отключено." }
            else if !local && !user { restriction = "Пакет расположен за пределами выбранного окружения." }
            else if !["pip", "uv"].contains(installer) {
                restriction = installer == "conda" ? "Пакетом управляет conda. Изменяйте его через conda." : "Владелец установки не подтверждён как pip или uv."
            } else { restriction = nil }
            rows.append(PackageRecord(name: name, source: .pip, managerPath: executable.path, version: version,
                kind: .pythonPackage, summary: String((item["summary"] as? String ?? "").prefix(1000)), installationPath: location,
                executables: item["commands"] as? [String] ?? [], dependencies: item["dependencies"] as? [String] ?? [],
                homepage: item["homepage"] as? String, environmentPath: prefix,
                upgradeRestriction: restriction ?? (direct ? "Пакет установлен из URL или локального проекта. Обновите исходную установку." : nil),
                removalRestriction: restriction ?? (normalized(name) == "pip" ? "Удаление pip отключено, чтобы сохранить управление окружением." : nil), isUserInstall: user))
        }
        return rows
    }

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
            location=location, installer=(dist.read_text('INSTALLER') or '').strip().lower(),
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
