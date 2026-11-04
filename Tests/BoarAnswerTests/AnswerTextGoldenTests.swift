import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// The answer path's text helpers must match the TypeScript on the modules' test strings and on real model answers from eval
/// runs (scripts/export-native-golden-answer.mjs).
struct AnswerTextGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("answer-text.json") }

    @Test func thinkingSplit() throws {
        let cases = try req(g["thinking"]).arr
        #expect(!cases.isEmpty)
        for c in cases {
            let o = c["out"]!
            let want = SplitThinking(answer: o["answer"]!.str!, thinking: o["thinking"]?.str, thinkingInProgress: o["thinkingInProgress"]!.flag)
            #expect(AnswerText.splitThinking(c["in"]!.str!) == want, "\(c["in"]!.str!)")
        }
    }

    @Test func inlineBullets() throws {
        let cases = try req(g["bullets"]).arr
        #expect(!cases.isEmpty)
        for c in cases { #expect(AnswerText.splitInlineBullets(c["in"]!.str!) == c["out"]!.str!, "\(c["in"]!.str!)") }
    }

    @Test func citationCleanup() throws {
        let cases = try req(g["citations"]).arr
        #expect(!cases.isEmpty)
        for c in cases {
            let n = c.opt("n")?.intValue
            #expect(AnswerText.cleanCitations(c["in"]!.str!, sourceCount: n) == c["out"]!.str!, "\(c["in"]!.str!) / \(n.map(String.init) ?? "null")")
        }
    }

    @Test func personalitiesFromTheExportedData() throws {
        let p = try Personalities.bundled()
        #expect(p.personalities.map(\.id) == ["succinct", "detailed", "personal", "custom"])
        #expect(p.defaultId == "detailed")
        #expect(p.defaultMaxTokens == 512)
        #expect(p.promptFor(nil, customPrompt: nil).systemPrompt == p.get("detailed").systemPrompt)
        let custom = p.promptFor("custom", customPrompt: "Mine.")
        #expect(custom.systemPrompt == "Mine." && custom.styleReminder == nil)
        #expect(p.get("unknown") == p.personalities[0])
    }
}
