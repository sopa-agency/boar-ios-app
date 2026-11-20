import BoarCore
import BoarRAG
import Foundation

/// The steps of a staged answer, in the order they run (android StagedAnswer.kt).
public enum StagedStep: String, Sendable, Equatable { case sources, intro, research, details, check }

/// A sentence from a source that answers the question, shown before the model writes: `source` is its index in the sources.
public struct KeyFact: Sendable, Equatable {
    public var source: Int
    public var sentence: String
    public init(source: Int, sentence: String) { self.source = source; self.sentence = sentence }
}

/// When each step happened, in ms from the start of the staged answer (the model load included). nil: it didn't run.
public struct StageTimes: Sendable, Equatable {
    public var sourcesMs: Double?
    public var modelReadyMs: Double?
    public var introFirstMs: Double?
    public var introDoneMs: Double?
    public var researchMs: Double?
    public var detailsFirstMs: Double?
    public var totalMs: Double?

    public init(
        sourcesMs: Double? = nil, modelReadyMs: Double? = nil, introFirstMs: Double? = nil, introDoneMs: Double? = nil,
        researchMs: Double? = nil, detailsFirstMs: Double? = nil, totalMs: Double? = nil
    ) {
        self.sourcesMs = sourcesMs; self.modelReadyMs = modelReadyMs; self.introFirstMs = introFirstMs
        self.introDoneMs = introDoneMs; self.researchMs = researchMs; self.detailsFirstMs = detailsFirstMs; self.totalMs = totalMs
    }

    /// Only the steps that ran, under Android's keys.
    public func toMap() -> [String: Double] {
        var m: [String: Double] = [:]
        if let v = sourcesMs { m["sources"] = v }
        if let v = modelReadyMs { m["model"] = v }
        if let v = introFirstMs { m["introFirst"] = v }
        if let v = introDoneMs { m["introDone"] = v }
        if let v = researchMs { m["research"] = v }
        if let v = detailsFirstMs { m["detailsFirst"] = v }
        if let v = totalMs { m["total"] = v }
        return m
    }
}

public struct StagedRequest: Sendable {
    public var query: String
    public var systemPrompt: String?
    /// The short intro's style line (Succinct's).
    public var introReminder: String?
    /// The details' style line (the picked style's); nil: the intro is the whole answer (a health question kept short).
    public var detailsReminder: String?
    public var maxTokens: Int
    public var history: ConversationHistory?
    public var enableThinking: Bool

    public init(
        query: String, systemPrompt: String?, introReminder: String?, detailsReminder: String?, maxTokens: Int,
        history: ConversationHistory? = nil, enableThinking: Bool = false
    ) {
        self.query = query; self.systemPrompt = systemPrompt; self.introReminder = introReminder
        self.detailsReminder = detailsReminder; self.maxTokens = maxTokens; self.history = history; self.enableThinking = enableThinking
    }
}

/// How a staged answer ended (android `StagedEvent.Done`).
public struct StagedDone: Sendable {
    public var intro: String
    public var details: String
    public var sources: [Chunk]
    public var keyFacts: [KeyFact]
    /// Numbers no source has; nil when the check didn't run.
    public var unsupported: [String]?
    public var times: StageTimes
    public var retrievalMs: Double?
    /// The details' generation (the intro's when there were no details).
    public var metrics: GenerationMetrics?
    /// The model couldn't be loaded: the cards are all there is.
    public var noModel: Bool
    /// Stop was pressed: what was shown so far is the answer.
    public var stopped: Bool

    public init(
        intro: String, details: String, sources: [Chunk], keyFacts: [KeyFact], unsupported: [String]?, times: StageTimes,
        retrievalMs: Double?, metrics: GenerationMetrics?, noModel: Bool = false, stopped: Bool = false
    ) {
        self.intro = intro; self.details = details; self.sources = sources; self.keyFacts = keyFacts
        self.unsupported = unsupported; self.times = times; self.retrievalMs = retrievalMs; self.metrics = metrics
        self.noModel = noModel; self.stopped = stopped
    }

    /// The answer as saved: the intro, then the details.
    public var text: String { StagedAnswer.join(intro, details) }
}

