/// The Personal Files style sends the user's parts whole, not the few sentences `Compress.forAnswer` keeps: the line with
/// the number was the one cut away (X6, Oct 21). They go in while they fit the context the model was opened with, next
/// to the prompt and the answer; otherwise the lowest-ranked part goes first, and a single part that alone is too big is
/// compressed to what's left (port of WholePassages.kt).
public enum WholePassages {
    /// Room kept free past the estimate: the token count is approximate, and the chat template adds its own marks.
    public static let margin = 128
    /// A part compressed to less than this says nothing useful; it gets at least this much.
    public static let minPartTokens = 64

    /// The tokens left for passages: contextSize − promptTokens − maxTokens − margin.
    public static func budget(contextSize: Int, promptTokens: Int, maxTokens: Int) -> Int { contextSize - promptTokens - maxTokens - margin }

    /// `chunks` best first; `promptTokens`: the prompt without its passages. Each part costs its "[n] title\nbody" plus the
    /// blank line between parts.
    public static func fit(
        _ query: String, _ chunks: [Chunk], contextSize: Int, promptTokens: Int, maxTokens: Int,
        count: (String) -> Int = Compress.approxTokens
    ) -> Compress.Result {
        func cost(_ i: Int, _ c: Chunk) -> Int { count("[\(i + 1)] \(c.title)\n\(c.body)") + 2 }
        let before = chunks.reduce(0) { $0 + count("\($1.title)\n\($1.body)") }
        let room = budget(contextSize: contextSize, promptTokens: promptTokens, maxTokens: maxTokens)
        var kept = chunks
        while kept.count > 1 && kept.enumerated().reduce(0, { $0 + cost($1.offset, $1.element) }) > room { kept.removeLast() }
        if kept.count == 1, let only = kept.first, cost(0, only) > room {
            // Compression counts the title and each sentence itself; the "[1] " and the blank line are kept aside.
            let left = max(minPartTokens, room - 4)
            let c = Compress.compress(query, [only], tokenBudget: left, count: count)
            if !c.chunks.isEmpty { return Compress.Result(chunks: c.chunks, keptIndices: c.keptIndices, tokensBefore: before, tokensAfter: c.tokensAfter) }
            // Not even one sentence fits (a long table row): its start, cut to the room left.
            var cut = only
            cut.body = only.body.u16Take(max(0, left - count(only.title) - 1) * 4)
            return Compress.Result(chunks: [cut], keptIndices: [0], tokensBefore: before, tokensAfter: count("\(cut.title)\n\(cut.body)"))
        }
        return Compress.Result(
            chunks: kept, keptIndices: Array(kept.indices), tokensBefore: before, tokensAfter: kept.reduce(0) { $0 + count("\($1.title)\n\($1.body)") }
        )
    }
}
