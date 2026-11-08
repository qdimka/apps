import Foundation

public enum ManagerDiscovery {
    public static func defaultSearchPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        paths += [home + "/.local/bin", home + "/.cargo/bin", "/opt/homebrew/bin", "/usr/local/bin", "/opt/anaconda3/bin",
                  home + "/anaconda3/bin", home + "/miniconda3/bin", "/opt/miniconda3/bin", "/usr/bin", "/bin"]
        let python = home + "/Library/Python"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: python) {
            paths += versions.sorted().map { python + "/" + $0 + "/bin" }
        }
        var seen = Set<String>()
        return paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    public static func find(_ source: PackageSource, searchPaths: [String]? = nil) -> URL? {
        for directory in searchPaths ?? defaultSearchPaths() {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(source.executableName)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public static func managers(npmPath: String? = nil, pythonPath: String? = nil, cargoRoot: String? = nil) -> [any PackageManager] {
        PackageSource.allCases.compactMap { source in
            let candidate: URL?
            switch source {
            case .npm: candidate = (npmPath ?? RuntimeDiscovery.npmChoices().first?.path).map { URL(fileURLWithPath: $0) }
            case .pip: candidate = pythonPath.map { URL(fileURLWithPath: $0) } ?? RuntimeDiscovery.preferredPython()
            default: candidate = find(source)
            }
            guard let url = candidate else { return nil }
            switch source {
            case .homebrew: return HomebrewManager(executable: url)
            case .uv: return UVManager(executable: url)
            case .pipx: return PipxManager(executable: url)
            case .npm: return NPMManager(executable: url)
            case .pip: return PipManager(executable: url)
            case .go: return GoManager(executable: url)
            case .cargo: return CargoManager(executable: url, root: cargoRoot.map { URL(fileURLWithPath: $0) })
            }
        }
    }
}
