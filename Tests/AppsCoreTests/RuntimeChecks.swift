import Foundation
import AppsCore

enum RuntimeChecks {
    static func executable(_ path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }
    static var all: [Check] { [
        Check(name: "Runtime discovery honors nvm default over the newest installed version") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let selected = home.appendingPathComponent(".nvm/versions/node/v20.1.0/bin/npm")
            try executable(selected)
            try executable(home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/npm"))
            let alias = home.appendingPathComponent(".nvm/alias/default")
            try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("v20.1.0\n".utf8).write(to: alias)
            let choices = RuntimeDiscovery.npmChoices(searchPaths: [], home: home)
            try expectEqual(choices.first?.path, selected.path)
            try expectEqual(choices.count, 2)
        },
        Check(name: "Python environment selection preserves venv symlink identity") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let base = directory.appendingPathComponent("base/bin/python")
            try executable(base)
            let venv = directory.appendingPathComponent("Project/.venv")
            try FileManager.default.createDirectory(at: venv.appendingPathComponent("bin"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: venv.appendingPathComponent("bin/python"), withDestinationURL: base)
            try Data("home = base\n".utf8).write(to: venv.appendingPathComponent("pyvenv.cfg"))
            let found = RuntimeDiscovery.resolvePythonSelection(directory.appendingPathComponent("Project"))
            try expectEqual(found?.path, venv.appendingPathComponent("bin/python").path)
            try expect(found?.path != base.path)
        },
        Check(name: "Default pip follows its Python shebang rather than unrelated python3") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let python = home.appendingPathComponent("conda/bin/python")
            try executable(python)
            let pip = home.appendingPathComponent("conda/bin/pip")
            try Data(("#!" + python.path + "\n").utf8).write(to: pip)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pip.path)
            try expectEqual(RuntimeDiscovery.preferredPython(searchPaths: [python.deletingLastPathComponent().path], home: home)?.path, python.path)
        }
    ] }
}
