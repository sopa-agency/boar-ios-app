import BoarRAG

/// The search slot (android `plugins/PipelineStages.kt`): a Boar Labs plugin looks at what the search found and returns the
/// passages the model reads. With no stage, search is exactly the built-in one.
public protocol SearchStage: Sendable {
    /// `chunks` in search order (twice `topK` when a stage is on, for it to choose from); return at most `topK`, plus at
    /// most `SearchStages.extra` dated table sources after them (Facts' country figures, t9 0110 item 5).
    func process(query: String, chunks: [Chunk], topK: Int) throws -> [Chunk]
}

public enum SearchStages {
    /// How many sources a search stage may add after the search's own `topK`.
    public static let extra = 1

    /// Search for an answer (android `BoarServices.search`): the built-in retrieval, then the stages, which get twice `topK`
    /// passages to choose from. Every answer path goes through it. A stage that fails is skipped, never fatal: the answer
    /// keeps what search found.
    public static func search(
        _ stages: [any SearchStage], query: String, topK: Int, retrieve: (String, Int) async throws -> [Chunk]
    ) async throws -> [Chunk] {
        if stages.isEmpty { return try await retrieve(query, topK) }
        var chunks = try await retrieve(query, topK * 2)
        for st in stages { if let next = try? st.process(query: query, chunks: chunks, topK: topK) { chunks = next } }
        return Array(chunks.prefix(topK + extra))
    }
}
