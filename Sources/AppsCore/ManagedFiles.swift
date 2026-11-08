import Foundation
import Darwin

public protocol FileTrashing: Sendable { func trash(_ url: URL) throws }
public struct SystemTrash: FileTrashing {
    public init() {}
    public func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}

enum ManagedFiles {
    static func fingerprint(_ url: URL) throws -> String {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw ManagerError.contextChanged }
        return "\(info.st_dev)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)|\(info.st_mode)|\(info.st_uid)"
    }
    static func owned(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    }
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

extension PackageManager {
    func boundedOutput(_ arguments: [String], timeout: Duration = .seconds(60)) async throws -> String {
        let result = try await withThrowingTaskGroup(of: CommandResult.self) { group in
            group.addTask { try await runner.run(executable: executable, arguments: arguments) }
            group.addTask { try await Task.sleep(for: timeout); throw CommandError.timedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        return try result.requireSuccess()
    }
}
