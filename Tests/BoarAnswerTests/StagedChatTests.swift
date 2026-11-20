import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// What the chat does with a staged answer: when it takes the path, the style lines, the view the events build, and what is
/// kept with the answer (android ChatViewModel's staged part and StagedAnswerTest's UI tests).
struct StagedChatTests {
    private static let volcano = Chunk(chunkId: "v1", docId: "volcano", title: "Volcano", body: "A volcano forms where magma rises through the crust. Mount Etna is 3,357 m high.", source: "https://example.org/volcano", similarity: 0.8, relevance: 0.5)
    private static let plate = Chunk(chunkId: "p1", docId: "plates", title: "Plate tectonics", body: "Most volcanoes form at plate boundaries where magma rises.")
    private static let off = Chunk(chunkId: "o1", docId: "football", title: "Football", body: "The 1950 World Cup was held in Brazil. Uruguay won it.")
    private static let q = "How do volcanoes form?"

    // MARK: the path

    @Test func theDefaultPathStagesOnlyWhenTheSettingIsOn() {
        #expect(StagedChat.chooses(enabled: true, instant: false, personal: false, deepResearch: false, aboutConversation: false, smallTalk: false))
        #expect(!StagedChat.chooses(enabled: false, instant: false, personal: false, deepResearch: false, aboutConversation: false, smallTalk: false))
    }

    @Test func aToolsAnswerPersonalFilesDeepResearchARecapAndSmallTalkKeepTheirOwnPath() {
        #expect(!StagedChat.chooses(enabled: true, instant: true, personal: false, deepResearch: false, aboutConversation: false, smallTalk: false))
        #expect(!StagedChat.chooses(enabled: true, instant: false, personal: true, deepResearch: false, aboutConversation: false, smallTalk: false))
        #expect(!StagedChat.chooses(enabled: true, instant: false, personal: false, deepResearch: true, aboutConversation: false, smallTalk: false))
        #expect(!StagedChat.chooses(enabled: true, instant: false, personal: false, deepResearch: false, aboutConversation: true, smallTalk: false))
        #expect(!StagedChat.chooses(enabled: true, instant: false, personal: false, deepResearch: false, aboutConversation: false, smallTalk: true))
    }

    @Test func succinctWritesTheIntroAndEveryOtherStyleTheDetails() {
        let det = StagedChat.reminders(style: "detailed", succinct: "S", picked: "D")
        #expect(det.intro == "S" && det.details == "D")
        // A health question (kept in Succinct) or the Succinct style: the intro is the whole answer.
        let short = StagedChat.reminders(style: "succinct", succinct: "S", picked: "S")
        #expect(short.intro == "S" && short.details == nil)
        // A custom prompt has no reminder: no details step either.
        #expect(StagedChat.reminders(style: "custom", succinct: "S", picked: nil).details == nil)
    }

    // MARK: the view the events build

    @Test func theCardsBecomeQuotesAndTheOtherSourcesGoBehindMoreSources() {
        var v = StagedView(withPassages: true)
        let sources = [Self.volcano, Self.plate, Self.off]
        v.apply(.step(.sources), query: Self.q)
        #expect(v.step == .sources)
        v.apply(.cards(sources: sources, keyFacts: [KeyFact(source: 0, sentence: "A volcano forms where magma rises through the crust.")], retrievalMs: 12), query: Self.q)
        #expect(v.keyFacts.count == 1)
        #expect(v.keyFacts[0].title == "Volcano" && v.keyFacts[0].passage == Self.volcano.body && v.keyFacts[0].docId == "volcano")
        // A source outside the quotes: its best sentence, or its first.
        #expect(v.more.map(\.title) == ["Plate tectonics", "Football"])
        #expect(v.more[0].sentence == "Most volcanoes form at plate boundaries where magma rises.")
        #expect(v.more[1].sentence == "The 1950 World Cup was held in Brazil.")
        #expect(v.withPassages)
    }

    @Test func thePassagesTheResearchAddedJoinTheMoreSourcesAndTheNumberCheckAndTheEndComeLast() {
        var v = StagedView()
        v.apply(.cards(sources: [Self.volcano], keyFacts: [], retrievalMs: 1), query: Self.q)
        #expect(v.more.count == 1, "no sentence matched: the source is still one tap away")
        v.apply(.moreSources([Self.plate]), query: Self.q)
        #expect(v.added == 1 && v.more.count == 2)
        v.apply(.checked(unsupported: ["3,357"]), query: Self.q)
        #expect(v.unsupported == ["3,357"])
        v.apply(.step(.check), query: Self.q)
        let done = StagedDone(intro: "i", details: "d", sources: [Self.volcano], keyFacts: [], unsupported: ["3,357"],
                              times: StageTimes(sourcesMs: 5, introFirstMs: 9, detailsFirstMs: 20, totalMs: 30), retrievalMs: 5, metrics: nil, stopped: true)
        v.apply(.done(done), query: Self.q)
        #expect(v.step == nil && v.stopped)
        #expect(v.times == ["sources": 5, "introFirst": 9, "detailsFirst": 20, "total": 30])
    }

