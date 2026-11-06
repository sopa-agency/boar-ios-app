import BoarCore
import Foundation

/// An installed knowledge pack, opened: format 1 (FTS5 + int8 vectors) or format 2 (WikiPack).
public enum OpenPack: Sendable {
    case format1(String, any SqlDatabase)
    case format2(String, WikiPack)

    public var id: String {
        switch self {
        case .format1(let id, _), .format2(let id, _): return id
        }
    }
}

/// Hybrid retrieval over the knowledge base and the installed packs (port of src/rag/retrieve.ts): lexical and
/// semantic results fused after the relevance gate, articles the question names first, what-to-do sections and lay
/// sources kept for action questions, and a second, English search for Portuguese questions. Nothing here touches
/// the network. The database work is synchronous inside the async calls; do not call it from the main actor.
public final class Retriever: Sendable {
    private let kb: KnowledgeBase
    /// Installed packs in the order the app lists them (catalog first, then local files by name).
    private let packs: @Sendable () -> [OpenPack]
    private let embed: @Sendable (String) async throws -> [Float]
    private let lexicon: @Sendable () -> PtLexicon.Lexicon

    public init(
        kb: KnowledgeBase, packs: @escaping @Sendable () -> [OpenPack], embed: @escaping @Sendable (String) async throws -> [Float],
        lexicon: @escaping @Sendable () -> PtLexicon.Lexicon
    ) {
        self.kb = kb; self.packs = packs; self.embed = embed; self.lexicon = lexicon
    }

    /// Embeds with a core `TextEmbedder` (an empty vector means "no embedding model": only keyword search runs).
    public convenience init(
        kb: KnowledgeBase, packs: @escaping @Sendable () -> [OpenPack], embedder: any TextEmbedder, lexicon: @escaping @Sendable () -> PtLexicon.Lexicon
    ) {
        self.init(kb: kb, packs: packs, embed: { try await embedder.embed($0) }, lexicon: lexicon)
    }

    /// `params`: fusion weights and similarity floors; the default is the retrieval the golden tests pin.
    public func retrieve(
        _ query: String, topK: Int = 6, queryVec: [Float]? = nil, includeWikiPacks: Bool = true, params: RetrievalParams = .default
    ) async throws -> [Chunk] {
        if !params.ownOnly { return OwnFiles.dropCoveredCards(try await retrieveAll(query, topK, queryVec, includeWikiPacks, params)) }
        // Personal Files: a file the question names is searched alone; a question about all the files brings each one's
        // opening part after what the search found, since no single passage is close to "summarize my files".
        let files = try kb.ownFiles()
        let vec: [Float]
        if let queryVec { vec = queryVec } else { vec = try await embed(query) }
        if let f = OwnFiles.named(query, files) {
            return Array(OwnFiles.dropCoveredCards(try kb.rankWithin(OwnFiles.docsOf(f, files), queryVec: vec, limit: topK + 1)).prefix(max(0, topK)))
        }
        let found = OwnFiles.dropCoveredCards(try await retrieveAll(query, topK, vec, includeWikiPacks, params))
        if !OwnFiles.aboutTheFiles(query) { return found }
        return OwnFiles.withOpenings(found, try kb.openingParts(files.map(\.docId)), hits: topK, limit: max(topK, OwnFiles.overviewMaxFiles))
    }

    /// The user's switched-on files, for the prompt's list of them (OwnFiles.note).
    public func ownFiles() throws -> [OwnFiles.File] { try kb.ownFiles() }

    private func retrieveAll(
        _ query: String, _ topK: Int, _ queryVec: [Float]?, _ includeWikiPacks: Bool, _ params: RetrievalParams
    ) async throws -> [Chunk] {
        let main = try await retrieveOne(query, topK, queryVec, includeWikiPacks, nil, nil, nil, params)
        // A Portuguese question against English sources: search again with the English names it mentions and put
        // those results first. The English embedder and keyword index barely match Portuguese words.
        if !PtLexicon.looksPortuguese(query) { return main }
        // A standard's number (EIP-1559, ERC-20, BIP-32) names its page exactly: it goes before any lexicon name.
        let ids = Identifiers.identifiersIn(query)
        let names = ids + PtLexicon.englishNamesIn(query, lexicon()).filter { !ids.contains($0) }
        if names.isEmpty { return main }
        let action = WikiPackText.hasActionIntent(query)
        let found = try await retrieveOne(names.joined(separator: " "), topK, nil, includeWikiPacks, names, action, Explain.hasExplainIntent(query), params)
        let named = Set(names.map { $0.lowercased() })
        // What-to-do sections first in an action question, then articles named exactly; disambiguation lists never.
        func rank(_ c: Chunk) -> Int { action && c.action ? 0 : (named.contains(c.title.lowercased()) ? 1 : 2) }
        let english = found.filter { !Self.isDisambiguation($0) }.stableSorted { rank($0) < rank($1) }
        let first = action ? english.filter(\.action) : english
        var seen = Set<String>()
        let merged = (Array(first.prefix(Int((Double(topK * 2) / 3.0).rounded(.up)))) + main + english)
            .filter { !Self.isDisambiguation($0) && seen.insert($0.chunkId).inserted }
        func byId(_ c: Chunk) -> Bool { ids.contains { Identifiers.titleHasIdentifier(c.title, $0) } }
        return Array(Dedupe.dedupeArticleCopies(merged.filter(byId) + merged.filter { !byId($0) }).prefix(max(0, topK)))
    }

