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

    @Test func theKnowledgeHintShowsBelowTheMinimum() throws {
        let s = try Suggestions.bundled()
        #expect(s.showsKnowledgeHint(s.minSuggestions - 1))
        #expect(!s.showsKnowledgeHint(s.minSuggestions))
    }
}
