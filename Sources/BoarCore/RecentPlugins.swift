import Foundation

/// The chat header's plugins sheet (android `RecentPlugins`, adam, Nov 11): the last `shown` plugins used, newest first,
/// among those switched on; when fewer were used, the others switched on fill it in their list order.
public enum RecentPlugins {
    /// Three (adam, Nov 13; it was five).
    public static let shown = 3
    public static let kept = 10

    public static func pick(active: [String], recent: [String], n: Int = shown) -> [String] {
        var seen = Set<String>()
        let all = recent.filter(active.contains) + active.filter { !recent.contains($0) }
        return Array(all.filter { seen.insert($0).inserted }.prefix(n))
    }

    /// `recent` with `id` moved to the front, at most `kept`.
    public static func used(_ recent: [String], id: String) -> [String] {
        Array(([id] + recent.filter { $0 != id }).prefix(kept))
    }

    /// A search on the Plugins page: every word of `query` in the name or the line under it, accents and case ignored.
    public static func matches(_ query: String, _ texts: String...) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        let hay = fold(texts.joined(separator: " "))
        return words.allSatisfy { hay.contains($0) }
    }

    private static func fold(_ s: String) -> String {
        String(String.UnicodeScalarView(s.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            ![.nonspacingMark, .spacingMark, .enclosingMark].contains($0.properties.generalCategory)
        }))
    }
}
