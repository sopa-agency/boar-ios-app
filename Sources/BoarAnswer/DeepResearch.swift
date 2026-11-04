import BoarCore
import BoarRAG
import BoarRouting
import Foundation

public enum ResearchStage: String, Sendable, Equatable { case decomposing, researching, synthesizing }

public struct ResearchProgress: Sendable, Equatable {
    public var stage: ResearchStage
    public var subQuestionIndex: Int?
    public var subQuestionCount: Int?
    public var subQuestion: String?
    public var answering: Bool

    public init(stage: ResearchStage, subQuestionIndex: Int? = nil, subQuestionCount: Int? = nil, subQuestion: String? = nil, answering: Bool = false) {
        self.stage = stage; self.subQuestionIndex = subQuestionIndex; self.subQuestionCount = subQuestionCount
        self.subQuestion = subQuestion; self.answering = answering
    }
}

public struct ResearchResult: Sendable {
    public var answer: String
    public var subQuestions: [String]
    /// Global numbered sources: "[n]" in the answer is `citations[n - 1]`.
    public var citations: [Chunk]
    /// The same sources as retrieved, before compression.
    public var fullCitations: [Chunk]
    /// A stage hit its time limit and was cut off.
    public var timedOut: Bool
    /// Written from the previous answer alone ("summary", "continue"): its sources are the previous answer's.
    public var fromPreviousAnswer: Bool
    /// The write-up's own numbers (context read, speed), for the answer's receipt; nil when nothing was written.
    public var metrics: GenerationMetrics?

    public init(
        answer: String, subQuestions: [String], citations: [Chunk], fullCitations: [Chunk], timedOut: Bool = false,
        fromPreviousAnswer: Bool = false, metrics: GenerationMetrics? = nil
    ) {
        self.answer = answer; self.subQuestions = subQuestions; self.citations = citations
        self.fullCitations = fullCitations; self.timedOut = timedOut
        self.fromPreviousAnswer = fromPreviousAnswer; self.metrics = metrics
    }
}

/// Deep Research (port of src/services/orchestrator.ts): one model, several passes. Decompose the question into 2–3
/// sub-questions, research each over its own retrieval (compressed, off-topic sources dropped, numbered globally), then
/// synthesize one answer. Same prompts as the TS (golden test with a recording generator).
public struct DeepResearch: Sendable {
    /// Per-sub-question context budget: three of these plus the synthesis still prefill fast.
    public static let subQuestionContextTokens = 600
    /// Characters of the previous answer a follow-up's rewrite and synthesis see (its opening carries the topic).
    public static let previousAnswerChars = 800

    private let generator: any StageGenerator
    private let retrieve: @Sendable (String, Int) async throws -> [Chunk]
    private let timeoutFor: @Sendable (Int) -> Int64?
    private let writeUpTimeoutFor: @Sendable (Int) -> Int64?

    /// - retrieve: `Retriever.retrieve(query, topK:)`.
    /// - timeoutFor: time limit for a stage of n tokens (`EngineTweaks.stageTimeoutMs`, the user's setting); nil = none.
    /// - writeUpTimeoutFor: the final write-up's limit (`EngineTweaks.writeUpTimeoutMs`: none on Auto, since Stop ends it); defaults to `timeoutFor`.
    public init(
        generator: any StageGenerator,
        retrieve: @escaping @Sendable (String, Int) async throws -> [Chunk],
        timeoutFor: @escaping @Sendable (Int) -> Int64? = { EngineTweaks().stageTimeoutMs(nPredict: $0) },
        writeUpTimeoutFor: (@Sendable (Int) -> Int64?)? = nil
    ) {
        self.generator = generator; self.retrieve = retrieve; self.timeoutFor = timeoutFor
        self.writeUpTimeoutFor = writeUpTimeoutFor ?? timeoutFor
    }

