import Foundation

public enum PackageSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case homebrew, uv, pipx, npm, pip, go, cargo
    public var id: String { rawValue }
    public var title: String {
        switch self { case .homebrew: "Homebrew"; case .uv: "uv tools"; case .pipx: "pipx"; case .npm: "npm"; case .pip: "pip"; case .go: "Go"; case .cargo: "Cargo" }
    }
    public var executableName: String {
        switch self { case .homebrew: "brew"; case .pip: "python3"; default: rawValue }
    }
}

public enum PackageKind: String, Sendable, Codable {
    case formula, cask, tool, npmPackage, pythonPackage, goTool, cargoPackage
    public var title: String {
        switch self { case .formula: "CLI / библиотека"; case .cask: "Приложение"; case .tool: "Python CLI"; case .npmPackage: "npm · глобально"; case .pythonPackage: "Пакет Python"; case .goTool: "Go CLI"; case .cargoPackage: "Rust CLI" }
    }
}

public enum UpdateStatus: String, Sendable, Codable {
    case notChecked, available, current, unsupported
    public var title: String {
        switch self {
        case .notChecked: "Не проверено"
        case .available: "Доступно обновление"
        case .current: "Обновление не найдено"
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
        public let identityScope: String?
    }
    public var id: ID { ID(source: source, managerPath: managerPath, name: name, kind: kind, identityScope: identityScope) }
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
    public var environmentPath: String?
    public var upgradeRestriction: String?
    public var removalRestriction: String?
    public var isUserInstall: Bool
    public var identityScope: String?
    public var packageReference: String?
    public var modulePath: String?
    public var buildOptions: [String: String]
    public var installationKey: String?

    public init(name: String, source: PackageSource, managerPath: String, version: String,
                kind: PackageKind = .tool, summary: String = "", installationPath: String? = nil,
                executables: [String] = [], dependencies: [String] = [], latestVersion: String? = nil,
                updateStatus: UpdateStatus = .notChecked, pinned: Bool = false, homepage: String? = nil,
                environmentPath: String? = nil, upgradeRestriction: String? = nil, removalRestriction: String? = nil, isUserInstall: Bool = false, installationKey: String? = nil, identityScope: String? = nil, packageReference: String? = nil, modulePath: String? = nil, buildOptions: [String: String] = [:]) {
        self.name = name; self.source = source; self.managerPath = managerPath; self.version = version
        self.kind = kind; self.summary = summary; self.installationPath = installationPath
        self.executables = executables; self.dependencies = dependencies; self.latestVersion = latestVersion
        self.updateStatus = updateStatus; self.pinned = pinned; self.homepage = homepage
        self.environmentPath = environmentPath; self.upgradeRestriction = upgradeRestriction; self.removalRestriction = removalRestriction
        self.isUserInstall = isUserInstall
        self.installationKey = installationKey
        self.identityScope = identityScope; self.packageReference = packageReference; self.modulePath = modulePath; self.buildOptions = buildOptions
    }
}
