import Foundation
import Testing

@testable import BoarAnswer

/// Press's "Ask BOAR to rewrite it" (android `PressRewriteTest`, t9 0625 item 4): prompts, clean-up and source marks. The
/// Kotlin checks that read the screen's source (the sheet's strings, Use as the only write, G-4's claim) are the app's
/// and have no counterpart here; `outcome` is the runner's text half (android `PressRewriter.run` after the model).
struct PressRewriteTests {
    let en = "Where the sun evaporates a lot of water and few rivers flow in, salt is left behind [1]. The Red Sea is one of the saltiest [2]."
    let pt = "Onde o sol evapora muita água e poucos rios chegam, o sal fica para trás [1]. O Mar Vermelho é um dos mais salgados [2]."

    @Test func eachOptionAsksForItsChangeInTheTextsLanguageAndKeepsTheMarks() {
        for o in PressRewrite.Option.allCases where o != .own {
            let p = PressRewrite.prompt(o, en, own: "for a 10-year-old")
            #expect(p.system.contains("Keep every source mark such as [1] or [2] exactly as written"), "\(o)")
            #expect(p.user.hasPrefix("PASSAGE:\n\(en)\n\nTASK: "), "\(o)")
            #expect((96...1024).contains(p.nPredict), "\(o)")
            let q = PressRewrite.prompt(o, pt, own: "para uma criança")
            #expect(q.system.contains("Mantenha cada marca de fonte"), "\(o)")
            #expect(q.user.hasPrefix("TRECHO:\n\(pt)\n\nTAREFA: "), "\(o)")
        }
        func task(_ p: PressRewrite.Prompt, _ marker: String = "TASK: ") -> String {
            p.user.components(separatedBy: marker).dropFirst().joined(separator: marker)
        }
        #expect(task(PressRewrite.prompt(.shorter, en)).hasPrefix("Rewrite it in at most"))
        #expect(task(PressRewrite.prompt(.simpler, en)).hasPrefix("Rewrite it with short, everyday words"))
        #expect(task(PressRewrite.prompt(.fix, en)).hasPrefix("Fix only the grammar"))
        #expect(task(PressRewrite.prompt(.list, pt), "TAREFA: ").hasPrefix("Transforme em uma lista"))
        #expect(PressRewrite.prompt(.own, en, own: "  for a 10-year-old ").user.hasSuffix("INSTRUCTION: for a 10-year-old"))
        // The language can come from the answer's question when the text alone is too short to tell.
        #expect(PressRewrite.prompt(.fix, "Sim [1].", languageOf: "Por que o mar é salgado? Sim [1].").system.hasPrefix("Você"))
        // A list gets more room than a shorter version.
        let long = String(repeating: en, count: 10)
        #expect(PressRewrite.prompt(.list, long).nPredict > PressRewrite.prompt(.shorter, long).nPredict)
    }

    @Test func theReasoningAndLabelsAreStripped() {
        #expect(PressRewrite.clean("<think>The user wants it shorter.</think>\n\nSalt stays behind [1].") == "Salt stays behind [1].")
        #expect(PressRewrite.clean("Rewritten: \"Salt stays behind [1].\"") == "Salt stays behind [1].")
        #expect(PressRewrite.clean("Texto reescrito: O sal fica [1].") == "O sal fica [1].")
        // While it streams, the reasoning doesn't show.
        #expect(PressRewrite.visible("<think>still thinking") == "")
        #expect(PressRewrite.visible("<think>x</think>Salt") == "Salt")
    }

    @Test func aSourceMarkLostOrAddedIsCaught() {
        #expect(PressRewrite.marks(en) == [1, 2])
        #expect(!PressRewrite.marksChanged(en, "Salt stays [1]; the Red Sea is salty [2]."))
        // Order or repeats don't matter, the set does.
        #expect(!PressRewrite.marksChanged(en, "The Red Sea [2] is salty [1] [1]."))
        #expect(PressRewrite.marksChanged(en, "Salt stays behind [1]."))
        #expect(PressRewrite.marksChanged(en, "Salt [1] stays [2] behind [3]."))
        #expect(!PressRewrite.marksChanged("No marks.", "Still none."))
    }

    /// android `PressRewriteOwnWordsTest`: the user's own words get the document to read and may write new text.
    @Test func theUsersOwnWordsGetTheDocumentToReadAndMayWriteNewText() {
        let doc = PressRewrite.documentContext("Field notes", ["Why is the sea salty?\nSeawater contains minerals and salts [1].", "", "A test sea"])
        #expect(doc == "Field notes\n\nWhy is the sea salty?\nSeawater contains minerals and salts [1].\n\nA test sea")
        let p = PressRewrite.prompt(.own, "this is a test", own: "replace this with a sentence about the document", document: doc)
        #expect(p.system.contains("may ask for new text") && p.system.contains("never add a new one"))
        #expect(p.user.hasPrefix("DOCUMENT (for context only, do not copy it):\nField notes"))
        #expect(p.user.contains("\n\nPASSAGE:\nthis is a test\n\nINSTRUCTION: replace this with a sentence about the document"))
        #expect(p.nPredict >= 320)
        // No document: the passage and the instruction alone; Portuguese follows the text.
        #expect(PressRewrite.prompt(.own, "x", own: "y").user.hasPrefix("PASSAGE:"))
        #expect(PressRewrite.prompt(.own, "Por que o mar é salgado? Não sei.", own: "mais curto").user.contains("INSTRUÇÃO: mais curto"))
        #expect(PressRewrite.documentContext("T", [String(repeating: "a", count: 3000)]).utf16.count <= 1500)
    }