    /// Deep Research with a `Retriever` and the user's engine tweaks for the time limits.
    public init(generator: any StageGenerator, retriever: Retriever, tweaks: EngineTweaks = EngineTweaks()) {
        self.init(
            generator: generator, retrieve: { q, k in try await retriever.retrieve(q, topK: k) },
            timeoutFor: { tweaks.stageTimeoutMs(nPredict: $0) }, writeUpTimeoutFor: { tweaks.writeUpTimeoutMs(nPredict: $0) }
        )
    }

    /// The earlier question and the answer to it, for a follow-up.
    public struct Exchange: Sendable, Equatable {
        public var question: String
        public var answer: String
        public init(question: String, answer: String) { self.question = question; self.answer = answer }
    }

    /// What the stages of one run share: whether one timed out, and the latest stage's numbers (after the write-up, the
    /// write-up's).
    struct RunState {
        var timedOut = false
        var metrics: GenerationMetrics?
    }

    // MARK: Run

    public func run(
        _ query: String,
        systemPrompt: String?,
        history: ConversationHistory?,
        maxTokens: Int,
        onProgress: @Sendable (ResearchProgress) -> Void = { _ in },
        onToken: @escaping @Sendable (String) -> Void = { _ in },
        shouldStop: @Sendable () -> Bool = { false },
        retrieveK: Int = 6,
        answerLanguage: String? = nil,
        onSources: @Sendable ([Chunk]) -> Void = { _ in },
        onPartialSources: @Sendable ([Chunk], Int, Int) -> Void = { _, _, _ in },
        previousAnswer: String? = nil,
        conversation: [Exchange] = []
    ) async throws -> ResearchResult {
        var state = RunState()
        // "Summarize our conversation in 3 bullet points" covered only the last two topics of nine (X6, Oct 16). Earlier
        // recaps and summaries are left out: read back, the next recap copied them instead of the topics (X6, Oct 16).
        let topics = conversation.filter { !Self.isConversationRecap($0.question) && !Self.isSummaryFollowUp($0.question) }
        if !topics.isEmpty && Self.isConversationRecap(query) {
            onProgress(ResearchProgress(stage: .synthesizing))
            let answer = try await recap(query, topics, history?.summary, systemPrompt, maxTokens, onToken, answerLanguage, &state)
            return ResearchResult(answer: answer, subQuestions: [], citations: [], fullCitations: [], timedOut: state.timedOut, metrics: state.metrics)
        }
        onProgress(ResearchProgress(stage: .decomposing))
        // A follow-up ("conclusion", "continue", "and its side effects?") is split, searched and judged as a standalone
        // question; split as written it searched for "conclusion" and refused (X6, Oct 13).
        let meta = Self.isMetaFollowUp(query)
        // A meta follow-up refers to the last answer whatever its wording ("TL;DR" reads as a name to FollowUp's rule).
        let exchange = meta ? Self.lastAnswered(query, history) : Self.lastExchange(query, history)
        let asked = query
        // "summary", "conclusion", "TL;DR", "continue": the answer is already on screen, so write from it instead of
        // researching again (~5 min of splitting and searching for a summary, X6, Oct 14).
        if let exchange, meta {
            onProgress(ResearchProgress(stage: .synthesizing))
            let answer = try await fromPrevious(query, exchange, previousAnswer, systemPrompt, maxTokens, onToken, answerLanguage, &state)
            return ResearchResult(
                answer: answer, subQuestions: [], citations: [], fullCitations: [], timedOut: state.timedOut, fromPreviousAnswer: true, metrics: state.metrics
            )
        }
        var query = query
        if let exchange { query = try await standalone(query, exchange, &state) }
        // Stop cancels only the generation running at that moment: the next stage would start a new one.
        if shouldStop() { return ResearchResult(answer: "", subQuestions: [], citations: [], fullCitations: [], timedOut: state.timedOut) }
        let subQuestions = try await decompose(query, &state)
        var subResults: [(question: String, answer: String)] = []
        var perQuestion: [[Chunk]] = []
        var all: [Chunk] = []
        var fullById: [String: Chunk] = [:]
        func full() -> [Chunk] { all.map { fullById[$0.chunkId] ?? $0 } }
        for (i, sub) in subQuestions.enumerated() {
            if shouldStop() { return ResearchResult(answer: "", subQuestions: subQuestions, citations: all, fullCitations: full(), timedOut: state.timedOut) }
            onProgress(ResearchProgress(stage: .researching, subQuestionIndex: i, subQuestionCount: subQuestions.count, subQuestion: sub))
            let retrieved = try await retrieve(sub, retrieveK)
            for c in retrieved where fullById[c.chunkId] == nil { fullById[c.chunkId] = c }
            let compressed = ResearchSupport.compressContext(sub, retrieved, tokenBudget: Self.subQuestionContextTokens).chunks
            // A source off the topic of this sub-question, or of the whole question, is not read, numbered or shown.
            let chunks = compressed.filter { ResearchSupport.context.onTopic(query: sub, $0) || ResearchSupport.context.onTopic(query: query, $0) }
            perQuestion.append(chunks)
            let merged = ResearchContext.mergeSources(perQuestion)
            let grew = merged.sources.count > all.count
            all = merged.sources
            if grew { onPartialSources(all, i, subQuestions.count) }
            onProgress(ResearchProgress(stage: .researching, subQuestionIndex: i, subQuestionCount: subQuestions.count, subQuestion: sub, answering: true))
            let a = try await researchSubQuestion(sub, chunks, merged.indexMaps[i], systemPrompt, history, &state)
            subResults.append((sub, a))
        }
        onSources(all)
        if shouldStop() { return ResearchResult(answer: "", subQuestions: subQuestions, citations: all, fullCitations: full(), timedOut: state.timedOut) }
        onProgress(ResearchProgress(stage: .synthesizing))
        let answer = try await synthesize(
            query, subResults, systemPrompt, maxTokens, onToken, answerLanguage, exchange.map { ($0, asked) }, &state
        )
        return ResearchResult(answer: answer, subQuestions: subQuestions, citations: all, fullCitations: full(), timedOut: state.timedOut, metrics: state.metrics)
    }

