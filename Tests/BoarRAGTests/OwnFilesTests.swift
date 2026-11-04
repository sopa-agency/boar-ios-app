import BoarCore
@testable import BoarRAG
import Foundation
import Testing

/// Personal Files knows the user's files as files (OwnFilesTest.kt): whole-file questions, a named file, the list, the cards.
@Suite struct OwnFilesTests {
    @Test func questionsAboutTheFilesAsAWholeInEnglishAndPortuguese() {
        for q in [
            "What are the main points of my files?", "Summarize my notes", "Give me an overview of my documents",
            "Which files do I have?", "Do I have a medical file?", "How many documents did I import?",
            "Resuma meus arquivos", "Quais são os pontos principais dos meus documentos?", "Tenho algum arquivo sobre o carro?",
            "O que tem nas minhas anotações?", "Resuma a minha documentação",
        ] { #expect(OwnFiles.aboutTheFiles(q), "\(q)") }
    }

    @Test func aQuestionAboutSomethingInTheFilesOrNotAboutFilesIsNotOne() {
        for q in [
            "When is the boar festival?", "What is the gate code for volunteers?", "Summarize the French revolution",
            "Which river is the longest?", "Quando é o festival?",
        ] { #expect(!OwnFiles.aboutTheFiles(q), "\(q)") }
    }

    private let files = [
        OwnFiles.File(docId: "c-doc0-blood-test-2026", name: "blood-test-2026.txt", parts: 1),
        OwnFiles.File(docId: "c-doc1-car-insurance", name: "car-insurance.pdf", parts: 3),
        OwnFiles.File(docId: "c-doc2-festival-notes", name: "festival-notes.txt", parts: 1),
        OwnFiles.File(docId: "c-doc3-patagonia-trip-plan", name: "patagonia-trip-plan.md", parts: 4),
    ]

    @Test func aFileNamedByItsOwnWords() {
        #expect(OwnFiles.named("What's in my blood test?", files)?.name == "blood-test-2026.txt")
        #expect(OwnFiles.named("When does my car insurance end?", files)?.name == "car-insurance.pdf")
        // A longer name needs two of its words.
        #expect(OwnFiles.named("What did I plan for the Patagonia trip?", files)?.name == "patagonia-trip-plan.md")
        #expect(OwnFiles.named("What do my festival notes say?", files)?.name == "festival-notes.txt")
    }

    @Test func genericWordsHalfANameOrATieNameNoFile() {
        #expect(OwnFiles.named("What do my notes say?", files) == nil)
        #expect(OwnFiles.named("Is a blood donation safe?", files) == nil)
        #expect(OwnFiles.named("Tell me about Patagonia", files) == nil)
        let twins = [OwnFiles.File(docId: "a", name: "car-insurance.pdf", parts: 1), OwnFiles.File(docId: "b", name: "car-insurance-2025.pdf", parts: 1)]
        #expect(OwnFiles.named("my car insurance", twins) == nil)
        #expect(OwnFiles.named("Compare my car insurance with the Patagonia trip plan", files) == nil)
    }

    @Test func thePromptListsTheFilesOnceEachUpToTwenty() {
        #expect(OwnFiles.note([]) == nil)
        let two = [OwnFiles.File(docId: "1", name: "a.txt", parts: 1), OwnFiles.File(docId: "2", name: "b.pdf", parts: 1), OwnFiles.File(docId: "3", name: "a.txt", parts: 1)]
        #expect(OwnFiles.note(two) == "The user's Personal Files (2): a.txt; b.pdf.")
        let many = (1...25).map { OwnFiles.File(docId: "\($0)", name: "f\($0).txt", parts: 1) }
        #expect(OwnFiles.note(many)!.hasSuffix("f20.txt; and 5 more."))
    }

    @Test func theListSitsBeforeTheContextAndPromptsWithoutItDontChange() {
        let c = [Chunk(chunkId: "x-c0", docId: "x", title: "notes", body: "The festival is in May.")]
        #expect(RagPure.assembleChatMessages("When?", c, filesOnly: true) == RagPure.assembleChatMessages("When?", c, filesOnly: true, filesNote: nil))
        let system = RagPure.assembleChatMessages("When?", c, filesOnly: true, filesNote: "The user's Personal Files (1): notes.txt.").first!.content
        #expect(system.contains("The user's Personal Files (1): notes.txt.\n\nContext:\n[1] notes"))
        let plain = RagPure.assemblePrompt("When?", c, filesOnly: true, filesNote: "The user's Personal Files (1): notes.txt.")
        #expect(plain.contains("The user's Personal Files (1): notes.txt.\n\nContext:"))
    }

    private let longMarkdown = "# Patagonia trip\nPlan for March.\n\n## Budget\nAbout 3,000 USD.\n\n## Packing\nTent, stove.\n" + String(repeating: "x", count: 2_100)

    @Test func aLongFileGetsACardWithItsOutlineAShortOneNone() throws {
        let card = try #require(OwnFiles.card(docId: "c-doc0-trip", collectionId: "c", title: "trip", fileName: "trip.md", body: longMarkdown, parts: 4, size: "3 kB"))
        #expect(card.chunkId == "c-doc0-trip-card")
        #expect(card.body.hasPrefix("File: trip.md (Markdown, 3 kB, 4 parts).\nSections: Patagonia trip; Budget; Packing.\nStarts: # Patagonia trip Plan for March."))
        #expect(OwnFiles.card(docId: "c-doc1-n", collectionId: "c", title: "n", fileName: "n.txt", body: "Short.", parts: 1, size: "1 kB") == nil)
    }

    @Test func aCardGoesOnceAPartOfItsFileIsThere() {
        let card = Chunk(chunkId: "d-card", docId: "d", title: "d (about this file)", body: "File: d.md")
        let part = Chunk(chunkId: "d-c1", docId: "d", title: "d (part 2/3)", body: "text")
        let other = Chunk(chunkId: "e-card", docId: "e", title: "e (about this file)", body: "File: e.md")
        #expect(OwnFiles.dropCoveredCards([card, part, other]).map(\.chunkId) == ["d-c1", "e-card"])
    }

    // --- Through the retrieval, on a real SQLite ---

    private let questionVec: [Float] = [1, 0, 0]
    /// Far from any question here: cosine 0 with `questionVec`.
    private let farVec: [Float] = [0, 1, 0]
    private var ownOnly: RetrievalParams { var p = RetrievalParams.default; p.ownOnly = true; return p }

    private func kb(active: Bool = true) throws -> KnowledgeBase {
        let k = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try k.insertChunk(Chunk(chunkId: "wiki-1", docId: "festival", title: "Festival", body: "A festival is an event celebrated by a community."), embedding: questionVec)
        try k.createCollection(id: "c", name: "Setup files", sourceFilename: "festival-notes.txt, blood-test-2026.txt", docCount: 2, chunkCount: 4, sizeBytes: 500, now: 1)
        try k.insertChunk(Chunk(chunkId: "c-doc0-festival-notes-c0", docId: "c-doc0-festival-notes", title: "festival-notes",
            body: "The boar festival is on the third Saturday of May. The gate code for volunteers is 4471.", source: "festival-notes.txt", collectionId: "c"), embedding: farVec)
        try k.insertChunk(Chunk(chunkId: "c-doc1-blood-test-2026-c0", docId: "c-doc1-blood-test-2026", title: "blood-test-2026 (part 1/2)",
            body: "Blood test, March 2026. Iron: 52 ug/dL (low).", source: "blood-test-2026.txt", collectionId: "c"), embedding: farVec)
        try k.insertChunk(Chunk(chunkId: "c-doc1-blood-test-2026-c1", docId: "c-doc1-blood-test-2026", title: "blood-test-2026 (part 2/2)",
            body: "Vitamin D: 18 ng/mL (low). Retest in June.", source: "blood-test-2026.txt", collectionId: "c"), embedding: [0.3, 0.95, 0])
        try k.insertChunk(Chunk(chunkId: "c-doc1-blood-test-2026-card", docId: "c-doc1-blood-test-2026", title: "blood-test-2026 (about this file)",
            body: "File: blood-test-2026.txt (text, 1 kB, 2 parts).\nStarts: Blood test, March 2026.", source: "blood-test-2026.txt", collectionId: "c"), embedding: farVec)
        if !active { try k.setCollectionActive("c", false) }
        return k
    }

    private func retriever(_ kb: KnowledgeBase) -> Retriever {
        let v = questionVec
        return Retriever(kb: kb, packs: { [] }, embed: { _ in v }, lexicon: { PtLexicon.Lexicon([:]) })
    }

    @Test func theSwitchedOnFilesWithTheirPartCountsAndNoCards() throws {
        #expect(try kb().ownFiles() == [
            OwnFiles.File(docId: "c-doc0-festival-notes", name: "festival-notes.txt", parts: 1),
            OwnFiles.File(docId: "c-doc1-blood-test-2026", name: "blood-test-2026.txt", parts: 2),
        ])
        #expect(try kb(active: false).ownFiles() == [])
    }

