import BoarCore
@testable import BoarRAG
import Testing

/// A Markdown file is cut at its "# " and "## " headings, one part per section; other files are sliced as before
/// (MarkdownSplitTest.kt).
@Suite struct MarkdownSplitTests {
    private func parts(_ name: String, _ text: String) throws -> [String] {
        try DocumentImport.plan(collectionId: "c", docs: DocumentImport.parse(.init(name: name, sizeBytes: Int64(text.utf16.count), text: text))).chunks.map(\.body)
    }

    @Test func eachHeadingStartsAPartAndStaysItsFirstLine() throws {
        let md = "# Wallet\n\nSeed kept in the red notebook.\n\n## Budget\n\nRent: 1,250 EUR on the 5th.\n### Detail\nPaid by transfer."
        #expect(try parts("notes.md", md) == [
            "# Wallet\n\nSeed kept in the red notebook.", "## Budget\n\nRent: 1,250 EUR on the 5th.\n### Detail\nPaid by transfer.",
        ])
    }

    @Test func textBeforeTheFirstHeadingIsAPartOfItsOwn() throws {
        #expect(try parts("a.md", "Intro line.\n\n# One\nBody.") == ["Intro line.", "# One\nBody."])
    }

    @Test func aHashWithoutASpaceIsNotAHeading() throws {
        #expect(try parts("a.md", "#tag line\n#2 item") == ["#tag line\n#2 item"])
    }

    @Test func aSectionLongerThanAPartIsSlicedInsideTheSection() throws {
        let long = "## Long\n" + String(repeating: "word ", count: DocumentImport.chunkChars / 4)
        let got = try parts("a.md", "# Short\nA.\n\n\(long)")
        #expect(got.first == "# Short\nA.")
        #expect(Array(got.dropFirst()) == DocumentImport.chunkText(long))
        #expect(got.count > 2)
    }

    @Test func markdownWithoutHeadingsIsSlicedAsBefore() throws {
        let text = String(repeating: "plain ", count: DocumentImport.chunkChars / 3)
        #expect(try parts("a.md", text) == DocumentImport.chunkText(text))
    }

    @Test func otherFileTypesKeepTheFixedSlices() throws {
        let text = "# Not a section\nBody.\n## Still not\nMore."
        #expect(try parts("a.txt", text) == [Js.trim(text)])
    }

    @Test func splitPartsAreNumberedInTheirTitles() throws {
        let chunks = DocumentImport.plan(collectionId: "c", docs: try DocumentImport.parse(.init(name: "n.md", sizeBytes: 20, text: "# A\nx\n# B\ny"))).chunks
        #expect(chunks.map(\.title) == ["n (part 1/2)", "n (part 2/2)"])
    }
}