public enum StagedEvent: Sendable {
    case step(StagedStep)
    /// What the search found, before any model runs: the passages ([1]..[n]) and the sentences that answer best.
    case cards(sources: [Chunk], keyFacts: [KeyFact], retrievalMs: Double)
    case piece(step: StagedStep, text: String)
    /// The intro so far is dropped and written again as the whole answer (a model that reasons first spent the short
    /// budget on its reasoning): clear what's shown (android 10a42933).
    case restart
    /// Passages the search between the steps added, numbered after the first ones.
    case moreSources([Chunk])
    /// Numbers in the answer that no source (nor the question) has.
    case checked(unsupported: [String])
    case done(StagedDone)
}

/// Whether Staged's area above an answer has anything to show (adam, Nov 12: "no source, no empty block").
public enum StagedShown {
    public static func any(quotes: Int, more: Int, added: Int, stepLine: Bool) -> Bool { quotes > 0 || more > 0 || added > 0 || stepLine }
}

/// Boar Staged answers: the answer arrives in steps, each one useful on its own, and Stop keeps whatever is on screen.
/// SOURCES: search and the sentences that answer, before the model is loaded. INTRO: two or three sentences. RESEARCH: a
/// second search with what the intro said, for passages the first one missed (no model). DETAILS: the same model adds what
/// the intro left out, reading every passage. CHECK: each number written must be in a source (in code, no second model).
/// One model at a time: the search runs between the generations, never during one. Port of android StagedAnswer.kt.
public struct StagedAnswer: Sendable {
    private let retrieve: @Sendable (String, Int) async throws -> [Chunk]
    private let classify: @Sendable (String) -> String
    private let retrievalIrrelevant: @Sendable (String) -> Bool
    private let clock: @Sendable () -> Double

    /// - retrieve: `Retriever.retrieve(query, topK:)`.
    /// - classify: classifyTask's name for a query; retrievalIrrelevant: isRetrievalIrrelevant for a task type name.
    public init(
        retrieve: @escaping @Sendable (String, Int) async throws -> [Chunk],
        classify: @escaping @Sendable (String) -> String,
        retrievalIrrelevant: @escaping @Sendable (String) -> Bool,
        clock: @escaping @Sendable () -> Double = monotonicMillis
    ) {
        self.retrieve = retrieve; self.classify = classify; self.retrievalIrrelevant = retrievalIrrelevant; self.clock = clock
    }