    @Test func mainPointsOfMyFilesBringsEachFilesOpeningPart() async throws {
        let k = try kb()
        #expect(try k.semanticSearch(questionVec, limit: 4, minSimilarity: 0.55, ownOnly: true).map(\.chunkId) == [])
        let found = try await retriever(k).retrieve("What are the main points of my files?", topK: 4, params: ownOnly).map(\.chunkId)
        #expect(found == ["c-doc0-festival-notes-c0", "c-doc1-blood-test-2026-c0"])
    }

    @Test func aNamedFileIsSearchedAloneAndWithoutTheFloor() async throws {
        let found = try await retriever(kb()).retrieve("What does my blood test say?", topK: 4, params: ownOnly)
        #expect(found.map(\.chunkId) == ["c-doc1-blood-test-2026-c1", "c-doc1-blood-test-2026-c0"])
    }

    @Test func theDefaultStyleKeepsItsSearch() async throws {
        let found = try await retriever(kb()).retrieve("What are the main points of my files?", topK: 4).map(\.chunkId)
        #expect(!found.contains { $0.hasPrefix("c-") }, "\(found)")
    }

    @Test func aCardInTheHitsDoesntTakeItsFilesOpeningInAnOverview() {
        let card = Chunk(chunkId: "d-card", docId: "d", title: "d (about this file)", body: "File: d.md")
        let hitE1 = Chunk(chunkId: "e-c3", docId: "e", title: "e (part 4/9)", body: "x")
        let hitE2 = Chunk(chunkId: "e-c5", docId: "e", title: "e (part 6/9)", body: "y")
        let openings = [
            Chunk(chunkId: "d-c0", docId: "d", title: "d", body: "d starts"), Chunk(chunkId: "e-c0", docId: "e", title: "e", body: "e starts"),
            Chunk(chunkId: "f-c0", docId: "f", title: "f", body: "f starts"),
        ]
        #expect(OwnFiles.withOpenings([card, hitE1, hitE2], openings, hits: 2, limit: 12).map(\.chunkId) == ["e-c3", "e-c5", "d-c0", "f-c0"])
    }

