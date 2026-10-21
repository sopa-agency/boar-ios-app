import BoarCore
import BoarRAG
import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// Deep Research and its context helpers must match src/services/orchestrator.ts and src/routing/context.ts
/// (scripts/export-native-golden-research.mjs): every stage's prompt and settings, the sources and their numbers.
struct DeepResearchGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("research.json") }

    private func line(_ o: JSONValue) -> String { "\(o["chunkId"]!.str!) | \(o["body"]!.str!) | \(o["relevance"]?.doubleValue.map { String($0) } ?? "nil")" }
    private func line(_ c: Chunk) -> String { "\(c.chunkId) | \(c.body) | \(c.relevance.map { String($0) } ?? "nil")" }

    @Test func onTopicTestAndContextCompression() throws {
        // The topic cases use the same stand-in retrieval; their chunks are all in the research recordings or the corpus.
        let corpus = try JSONValue(jsonString: Fixtures.text(Fixtures.asset("corpus/corpus.json")))!.arr
        var docs: [String: Chunk] = [:]
        for (i, d) in corpus.enumerated() {
            docs["seed:\(i)"] = Chunk(chunkId: "seed:\(i)", docId: "seed:\(d["title"]!.str!)", title: d["title"]!.str!, body: d["body"]!.str!, source: d["source"]?.str)
        }
        let topics = try req(g["topic"]).arr
        #expect(topics.count == 165)
        var failed = 0
        for t in topics {
            let q = t["query"]!.str!
            let chunks: [Chunk]
            if let list = t["chunks"]?.arrayValue { chunks = list.map(goldenChunk) } else { chunks = try t["chunkIds"]!.strs.map { try #require(docs[$0]) } }
            let onTopic = chunks.map { ResearchSupport.context.onTopic(query: q, $0) }
            let c = ResearchSupport.compressContext(q, chunks, tokenBudget: t["budget"]!.int)
            let ok = onTopic == t["onTopic"]!.arr.map(\.flag)
                && c.chunks.map(line) == t["compressed"]!.arr.map(line)
                && c.keptIndices == t["keptIndices"]!.arr.map(\.int)
                && c.tokensBefore == t["tokensBefore"]!.int && c.tokensAfter == t["tokensAfter"]!.int
            if !ok {
                failed += 1
                if failed <= 5 { Issue.record("topic \(q): onTopic \(onTopic) want \(t["onTopic"]!.arr.map(\.flag)); compressed \(c.chunks.map(line)) want \(t["compressed"]!.arr.map(line))") }
            }
        }
        #expect(failed == 0)
    }

    @Test func mergedSourceNumbers() throws {
        let m = try req(g["merge"])
        let c = (0..<4).map { Chunk(chunkId: "seed:\($0)", docId: "d", title: "t\($0)", body: "b") }
        let got = ResearchContext.mergeSources([[c[0], c[1]], [c[1], c[2]], [], [c[2], c[0], c[3]]])
        #expect(got.sources.map(\.chunkId) == m["sources"]!.strs)
        #expect(got.indexMaps == m["indexMaps"]!.arr.map { $0.arr.map(\.int) })
    }

    @Test func everyStagesPromptTheSourcesAndTheAnswer() async throws {
        let runs = try req(g["research"]).arr
        #expect(runs.count == 28)
        for r in runs {
            let q = r["query"]!.str!
            let calls = r["calls"]!.arr
            let retrievals = r["retrievals"]!.arr
            let n = Cursor()
            let k = Cursor()
            let generator = ClosureStageGenerator { system, user, nPredict, temperature, _, onToken in
                let i = n.next()
                guard i < calls.count else { Issue.record("\(q): unexpected stage \(i + 1)"); return GenResult(text: "") }
                let want = calls[i]
                #expect(system == want["system"]!.str!, "\(q) stage \(i + 1) system")
                #expect(user == want["user"]!.str!, "\(q) stage \(i + 1) user")
                #expect(nPredict == want["nPredict"]!.int, "\(q) stage \(i + 1) nPredict")
                #expect(abs(Double(temperature) - want["temperature"]!.dbl) < 1e-6, "\(q) stage \(i + 1) temperature")
                let reply = want["reply"]!.str!
                onToken?(reply)
                return GenResult(text: reply)
            }
            let retrieve: @Sendable (String, Int) async throws -> [Chunk] = { sq, topK in
                let i = k.next()
                guard i < retrievals.count else { Issue.record("\(q): unexpected retrieval \(i + 1)"); return [] }
                let want = retrievals[i]
                #expect(sq == want["query"]!.str!, "\(q) retrieval \(i + 1)")
                #expect(topK == want["k"]!.int)
                return want["chunks"]!.arr.map(goldenChunk)
            }
            let history = r.opt("summary")?.str.map { ConversationHistory(summary: $0) }
            let res = try await DeepResearch(generator: generator, retrieve: retrieve).run(
                q, systemPrompt: r["system"]?.str, history: history, maxTokens: 512, answerLanguage: r["language"]?.str
            )
            #expect(n.value == calls.count, "\(q) stages")
            #expect(res.subQuestions == r["subQuestions"]!.strs, "\(q) sub-questions")
            #expect(res.answer == r["answer"]!.str!, "\(q) answer")
            #expect(res.citations.map(line) == r["citations"]!.arr.map(line), "\(q) citations")
            #expect(res.fullCitations.map(\.chunkId) == r["fullCitations"]!.strs, "\(q) full citations")
        }
    }
}
