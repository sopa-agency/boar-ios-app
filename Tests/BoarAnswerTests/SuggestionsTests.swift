import Foundation
import Testing

@testable import BoarAnswer

/// suggestionsFor on every model, language and installed set, against the TS (golden/suggestions.txt).
struct SuggestionsTests {
    @Test func sameSuggestionsAsTheTS() throws {
        let s = try Suggestions.bundled()
        let lines = try Fixtures.text(Fixtures.golden.appendingPathComponent("suggestions.txt")).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for line in lines {
            let parts = line.components(separatedBy: "|")
            try #require(parts.count == 4, "\(line)")
            let installed = parts[2].components(separatedBy: ",").filter { !$0.isEmpty }
            let got = s.forModel(parts[0] == "null" ? nil : parts[0], language: parts[1] == "null" ? nil : parts[1], installed: installed)
            #expect(got.joined(separator: ",") == parts[3], "\(line)")
        }
        #expect(lines.count == 80)
    }

    @Test func theIdeaPoolIsTheTestedIdeasThenTheBenchOnes() throws {
        let s = try Suggestions.bundled()
        let bench = (1...21).map { "b\($0)" }
        // Three or more tested on the model: those, then the bench.
        #expect(s.ideaPool("qwen3-4b-instruct-2507-q4km", language: "en") == ["q2", "q7", "q8"] + bench)
        #expect(s.ideaPool("qwen3-4b-instruct-2507-q4km", language: "en", installed: ["wiki-vital5"])
            == ["q2", "q4", "q7", "q8"] + bench)
        // One tested in Portuguese: filled from the other models, same language, without repeats.
        #expect(s.ideaPool("qwen2.5-1.5b-instruct-q4km", language: "pt-BR", installed: ["boar-preparedness"])
            == ["q8", "q4"] + bench)
        // No model, or one with no tested ideas: the other models' ideas.
        #expect(s.ideaPool(nil, language: "en") == ["q2", "q7", "q8"] + bench)
        #expect(s.ideaPool("hf-some-model", language: "pt") == ["q8"] + bench)
        #expect(Suggestions.benchIdeas == bench && Suggestions.ideasShown == 3)
    }

    @Test func theKnowledgeHintShowsBelowTheMinimum() throws {
        let s = try Suggestions.bundled()
        #expect(s.showsKnowledgeHint(s.minSuggestions - 1))
        #expect(!s.showsKnowledgeHint(s.minSuggestions))
    }
}
