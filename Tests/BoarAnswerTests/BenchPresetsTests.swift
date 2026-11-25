import BoarCore
import BoarModels
import CryptoKit
import Foundation
import Testing

@testable import BoarAnswer

/// Android's BenchPresetsTest (v2.0.0, t9 0521 items 1-3 and 8): the fixed set unchanged, the topic files, levels and the
/// expected time.
struct BenchPresetsTests {
    static let sets = try! EvalSets.bundled()
    static let topics = BenchTopic.bundled()
    static let small = ModelRef(id: BenchPresets.smallModel, label: "Qwen3-1.7B")
    static let large = ModelRef(id: BenchPresets.largeModel, label: "Qwen3-4B")
    static let phi = ModelRef(id: "phi-3.5-mini-instruct-q4km", label: "Phi")

    private var sets: EvalSets { Self.sets }
    private var topics: [String: BenchTopic] { Self.topics }

    @Test func theSeventeenAndTheSixStayByteForByte() throws {
        let data = try BoarData.data(.evalSet)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "1f4b8f487bbba8b235701e7138088481c55e4906858cab22343e11d986a16629")
        #expect(sets.evalSet.count == 17)
        #expect(sets.extraSets.count == 6)
        #expect(sets.evalSet.map(\.id) == ["greeting-1", "factual-1", "factual-2", "explanation-1", "explanation-2", "comparison-1", "comparison-2",
                                           "synthesis-1", "synthesis-2", "synthesis-3", "reasoning-1", "reasoning-2", "reasoning-3", "grounded-1", "grounded-2",
                                           "no-kb-1", "no-kb-2"])
        #expect(sets.evalSet.allSatisfy { $0.setVersion == "1" })
    }

    @Test func theCoreTopicRunsTheSeventeenExactlyAsTheSetHasThem() throws {
        #expect(try topics["core"]!.queries(sets) == sets.evalSet)
        #expect(try topics["vitalik"]!.queries(sets) == sets.extraSets)
    }

    @Test func everyTopicFileParsesIsReviewedByT9AndItsQuestionsResolve() throws {
        #expect(Set(topics.keys) == ["core", "vitalik", "plugins", "problems", "howto", "research", "quick", "cards", "portuguese", "health"])
        for t in topics.values {
            #expect(t.status == "reviewed by t9, 14 Nov", "\(t.id)")
            let qs = try t.queries(sets)
            #expect(qs.count == Set(qs.map(\.id)).count, "\(t.id)")
            for q in t.questions where !q.fromSet {
                #expect(qs.first { $0.id == q.id }?.setVersion == "\(t.id)-v1")
            }
        }
    }

    @Test func cardsHasTheFourteenQuestionsPortugueseTheThirtyOfTheLanguageFix() throws {
        let cards = try topics["cards"]!.queries(sets)
        #expect(cards.count == 14)
        #expect(cards.first?.query == "How do you purify water in the wild, step by step?")
        #expect(cards.last?.query == "Como purificar água na natureza, passo a passo?")
        let pt = try #require(topics["portuguese"])
        #expect(pt.questions.count == 30)
        #expect(pt.questions.allSatisfy { $0.id.hasPrefix("pt-") && $0.rules?.language == "pt" })
    }

    @Test func theNewestVersionOfATopicWins() {
        #expect(BenchTopic.newest(["a.v1.json", "b.v1.json", "a.v2.json", "README.md"]) == ["a.v2.json", "b.v1.json"])
        #expect(BenchTopic.fileName("plugins.json") == nil)
    }

    @Test func presetNamesALevelAloneIsTheSeventeenATopicAfterADash() {
        #expect(BenchPresets.parse("fast") == BenchPreset(.fast, ["core"]))
        #expect(BenchPresets.parse("fast-plugins") == BenchPreset(.fast, ["plugins"]))
        #expect(BenchPresets.parse("medium-research") == BenchPreset(.medium, ["research"]))
        #expect(BenchPresets.parse("slow-plugins") == nil)
        #expect(BenchPreset(.complete, ["research"]).name == "complete-research")
        #expect(BenchPreset(.fast, ["core"]).name == "fast")
    }

    @Test func fastTakesTheSmallModelOrTheOnlyOneMediumAndCompleteTakeBoth() {
        #expect(BenchPresets.models(.fast, installed: [Self.phi, Self.large, Self.small]) == [Self.small])
        #expect(BenchPresets.models(.fast, installed: [Self.large]) == [Self.large])
        #expect(BenchPresets.models(.medium, installed: [Self.phi, Self.large, Self.small]) == [Self.small, Self.large])
        #expect(BenchPresets.models(.complete, installed: [Self.phi, Self.large]) == [Self.large, Self.phi])
    }

    private func plan(_ name: String) throws -> BenchPlan {
        try #require(BenchPresets.plan(BenchPresets.parse(name)!, installed: [Self.small, Self.large], topics: topics, sets: sets).plan)
    }

    @Test func levelsSetTheStylesDeepResearchOnlyAtCompleteAndOnlyForTheResearchTopic() throws {
        #expect(try plan("fast").passes.map(\.key) == ["succinct"])
        #expect(try plan("medium-plugins").passes.map(\.key) == ["succinct"])
        #expect(try plan("complete").passes.map(\.key) == ["succinct", "detailed"])
        let research = try plan("complete-research")
        #expect(research.passes.map(\.key) == ["succinct", "detailed", "deep"])
        #expect(research.queries.count == research.passQueries["deep"]?.count)
        #expect(research.answers == 2 * 3 * research.queries.count)
        #expect(try plan("fast").answers == 17)
        #expect(try plan("fast-plugins").labs == topics["plugins"]?.labs)
        let plugins = try plan("fast-plugins")
        #expect(plugins.queries.allSatisfy { plugins.topicOf[$0.id] == "plugins" })
        #expect(BenchPresets.plan(BenchPresets.parse("fast-nope")!, installed: [Self.small], topics: topics, sets: sets).error != nil)
        #expect(BenchPresets.plan(BenchPresets.parse("fast")!, installed: [], topics: topics, sets: sets).error != nil)
    }

    @Test func expectedTimeFromTheF3MediansThenFromTheLastRunOfTheLevel() throws {
        #expect(abs(BenchPresets.estimate(try plan("fast")).seconds - 17 * 8.9) <= 1e-6)
        #expect(abs(BenchPresets.estimate(try plan("medium")).seconds - 17 * (8.9 + 26.8)) <= 1e-6)
        // complete: about 3.9 min a question
        #expect(abs(BenchPresets.estimate(try plan("complete")).seconds / 17 - 232.7) <= 1e-6)
        let deep = BenchPresets.estimate(try plan("complete-research"))
        #expect(deep.untimed == 2 * (try plan("complete-research")).queries.count)
        let previous = [
            JSONValue(jsonString: #"{"modelId":"\#(Self.small.id)","style":"succinct","outcome":"success","totalLatencyMs":4000}"#)!,
            JSONValue(jsonString: #"{"modelId":"\#(Self.small.id)","style":"succinct","outcome":"success","totalLatencyMs":6000}"#)!,
        ]
        let e = BenchPresets.estimate(try plan("fast"), previousRows: previous)
        #expect(abs(e.seconds - 17 * 5.0) <= 1e-6)
        #expect(e.fromPrevious)
    }

    @Test func aRequestCanAskForAPresetByNameOrByLevelAndTopics() throws {
        #expect(try DeviceEval.parseRequest(#"{"requestId":"p1","preset":"fast-plugins"}"#).preset == BenchPreset(.fast, ["plugins"]))
        #expect(try DeviceEval.parseRequest(#"{"requestId":"p2","level":"medium","topics":["cards","portuguese"]}"#).preset == BenchPreset(.medium, ["cards", "portuguese"]))
        #expect(try DeviceEval.parseRequest(#"{"requestId":"p3"}"#).preset == nil)
        for bad in [#"{"requestId":"p4","preset":"slow"}"#, #"{"requestId":"p5","level":"x"}"#, #"{"requestId":"p6","preset":"fast","queries":["factual-1"]}"#] {
            #expect(throws: EvalRequestError.self, "\(bad)") { try DeviceEval.parseRequest(bad) }
        }
    }
}

/// Android's SearchOnlyRequestTest (t9 0321): the bench's search-only request, from a connected computer only; the
/// sources with their scores, no answer. Android's request carries an outside question set ("questions", legacy pipeline),
/// which iOS doesn't take: the request here names the fixed set's ids instead.
struct SearchOnlyRequestTests {
    @Test func aRequestAsksForItWithABooleanAndNothingElseDoes() throws {
        #expect(try DeviceEval.parseRequest(#"{"requestId":"s1","queries":["factual-1"],"searchOnly":true}"#).searchOnly == true)
        #expect(try DeviceEval.parseRequest(#"{"requestId":"s2","queries":["factual-1"]}"#).searchOnly == nil)
        #expect(throws: EvalRequestError("\"searchOnly\" must be a boolean")) {
            try DeviceEval.parseRequest(#"{"requestId":"s3","searchOnly":"yes"}"#)
        }
    }
}
