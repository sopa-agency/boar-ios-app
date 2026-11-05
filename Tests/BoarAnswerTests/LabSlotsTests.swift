import BoarRAG
import Testing

@testable import BoarAnswer

/// The Boar Labs slots' shared rules (android LabTools.kt, AnswerTools.kt, AnswerChecks.kt).
struct LabSlotsTests {
    private struct Fails: Error {}

    private struct Tool: AnswerTool {
        let result: ToolResult?
        var throwsError = false
        func run(query: String, history: [ConversationTurn]) throws -> ToolResult? {
            if throwsError { throw Fails() }
            return result
        }
    }

    private struct Check: AnswerCheck {
        let repair: Repair?
        var throwsError = false
        func check(question: String, answer: String) throws -> Repair? {
            if throwsError { throw Fails() }
            return repair
        }
    }

    @Test func safetyFirstThenPolyglotThenGridOrder() {
        #expect(LabTools.slotRank("cohazard") == 0)
        #expect(LabTools.slotRank("polyglot") == 1)
        #expect(LabTools.slotRank("calc") == 2)
        #expect(LabTools.slotRank("facts") == 2)
        let sorted = ["calc", "facts", "polyglot", "cohazard", "distance"].sorted { LabTools.slotRank($0) < LabTools.slotRank($1) }
        #expect(sorted.prefix(2) == ["cohazard", "polyglot"])
    }

    @Test func firstSkipsNilAndThrowingItems() {
        let tools: [any AnswerTool] = [
            Tool(result: nil),
            Tool(result: .instant(tool: "x", text: "boom"), throwsError: true),
            Tool(result: .context(tool: "facts-population", text: "Population: 1")),
            Tool(result: .instant(tool: "late", text: "never")),
        ]
        #expect(AnswerTools.run(tools, query: "q", history: []) == .context(tool: "facts-population", text: "Population: 1"))
        #expect(AnswerTools.run([], query: "q", history: []) == nil)
    }

    @Test func contextGoesAfterTheSystemPrompt() {
        #expect(AnswerTools.systemPrompt("base", .context(tool: "t", text: "fact")) == "base\n\nfact")
        #expect(AnswerTools.systemPrompt("base", .instant(tool: "t", text: "answer")) == "base")
        #expect(AnswerTools.systemPrompt("base", nil) == "base")
        #expect(ToolResult.instant(tool: "calculator-battery", text: "4 h").tool == "calculator-battery")
        #expect(ToolResult.instant(tool: "a", text: "b").instantText == "b")
        #expect(ToolResult.context(tool: "a", text: "b").instantText == nil)
    }

    @Test func checksRunOnlyOnAFinishedModelAnswer() {
        #expect(LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: nil, blank: false))
        #expect(LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: "adaptive", blank: false))
        #expect(!LabTools.checksAnswer(instant: true, stopped: false, timedOut: false, failed: false, path: nil, blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: true, timedOut: false, failed: false, path: nil, blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: true, failed: false, path: nil, blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: true, path: nil, blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: "deep", blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: "chat", blank: false))
        #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: nil, blank: true))
    }

    @Test func firstRepairWins() {
        let checks: [any AnswerCheck] = [
            Check(repair: Repair(tool: "boom", text: ""), throwsError: true),
            Check(repair: nil),
            Check(repair: Repair(tool: "verdict-guard-date", text: "No.")),
        ]
        #expect(AnswerChecks.run(checks, question: "q", answer: "Yes.") == Repair(tool: "verdict-guard-date", text: "No."))
        #expect(AnswerChecks.run([], question: "q", answer: "Yes.") == nil)
    }
}
