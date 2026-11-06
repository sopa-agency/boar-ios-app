import Foundation

/// A passage the retrieval found (ChunkRecord + RetrievedChunk of src/rag).
public struct Chunk: Sendable, Equatable {
    public var chunkId: String
    public var docId: String
    public var title: String
    public var body: String
    public var source: String?
    public var collectionId: String?
    /// After fusion: a normalized weighted sum, only meaningful relative to other chunks.
    public var score: Double
    public var matchType: MatchType
    /// Real cosine similarity to the question, when the semantic search saw this chunk.
    public var similarity: Double?
    /// A what-to-do passage (a preparedness pack section like "During an earthquake").
    public var action: Bool
    /// Share of the question's words its title and best sentence cover (0..1), what the UI shows; set by compression.
    public var relevance: Double?

    public init(
        chunkId: String, docId: String, title: String, body: String, source: String? = nil, collectionId: String? = nil,
        score: Double = 0.0, matchType: MatchType = .lexical, similarity: Double? = nil, action: Bool = false, relevance: Double? = nil
    ) {
        self.chunkId = chunkId; self.docId = docId; self.title = title; self.body = body
        self.source = source; self.collectionId = collectionId
        self.score = score; self.matchType = matchType; self.similarity = similarity
        self.action = action; self.relevance = relevance
    }
}

public enum MatchType: String, Sendable, Equatable {
    case lexical, semantic, hybrid
}

public struct LexicalTerm: Sendable, Equatable {
    public var forms: [String]
    public init(forms: [String]) { self.forms = forms }
}

public struct LexicalQuery: Sendable, Equatable {
    public var match: String
    public var terms: [LexicalTerm]
    public init(match: String, terms: [LexicalTerm]) { self.match = match; self.terms = terms }
}

public struct ConversationTurn: Sendable, Equatable {
    public var role: String
    public var text: String
    public init(role: String, text: String) { self.role = role; self.text = text }
}

public struct ConversationHistory: Sendable, Equatable {
    public var summary: String?
    public var turns: [ConversationTurn]
    public init(summary: String? = nil, turns: [ConversationTurn] = []) { self.summary = summary; self.turns = turns }
}

public struct PromptMessage: Sendable, Equatable {
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

/// Pure retrieval and prompt helpers (port of src/rag/pure.ts). Outputs match the TS byte for byte (golden tests).
public enum RagPure {
    /// bge-small cosine floor for a semantic hit to count (measured 2026-09-26; see pure.ts).
    public static let minSemanticSimilarity = 0.55
    public static let answerContextChunks = 4
    public static let maxChunksPerArticle = 2
    /// Nothing below this real similarity is sent to the model (pure.ts ANSWER_MIN_SIMILARITY).
    public static let answerMinSimilarity = 0.7
    private static let maxLexicalTerms = 12