    @Test func noSourcesNoStagedAreaNoGap() {
        // adam, Nov 12: nothing to quote and no step line, so nothing is drawn.
        var v = StagedView()
        #expect(!v.hasContent(streaming: false, written: false))
        v.step = .intro
        #expect(!v.hasContent(streaming: true, written: false), "before the first word the chat's wait line says it")
        #expect(v.hasContent(streaming: true, written: true))
        #expect(!v.hasContent(streaming: false, written: true))
        v.step = nil
        v.more = [KeyFactView(query: Self.q, chunk: Self.plate)]
        #expect(v.hasContent(streaming: false, written: true))
    }

    @Test func theListUnderTheAnswerStaysOutWhileStagedShowsTheSources() {
        #expect(StagedChat.listsSources(staged: nil))
        #expect(!StagedChat.listsSources(staged: StagedView()))
    }

    // MARK: kept with the answer

    @Test func theCardSurvivesTheMetaRoundTrip() throws {
        var v = StagedView(withPassages: true)
        v.apply(.cards(sources: [Self.volcano, Self.plate], keyFacts: [KeyFact(source: 0, sentence: "A volcano forms where magma rises through the crust.")], retrievalMs: 1), query: Self.q)
        v.apply(.moreSources([Self.off]), query: Self.q)
        v.apply(.checked(unsupported: ["3,357", "1950"]), query: Self.q)
        v.stopped = true
        let meta = JSONValue.object(["sources": .array([]), "staged": StagedChat.json(v)]).jsonString
        let back = try #require(StagedChat.view(fromMeta: meta, times: ["total": 30]))
        #expect(back.keyFacts == v.keyFacts.map { var k = $0; k.relevance = nil; k.similarity = nil; return k })
        #expect(back.more.map(\.sentence) == v.more.map(\.sentence) && back.more.map(\.docId) == v.more.map(\.docId))
        #expect(back.added == 1 && back.withPassages && back.stopped)
        #expect(back.unsupported == ["3,357", "1950"])
        #expect(back.times == ["total": 30] && back.step == nil)
        // The source keeps its address for the reader; the passage is its body.
        #expect(back.keyFacts[0].source == "https://example.org/volcano")
    }

    @Test func aCheckThatFoundNothingIsKeptApartFromOneThatDidNotRun() throws {
        let clean = StagedView(unsupported: [])
        let ran = try #require(StagedChat.view(fromMeta: JSONValue.object(["staged": StagedChat.json(clean)]).jsonString, times: nil))
        #expect(ran.unsupported == [])
        let skipped = try #require(StagedChat.view(fromMeta: JSONValue.object(["staged": StagedChat.json(StagedView())]).jsonString, times: nil))
        #expect(skipped.unsupported == nil)
        // Defaults hold what Android leaves out of a small card.
        #expect(!skipped.withPassages && !skipped.stopped && skipped.more.isEmpty && skipped.added == 0)
    }

    @Test func anAnswerWrittenTheUsualWayHasNoStagedView() {
        #expect(StagedChat.view(fromMeta: JSONValue.object(["sources": .array([])]).jsonString, times: nil) == nil)
        #expect(StagedChat.view(fromMeta: nil, times: nil) == nil)
        #expect(StagedChat.view(fromMeta: "not json", times: nil) == nil)
    }

    /// Android's own meta (ChatViewModel.stagedJson) opens on this phone: same keys, source and docId empty when none.
    @Test func androidsMetaOpens() throws {
        let meta = """
        {"sources":[],"staged":{"keyFacts":[{"sentence":"S","passage":"P","title":"T","docId":"d","source":""}],"added":2,"unsupported":["12"],"withPassages":true}}
        """
        let v = try #require(StagedChat.view(fromMeta: meta, times: nil))
        #expect(v.keyFacts == [KeyFactView(sentence: "S", passage: "P", title: "T", source: nil, docId: "d")])
        #expect(v.added == 2 && v.unsupported == ["12"] && v.withPassages)
    }

    // MARK: the UI sources (android's tests read ChatScreen.kt and StagedCard.kt; these read the Swift views)

    private static func appSource(_ path: String, file: String = #filePath) throws -> String {
        var root = URL(fileURLWithPath: file)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// X6, Nov 10: with Staged's quotes open, a clip on the answer stopped every tap on its lower half (Copy, rating).
    /// The bubble's shape is drawn (background and border), never clipped.
    @Test func aTallAnswerKeepsItsTapsTheBubblesShapeIsDrawnAndNeverClipped() throws {
        let view = try Self.appSource("App/Features/Chat/AnswerView.swift")
        let bubble = view.components(separatedBy: ".padding(.horizontal, 16)").last?.components(separatedBy: ".environment(\\.openURL").first ?? ""
        #expect(bubble.contains(".background(Color(palette.bgSurface), in: Self.shape)"))
        #expect(!bubble.contains(".clipShape(") && !bubble.contains(".clipped("), "an answer with its quotes open is tall")
    }

    /// The quotes stay open, "+N sources" holds the rest, a tap on a quote opens its source.
    @Test func theCardKeepsTheQuotesOpenShowsMoreSourcesAndOpensASourceOnATap() throws {
        let card = try Self.appSource("App/Features/Chat/StagedCard.swift")
        #expect(card.contains("ChatFolds.shared.binding(") && card.contains("default: true"))
        #expect(card.contains("Fewer sources"))
        #expect(card.contains("onOpen("))
        let answer = try Self.appSource("App/Features/Chat/AnswerView.swift")
        #expect(answer.contains("StagedChat.listsSources(staged: message.staged)"))
        #expect(answer.contains("StagedCard("))
    }
}
