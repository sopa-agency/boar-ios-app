import BoarCore
import BoarRAG
import BoarRouting
import Foundation

/// A key fact as the chat shows it: the sentence, the passage it comes from (opened by a tap) and the source to read
/// (android `KeyFactView`; the source's body is the passage).
public struct KeyFactView: Sendable, Equatable, Hashable {
    public var sentence: String
    public var passage: String
    public var title: String
    public var source: String?
    public var relevance: Double?
    public var similarity: Double?
    public var docId: String?

    public init(sentence: String, passage: String, title: String, source: String? = nil, relevance: Double? = nil, similarity: Double? = nil, docId: String? = nil) {
        self.sentence = sentence; self.passage = passage; self.title = title; self.source = source
        self.relevance = relevance; self.similarity = similarity; self.docId = docId
    }

    /// A source's line for "+N sources": its best sentence for `query` (or its first) and its passage.
    public init(query: String, chunk c: Chunk) {
        self.init(sentence: StagedAnswer.factOf(query, c), passage: c.body, title: c.title, source: c.source, relevance: c.relevance,
                  similarity: c.similarity, docId: c.docId)
    }

    init?(fact f: KeyFact, in chunks: [Chunk]) {
        guard chunks.indices.contains(f.source) else { return nil }
        let c = chunks[f.source]
        self.init(sentence: f.sentence, passage: c.body, title: c.title, source: c.source, relevance: c.relevance, similarity: c.similarity, docId: c.docId)
    }
}

/// What a staged answer shows over its text (android `StagedView`): the step running now, the sentences from the sources
/// that answer (each with its passage), the passages the research step added, the numbers no source has, and when each
/// step happened. Kept with the answer, so a reopened chat shows it too.
public struct StagedView: Sendable, Equatable, Hashable {
    public var step: StagedStep?
    public var keyFacts: [KeyFactView]
    public var added: Int
    public var unsupported: [String]?
    public var times: [String: Double]
    public var stopped: Bool
    /// A health question: each sentence shows with its passage, never alone.
    public var withPassages: Bool
    /// The other sources (not among `keyFacts`, and what the research step added), behind "+N sources" (adam, Nov 10).
    public var more: [KeyFactView]

    public init(
        step: StagedStep? = nil, keyFacts: [KeyFactView] = [], added: Int = 0, unsupported: [String]? = nil, times: [String: Double] = [:],
        stopped: Bool = false, withPassages: Bool = false, more: [KeyFactView] = []
    ) {
        self.step = step; self.keyFacts = keyFacts; self.added = added; self.unsupported = unsupported; self.times = times
        self.stopped = stopped; self.withPassages = withPassages; self.more = more
    }

    /// Takes one engine event into the view, as the chat does (android ChatViewModel's staged collect); `query` is the
    /// question the "+N sources" lines are written for. Pieces and the final text are the chat's own business.
    public mutating func apply(_ event: StagedEvent, query: String) {
        switch event {
        case .step(let s):
            step = s
        case .cards(let sources, let facts, _):
            keyFacts = facts.compactMap { KeyFactView(fact: $0, in: sources) }
            let shown = Set(facts.map(\.source))
            more = sources.enumerated().filter { !shown.contains($0.offset) }.map { KeyFactView(query: query, chunk: $0.element) }
        case .moreSources(let added):
            self.added += added.count
            more += added.map { KeyFactView(query: query, chunk: $0) }
        case .checked(let u):
            unsupported = u
        case .done(let d):
            step = nil
            times = d.times.toMap()
            stopped = d.stopped
        case .piece, .restart:
            break
        }
    }

    /// Whether the area above the answer has anything to show (`StagedShown`); `written`: the answer's text has started.
    public func hasContent(streaming: Bool, written: Bool) -> Bool {
        StagedShown.any(quotes: keyFacts.count, more: more.count, added: added, stepLine: streaming && written && step != nil)
    }
}