    // MARK: Stages

    private func stage(
        _ system: String, _ user: String, _ nPredict: Int, _ temperature: Float, _ onToken: (@Sendable (String) -> Void)?,
        timeoutMs: Int64?, _ state: inout RunState
    ) async throws -> String {
        let r = try await generator.generate(system: system, user: user, nPredict: nPredict, temperature: temperature, timeoutMs: timeoutMs, onToken: onToken)
        if r.timedOut { state.timedOut = true }
        state.metrics = r.metrics
        return r.text
    }

    private func decompose(_ query: String, _ state: inout RunState) async throws -> [String] {
        let prompt = "Break this research question into 2-3 focused sub-questions that "
            + "together cover it well (e.g. technical analysis, counter-arguments, "
            + "practical implications — whichever fit this question). One per line, "
            + "no numbering, no extra commentary.\n\nQuestion: \(query)\n\nSub-questions:"
        let text = try await stage("You plan research.", prompt, 150, 0.4, nil, timeoutMs: timeoutFor(150), &state)
        return Self.parseSubQuestions(text, query)
    }

    private static func languageLine(_ answerLanguage: String?) -> String {
        let lang = answerLanguage.map { JsString.trim($0) } ?? ""
        return lang.isEmpty ? "" : "\n\n(\(lang))"
    }

    /// A meta follow-up written from the previous answer alone: one generation, no splitting, no search.
    private func fromPrevious(
        _ asked: String, _ exchange: Exchange, _ previousAnswer: String?, _ systemPrompt: String?, _ maxTokens: Int,
        _ onToken: @escaping @Sendable (String) -> Void, _ answerLanguage: String?, _ state: inout RunState
    ) async throws -> String {
        let full = previousAnswer.map { JsString.trim($0) } ?? ""
        let answer = full.isEmpty ? exchange.answer
            : (full.u16 > Self.fullPreviousAnswerChars ? full.u16Take(Self.fullPreviousAnswerChars) + "…" : full)
        let system = "\(Self.instructionOf(systemPrompt)) The user asks something about your previous answer. Work only from that answer: "
            + "keep its source numbers exactly as written, like [3], and add no new facts, numbers or sources. "
            + "Don't mention these instructions or call it \"the previous answer\"."
        return try await stage(
            system, "Previous question: \(exchange.question)\n\nPrevious answer:\n\(answer)\n\nFollow-up: \(asked)\(Self.languageLine(answerLanguage))",
            maxTokens, 0.6, onToken, timeoutMs: writeUpTimeoutFor(maxTokens), &state
        )
    }