    private func retrieveOne(
        _ query: String, _ topK: Int, _ queryVec: [Float]?, _ includeWikiPacks: Bool, _ titles: [String]?, _ action: Bool?, _ explain: Bool?,
        _ params: RetrievalParams
    ) async throws -> [Chunk] {
        // A later step could skip the embedding when params.semanticWeight is 0 (keyword): lexical hits still read their
        // similarity from it for the relevance gate, so that needs a decision first.
        let vec: [Float]
        if let queryVec { vec = queryVec } else { vec = try await embed(query) }
        let lexical = try kb.lexicalSearch(query, queryVec: vec, limit: topK * 2, ownOnly: params.ownOnly)
        let semantic = try kb.semanticSearch(vec, limit: topK * 2, minSimilarity: params.minSemanticSimilarity, ownOnly: params.ownOnly)
        // Personal Files: the user's own files only, never the packs.
        let installed = params.ownOnly ? [] : packs()
        // A failing pack is skipped, never fatal.
        var f1: [Packs.Found] = []
        var wiki: [(String, [PackHit])] = []
        for p in installed {
            switch p {
            case .format1(let id, let db):
                if let r = try? Packs.searchFormat1(db, packId: id, query: query, queryVec: vec, limit: topK * 2, explain: explain, minSimilarity: params.minSemanticSimilarity) { f1.append(r) }
            case .format2(let id, let pack):
                guard includeWikiPacks else { continue }
                let opts = PackSearchOptions(titles: titles ?? [], k: topK, action: action, explain: explain, queryVec: vec)
                if let r = try? pack.searchDetailed(query, opts) { wiki.append((id, r.hits)) }
            }
        }
        func chunks(_ keep: (PackHit) -> Bool) -> [Chunk] {
            wiki.flatMap { (id, hits) in hits.filter(keep).map { Packs.packHitToChunk(id, $0) } }
        }

        // Passages from articles the question names come first, in the pack's own order; a named disambiguation page
        // is a list of links, not a source. The pack's keyword hits compete with everything else.
        let named = chunks { $0.via == "title" }.filter { !Self.isDisambiguation($0) }
        let wikiLexical = chunks { $0.via != "title" }
        // The knowledge base and format-1 packs pass the relevance gate first; large-pack hits have their own
        // ranking and no similarity, so they aren't gated here.
        // With keyword weight 0 (meaning) the large-pack hits still compete at the meaning weight: they are the library's
        // only results here (the pack ranks them with the question's embedding too), not keyword-only ones.
        let keywordOff = params.lexicalWeight <= 0.0
        // The user's own documents (a collection they imported): a keyword hit that already covers the question's key
        // words reaches the model without the similarity floor. Their parts are long and mixed, so a short question scored
        // under the floor against the very post it names (X6, Oct 21). The library and the packs keep the floor.
        let own = lexical.filter { $0.collectionId != nil }
        let shared = lexical.filter { $0.collectionId == nil }
        let fused = RagPure.fuse(
            (keywordOff ? [] : own + RagPure.gateByRelevance(shared + f1.flatMap(\.lexical), minSimilarity: params.answerMinSimilarity)) + wikiLexical,
            // Only the user's files can come back in Personal Files, so their meaning hits pass at the search floor (0.55):
            // a lower floor can't pull in the library there.
            RagPure.gateByRelevance(
                semantic + f1.flatMap(\.semantic), minSimilarity: params.ownOnly ? params.minSemanticSimilarity : params.answerMinSimilarity
            ),
            topK: topK,
            lexicalWeight: keywordOff ? params.semanticWeight : params.lexicalWeight,
            semanticWeight: params.semanticWeight
        )
        // A what-to-do question: up to three pack sections that say what to do, right after the named articles.
        let isAction = action ?? WikiPackText.hasActionIntent(query)
        let steps = isAction ? Array(chunks { $0.via != "title" && $0.action }.prefix(3)) : []
        var firstSeen = Set<String>()
        let first = (named + steps).filter { firstSeen.insert($0.chunkId).inserted }
        let seen = Set(first.map(\.chunkId))
        // One copy per article passage across libraries, before the cut.
        var result = Array(Dedupe.dedupeArticleCopies(first + fused.filter { !seen.contains($0.chunkId) }).prefix(max(topK, named.count)))
        // The lay sources the pack search added past its limit (a first-aid manual next to the clinical article) stay.
        if isAction {
            let inResult = Set(result.map(\.chunkId))
            let lay = chunks { WikiPackText.laySources.contains($0.source) }.filter { !inResult.contains($0.chunkId) }
            result += Array(Dedupe.dedupeArticleCopies(result + lay).dropFirst(result.count).prefix(2))
        }
        return result
    }

    private static let disambigTitle = Rx("(?i)\\(disambiguation\\)\\z")
    private static let refers = Rx("(?i)\(Js.b0)may (also )?refer to\(Js.b1)")

    /// A "may refer to" list or a "(disambiguation)" page: never a source.
    public static func isDisambiguation(_ c: Chunk) -> Bool {
        disambigTitle.contains(c.title) || refers.contains(c.body.u16Take(300))
    }
}
