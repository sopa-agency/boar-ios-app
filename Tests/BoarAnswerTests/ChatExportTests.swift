import Testing

@testable import BoarAnswer

/// android engine/chat `ChatExportTest.kt` (its AnswerLimit case belongs to another port).
struct ChatExportTests {
    private let labels = ChatExport.Labels(reasoning: "Reasoning", sources: "Sources")

    @Test func answerWithReasoningAndSources() {
        let md = ChatExport.turn(ChatExport.Turn(question: "Why is the sky blue?", answer: "Rayleigh scattering [1].",
                                                 reasoning: "Short waves\n\nscatter more",
                                                 sources: [("Rayleigh scattering", "pack:wiki"), ("Sky", nil)],
                                                 details: "18.0 s · 10.4 tok/s"), labels)
        #expect(md == "## Why is the sky blue?\n\n> 💭 **Reasoning**\n>\n> Short waves\n>\n> scatter more\n\nRayleigh scattering [1].\n\n**Sources**\n\n1. Rayleigh scattering — pack:wiki\n2. Sky\n\n_18.0 s · 10.4 tok/s_\n")
    }

    @Test func plainAnswer() {
        #expect(ChatExport.turn(ChatExport.Turn(question: nil, answer: " Hello. ", reasoning: nil, sources: [], details: nil), labels) == "Hello.\n")
    }

    @Test func chatJoinsTurns() {
        let t = ChatExport.Turn(question: "Q", answer: "A", reasoning: nil, sources: [], details: nil)
        #expect(ChatExport.chat("Trip", [t, t], labels) == "# Trip\n\n## Q\n\nA\n\n---\n\n## Q\n\nA\n")
    }

    @Test func fileNames() {
        #expect(ChatExport.fileName("Por que o céu é azul?", date: "2026-10-15") == "boar-2026-10-15-por-que-o-ceu-e-azul.md")
        #expect(ChatExport.fileName("💭", date: "2026-10-15") == "boar-2026-10-15.md")
    }

    // Not in the Kotlin test: the source line drops a source equal to its title, and the slug's 48-letter cut.
    @Test func aSourceEqualToItsTitleIsNotRepeated() {
        let md = ChatExport.turn(ChatExport.Turn(question: nil, answer: "A", reasoning: nil, sources: [("Sky", "Sky"), ("Sea", " ")], details: " "), labels)
        #expect(md == "A\n\n**Sources**\n\n1. Sky\n2. Sea\n")
    }

    @Test func theSlugIsCutAt48WithoutATrailingDash() {
        let name = ChatExport.fileName(String(repeating: "abcd ", count: 20), date: "2026-11-05")
        // 48 characters of "abcd-abcd-…": nine "abcd-" and "abc".
        #expect(name == "boar-2026-11-05-abcd-abcd-abcd-abcd-abcd-abcd-abcd-abcd-abcd-abc.md")
        // A cut that ends on a dash drops it: 47 letters and dashes, then "-".
        #expect(ChatExport.fileName(String(repeating: "a", count: 47) + " b", date: "d") == "boar-d-" + String(repeating: "a", count: 47) + ".md")
    }
}
