import Foundation

public struct SemanticVersion: Comparable, Sendable {
    private let core: [Int]
    private let prerelease: [String]

    public init?(_ text: String) {
        let pattern = #"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length == text.utf16.count else { return nil }
        func field(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
        let numbers = (1...3).compactMap { field($0).flatMap(Int.init) }
        guard numbers.count == 3 else { return nil }
        let identifiers = field(4)?.split(separator: ".").map(String.init) ?? []
        guard !identifiers.contains(where: { Self.numeric($0) && $0.count > 1 && $0.hasPrefix("0") }) else { return nil }
        core = numbers; prerelease = identifiers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for (a, b) in zip(lhs.core, rhs.core) where a != b { return a < b }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let an = numeric(a), bn = numeric(b)
            if an != bn { return an }
            if an && a.count != b.count { return a.count < b.count }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
    private static func numeric(_ text: String) -> Bool { !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } }
}