    /// Float32 products are rounded to float before they are added to the double accumulators, as on the JVM.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) {
            dot += Double(a[i] * b[i]); na += Double(a[i] * a[i]); nb += Double(b[i] * b[i])
        }
        return na == 0.0 || nb == 0.0 ? 0.0 : dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Cosine against an int8 vector as stored in a knowledge pack (the per-vector scale cancels out).
    public static func cosineInt8(_ query: [Float], _ bytes: Data) -> Double {
        var dot = 0.0, nq = 0.0, nv = 0.0
        let n = min(query.count, bytes.count)
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n {
                let v = Double(Int8(bitPattern: raw[i]))
                dot += Double(query[i]) * v; nq += Double(query[i] * query[i]); nv += v * v
            }
        }
        return nq == 0.0 || nv == 0.0 ? 0.0 : dot / (nq.squareRoot() * nv.squareRoot())
    }

    private static let stopwords: Set<String> = [
        "a", "about", "after", "all", "also", "am", "an", "and", "any", "are", "as", "at",
        "be", "because", "been", "before", "being", "best", "better", "between", "both", "but", "by",
        "can", "could", "compare", "comparison", "describe", "detail", "details", "did",
        "difference", "differences", "do", "does", "doing", "during", "each", "explain",
        "for", "from", "give", "had", "has", "have", "having", "he", "her", "here", "him",
        "his", "how", "i", "if", "in", "into", "is", "it", "its", "just", "know", "like",
        "me", "mean", "means", "meant", "more", "most", "much", "my", "no", "not", "of",
        "on", "or", "other", "our", "overview", "please", "same", "she", "should", "show",
        "so", "some", "something", "such", "summarize", "summary", "tell", "than", "that",
        "the", "their", "them", "then", "there", "these", "they", "thing", "things", "this",
        "those", "through", "to", "too", "under", "up", "us", "very", "versus", "vs", "want",
        "was", "we", "were", "what", "when", "where", "which", "while", "who", "whom", "whose",
        "why", "will", "with", "work", "works", "would", "you", "your", "happen", "happened",
        "happens", "cause", "caused", "causes",
    ]

    private static let nonWord = Rx("[^\\p{L}\\p{N}]+")
    private static let ssisus = Rx("(ss|is|us)$")
    private static let eses = Rx("(s|x|z|o|ch|sh)es$")

    /// NFKD, accents dropped, lower case, split on anything that isn't a letter or digit.
    public static func tokenize(_ text: String) -> [String] {
        let folded = Js.combining.replace(Js.nfkd(text), with: "").lowercased()
        return nonWord.split(folded).filter { !$0.isEmpty }
    }

    private static func singularsOf(_ token: String) -> [String] {
        if token.u16Count < 4 || !token.u16EndsWith("s") || ssisus.contains(token) { return [] }
        if token.u16EndsWith("ies") { return [token.u16DropLast(3) + "y"] }
        if eses.contains(token) { return [token.u16DropLast(1), token.u16DropLast(2)] }
        return [token.u16DropLast(1)]
    }

    /// The question's content words as an FTS5 OR query, each quoted; nil when only filler is left.
    public static func buildLexicalQuery(_ query: String) -> LexicalQuery? {
        var seen = Set<String>()
        var terms: [LexicalTerm] = []
        for token in tokenize(query) {
            if token.u16Count < 2 || stopwords.contains(token) { continue }
            let forms = [token] + singularsOf(token)
            if forms.contains(where: { seen.contains($0) }) { continue }
            seen.formUnion(forms)
            terms.append(LexicalTerm(forms: forms))
            if terms.count >= maxLexicalTerms { break }
        }
        if terms.isEmpty { return nil }
        return LexicalQuery(match: terms.flatMap { $0.forms.map { "\"\($0)\"" } }.joined(separator: " OR "), terms: terms)
    }

    /// Short queries need every term, longer ones a strict majority.
    public static func requiredTermMatches(_ termCount: Int) -> Int { termCount <= 2 ? termCount : termCount / 2 + 1 }

    public static func countMatchedTerms(_ text: String, _ terms: [LexicalTerm]) -> Int {
        let tokens = Set(tokenize(text))
        return terms.reduce(0) { n, t in t.forms.contains(where: { tokens.contains($0) }) ? n + 1 : n }
    }

    public static func filterByTermCoverage(_ hits: [Chunk], _ terms: [LexicalTerm]) -> [Chunk] {
        let required = requiredTermMatches(terms.count)
        return hits.filter { countMatchedTerms("\($0.title) \($0.body)", terms) >= required }
    }

    /// Weighted-sum fusion of two scored result sets, each normalized to its own max; at most `maxChunksPerArticle`
    /// per title. A relative re-ranking, not a relevance gate. A set weighted 0 is left out, not added at score 0 where it
    /// would still fill the remaining places.
    public static func fuse(_ lexical: [Chunk], _ semantic: [Chunk], topK: Int, lexicalWeight: Double = 0.5, semanticWeight: Double = 0.5) -> [Chunk] {
        var byId: [String: Chunk] = [:]
        var order: [String] = []
        func add(_ chunks: [Chunk], _ weight: Double) {
            if chunks.isEmpty || weight <= 0.0 { return }
            let max = Swift.max(chunks.map(\.score).max()!, 1e-9)
            for c in chunks {
                let norm = (c.score / max) * weight
                if var existing = byId[c.chunkId] {
                    existing.score += norm
                    existing.matchType = .hybrid
                    if let s = c.similarity { existing.similarity = Swift.max(existing.similarity ?? -1.0, s) }
                    byId[c.chunkId] = existing
                } else {
                    var n = c
                    n.score = norm
                    byId[c.chunkId] = n
                    order.append(c.chunkId)
                }
            }
        }
        add(lexical, lexicalWeight)
        add(semantic, semanticWeight)
        var perTitle: [String: Int] = [:]
        var out: [Chunk] = []
        for c in order.map({ byId[$0]! }).stableSorted(by: { $0.score > $1.score }) {
            let key = kotlinTrim(c.title).lowercased()
            let n = perTitle[key] ?? 0
            if n >= maxChunksPerArticle { continue }
            perTitle[key] = n + 1
            out.append(c)
            if out.count >= topK { break }
        }
        return out
    }

    public static func gateByRelevance(_ chunks: [Chunk], minSimilarity: Double = answerMinSimilarity) -> [Chunk] {
        chunks.filter { c in c.similarity.map { $0 >= minSimilarity } ?? false }
    }

    private static let contextInstruction =
        " Use the context below when relevant, and cite a source you used by its number, like [1] or [2]. "
        + "If the context doesn't cover it, say so, then answer briefly from general knowledge, without specific figures or names you're unsure of."

    /// The Personal Files style's context instruction: the user's own files only, quoted as written, and a fixed line when
    /// they don't hold the answer, never an answer from general knowledge.
    public static let filesOnlyInstruction =
        " Use only the context below, from the user's own files, and cite it by its number, like [1]. "
        + "Quote numbers, names and dates exactly as the file writes them. "
        + "If the context doesn't contain the answer, say exactly: I couldn't find this in your Personal Files."

    private static func contextInstruction(_ filesOnly: Bool) -> String { filesOnly ? filesOnlyInstruction : contextInstruction }

    /// Who BOAR is and what it can't do; every answer gets it, Deep Research's write-up included.
    public static let groundingInstruction =
        "You are BOAR, an offline AI research app running on this phone; \"Boar\" is the app's name, never the animal, so never describe yourself as one. "
        + "You have no ability to control real-world devices or take physical actions \u{2014} no alarms, "
        + "lights, thermostats, timers, or any other device or system. You can only respond with text. "
        + "Treat greetings and casual small talk conversationally and briefly, not as a command or task. "
        + "Never claim to have done something (set, adjusted, turned on/off, scheduled, etc.) that you "
        + "don't actually have the ability to do."

    private static func instructionOf(_ systemPrompt: String?) -> String {
        if let s = systemPrompt, !kotlinTrim(s).isEmpty { return kotlinTrim(s) }
        return "You are an offline research assistant."
    }

    private static func styleSection(_ styleReminder: String?) -> String {
        guard let r = styleReminder else { return "" }
        let s = kotlinTrim(r)
        return s.isEmpty ? "" : "\n\n(Response style: \(s))"
    }

    private static func contextOf(_ chunks: [Chunk]) -> String {
        chunks.enumerated().map { "[\($0.offset + 1)] \($0.element.title)\n\($0.element.body)" }.joined(separator: "\n\n")
    }

    private static func nonEmptyTrimmed(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = kotlinTrim(s)
        return t.isEmpty ? nil : t
    }

    /// Personal Files' list of the user's files (OwnFiles.note), right before the context it explains.
    private static func filesSection(_ filesNote: String?, _ sep: String) -> String {
        nonEmptyTrimmed(filesNote).map { "\($0)\(sep)" } ?? ""
    }

    /// The completion-style prompt ("Question: …\n\nAnswer:"). `filesOnly`: the Personal Files instruction; `filesNote`: its
    /// list of the user's files.
    public static func assemblePrompt(
        _ userQuery: String, _ chunks: [Chunk], systemPrompt: String? = nil, history: ConversationHistory? = nil, styleReminder: String? = nil,
        filesOnly: Bool = false, filesNote: String? = nil
    ) -> String {
        let instruction = instructionOf(systemPrompt)
        let summary = nonEmptyTrimmed(history?.summary).map { "Summary of earlier conversation:\n\($0)\n\n" } ?? ""
        var turns = ""
        if let t = history?.turns, !t.isEmpty {
            let lines = t.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
            turns = "Recent conversation:\n\(lines)\n\n"
        }
        let hasContext = !chunks.isEmpty
        let ctxInstr = hasContext ? contextInstruction(filesOnly) : ""
        let ctx = hasContext ? "Context:\n\(contextOf(chunks))\n\n" : ""
        return "\(instruction)\(ctxInstr) \(groundingInstruction)\n\n\(summary)\(turns)\(filesSection(filesNote, "\n\n"))\(ctx)Question: \(userQuery)\(styleSection(styleReminder))\n\nAnswer:"
    }

    /// The fixed start of every sourced answer prompt for a tone, kept prefilled in the KV cache.
    public static func answerPromptPrefix(systemPrompt: String? = nil, withContext: Bool = true, filesOnly: Bool = false) -> (system: String, prompt: String) {
        // Without sources the prompt has no context instruction, so the two start differently right after the tone.
        let head = "\(instructionOf(systemPrompt))\(withContext ? contextInstruction(filesOnly) : "") \(groundingInstruction)"
        return (head, "\(head)\n\n")
    }

    /// The same content as role-separated messages, for the model's own chat template.
    public static func assembleChatMessages(
        _ userQuery: String, _ chunks: [Chunk], systemPrompt: String? = nil, history: ConversationHistory? = nil, styleReminder: String? = nil,
        filesOnly: Bool = false, filesNote: String? = nil
    ) -> [PromptMessage] {
        let instruction = instructionOf(systemPrompt)
        let hasContext = !chunks.isEmpty
        let ctxInstr = hasContext ? contextInstruction(filesOnly) : ""
        let ctx = hasContext ? "\n\nContext:\n\(contextOf(chunks))" : ""
        let summary = nonEmptyTrimmed(history?.summary).map { "\n\nSummary of earlier conversation:\n\($0)" } ?? ""
        // After the fixed start (kept prefilled), so the list costs only its own tokens.
        let filesRaw = filesSection(filesNote, "")
        let files = filesRaw.isEmpty ? "" : "\n\n\(filesRaw)"
        let system = PromptMessage(role: "system", content: "\(instruction)\(ctxInstr) \(groundingInstruction)\(summary)\(files)\(ctx)")
        let past = (history?.turns ?? []).map { PromptMessage(role: $0.role, content: $0.text) }
        return [system] + past + [PromptMessage(role: "user", content: userQuery + styleSection(styleReminder))]
    }
}
