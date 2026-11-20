import BoarCore
import BoarRAG
import Foundation
import Testing

/// The user's own documents through the whole retrieval, on a real SQLite with FTS5 (UserDocumentsRetrievalTest.kt).
/// Only the ebook case is here; the class's other tests (a part under the answer floor, Personal Files floors) are
/// covered in OwnFilesTests's retrieval section.
@Suite struct UserDocumentsRetrievalTests {
    private let questionVec: [Float] = [1, 0, 0]
    /// Cosine 0.6 with the question: above the semantic search's floor (0.55), under the answer floor (0.70).
    private let weakVec: [Float] = [0.6, 0.8, 0]

    private func retriever(_ kb: KnowledgeBase) -> Retriever {
        let v = questionVec
        return Retriever(kb: kb, packs: { [] }, embed: { _ in v }, lexicon: { PtLexicon.Lexicon([:]) })
    }

    /// The F3, 15 Nov (all62): "Quais são as três montanhas mais altas, e qual a altura de cada uma?" cited only the
    /// user's investment ebook (part 16/17), which matched "qual", "cada", "uma"... by keyword. Fixed by the Portuguese
    /// function words as stop words (t9 0400 item 2): this keeps it fixed.
    @Test func aPortugueseFileSharingOnlyFunctionWordsWithTheQuestionDoesntOutrankTheLibrary() async throws {
        let q = "Quais são as três montanhas mais altas, e qual a altura de cada uma?"
        // Function words only, as many as the old search needed to let it in (6 of the question's 10 terms then).
        let ebook = "Quais são as opções mais seguras? Qual a melhor forma de investir? Cada uma tem riscos; qual escolher depende de "
            + "você e de uma análise cuidadosa, e não há uma resposta que sirva para cada caso."
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try kb.insertChunk(Chunk(chunkId: "wiki-everest", docId: "mountain", title: "Mountain", body: "The highest mountains are Mount Everest, K2 and Kangchenjunga."), embedding: questionVec)
        try kb.createCollection(id: "ebook", name: "ebook", sourceFilename: "eBook_investimentos_internacional.pdf", docCount: 1, chunkCount: 1, sizeBytes: 50_000, now: 1)
        try kb.insertChunk(Chunk(chunkId: "ebook-16", docId: "ebook", title: "eBook_investimentos_internacional (part 16/17)", body: ebook, collectionId: "ebook"), embedding: weakVec)
        let found = try await retriever(kb).retrieve(q, topK: 4, queryVec: questionVec)
        #expect(!found.contains { $0.collectionId == "ebook" }, "\(found.map(\.title))")
        #expect(found.first?.title == "Mountain")
        // Its own words still bring a file in: the rule above isn't weakened.
        let own = try await retriever(kb).retrieve("Qual a melhor forma de investir em opções?", topK: 4, queryVec: questionVec)
        #expect(own.contains { $0.collectionId == "ebook" })
    }
}
