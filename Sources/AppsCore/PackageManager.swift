import Foundation

public enum ManagerError: LocalizedError {
    case invalidData(String), invalidTarget
    public var errorDescription: String? {
        switch self {
        case let .invalidData(source): "Не удалось прочитать данные \(source). Возможно, формат этой версии менеджера не поддерживается."
        case .invalidTarget: "Пакет не принадлежит выбранной установке менеджера или его имя недопустимо."
        }
    }
}

public protocol PackageManager: Sendable {
    var source: PackageSource { get }
    var executable: URL { get }
    var runner: any CommandRunning { get }
    func list() async throws -> [PackageRecord]
    func checkUpdates() async throws -> [PackageRecord]
    func upgrade(_ package: PackageRecord) async throws -> CommandResult
    func uninstall(_ package: PackageRecord) async throws -> CommandResult
}

extension PackageManager {
    func validate(_ package: PackageRecord) throws {
        guard package.source == source, package.managerPath == executable.path,
              package.name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+@/-]*$"#, options: .regularExpression) != nil,
              !package.name.split(separator: "/").contains("..") else { throw ManagerError.invalidTarget }
    }
    func output(_ arguments: [String]) async throws -> String {
        try await runner.run(executable: executable, arguments: arguments).requireSuccess()
    }
}

func jsonObject(_ text: String, source: String) throws -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ManagerError.invalidData(source)
    }
    return object
}
