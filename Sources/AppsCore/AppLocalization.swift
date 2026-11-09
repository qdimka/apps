import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en", russian = "ru"
    public var id: String { rawValue }
    public var nativeName: String { self == .english ? "English" : "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439}" }
    public static func resolve(_ preference: String?) -> Self { preference.flatMap(Self.init(rawValue:)) ?? .english }
}

public enum AppLocalization {
    public static let preferenceKey = "appLanguage"
    public static var current: AppLanguage { AppLanguage.resolve(UserDefaults.standard.string(forKey: preferenceKey)) }
    private static let resources: Bundle = {
        // SwiftPM's development fallback is not present on a downloaded installation.
        if let root = Bundle.main.resourceURL,
           let embedded = Bundle(url: root.appendingPathComponent("apps_AppsCore.bundle")) { return embedded }
        return Bundle.module
    }()
    public static func catalog(_ language: AppLanguage) throws -> [String: String] {
        guard let file = resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language.rawValue),
              let entries = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: String] else {
            throw NSError(domain: "apps.localization", code: 1, userInfo: [NSLocalizedDescriptionKey: "Localization catalog is missing or invalid."])
        }
        return entries
    }
    private static let translations: [AppLanguage: [String: String]] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { ($0, (try? catalog($0)) ?? [:]) })

    public static func relocalized(_ value: String, from: AppLanguage, to: AppLanguage) -> String {
        guard from != to, let source = translations[from] else { return value }
        if let key = source.first(where: { $0.value == value })?.key { return text(key, language: to) }
        for (key, format) in source where format.contains("%@") {
            let pieces = format.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
            let pattern = "^" + pieces.joined(separator: "(.*?)") + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            let arguments = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
            return text(key, arguments: arguments, language: to)
        }
        return value
    }

    public static func text(_ key: String, arguments: [String] = [], language: AppLanguage? = nil) -> String {
        let selected = language ?? current
        let format = translations[selected]?[key] ?? translations[.english]?[key] ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: selected.rawValue), arguments: arguments.map { $0 as CVarArg })
    }
}

// Capture interpolation separately from the catalog key. Package names and paths are data,
// never localization keys or format strings.
public struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
    }
}

public func L(_ value: LocalizedText, language: AppLanguage? = nil) -> String { AppLocalization.text(value.key, arguments: value.arguments, language: language) }