    /// A summary of the whole conversation from each exchange's opening: one generation, no search.
    private func recap(
        _ asked: String, _ conversation: [Exchange], _ earlierSummary: String?, _ systemPrompt: String?, _ maxTokens: Int,
        _ onToken: @escaping @Sendable (String) -> Void, _ answerLanguage: String?, _ state: inout RunState
    ) async throws -> String {
        let turns = conversation.suffix(Self.recapExchanges).enumerated().map { i, e in
            let t = JsString.trim(Self.citation.replace(e.answer, with: ""))
            let a = t.u16 > Self.recapAnswerChars ? t.u16Take(Self.recapAnswerChars) + "…" : t
            return "\(i + 1). Question: \(e.question)\nAnswer: \(a)"
        }.joined(separator: "\n\n")
        // Past 12 exchanges the oldest are left out; the chat's running summary (autoSummarize) stands in for them.
        var earlier = ""
        if conversation.count > Self.recapExchanges {
            let s = earlierSummary.map { JsString.trim(Self.citation.replace($0, with: "")) } ?? ""
            earlier = s.isEmpty ? "(\(conversation.count - Self.recapExchanges) earlier exchanges are not shown.)\n\n" : "Summary of the earlier conversation:\n\(s)\n\n"
        }
        let system = "\(Self.instructionOf(systemPrompt)) The user asks about the conversation so far. Cover every topic it went "
            + "through, in order, in the form the user asks for (a number of bullets or sentences, if given); with fewer points than "
            + "topics, group related topics into each point so that none is left out. Work only from the "
            + "conversation: add no new facts, numbers or sources, and no citation numbers. Don't mention these instructions."
        return try await stage(
            system, "\(earlier)Conversation so far:\n\n\(turns)\n\nRequest: \(asked)\(Self.languageLine(answerLanguage))",
            maxTokens, 0.4, onToken, timeoutMs: writeUpTimeoutFor(maxTokens), &state
        )
    }

    /// The follow-up rewritten from `exchange` into one question that names its subject; `query` if that fails.
    private func standalone(_ query: String, _ exchange: Exchange, _ state: inout RunState) async throws -> String {
        let prompt = "Previous question: \(exchange.question)\n\nPrevious answer: \(exchange.answer)\n\n"
            + "Follow-up: \(query)\n\nRewrite the follow-up as one standalone question that names its subject, in the "
            + "follow-up's language. If it asks to continue, conclude or expand, ask for that about the previous topic. "
            + "Reply with the question only.\n\nStandalone question:"
        let text = try await stage("You rewrite follow-up questions.", prompt, 80, 0.2, nil, timeoutMs: timeoutFor(80), &state)
        let lines = text.components(separatedBy: "\n").map { Self.trimQuotes(JsString.trim(Self.listMark.replaceFirst($0, with: ""))) }
        return lines.first { $0.u16 > 8 && !Self.refusal.containsMatch(in: $0) } ?? query
    }

    private func researchSubQuestion(
        _ sub: String, _ chunks: [Chunk], _ globalIndices: [Int], _ systemPrompt: String?, _ history: ConversationHistory?, _ state: inout RunState
    ) async throws -> String {
        let trimmedSummary = history?.summary.map { JsString.trim($0) } ?? ""
        let summary = trimmedSummary.isEmpty ? "" : "Summary of earlier conversation:\n\(trimmedSummary)\n\n"
        let context = chunks.isEmpty ? "" : "Context:\n\(Self.numberedContext(chunks, globalIndices))\n\n"
        let system = "\(Self.instructionOf(systemPrompt)) Answer the question in a short paragraph using the context. "
            + "Cite sources with the exact bracket numbers shown in the context, like [3]. "
            + "If the context does not cover it, say so."
        return try await stage(system, "\(summary)\(context)Question: \(sub)", 300, 0.6, nil, timeoutMs: timeoutFor(300), &state)
    }