/// The chat side of Staged answers that needs no UI: when the chat takes the path, which style lines it gets, and what
/// is kept with the answer (android ChatViewModel, `stagedJson` / `stagedFromMeta`).
public enum StagedChat {
    /// The default path only: not a tool's instant answer, Personal Files, Deep Research, a recap of the chat or small talk.
    public static func chooses(enabled: Bool, instant: Bool, personal: Bool, deepResearch: Bool, aboutConversation: Bool, smallTalk: Bool) -> Bool {
        enabled && !instant && !personal && !deepResearch && !aboutConversation && !smallTalk
    }

    /// One sources design (adam, Nov 12): the list under the answer stays out while Staged shows the sources as quotes and
    /// "+N sources" (android ChatScreen `above`).
    public static func listsSources(staged: StagedView?) -> Bool { staged == nil }

    /// The intro's style line (Succinct's) and the details' (the style picked; none when the answer is kept short).
    public static func reminders(style: String, succinct: String?, picked: String?) -> (intro: String?, details: String?) {
        (succinct, style == "succinct" ? nil : picked)
    }

    // MARK: kept with the answer

    private static func factsJson(_ l: [KeyFactView]) -> JSONValue {
        .array(l.map { k in
            .object([
                "sentence": .string(k.sentence), "passage": .string(k.passage), "title": .string(k.title),
                "docId": .string(k.docId ?? ""), "source": .string(k.source ?? ""),
            ])
        })
    }

    /// The "staged" member of an answer's meta: key facts and check ("+N sources" and the health passages too, so a
    /// reopened chat shows the same card). The times are in the receipt.
    public static func json(_ v: StagedView) -> JSONValue {
        var o: [String: JSONValue] = ["keyFacts": factsJson(v.keyFacts), "added": JSONValue(v.added)]
        if !v.more.isEmpty { o["more"] = factsJson(v.more) }
        if v.withPassages { o["withPassages"] = .bool(true) }
        if let u = v.unsupported { o["unsupported"] = .array(u.map { .string($0) }) }
        if v.stopped { o["stopped"] = .bool(true) }
        return .object(o)
    }

    /// An answer's meta (the whole JSON text) back into its staged view; nil when it has none. `times`: the receipt's stages.
    public static func view(fromMeta meta: String?, times: [String: Double]?) -> StagedView? {
        guard let meta, let root = JSONValue(jsonString: meta), let o = root["staged"], case .object = o else { return nil }
        func facts(_ key: String) -> [KeyFactView] {
            (o[key]?.arrayValue ?? []).map { e in
                func s(_ k: String) -> String { e[k]?.stringValue ?? "" }
                return KeyFactView(sentence: s("sentence"), passage: s("passage"), title: s("title"), source: s("source").isEmpty ? nil : s("source"),
                                   docId: s("docId").isEmpty ? nil : s("docId"))
            }
        }
        return StagedView(
            keyFacts: facts("keyFacts"), added: o["added"]?.doubleValue.map { Int($0) } ?? 0,
            unsupported: o["unsupported"]?.arrayValue?.compactMap(\.stringValue), times: times ?? [:],
            stopped: o["stopped"]?.boolValue ?? false, withPassages: o["withPassages"]?.boolValue ?? false, more: facts("more")
        )
    }
}

extension StagedAnswer {
    /// The engine with BoarRouting's classifier and a `Retriever` (as `AnswerPipeline`'s): `stages`: the labs' search stages;
    /// `annotate`: what the chat adds to each passage found.
    public init(
        retriever: Retriever, params: RetrievalParams = .default, stages: [any SearchStage] = [],
        annotate: @escaping @Sendable (Chunk) -> Chunk = { $0 }, clock: @escaping @Sendable () -> Double = monotonicMillis
    ) {
        self.init(
            retrieve: { q, k in
                try await SearchStages.search(stages, query: q, topK: k) { try await retriever.retrieve($0, topK: $1, params: params) }.map(annotate)
            },
            classify: { Classify.classifyTask($0).value },
            retrievalIrrelevant: { name in TaskType(rawValue: name).map(Classify.isRetrievalIrrelevant) ?? false },
            clock: clock
        )
    }
}
