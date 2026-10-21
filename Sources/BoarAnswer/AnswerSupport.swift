import BoarCore
import BoarRAG
import BoarRouting
import Foundation

// MARK: - Internal helpers shared by the answer layer

/// A compiled regular expression with the Kotlin `Regex` operations the answer layer uses. ICU through
/// `NSRegularExpression`; patterns are written for Java semantics (`\d` as `[0-9]`, `\s` spelled out), and every offset
/// is UTF-16, as on the JVM.
struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        do {
            re = try NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        } catch {
            fatalError("invalid regex \(pattern): \(error)")
        }
    }

    private func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    func firstMatch(in s: String) -> NSTextCheckingResult? { re.firstMatch(in: s, options: [], range: full(s)) }
    func containsMatch(in s: String) -> Bool { firstMatch(in: s) != nil }
    func matches(in s: String) -> [NSTextCheckingResult] { re.matches(in: s, options: [], range: full(s)) }
    func count(in s: String) -> Int { re.numberOfMatches(in: s, options: [], range: full(s)) }

    /// Kotlin `Regex.replace(input, replacement)`: `$1` refers to group 1.
    func replace(_ s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: full(s), withTemplate: template)
    }

    /// Kotlin `String.replaceFirst(Regex, String)`.
    func replaceFirst(_ s: String, with template: String) -> String {
        guard let m = firstMatch(in: s) else { return s }
        let ns = s as NSString
        let replacement = re.replacementString(for: m, in: s, offset: 0, template: template)
        return ns.replacingCharacters(in: m.range, with: replacement)
    }

    /// Kotlin `Regex.replace(input) { transform }`.
    func replace(_ s: String, transform: (NSTextCheckingResult) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in matches(in: s) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform(m)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Kotlin `CharSequence.split(Regex)` for non-empty matches: every piece, empty ones kept.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in matches(in: s) where m.range.length > 0 {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}

extension NSTextCheckingResult {
    /// The text of group `i` in `s`, nil when it did not take part.
    func group(_ i: Int, in s: String) -> String? {
        let r = range(at: i)
        return r.location == NSNotFound ? nil : (s as NSString).substring(with: r)
    }
}

extension String {
    /// Length in UTF-16 units: Kotlin `String.length`.
    var u16: Int { utf16.count }

    /// Kotlin `take(n)`: the first n UTF-16 units.
    func u16Take(_ n: Int) -> String {
        let len = u16
        if n >= len { return self }
        return (self as NSString).substring(to: max(0, n))
    }

    /// Kotlin `indexOf(needle)` in UTF-16 units; nil when absent.
    func u16IndexOf(_ needle: String) -> Int? {
        let r = (self as NSString).range(of: needle, options: .literal)
        return r.location == NSNotFound ? nil : r.location
    }

    /// Kotlin `startsWith(prefix)` on UTF-16 units.
    func u16HasPrefix(_ prefix: String) -> Bool { utf16.starts(with: prefix.utf16) }

    /// Kotlin `substring(from, to)` in UTF-16 units.
    func u16Substring(_ from: Int, _ to: Int? = nil) -> String {
        let ns = self as NSString
        let end = to ?? ns.length
        return ns.substring(with: NSRange(location: from, length: end - from))
    }
}

/// A value shared between a generation callback and the code around it.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    @discardableResult func withValue<R>(_ body: (inout Value) -> R) -> R { lock.withLock { body(&stored) } }
}

/// Milliseconds on a monotonic clock (Kotlin `System.nanoTime() / 1e6`).
@Sendable public func monotonicMillis() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

// MARK: - Routing seam adapters

/// The text tools `ResearchContext` needs, from BoarRAG's `Compress`.
struct CompressResearchTools: ResearchTextTools {
    func tokenizeTerms(_ text: String) -> [String] { Compress.tokenizeTerms(text) }
    func splitSentences(_ text: String) -> [String] { Compress.splitSentences(text) }
}

extension Chunk: ResearchPassage {}

/// `ResearchContext` over BoarRAG's text tools, and `compressContext` (src/routing/context.ts).
public enum ResearchSupport {
    public static let context = ResearchContext(tools: CompressResearchTools())

    /// compressContext: `Compress.compress` with the older opening check and per-chunk relevance.
    public static func compressContext(_ query: String, _ chunks: [Chunk], tokenBudget: Int = 1200) -> Compress.Result {
        Compress.compress(
            query, chunks, tokenBudget: tokenBudget, maxSentencesPerChunk: 4, pinned: [], openingMustFitWithMatch: false, withRelevance: true
        )
    }
}