    /// `followUp`: the last exchange and the follow-up as the user wrote it, when `query` was rewritten from them.
    private func synthesize(
        _ query: String, _ results: [(question: String, answer: String)], _ systemPrompt: String?, _ maxTokens: Int,
        _ onToken: @escaping @Sendable (String) -> Void, _ answerLanguage: String?, _ followUp: (Exchange, String)?, _ state: inout RunState
    ) async throws -> String {
        let perspectives = results.enumerated().map { "Perspective \($0.offset + 1) (\($0.element.question)):\n\($0.element.answer)" }.joined(separator: "\n\n")
        let system = "\(Self.instructionOf(systemPrompt)) You are synthesizing multiple research perspectives into one answer. "
            + "Compare them, reconcile any conflicts, and write one unified, well-reasoned answer. "
            + "Keep the source numbers exactly as the perspectives cite them, like [3]; do not renumber or invent sources."
            // A Detailed write-up ended with "Synthesis of Perspectives: Perspective 1… 2… 3…" (X6, Oct 14); the TS prompt
            // stops at the sentence above, so the golden recordings carry this one added.
            + " Do this silently: the reader never sees the perspectives, so never mention them, the sub-questions or the research steps, and add no section about them."
            // The write-up is the answer the user reads: it gets BOAR's identity as a normal answer does, whatever the style.
            + " " + RagPure.groundingInstruction
        let lang = answerLanguage.map { JsString.trim($0) } ?? ""
        let language = lang.isEmpty ? "" : "\n\n(\(lang))"
        let earlier = followUp.map { e, asked in "Previous question: \(e.question)\n\nPrevious answer: \(e.answer)\n\nFollow-up as asked: \(asked)\n\n" } ?? ""
        return try await stage(
            system, "\(earlier)Original question: \(query)\n\n\(perspectives)\(language)", maxTokens, 0.6, onToken,
            timeoutMs: writeUpTimeoutFor(maxTokens), &state
        )
    }

    // MARK: Pure helpers

    /// Characters of the previous answer a meta follow-up is written from (about 1,500 tokens: a 2,048-token answer fits).
    public static let fullPreviousAnswerChars = 6000

    /// What a meta follow-up asks for (English and Portuguese): summarize, conclude, continue.
    private static let metaCore: Set<String> = [
        "summary", "summarize", "summarise", "sum", "recap", "tldr", "conclusion", "conclude", "continue", "go", "more", "expand",
        "resumo", "resuma", "resumir", "resume", "conclusão", "conclusao", "concluir", "conclua", "continua", "continuar", "prossiga", "mais",
    ]
    /// Words that may come with it ("a brief summary please", "go on", "tell me more", "um resumo por favor").
    private static let metaFiller: Set<String> = [
        "up", "on", "going", "keep", "a", "an", "the", "please", "pls", "brief", "short", "quick", "executive", "final", "give",
        "me", "can", "you", "could", "write", "make", "now", "it", "this", "that", "of", "so", "and", "just", "tell", "in",
        "um", "uma", "o", "por", "favor", "faça", "faca", "dê", "de", "isso", "agora", "breve", "curto", "rápido", "executivo", "em",
    ]
    private static let nonLetters = Rx("[^\\p{L}]+")

    /// Kotlin `split(Regex("[^\\p{L}]+"))` of the lower-cased query.
    private static func letterWords(_ query: String) -> [String] { nonLetters.split(query.lowercased()) }

