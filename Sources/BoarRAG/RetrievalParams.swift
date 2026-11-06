/// The knobs of `Retriever.retrieve`: how keyword and meaning results are weighed in `RagPure.fuse`, and the similarity
/// floors a hit must clear. `default` is today's retrieval exactly (port of RetrievalParams.kt).
public struct RetrievalParams: Sendable, Equatable {
    /// Weight of the keyword (BM25) results in the fusion.
    public var lexicalWeight: Double
    /// Weight of the meaning (embedding) results in the fusion.
    public var semanticWeight: Double
    /// Cosine floor for a semantic hit from the knowledge base or a format-1 pack to count.
    public var minSemanticSimilarity: Double
    /// Real similarity a knowledge-base or format-1 hit needs before it can reach the model.
    public var answerMinSimilarity: Double
    /// The user's own files only (the Personal Files style): no library, no packs, and a meaning hit passes at
    /// `minSemanticSimilarity` instead of `answerMinSimilarity`, since nothing else can come back.
    public var ownOnly: Bool

    public init(
        lexicalWeight: Double = 0.5, semanticWeight: Double = 0.5, minSemanticSimilarity: Double = RagPure.minSemanticSimilarity,
        answerMinSimilarity: Double = RagPure.answerMinSimilarity, ownOnly: Bool = false
    ) {
        self.lexicalWeight = lexicalWeight; self.semanticWeight = semanticWeight
        self.minSemanticSimilarity = minSemanticSimilarity; self.answerMinSimilarity = answerMinSimilarity; self.ownOnly = ownOnly
    }

    public static let `default` = RetrievalParams()
}

/// How retrieval ranks what it finds; `custom` keeps whatever weights and floors were set by hand.
public enum RetrievalMode: String, Sendable, CaseIterable {
    case balanced = "BALANCED", keyword = "KEYWORD", meaning = "MEANING", custom = "CUSTOM"

    /// This mode's parameters; `custom` is used for `.custom` only.
    public func params(custom: RetrievalParams = .default) -> RetrievalParams {
        switch self {
        case .balanced: return .default
        case .keyword: var p = RetrievalParams.default; p.semanticWeight = 0.0; return p
        case .meaning: var p = RetrievalParams.default; p.lexicalWeight = 0.0; return p
        case .custom: return custom
        }
    }
}