    /// android `PressRewriteNewMarksTest`.
    @Test func newTextNeverGetsASourceMarkThePassageDidntHave() {
        #expect(PressRewrite.dropNewMarks("this is a test", "this document is about the salinity of the sea [1]") == "this document is about the salinity of the sea")
        #expect(PressRewrite.dropNewMarks("Rocks give salt [2].", "Salt comes from rocks [2]. It stays [5].") == "Salt comes from rocks [2]. It stays.")
        // Every option (validator G-2): the runner's outcome drops them whatever was asked.
        #expect(PressRewrite.outcome("this is a test", raw: "<think>x</think>A sentence [1].") == .done(text: "A sentence.", marksChanged: false))
    }

    /// The runner's verdict on what came back (android `PressRewriter.Outcome`).
    @Test func theOutcomeSaysFailedUnchangedOrDone() {
        #expect(PressRewrite.outcome(en, raw: "<think>only thinking</think>") == .failed)
        #expect(PressRewrite.outcome(en, raw: "  " + en.uppercased() + " ") == .unchanged)
        #expect(PressRewrite.outcome(en, raw: "Salt stays [1].") == .done(text: "Salt stays [1].", marksChanged: true))
        #expect(PressRewrite.outcome(en, raw: "Rewritten: Salt stays [1]; the Red Sea is salty [2].")
                == .done(text: "Salt stays [1]; the Red Sea is salty [2].", marksChanged: false))
    }

    @Test func shorterAimsAtHalfTheWordsAndNeverUnderEight() {
        #expect(PressRewrite.words("one two [1] three, 4") == 4)
        #expect(PressRewrite.words("  — [2] ") == 0)
        #expect(PressRewrite.shorterTarget("a b c") == 8)
        #expect(PressRewrite.shorterTarget(String(repeating: "word ", count: 40)) == 20)
        #expect(PressRewrite.instruction(.shorter, own: nil, pt: false, text: String(repeating: "word ", count: 40))
                == "Rewrite it in at most 20 words (it has 40 now). Keep only the main points and cut the rest.")
        // The user's words are cut at 200 characters, as Kotlin's take.
        #expect(PressRewrite.instruction(.own, own: String(repeating: "x", count: 300), pt: false).utf16.count == "Rewrite it this way: ".utf16.count + 200)
    }
}

/// android `PressMorePresetsTest` (adam, Nov 14: "add 2 more presets… to fill the second line"; t9 0136: More formal,
/// As a paragraph). The chips' order and strings are the app's.
struct PressMorePresetsTests {
    let en = "Salt in the sea comes from rocks [1]. Rivers carry it down [2]."
    let pt = "O sal do mar vem das rochas [1]. Os rios o levam até o mar [2]."

    @Test func moreFormalKeepsTheFactsAndTheLengthInEnglishAndPortuguese() {
        let e = PressRewrite.instruction(.formal, own: nil, pt: false, text: en)
        #expect(e.hasPrefix("Rewrite it in a formal, neutral tone, as for a report") && e.contains("no contractions")
                && e.contains("(about \(PressRewrite.words(en)) words)"), "\(e)")
        let p = PressRewrite.instruction(.formal, own: nil, pt: true, text: pt)
        #expect(p.hasPrefix("Reescreva em tom formal e neutro") && p.contains("(cerca de \(PressRewrite.words(pt)) palavras)"), "\(p)")
    }

    @Test func asAParagraphJoinsThePointsWithNoNewFactsInEnglishAndPortuguese() {
        let e = PressRewrite.instruction(.paragraph, own: nil, pt: false, text: en)
        #expect(e.contains("one paragraph of full sentences") && e.contains("no bullets and no line breaks") && e.hasSuffix("The same facts, no new ones."))
        let p = PressRewrite.instruction(.paragraph, own: nil, pt: true, text: pt)
        #expect(p.contains("um só parágrafo") && p.hasSuffix("Os mesmos fatos, nenhum fato novo."))
    }

    @Test func bothUseThePassageFirstPromptTheSameSystemAndMarksRulesAndTheDefaultRoom() {
        for o in [PressRewrite.Option.formal, .paragraph] {
            let pe = PressRewrite.prompt(o, String(repeating: en, count: 6))
            #expect(pe.user.hasPrefix("PASSAGE:") && pe.user.contains("\n\nTASK: ") && pe.system.contains("Keep every source mark"))
            #expect(PressRewrite.prompt(.simpler, String(repeating: en, count: 6)).nPredict == pe.nPredict)
            let pp = PressRewrite.prompt(o, String(repeating: pt, count: 6))
            #expect(pp.user.hasPrefix("TRECHO:") && pp.user.contains("TAREFA: ") && pp.system.contains("Mantenha cada marca de fonte"))
        }
    }
}
