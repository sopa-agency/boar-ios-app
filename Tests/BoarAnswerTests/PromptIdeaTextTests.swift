import Foundation
import Testing

@testable import BoarAnswer

/// Every idea key the empty chat can draw has its text in the app: a key added to `suggestions.json` without a case in
/// `PromptIdea.text` (App/Sources/Model/ChatTypes.swift) would be dropped from the cards without a word. The app target
/// has no unit tests, so this reads its source and string catalog.
struct PromptIdeaTextTests {
    @Test func everyDrawableIdeaHasATopicAndAQuestionInBothLanguages() throws {
        let s = try Suggestions.bundled()
        let keys = Set(s.validation.byModel.values.flatMap { $0.values.flatMap { $0 } } + Suggestions.benchIdeas)
        #expect(keys.count > Suggestions.benchIdeas.count)

        let source = try Fixtures.text(Fixtures.root.appending(path: "App/Sources/Model/ChatTypes.swift"))
        let body = try #require(source.components(separatedBy: "enum PromptIdea {").last)
        // case "q1": (String(localized: "Science"), String(localized: "How Earth's tilt …"))
        let line = /case "([a-z0-9]+)": \(String\(localized: "([^"]+)"\), String\(localized: "([^"]+)"\)\)/
        var texts: [String: (topic: String, question: String)] = [:]
        for m in body.matches(of: line) { texts[String(m.1)] = (String(m.2), String(m.3)) }

        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Localizable.xcstrings"))) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        func translated(_ key: String) -> Bool {
            let pt = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["pt"] as? [String: Any]
            return (pt?["stringUnit"] as? [String: Any])?["value"] is String
        }

        for key in keys.sorted() {
            guard let t = texts[key] else {
                Issue.record("idea \(key) has no case in PromptIdea.text")
                continue
            }
            #expect(translated(t.topic), "idea \(key): topic \"\(t.topic)\" has no Portuguese")
            #expect(translated(t.question), "idea \(key): question \"\(t.question)\" has no Portuguese")
        }
    }
}