    /// A short message that only asks to summarize, conclude or continue the last answer ("TL;DR", "a brief summary
    /// please", "continue", "resuma"). A question with a subject of its own ("summary of the causes of war") isn't one.
    public static func isMetaFollowUp(_ query: String) -> Bool {
        let lowered = query.lowercased().replacingOccurrences(of: "tl;dr", with: "tldr").replacingOccurrences(of: "tl dr", with: "tldr")
        let words = nonLetters.split(lowered).filter { !$0.isEmpty }
        if words.isEmpty || words.count > 6 { return false }
        let content = words.filter { !metaFiller.contains($0) }
        return !content.isEmpty && content.allSatisfy { metaCore.contains($0) }
    }

    /// Words of a meta follow-up that ask for more rather than a summary ("continue", "tell me more", "prossiga").
    private static let metaMore: Set<String> = ["continue", "go", "more", "expand", "continua", "continuar", "prossiga", "mais"]

    /// A meta follow-up that only asks to summarize or conclude the last answer ("TL;DR", "a brief summary please"): plain
    /// chat writes it from that answer. "continue" isn't one: written from the last answer with nothing new allowed, it
    /// repeated that answer word for word (X6, Oct 16).
    public static func isSummaryFollowUp(_ query: String) -> Bool {
        isMetaFollowUp(query) && !letterWords(query).contains { metaMore.contains($0) }
    }

    /// Exchanges a recap reads (the most recent ones) and characters of each answer: 12 × ~600 stays near 2,500 tokens.
    public static let recapExchanges = 12
    public static let recapAnswerChars = 600

    private static let recapAsk = Rx("\\b(summar(y|ize|ise)|recap|tl;?dr|resum[aoeir]*|resumo)\\b", ignoreCase: true)
    // "Write an artifact about our conversation", "faça um relatório da nossa conversa": a write-up of the chat is a recap
    // too. The verb, then the document later on the same line: two searches, not one "verb.*document" regex (that one
    // retried ".*" from every verb and took 2.7 s on 20,000 characters of "write,").
    private static let writeUpVerb = Rx(
        "\\b(write|make|create|draft|prepare|compile|turn|put|give me|escrev\\p{L}*|fa[çc]a|fazer|cri[ae]\\p{L}*|mont\\p{L}*|ger[ae]\\p{L}*|prepar\\p{L}*)\\b",
        ignoreCase: true
    )
    private static let writeUpDoc = Rx(
        "\\b(report|document|doc|notes|artifact|write-?up|overview|memo|brief|article|outline|relat[óo]rio|documento|notas|artefato|texto|artigo)\\b",
        ignoreCase: true
    )
    // The line ends "." stops at.
    private static let lineEnd = Rx("[\\n\\r\\u0085\\u2028\\u2029]")

    private static func isWriteUpAsk(_ query: String) -> Bool {
        lineEnd.split(query).contains { line in
            guard let v = writeUpVerb.firstMatch(in: line) else { return false }
            let ns = line as NSString
            let from = v.range.location + v.range.length
            return writeUpDoc.re.firstMatch(in: line, options: [], range: NSRange(location: from, length: ns.length - from)) != nil
        }
    }
    // This chat, not a conversation named in the question ("the conversation between Kennedy and Khrushchev"). A write-up
    // must name the chat itself: "a report on Bitcoin's history so far" is about Bitcoin.
    private static let chatReference = Rx(
        "\\b((our|this|my) (whole |entire )?(conversation|chat|discussion|session)|(what )?we('ve| have)? (talked about|discussed|covered)|"
            + "(nossa|essa|esta) conversa|(o que )?(falamos|conversamos|discutimos))\\b",
        ignoreCase: true
    )
    private static let recapObject = Rx(
        "\\b((our|this|my) (whole |entire )?(conversation|chat|discussion|session)|all (of )?(this|that)|"
            + "(what )?we('ve| have)? (talked about|discussed|covered)|so far|"
            + "(nossa|essa|esta) conversa|(o que )?(falamos|conversamos|discutimos))\\b",
        ignoreCase: true
    )

    /// Citation numbers like [3]: a recap shows no sources, so the earlier answers' numbers would point at nothing.
    private static let citation = Rx("[ \\t\\n\\x0B\\f\\r]*\\[[0-9]{1,4}\\]")
    private static let whitespace = Rx("[ \\t\\n\\x0B\\f\\r]+")

