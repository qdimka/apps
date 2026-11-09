import Foundation

public struct RuntimeChoice: Identifiable, Hashable, Sendable {
    public let path: String
    public let label: String
    public var id: String { path }
    public init(path: String, label: String? = nil) { self.path = path; self.label = label ?? path }
}

public enum RuntimeDiscovery {
    public static func npmChoices(searchPaths: [String]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [RuntimeChoice] {
        let nvm = home.appendingPathComponent(".nvm")
        let nodeRoot = nvm.appendingPathComponent("versions/node")
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nodeRoot.path)) ?? [])
            .filter { $0.hasPrefix("v") }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        var alias = "default"
        var preferred: String?
        for _ in 0..<8 {
            let file = nvm.appendingPathComponent("alias").appendingPathComponent(alias).standardizedFileURL
            guard file.path.hasPrefix(nvm.appendingPathComponent("alias").path + "/"),
                  let value = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { break }
            let version = value.hasPrefix("v") ? value : "v" + value
            if let match = versions.first(where: { $0 == version || $0.hasPrefix(version + ".") }) { preferred = match; break }
            alias = value
        }
        var paths = searchPaths ?? ManagerDiscovery.defaultSearchPaths()
        if let preferred { paths.append(nodeRoot.appendingPathComponent(preferred).appendingPathComponent("bin").path) }
        paths += versions.map { nodeRoot.appendingPathComponent($0).appendingPathComponent("bin").path }
        paths += [home.appendingPathComponent(".volta/bin").path]
        return unique(paths.map { URL(fileURLWithPath: $0).appendingPathComponent("npm") })
    }

    public static func preferredPython(searchPaths: [String]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let paths = searchPaths ?? ManagerDiscovery.defaultSearchPaths()
        for name in ["pip", "pip3"] {
            for path in paths {
                let pip = URL(fileURLWithPath: path).appendingPathComponent(name)
                guard isExecutable(pip), let handle = try? FileHandle(forReadingFrom: pip) else { continue }
                let data = try? handle.read(upToCount: 4096)
                try? handle.close()
                guard let data, let text = String(data: data, encoding: .utf8),
                      let line = text.components(separatedBy: .newlines).first, line.hasPrefix("#!/") else { continue }
                let interpreter = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = URL(fileURLWithPath: interpreter)
                if url.lastPathComponent.lowercased().hasPrefix("python"), isExecutable(url) { return url }
            }
        }
        return pythonURLs(paths: paths, home: home).first(where: isExecutable)
    }

    public static func pythonChoices(searchPaths: [String]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, includeProjects: Bool = true) -> [RuntimeChoice] {
        let paths = searchPaths ?? ManagerDiscovery.defaultSearchPaths()
        var candidates: [URL] = []
        if let preferred = preferredPython(searchPaths: paths, home: home) { candidates.append(preferred) }
        candidates += pythonURLs(paths: paths, home: home)
        if includeProjects { candidates += projectPythons(home: home) }
        return unique(candidates, preserveVenv: true)
    }

    public static func resolvePythonSelection(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            return url.lastPathComponent.lowercased().hasPrefix("python") && isExecutable(url) ? url : nil
        }
        for path in ["bin/python", "bin/python3", ".venv/bin/python", ".venv/bin/python3", "venv/bin/python", "venv/bin/python3"] {
            let candidate = url.appendingPathComponent(path)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    private static func pythonURLs(paths: [String], home: URL) -> [URL] {
        var urls = paths.flatMap { path in ["python3", "python"].map { URL(fileURLWithPath: path).appendingPathComponent($0) } }
        let registry = home.appendingPathComponent(".conda/environments.txt")
        if let text = try? String(contentsOf: registry, encoding: .utf8) {
            urls += text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("bin/python") }
        }
        return urls
    }

    // Bound traversal to development directories; never recurse through an env, dependency tree or symlink.
    private static func projectPythons(home: URL) -> [URL] {
        let roots = ["Documents/Repositories", "Projects", "Developer", "code", ".virtualenvs", ".local/share/virtualenvs", ".pyenv/versions"]
        let ignored: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "target", "Library", "site-packages", "__pycache__"]
        var queue = roots.map { (home.appendingPathComponent($0), 0) }, index = 0, result: [URL] = []
        while index < queue.count && index < 2500 && result.count < 150 {
            let (directory, depth) = queue[index]; index += 1
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pyvenv.cfg").path) || FileManager.default.fileExists(atPath: directory.appendingPathComponent("conda-meta").path) {
                if let python = resolvePythonSelection(directory) { result.append(python) }
                continue
            }
            guard depth < 5, let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) where !ignored.contains(child.lastPathComponent) && (!child.lastPathComponent.hasPrefix(".") || child.lastPathComponent == ".venv") {
                queue.append((child, depth + 1))
            }
        }
        return result
    }

    public static func includingSaved(_ choices: [RuntimeChoice], paths: [String], python: Bool) -> [RuntimeChoice] {
        let existing = unique(choices.map { URL(fileURLWithPath: $0.path) } + paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }, preserveVenv: python)
        var result = existing
        for path in paths where path.hasPrefix("/") && !isExecutable(URL(fileURLWithPath: path)) && !result.contains(where: { $0.path == path }) {
            result.append(RuntimeChoice(path: path, label: path + L(" (unavailable)")))
        }
        return result
    }

    private static func unique(_ urls: [URL], preserveVenv: Bool = false) -> [RuntimeChoice] {
        var seen = Set<String>()
        return urls.compactMap { url in
            guard isExecutable(url) else { return nil }
            let root = url.deletingLastPathComponent().deletingLastPathComponent()
            let key = preserveVenv && FileManager.default.fileExists(atPath: root.appendingPathComponent("pyvenv.cfg").path)
                ? root.standardizedFileURL.path : url.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { return nil }
            return RuntimeChoice(path: url.path)
        }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
