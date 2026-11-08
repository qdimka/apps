import Foundation

public enum PackageSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case homebrew, uv, pipx
    public var id: String { rawValue }
    public var title: String {
        switch self { case .homebrew: "Homebrew"; case .uv: "uv tools"; case .pipx: "pipx" }
    }
    public var executableName: String { self == .homebrew ? "brew" : rawValue }
}

public enum PackageKind: String, Sendable, Codable {
    case formula, cask, tool
    public var title: String {
        switch self { case .formula: "CLI / библиотека"; case .cask: "Приложение"; case .tool: "Python CLI" }
    }
}

public enum UpdateStatus: String, Sendable, Codable {
    case notChecked, available, current, unsupported
    public var title: String {
        switch self {
        case .notChecked: "Не проверено"
        case .available: "Доступно обновление"
        case .current: "Актуальная версия"
        case .unsupported: "Версия не проверена"
        }
    }
}

public struct PackageRecord: Identifiable, Hashable, Sendable, Codable {
    public struct ID: Hashable, Sendable, Codable {
        public let source: PackageSource
        public let managerPath: String
        public let name: String
        public let kind: PackageKind
    }
    public var id: ID { ID(source: source, managerPath: managerPath, name: name, kind: kind) }
    public let name: String
    public let source: PackageSource
    public let managerPath: String
    public var version: String
    public var kind: PackageKind
    public var summary: String
    public var installationPath: String?
    public var executables: [String]
    public var dependencies: [String]
    public var latestVersion: String?
    public var updateStatus: UpdateStatus
    public var pinned: Bool
    public var homepage: String?

    public init(name: String, source: PackageSource, managerPath: String, version: String,
                kind: PackageKind = .tool, summary: String = "", installationPath: String? = nil,
                executables: [String] = [], dependencies: [String] = [], latestVersion: String? = nil,
                updateStatus: UpdateStatus = .notChecked, pinned: Bool = false, homepage: String? = nil) {
        self.name = name; self.source = source; self.managerPath = managerPath; self.version = version
        self.kind = kind; self.summary = summary; self.installationPath = installationPath
        self.executables = executables; self.dependencies = dependencies; self.latestVersion = latestVersion
        self.updateStatus = updateStatus; self.pinned = pinned; self.homepage = homepage
    }
}
