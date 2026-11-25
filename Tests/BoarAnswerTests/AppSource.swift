import Foundation
import Testing

/// The app's Swift source as text, for the wiring tests that stand in for android's tests that read the Kotlin UI source
/// (the app target has no unit-test host; see `PromptQueueWiringTests`, `KeepGoingWiringTests`).
enum AppSource {
    static func text(_ path: String) throws -> String { try Fixtures.text(Fixtures.root.appending(path: path)) }

    /// Every `.swift` file under `dir` (relative to the repository), as paths `text` reads.
    static func swiftFiles(under dir: String) throws -> [String] {
        let root = Fixtures.root.appending(path: dir)
        let walker = try #require(FileManager.default.enumerator(atPath: root.path(percentEncoded: false)))
        return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.map { "\(dir)/\($0)" }
    }

    /// `text` after the first `marker`, up to the next `end` (Kotlin's substringAfter().substringBefore()).
    static func slice(_ text: String, after marker: String, before end: String) throws -> String {
        let from = try #require(text.range(of: marker), Comment(rawValue: "no \(marker)")).upperBound
        let rest = text[from...]
        return String(rest[..<(rest.range(of: end)?.lowerBound ?? rest.endIndex)])
    }

    /// The String Catalog's Portuguese for a key (nil: no key or no Portuguese).
    static func portuguese(_ key: String) throws -> String? {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(text("App/Resources/Localizable.xcstrings").utf8)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let entry = strings[key] as? [String: Any]
        let pt = (entry?["localizations"] as? [String: Any])?["pt"] as? [String: Any]
        return (pt?["stringUnit"] as? [String: Any])?["value"] as? String
    }
}
