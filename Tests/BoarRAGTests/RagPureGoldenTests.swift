import BoarCore
import BoarRAG
import Foundation
import Testing

/// The Swift port must reproduce the TypeScript engine's outputs (scripts/export-native-golden.mjs).
@Suite struct RagPureGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("rag-pure.json") }

    @Test func lexicalQueriesMatchForEveryQuestion() throws {
        let cases = try req(g["lexical"]).arr
        #expect(cases.count > 20)
        for c in cases {
            let q = try req(c["q"]).str!
            let got = RagPure.buildLexicalQuery(q)
            let expected = try req(c["out"])
            if expected.isNull { #expect(got == nil, "q=\(q)"); continue }
            #expect(got?.match == expected["match"]?.str, "match for q=\(q)")
            #expect(got?.terms.map(\.forms) == expected["terms"]?.arr.map { $0["forms"]!.arr.map { $0.str! } }, "terms for q=\(q)")
        }
    }

    @Test func requiredTermMatches() throws {
        for c in try req(g["required"]).arr { #expect(RagPure.requiredTermMatches(c["n"]!.int) == c["out"]!.int) }
    }

    @Test func fusionRanksScoresAndCapsPerArticleTheSameWay() throws {
        for c in try req(g["fuse"]).arr {
            let got = RagPure.fuse(c["lexical"]!.arr.map(goldenChunk), c["semantic"]!.arr.map(goldenChunk), topK: c["topK"]!.int)
            let exp = c["out"]!.arr.map(goldenChunk)
            #expect(got.map(\.chunkId) == exp.map(\.chunkId))
            for (e, a) in zip(exp, got) {
                #expect(abs(e.score - a.score) <= 1e-12)
                #expect(e.matchType == a.matchType)
                #expect(e.similarity == a.similarity)
            }
        }
    }

    @Test func relevanceGateKeepsTheSameChunks() throws {
        let o = try req(g["gate"])
        #expect(RagPure.gateByRelevance(o["in"]!.arr.map(goldenChunk)).map(\.chunkId) == o["out"]!.arr.map(goldenChunk).map(\.chunkId))
    }

    @Test func cosineSimilaritiesMatch() throws {
        for c in try req(g["cosine"]).arr {
            let a = c["a"]!.arr.map { Float($0.dbl) }, b = c["b"]!.arr.map { Float($0.dbl) }
            #expect(abs(RagPure.cosine(a, b) - c["out"]!.dbl) <= 1e-6)
        }
        for c in try req(g["cosineInt8"]).arr {
            let q = c["q"]!.arr.map { Float($0.dbl) }
            let v = Data(c["v"]!.arr.map { UInt8(bitPattern: Int8(truncatingIfNeeded: $0.int)) })
            #expect(abs(RagPure.cosineInt8(q, v) - c["out"]!.dbl) <= 1e-6)
        }
    }

    @Test func promptsAndChatMessagesAreIdentical() throws {
        let prompts = try req(g["prompts"]).arr
        #expect(!prompts.isEmpty)
        for o in prompts {
            var history: ConversationHistory? = nil
            if let h = o["history"], h.objectValue != nil {
                history = ConversationHistory(
                    summary: h["summary"]?.str,
                    turns: h["turns"]?.arr.map { ConversationTurn(role: $0["role"]!.str!, text: $0["text"]!.str!) } ?? []
                )
            }
            let chunks = o["chunks"]!.arr.map(goldenChunk)
            let q = o["query"]!.str!
            #expect(RagPure.assemblePrompt(q, chunks, systemPrompt: o["systemPrompt"]?.str, history: history, styleReminder: o["style"]?.str) == o["prompt"]!.str)
            let msgs = RagPure.assembleChatMessages(q, chunks, systemPrompt: o["systemPrompt"]?.str, history: history, styleReminder: o["style"]?.str)
            let want = o["messages"]!.arr.map { PromptMessage(role: $0["role"]!.str!, content: $0["content"]!.str!) }
            #expect(msgs == want)
        }
        for o in try req(g["prefix"]).arr {
            let p = RagPure.answerPromptPrefix(systemPrompt: o["systemPrompt"]?.str)
            #expect(p.system == o["out"]!["system"]!.str)
            #expect(p.prompt == o["out"]!["prompt"]!.str)
        }
    }
}