    /// Streams the steps, the pieces and the final `.done`. `load` runs after the cards, so they show while the model loads;
    /// nil from it leaves the cards (`noModel`). Failures (retrieval, the model) are thrown from the stream. Dropping the
    /// stream stops the generation in flight.
    public func answer(
        _ req: StagedRequest, load: @escaping @Sendable () async -> (any TextModelSession)?, shouldStop: @escaping @Sendable () -> Bool
    ) -> AsyncThrowingStream<StagedEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(req, load: load, shouldStop: shouldStop) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ req: StagedRequest, load: @Sendable () async -> (any TextModelSession)?, shouldStop: @Sendable () -> Bool,
        emit: @Sendable (StagedEvent) -> Void
    ) async throws {
        let t0 = clock()
        func now() -> Double { clock() - t0 }
        var times = StageTimes()
        let task = classify(req.query)
        var sources: [Chunk] = []
        var keyFacts: [KeyFact] = []
        var retrievalMs: Double?
        if !retrievalIrrelevant(task) {
            emit(.step(.sources))
            let found = try await FollowUp.search(req.query, history: req.history, textOf: { (c: Chunk) in "\(c.title) \(c.body)" }) {
                try await retrieve($0, AnswerPipeline.answerContextChunks)
            }
            sources = Compress.forAnswer(found.searchedFor, found.chunks, taskType: task).chunks
            keyFacts = Self.keyFacts(found.searchedFor, sources)
            let ms = now()
            retrievalMs = ms
            times.sourcesMs = ms
            emit(.cards(sources: sources, keyFacts: keyFacts, retrievalMs: ms))
        }
        func done(_ intro: String, _ details: String, _ metrics: GenerationMetrics?, _ unsupported: [String]?, noModel: Bool = false) -> StagedEvent {
            var t = times
            t.totalMs = now()
            return .done(StagedDone(
                intro: intro, details: details, sources: sources, keyFacts: keyFacts, unsupported: unsupported, times: t,
                retrievalMs: retrievalMs, metrics: metrics, noModel: noModel, stopped: shouldStop()
            ))
        }
        if shouldStop() { emit(done("", "", nil, nil)); return }

        emit(.step(.intro))
        let loaded = await load()
        times.modelReadyMs = now()
        guard let session = loaded else { emit(done("", "", nil, nil, noModel: true)); return }
        var intro = ""
        var metrics = try await generate(
            session, Self.prompt(session, req.query, sources, req.systemPrompt, req.history, req.introReminder),
            maxTokens: min(Self.introTokens, req.maxTokens), thinking: req.enableThinking
        ) { piece in
            if times.introFirstMs == nil { times.introFirstMs = now() }
            intro += piece
            emit(.piece(step: .intro, text: piece))
        }
        times.introDoneMs = now()
        var introText = AnswerText.stripThinking(intro).kotlinTrim()
        var fullAnswer = false
        // Only reasoning came back (LFM2.5 spent the 160 tokens inside <think>, X6, Nov 10): write it again as the whole
        // answer, the normal answer's prompt and budget, with no details step after it.
        if introText.isEmpty && intro.contains(where: { !$0.isWhitespace }) && !shouldStop() {
            emit(.restart)
            intro = ""
            fullAnswer = true
            metrics = try await generate(
                session, Self.prompt(session, req.query, sources, req.systemPrompt, req.history, req.detailsReminder ?? req.introReminder),
                maxTokens: req.maxTokens, thinking: req.enableThinking
            ) { piece in
                intro += piece
                emit(.piece(step: .intro, text: piece))
            }
            introText = AnswerText.stripThinking(intro).kotlinTrim()
        }

        var details = ""
        if let detailsReminder = req.detailsReminder, !introText.isEmpty, !fullAnswer, !shouldStop() {
            if !sources.isEmpty {
                emit(.step(.research))
                let added = try await moreSources(req.query, introText, sources)
                times.researchMs = now()
                if !added.isEmpty {
                    sources += added
                    emit(.moreSources(added))
                }
            }
            if !shouldStop() {
                emit(.step(.details))
                // The intro stays in the conversation as the model's own turn, so the details go on from it.
                let history = ConversationHistory(
                    summary: req.history?.summary,
                    turns: (req.history?.turns ?? []) + [ConversationTurn(role: "user", text: req.query), ConversationTurn(role: "assistant", text: introText)]
                )
                metrics = try await generate(
                    session, Self.prompt(session, Self.detailsAsk, sources, req.systemPrompt, history, detailsReminder, languageOf: req.query),
                    maxTokens: req.maxTokens, thinking: req.enableThinking
                ) { piece in
                    if times.detailsFirstMs == nil { times.detailsFirstMs = now() }
                    details += piece
                    emit(.piece(step: .details, text: piece))
                }
            }
        }

        let detailsText = AnswerText.stripThinking(details).kotlinTrim()
        var unsupported: [String]?
        let written = [introText, detailsText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !written.isEmpty && !sources.isEmpty {
            emit(.step(.check))
            let found = Self.unsupportedNumbers(written, sources.map { "\($0.title)\n\($0.body)" } + [req.query])
            unsupported = found
            emit(.checked(unsupported: found))
        }
        emit(done(introText, detailsText, metrics, unsupported))
    }

    private func generate(
        _ session: any TextModelSession, _ p: (input: GenerationRequest.Input, stops: [String]), maxTokens: Int, thinking: Bool,
        onPiece: (String) async -> Void
    ) async throws -> GenerationMetrics? {
        var metrics: GenerationMetrics?
        let request = GenerationRequest(input: p.input, sampling: Sampling(nPredict: maxTokens, temperature: 0.7, stops: p.stops), enableThinking: thinking)
        for try await e in session.generate(request) {
            switch e {
            case .piece(let text): await onPiece(text)
            case .done(let m): metrics = m
            }
        }
        // A dropped stream ends the generation quietly: don't go on to the next step.
        try Task.checkCancellation()
        return metrics
    }

    /// `languageOf`: the question that sets the answer's language (the details step asks `detailsAsk`, in English).
    private static func prompt(
        _ session: any TextModelSession, _ query: String, _ sources: [Chunk], _ systemPrompt: String?, _ history: ConversationHistory?,
        _ reminder: String?, languageOf: String? = nil
    ) -> (input: GenerationRequest.Input, stops: [String]) {
        if session.capabilities.hasChatTemplate {
            let messages = RagPure.assembleChatMessages(
                query, sources, systemPrompt: systemPrompt, history: history, styleReminder: reminder, languageOf: languageOf
            ).map { ChatMessage(role: $0.role, content: $0.content) }
            return (.messages(messages), [])
        }
        return (.prompt(RagPure.assemblePrompt(query, sources, systemPrompt: systemPrompt, history: history, styleReminder: reminder, languageOf: languageOf)), AnswerPipeline.defaultStopSequences)
    }

    /// Searched again with the question and the intro: passages from articles not already read, the answering sentences only.
    private func moreSources(_ query: String, _ intro: String, _ have: [Chunk]) async throws -> [Chunk] {
        let seen = Set(have.map(\.docId))
        let fresh = try await retrieve("\(query) \(intro)", AnswerPipeline.answerContextChunks).filter { !seen.contains($0.docId) }
        if fresh.isEmpty { return [] }
        return Array(Compress.forAnswer(query, fresh, taskType: classify(query)).chunks.prefix(Self.moreSourcesMax))
    }

    // MARK: Companion (android `StagedAnswer.Companion`)

    /// The intro's cap: Succinct's two or three sentences with room to finish one.
    public static let introTokens = 160
    /// Passages the research step may add.
    public static let moreSourcesMax = 2
    public static let keyFactsMax = 3
    private static let keyFactChars = 280
    /// The details' turn: the intro above is the model's own.
    public static let detailsAsk = "Now give the details your short answer above left out, from the context, citing [n]. Don't repeat the short answer."

    /// The answer as shown and saved: the intro, then the details on their own paragraph. The chat calls it while the pieces
    /// stream in, so the text reads as it will once done (a break added per piece put one token per line, X6).
    public static func join(_ intro: String, _ details: String) -> String {
        [intro.kotlinTrim(), details.kotlinTrim()].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func cut(_ t: String) -> String { t.u16 > keyFactChars ? t.u16Take(keyFactChars).kotlinTrim() + "\u{2026}" : t }

    /// One source's line for the "+N sources" list (adam, Nov 10): its best answering sentence, or its first sentence when
    /// none holds a word of the question; cut like the key facts.
    public static func factOf(_ query: String, _ source: Chunk) -> String {
        var best: Compress.ScoredSentence?
        for s in Compress.scoreSentences(query, [source]) where s.score > 0 && (best == nil || s.score > best!.score) { best = s }
        let text = (best?.text ?? Compress.splitSentences(source.body).first ?? source.body).kotlinTrim()
        return cut(text)
    }

    /// The best answering sentence of each source, best first, at most `keyFactsMax`; none when no word of the question is in it.
    public static func keyFacts(_ query: String, _ sources: [Chunk]) -> [KeyFact] {
        var order: [Int] = []
        var bestOf: [Int: Compress.ScoredSentence] = [:]
        for s in Compress.scoreSentences(query, sources) where s.score > 0 {
            if let b = bestOf[s.chunkIndex] {
                if s.score > b.score { bestOf[s.chunkIndex] = s }
            } else {
                order.append(s.chunkIndex); bestOf[s.chunkIndex] = s
            }
        }
        // Kotlin's sortedByDescending is stable: ties keep the sources' order.
        let ranked = order.enumerated().sorted { a, b in
            let (x, y) = (bestOf[a.element]!.score, bestOf[b.element]!.score)
            return x != y ? x > y : a.offset < b.offset
        }
        return ranked.prefix(keyFactsMax).map { KeyFact(source: $0.element, sentence: cut(bestOf[$0.element]!.text.kotlinTrim())) }
    }

    // Java regex semantics (Kotlin `Regex`): `\d` is ASCII and `\s` the six ASCII blanks, `\p{L}` Unicode.
    private static let ws = "[ \\t\\n\\x0B\\f\\r]"
    private static let number = Rx("[0-9][0-9,.]*[0-9]|[0-9]")
    private static let citation = Rx("\\[[0-9]+(?:\(ws)*[,\u{2013}\\-]\(ws)*[0-9]+)*\\]")
    private static let listMark = Rx("(?m)^\(ws)*[0-9]+[.)]\(ws)")
    /// A scale word right after a number: "146 million", "1,5 bilhão", "200 mil".
    private static let scale = Rx(
        "^\(ws)*(thousand|million|millions|billion|billions|trillion|mil|milhão|milhao|milhões|milhoes|bilhão|bilhao|bilhões|bilhoes|trilhão|trilhões)(?![\\p{L}])",
        ignoreCase: true
    )
    private static let groupedComma = Rx("\\A[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?\\z")
    private static let groupedDot = Rx("\\A[0-9]{1,3}(\\.[0-9]{3})+(,[0-9]+)?\\z")
    private static let decimalComma = Rx("\\A[0-9]+,[0-9]{1,2}\\z")

    private static func trimDotComma(_ s: String) -> String {
        var u = Substring(s)
        while let l = u.last, l == "." || l == "," { u.removeLast() }
        return String(u)
    }

    /// Strictly Java's `toDoubleOrNull` for what the number regex yields (digits, commas, dots).
    private static func double(_ s: String) -> Double? { s.contains(",") ? nil : Double(s) }

    /// The numbers in `text` that none of `evidence` has (Commonplace's check, done in code): "1,200" and "1200" match.
    /// Citations, list numbers and numbers up to 10 are left out (counts like "3 steps" are the model's own wording).
    public static func unsupportedNumbers(_ text: String, _ evidence: [String]) -> [String] {
        func norm(_ n: String) -> String { trimDotComma(n).replacingOccurrences(of: ",", with: "") }
        var known = Set<String>()
        var values: [Double] = []
        for e in evidence {
            for m in number.matches(in: e) {
                let v = (e as NSString).substring(with: m.range)
                known.insert(norm(v))
                if let d = valueOf(trimDotComma(v)) { values.append(d) }
            }
        }
        let body = listMark.replace(citation.replace(text, with: " "), with: " ")
        let ns = body as NSString
        var out: [String] = []
        for m in number.matches(in: body) {
            let value = ns.substring(with: m.range)
            let after = ns.substring(from: m.range.location + m.range.length)
            // Small counts are the model's own wording ("3 steps"), unless a scale word makes them big ("1.5 million").
            let big = double(norm(value)).map { $0 > 10 } ?? true
            guard big || scale.containsMatch(in: after) else { continue }
            guard !known.contains(norm(value)), !scaledMatch(value, after, values) else { continue }
            let shown = trimDotComma(value)
            if !out.contains(shown) { out.append(shown) }
        }
        return out
    }

    /// "146 million" against a source's 146,119,928 (t9 0400 item 3: flagged on the F3): a figure written with a scale word is
    /// backed when some source number, at that scale, rounds to it at the digits stated ("146", "1.5", "1,5"). `after`: the
    /// text right after the number.
    private static func scaledMatch(_ value: String, _ after: String, _ values: [Double]) -> Bool {
        guard let m = scale.firstMatch(in: after), let w = m.group(1, in: after) else { return false }
        let word = w.lowercased()
        let factor: Double =
            word == "thousand" || word == "mil" ? 1e3 : word.hasPrefix("mil") ? 1e6 : word.hasPrefix("bil") ? 1e9 : 1e12
        let raw = trimDotComma(value)
        // The scale word says the mark (validator R-B6: "1.234 million" was read 1,234 million, a 1000x accept): English
        // "million" takes a decimal dot ("1.234 million", "1,500 million" in thousands), Portuguese "milhões" a decimal
        // comma ("1,234 milhões", "1.500 milhões" in thousands).
        let ptWord = !["thousand", "million", "millions", "billion", "billions", "trillion"].contains(word)
        let mark: Character = ptWord ? "," : "."
        let single = raw.filter { $0 == "." || $0 == "," }.count == 1
        let dec = single && raw.contains(mark)
        let digits = dec ? raw.replacingOccurrences(of: ptWord ? "." : ",", with: "").replacingOccurrences(of: ",", with: ".")
            : raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
        guard let stated = double(digits) else { return false }
        let places = dec ? raw.count - raw.distance(from: raw.startIndex, to: raw.firstIndex(of: mark)!) - 1 : 0
        let f = pow(10.0, Double(places))
        // Math.round: half up.
        return values.contains { ($0 / factor * f + 0.5).rounded(.down) / f == stated }
    }

    /// A written number's value: "146,119,928", "146.119.928" (pt), "8,515,767.5", "3,5"; nil when it can't tell.
    private static func valueOf(_ n: String) -> Double? {
        if groupedComma.containsMatch(in: n) { return double(n.replacingOccurrences(of: ",", with: "")) }
        if groupedDot.containsMatch(in: n) { return double(n.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) }
        if decimalComma.containsMatch(in: n) { return double(n.replacingOccurrences(of: ",", with: ".")) }
        return double(n)
    }
}
