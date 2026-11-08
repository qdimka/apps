import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    }
    public var log: String { [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n") }
    public func requireSuccess() throws -> String {
        guard exitCode == 0 else { throw CommandError.failed(exitCode, log) }
        return stdout
    }
}

public enum CommandError: LocalizedError, Equatable {
    case timedOut, outputTooLarge, failed(Int32, String)
    public var errorDescription: String? {
        switch self {
        case .timedOut: "Команда превысила время ожидания. Проверьте состояние менеджера перед повтором."
        case .outputTooLarge: "Вывод команды превышает 32 МБ."
        case let .failed(code, output): "Команда завершилась с кодом \(code).\n\(output)"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandResult
}

public struct CommandRunner: CommandRunning {
    public let timeout: TimeInterval
    public init(timeout: TimeInterval = 1800) { self.timeout = timeout }

    public func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try execution.run(executable, arguments, timeout: timeout)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { execution.stop(cancelled: true) }
    }
}

// A process and its cancellation state are shared between the worker and timer.
// Each mutable field is protected by lock; output goes to separate files to avoid
// full-pipe deadlocks and retaining unbounded output in memory.
private final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    private var finished = false

    func stop(cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if cancelled { self.cancelled = true } else { timedOut = true }
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                lock.lock(); defer { lock.unlock() }
                if !finished && process.isRunning { Darwin.kill(pid, SIGKILL) }
            }
        }
    }

    func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("apps-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = out; process.standardError = err
        process.standardInput = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        let directories = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (directories + [env["PATH"] ?? ""]).joined(separator: ":")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["NO_COLOR"] = "1"; env["PIP_NO_INPUT"] = "1"; env["UV_NO_PROGRESS"] = "1"
        process.environment = env

        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run(); lock.unlock() }
        catch { finished = true; lock.unlock(); throw error }
        let timer = DispatchWorkItem { [self] in stop(cancelled: false) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        process.waitUntilExit()
        timer.cancel()
        lock.lock()
        finished = true
        let wasCancelled = cancelled, didTimeOut = timedOut
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if didTimeOut { throw CommandError.timedOut }
        return try CommandResult(exitCode: process.terminationStatus, stdout: read(outURL), stderr: read(errURL))
    }

    private func read(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 32 * 1024 * 1024 else { throw CommandError.outputTooLarge }
        return String(decoding: data, as: UTF8.self)
    }
}
