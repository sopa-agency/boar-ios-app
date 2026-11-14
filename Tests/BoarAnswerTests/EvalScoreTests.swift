import BoarCore
import Testing

@testable import BoarAnswer

/// android EvalScoreTest.kt (the cases of src/eval/score.test.ts), so the phone's score matches Android's and the server's.
struct EvalScoreTests {
    private typealias Row = EvalScore.Row

    private func row(configId: String = "model:a", tokPerSec: Double? = 10, tokensGenerated: Double? = 100,
                     outcome: String = "success", timedOut: Bool = false, expectedKbHit: Bool? = nil, ttftMs: Double? = 2000,
                     peakRssBytes: Double? = nil) -> Row {
        Row(configId: configId, configLabel: "Model A", modelId: "a", outcome: outcome, timedOut: timedOut,
            tokensGenerated: tokensGenerated, tokPerSec: tokPerSec, ttftMs: ttftMs, totalLatencyMs: 12000,
            expectedKbHit: expectedKbHit, peakRssBytes: peakRssBytes)
    }

    @Test func medianMatchesPercentileCont() {
        #expect(EvalScore.median([3, 1, 2]) == 2)
        #expect(EvalScore.median([4, 1, 3, 2]) == 2.5)
        #expect(EvalScore.median([]) == nil)
    }

    @Test func weightsSpeed60Reliability25Retrieval15() {
        #expect(EvalScore.scoreParts(speed: 1, reliability: 1, retrieval: 1) == 100)
        #expect(EvalScore.scoreParts(speed: 0.5, reliability: 1, retrieval: 1) == 70)
        #expect(EvalScore.scoreParts(speed: 1, reliability: 1, retrieval: 0) == 85)
    }

    @Test func rescalesWhenNoQuestionExpectedAnArticle() {
        #expect(EvalScore.scoreParts(speed: 1, reliability: 1, retrieval: nil) == 100)
        #expect(EvalScore.scoreParts(speed: 0.5, reliability: 1, retrieval: nil) == 65)
    }

    @Test func zeroBelowHalfTheAnswersCompleted() {
        #expect(EvalScore.scoreParts(speed: 1, reliability: 0.49, retrieval: 1) == 0)
        #expect(EvalScore.scoreParts(speed: 1, reliability: 0.5, retrieval: 1) == 88)
    }

    @Test func speedOnlyOnCompletedAnswersOf16TokensOrMore() {
        let s = EvalScore.scoreConfig([row(tokPerSec: 10), row(tokPerSec: 30), row(tokPerSec: 99, tokensGenerated: 9),
                                       row(tokPerSec: 99, outcome: "failure")])
        #expect(s.medianTokPerSec == 20)
        #expect(s.speed == 1)
        #expect(s.reliability == 0.75)
    }

    @Test func aTimedOutAnswerIsNotCompleted() {
        #expect(EvalScore.scoreConfig([row(), row(timedOut: true)]).completed == 1)
    }

    @Test func retrievalOnlyOnQuestionsThatExpectAnArticle() {
        let s = EvalScore.scoreConfig([row(expectedKbHit: true), row(expectedKbHit: false), row(expectedKbHit: nil)])
        #expect([s.retrievalQuestions, s.retrievalHits] == [2, 1])
        #expect(s.retrieval == 0.5)
    }

    @Test func keepsTheRawMetrics() {
        let s = EvalScore.scoreConfig([row(ttftMs: 1000, peakRssBytes: 5), row(ttftMs: 3000, peakRssBytes: 9)])
        #expect(s.medianTtftMs == 2000)
        #expect(s.medianTotalMs == 12000)
        #expect(s.peakRssBytes == 9)
        #expect(s.modelLabel == "Model A")
    }

    @Test func bestFirst() {
        let scores = EvalScore.scoreRun([row(configId: "slow", tokPerSec: 4), row(configId: "fast", tokPerSec: 20)])
        #expect(scores.map(\.configId) == ["fast", "slow"])
    }

    @Test func readsARunnerRow() throws {
        let o = try #require(JSONValue(jsonString: """
            {"configId":"model:q","configLabel":"Q","modelId":"q","outcome":"success","timedOut":false,
            "tokensGenerated":120,"tokPerSec":21.3,"ttftMs":4300,"totalLatencyMs":23000,"expectedKbHit":true,"peakRssBytes":null}
            """))
        #expect(Row(o) == Row(configId: "model:q", configLabel: "Q", modelId: "q", outcome: "success", timedOut: false,
                              tokensGenerated: 120, tokPerSec: 21.3, ttftMs: 4300, totalLatencyMs: 23000, expectedKbHit: true,
                              peakRssBytes: nil))
    }

    /// iOS only: the research bench's rows name it `sourceHit`.
    @Test func readsABenchRowsSourceHit() throws {
        let o = try #require(JSONValue(jsonString: #"{"configId":"model:q","outcome":"success","sourceHit":false}"#))
        #expect(Row(o).expectedKbHit == false)
        let both = try #require(JSONValue(jsonString: #"{"configId":"model:q","expectedKbHit":true,"sourceHit":false}"#))
        #expect(Row(both).expectedKbHit == true)
    }
}