    /// A request to summarize this conversation ("Summarize our conversation in 3 bullet points", "resuma a nossa conversa").
    public static func isConversationRecap(_ query: String) -> Bool {
        whitespace.split(query).filter { !JsString.trim($0).isEmpty }.count <= 16
            && (recapAsk.containsMatch(in: query) && recapObject.containsMatch(in: query)
                || isWriteUpAsk(query) && chatReference.containsMatch(in: query))
    }

    private static let listMark = Rx("^[-*0-9.)\(JsString.wsInner)]+")

    /// A model declining instead of answering ("I'm sorry, but…", "Desculpe, não posso…").
    private static let refusal = Rx(
        "^(i'?m sorry|i am sorry|sorry|i (cannot|can't|can ?not|am unable|'m unable|don't have|do not have)|as an ai|"
            + "unfortunately|desculp|lamento|infelizmente|não (posso|consigo|tenho)|nao (posso|consigo|tenho))",
        ignoreCase: true
    )

    /// Kotlin `String.trim('"')`.
    private static func trimQuotes(_ s: String) -> String {
        var u = Array(s.utf16)
        while u.last == 0x22 { u.removeLast() }
        var start = 0
        while start < u.count && u[start] == 0x22 { start += 1 }
        return String(decoding: u[start...], as: UTF16.self)
    }

    /// The last exchange before `query` when `query` reads as a follow-up (`FollowUp.plan`: it points back, or it is short
    /// with no name of its own); nil for a question that stands alone or a conversation's first.
    public static func lastExchange(_ query: String, _ history: ConversationHistory?) -> Exchange? {
        let p = FollowUp.plan(query, history)
        if p.direct == nil && p.fallback == nil { return nil }
        return lastAnswered(query, history)
    }

    /// The latest question in `history` that got an answer, and that answer (cut to `previousAnswerChars`).
    public static func lastAnswered(_ query: String, _ history: ConversationHistory?) -> Exchange? {
        let turns = history?.turns ?? []
        // The latest question that got an answer: a stopped answer leaves its question in the history with no answer, and
        // "continue" after a stopped "conclusion" researched "conclusion" itself (argumentation, X6, Oct 14).
        func answerAfter(_ i: Int) -> String {
            for t in turns[(i + 1)...] {
                if t.role == "user" { break }
                if t.role == "assistant" { return JsString.trim(t.text) }
            }
            return ""
        }
        // The same words asked before count too: a second "continue" builds on the first one's answer.
        guard let i = turns.indices.last(where: { turns[$0].role == "user" && !JsString.trim(turns[$0].text).isEmpty && !answerAfter($0).isEmpty }) else { return nil }
        let answer = answerAfter(i)
        return Exchange(
            question: JsString.trim(turns[i].text),
            answer: answer.u16 > previousAnswerChars ? answer.u16Take(previousAnswerChars) + "…" : answer
        )
    }

    /// The decomposition's lines as sub-questions (at most 3), refusals dropped; the question itself when none is usable.
    public static func parseSubQuestions(_ text: String, _ query: String) -> [String] {
        let lines = text.components(separatedBy: "\n").map { JsString.trim(listMark.replaceFirst($0, with: "")) }
            .filter { $0.u16 > 8 && !refusal.containsMatch(in: $0) }
        let first = Array(lines.prefix(3))
        return first.isEmpty ? [query] : first
    }

    /// Context block numbered with global source numbers.
    public static func numberedContext(_ chunks: [Chunk], _ globalIndices: [Int]) -> String {
        chunks.enumerated().map { "[\(globalIndices[$0.offset] + 1)] \($0.element.title)\n\($0.element.body)" }.joined(separator: "\n\n")
    }

    private static func instructionOf(_ systemPrompt: String?) -> String {
        let t = systemPrompt.map { JsString.trim($0) } ?? ""
        return t.isEmpty ? "You are an offline research assistant." : t
    }
}
