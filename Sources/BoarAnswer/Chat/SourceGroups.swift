import Foundation

/// The sources under an answer, one per article: passages of the same article become one entry with the best score,
/// listed best first. The answer's [n] citations are renumbered to match, so a number still points at its passage's
/// article (android `engine/answer/SourceGroups.kt`).
public enum SourceGroups {
    /// `items` in their new order, and each old 1-based number's new one.
    public struct Grouped<T> {
        public var items: [T]
        public var renumber: [Int: Int]
    }

    public static func group<T>(_ passages: [T], key: (T) -> String, score: (T) -> Double?, merge: ([T]) -> T) -> Grouped<T> {
        var keys: [String] = []
        var byKey: [String: [(index: Int, value: T)]] = [:]
        for (i, p) in passages.enumerated() {
            let k = key(p)
            if byKey[k] == nil { keys.append(k) }
            byKey[k, default: []].append((i, p))
        }
        func value(_ p: T) -> Double { score(p) ?? -.infinity }
        // Stable: equal scores keep the order the model read them in (Kotlin's sortedByDescending).
        func stableDescending<E>(_ xs: [E], _ by: (E) -> Double) -> [E] {
            xs.enumerated().sorted { a, b in
                let (x, y) = (by(a.element), by(b.element))
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        let groups = keys.map { byKey[$0]! }
        let ordered = stableDescending(groups) { g in g.map { value($0.value) }.max() ?? -.infinity }
        var renumber: [Int: Int] = [:]
        var items: [T] = []
        for (i, g) in ordered.enumerated() {
            for p in g { renumber[p.index + 1] = i + 1 }
            items.append(merge(stableDescending(g) { value($0.value) }.map(\.value)))
        }
        return Grouped(items: items, renumber: renumber)
    }

    /// Java's `\s`, ASCII only.
    private static let url = Rx("https?://[^ \\t\\n\\x0B\\f\\r)]+")

    /// Which article a passage belongs to: its page URL when the source names one, so the same article from two packs is
    /// one source; else its document id; else its title.
    public static func articleKey(source: String?, docId: String?, title: String) -> String {
        if let source, let m = url.firstMatch(in: source), let found = m.group(0, in: source) { return found }
        return docId ?? title
    }

    private static let cite = Rx("\\[([0-9]{1,4})\\]")
    private static let repeated = Rx("\\[([0-9]{1,4})\\]((?:[ \\t]*\\[\\1\\])+)")

    /// "[3] … [1][2]" with 1 and 2 merged: "[1] … [2]". Numbers it doesn't know are left as written.
    public static func renumber(_ text: String, map: [Int: Int]) -> String {
        if map.allSatisfy({ $0.key == $0.value }) { return text }
        let out = cite.replace(text) { m in
            let whole = m.group(0, in: text) ?? ""
            guard let n = m.group(1, in: text).flatMap({ Int($0) }), let to = map[n] else { return whole }
            return "[\(to)]"
        }
        return repeated.replace(out) { m in "[\(m.group(1, in: out) ?? "")]" }
    }
}