    @Test func aNamedJsonListFileSearchesAllOfItsDocuments() async throws {
        let k = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try k.createCollection(id: "j", name: "recipes", sourceFilename: "recipes.json", docCount: 2, chunkCount: 2, sizeBytes: 100, now: 1)
        try k.insertChunk(Chunk(chunkId: "j-doc0-soup-c0", docId: "j-doc0-soup", title: "Soup", body: "Onion soup.", source: "recipes.json", collectionId: "j"), embedding: farVec)
        try k.insertChunk(Chunk(chunkId: "j-doc1-bread-c0", docId: "j-doc1-bread", title: "Bread", body: "Sourdough bread.", source: "recipes.json", collectionId: "j"), embedding: questionVec)
        let found = try await retriever(k).retrieve("What's in my recipes?", topK: 4, params: ownOnly).map(\.chunkId)
        #expect(found == ["j-doc1-bread-c0", "j-doc0-soup-c0"])
    }

    @Test func anExportLeavesTheCardsOut() throws {
        #expect(try kb().collectionDocs("c").map(\.title) == ["festival-notes", "blood-test-2026 (part 1/2)", "blood-test-2026 (part 2/2)"])
    }

    @Test func switchedOffFilesStayOutOfEveryPersonalFilesPath() async throws {
        let r = retriever(try kb(active: false))
        #expect(try await r.retrieve("What are the main points of my files?", topK: 4, params: ownOnly) == [])
        #expect(try await r.retrieve("What does my blood test say?", topK: 4, params: ownOnly) == [])
    }
}

