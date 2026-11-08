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
        case let .failed(code, output): "Команда завершилась с кодом \(code).\n\(output.suffix(4000))"
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

// Each command owns a POSIX process group. Cancellation kills that entire group,
// including subprocess installers that outlive their immediate parent.
private final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var childPID: pid_t = 0
    private var cancelled = false
    private var timedOut = false
    private var finished = false

    func stop(cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if cancelled { self.cancelled = true } else { timedOut = true }
        if childPID > 0 {
            Darwin.kill(-childPID, SIGTERM)
            let group = childPID
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                lock.lock(); defer { lock.unlock() }
                if !finished { Darwin.kill(-group, SIGKILL) }
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
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }

        var env = ProcessInfo.processInfo.environment
        let directories = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (directories + [env["PATH"] ?? ""]).joined(separator: ":")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_AUTOREMOVE"] = "1"
        env["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
        env["NO_COLOR"] = "1"; env["PIP_NO_INPUT"] = "1"; env["UV_NO_PROGRESS"] = "1"
        var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var environment = env.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in environment { free(pointer) }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checked(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checked(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checked(posix_spawn_file_actions_adddup2(&actions, out.fileDescriptor, STDOUT_FILENO))
        try checked(posix_spawn_file_actions_adddup2(&actions, err.fileDescriptor, STDERR_FILENO))
        try checked(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try checked(posix_spawn_file_actions_addchdir_np(&actions, FileManager.default.homeDirectoryForCurrentUser.path))
        try checked(posix_spawnattr_setpgroup(&attributes, 0))
        var mask = sigset_t(), defaults = sigset_t()
        sigemptyset(&mask); sigemptyset(&defaults)
        sigaddset(&defaults, SIGTERM); sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGHUP)
        try checked(posix_spawnattr_setsigmask(&attributes, &mask))
        try checked(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        var pid: pid_t = 0
        let spawnError = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &environment)
        if spawnError != 0 { finished = true; lock.unlock(); try checked(spawnError) }
        childPID = pid
        lock.unlock()
        let timer = DispatchWorkItem { [self] in stop(cancelled: false) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(pid, &status, 0) } while waited == -1 && errno == EINTR
        let waitError = errno
        timer.cancel()
        lock.lock()
        let wasCancelled = cancelled, didTimeOut = timedOut
        // Parent exit does not prove its children have exited. Kill the remaining
        // group before releasing the operation slot after timeout/cancellation.
        if wasCancelled || didTimeOut { Darwin.kill(-pid, SIGKILL) }
        finished = true
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if didTimeOut { throw CommandError.timedOut }
        if waited == -1 { throw POSIXError(POSIXErrorCode(rawValue: waitError) ?? .ECHILD) }
        let signal = status & 0x7f
        let exitCode = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return try CommandResult(exitCode: exitCode, stdout: read(outURL), stderr: read(errURL))
    }

    private func checked(_ code: Int32) throws {
        if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }

    private func read(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 32 * 1024 * 1024 else { throw CommandError.outputTooLarge }
        return String(decoding: data, as: UTF8.self)
    }
}