/// Retrieval's default parameters are today's constants; each mode changes only its own weight (RetrievalParamsTest.kt).
@Suite struct RetrievalParamsTests {
    @Test func theDefaultIsTodaysRetrieval() {
        let d = RetrievalParams.default
        #expect(d.lexicalWeight == 0.5 && d.semanticWeight == 0.5)
        #expect(d.minSemanticSimilarity == RagPure.minSemanticSimilarity && d.answerMinSimilarity == RagPure.answerMinSimilarity)
        #expect(RetrievalParams() == d)
    }

    @Test func modesMapToTheirWeights() {
        var keyword = RetrievalParams.default; keyword.semanticWeight = 0
        var meaning = RetrievalParams.default; meaning.lexicalWeight = 0
        #expect(RetrievalMode.balanced.params() == .default)
        #expect(RetrievalMode.keyword.params() == keyword)
        #expect(RetrievalMode.meaning.params() == meaning)
        let custom = RetrievalParams(lexicalWeight: 0.3, semanticWeight: 0.7, minSemanticSimilarity: 0.6, answerMinSimilarity: 0.75)
        #expect(RetrievalMode.custom.params(custom: custom) == custom)
        #expect(RetrievalMode.custom.params() == .default)
    }

    @Test func aSetWeightedZeroIsLeftOutOfTheFusion() {
        let lex = [Chunk(chunkId: "a", docId: "a", title: "A", body: "x", score: 3.0)]
        let sem = [Chunk(chunkId: "b", docId: "b", title: "B", body: "x", score: 0.9, matchType: .semantic, similarity: 0.9)]
        let k = RetrievalMode.keyword.params()
        #expect(RagPure.fuse(lex, sem, topK: 4, lexicalWeight: k.lexicalWeight, semanticWeight: k.semanticWeight).map(\.chunkId) == ["a"])
        let m = RetrievalMode.meaning.params()
        let got = RagPure.fuse(lex, sem, topK: 4, lexicalWeight: m.lexicalWeight, semanticWeight: m.semanticWeight)
        #expect(got.map(\.chunkId) == ["b"])
        #expect(got.allSatisfy { $0.score.isFinite })
    }
}

/// The Personal Files prompt: the user's files only, quoted as written, and the fixed line instead of general knowledge.
@Suite struct FilesOnlyPromptTests {
    private let chunks = [Chunk(chunkId: "c", docId: "d", title: "budget", body: "Rent: 1,250 EUR.")]

    @Test func theChatTemplatePromptAsksForTheFixedLine() {
        let system = RagPure.assembleChatMessages("What is my rent?", chunks, systemPrompt: "Answer only from the files.", filesOnly: true).first!.content
        #expect(system.contains("say exactly: I couldn't find this in your Personal Files."))
        #expect(system.contains("Quote numbers, names and dates exactly as the file writes them."))
        #expect(!system.contains("general knowledge"))
    }

    @Test func thePlainPromptDoesToo() {
        let prompt = RagPure.assemblePrompt("What is my rent?", chunks, systemPrompt: "Answer only from the files.", filesOnly: true)
        #expect(prompt.contains("I couldn't find this in your Personal Files."))
        #expect(!prompt.contains("general knowledge"))
    }

    @Test func theWarmedPrefixIsTheStartOfTheFilesOnlyPrompt() {
        let (head, plain) = RagPure.answerPromptPrefix(systemPrompt: "Answer only from the files.", withContext: true, filesOnly: true)
        #expect(RagPure.assembleChatMessages("q", chunks, systemPrompt: "Answer only from the files.", filesOnly: true).first!.content.hasPrefix(head))
        #expect(RagPure.assemblePrompt("q", chunks, systemPrompt: "Answer only from the files.", filesOnly: true).hasPrefix(plain))
    }

    @Test func otherStylesKeepTheGeneralKnowledgeFallback() {
        #expect(RagPure.assemblePrompt("q", chunks, systemPrompt: "x").contains("general knowledge"))
    }
}
