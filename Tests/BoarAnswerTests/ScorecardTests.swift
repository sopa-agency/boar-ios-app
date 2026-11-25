import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// Android's ScorecardTest (v2.0.0, t9 0521 item 4): what the computer scores, "to read" for the rest, and the comparison
/// with the previous run.
struct ScorecardTests {
    private let topics = BenchPresetsTests.topics

    private func row(_ s: String) -> JSONValue { JSONValue(jsonString: s)! }
    private func plugin(_ id: String, _ tool: String?, _ answer: String, topic: String? = "plugins") -> JSONValue {
        var o: [String: JSONValue] = ["queryId": .string(id), "modelId": "m", "style": "succinct", "outcome": "success", "answer": .string(answer)]
        if let tool { o["tool"] = .string(tool) }
        if let topic { o["topic"] = .string(topic) }
        return .object(o)
    }

    @Test func aPluginsExactTextAndRoutePassAnythingElseFails() {
        #expect(Scorecard.judge(plugin("calc-battery-en", "calculator-battery", "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh."), topics).verdict == .pass)
        #expect(Scorecard.judge(plugin("calc-battery-en", "calculator-battery", "About 19 Wh."), topics).verdict == .fail)
        let noPlugin = Scorecard.judge(plugin("calc-battery-en", nil, "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh."), topics)
        #expect(noPlugin.checks.filter { $0.ok == false }.map(\.rule) == ["tool"])
        #expect(Scorecard.judge(plugin("calc-health-left-alone", nil, "104 °F. Call a doctor."), topics).verdict == .pass)
        #expect(Scorecard.judge(plugin("calc-health-left-alone", "temperature-conversion", "40 °C = 104 °F"), topics).verdict == .fail)
    }

    @Test func noQuestionRuleMeansToReadAFailedAnswerAlwaysFails() {
        #expect(Scorecard.judge(row(#"{"queryId":"explanation-1","outcome":"success","answer":"..."}"#), topics).verdict == .toRead)
        #expect(Scorecard.judge(row(#"{"queryId":"explanation-1","outcome":"failure","answer":""}"#), topics).verdict == .fail)
    }

    @Test func oldRowsFindTheirTopicByQuestionId() {
        let all = Array(topics.values)
        #expect(Scorecard.topicOf(row(#"{"queryId":"factual-1"}"#), all) == "core")
        #expect(Scorecard.topicOf(row(#"{"queryId":"pt-short-1"}"#), all) == "portuguese")
        #expect(Scorecard.topicOf(row(#"{"queryId":"warmup-000"}"#), all) == "custom")
    }

    @Test func languageCitationsNumbersCardsAndKeptShortAreReadFromTheAnswer() {
        let r = TopicRules(language: "pt", citesOnlyRealSources: true, numbers: [NumberRule(8849, tolerance: 0.001)], cards: ["chart"], minChartPoints: 3)
        // One enumeration: CardRules reads "K2" there; as a list line ("- K2: 8.611 m") its label can't hold a digit.
        let good = row(#"{"query":"Quais são as três montanhas mais altas?","answer":"As três montanhas mais altas do mundo são o Everest com 8.849 m [1], o K2 com 8.611 m e o Kangchenjunga com 8.586 m.","retrievedTitles":["Mount Everest"]}"#)
        #expect(Scorecard.check(good, r).allSatisfy { $0.ok == true }, "\(Scorecard.check(good, r))")
        let bad = row(#"{"query":"Quais são as três montanhas mais altas?","answer":"The highest is Everest at 8,000 m [3].","retrievedTitles":["Mount Everest"]}"#)
        #expect(Set(Scorecard.check(bad, r).filter { $0.ok == false }.map(\.rule)) == ["language", "citesOnlyRealSources", "numbers", "cards", "minChartPoints"])
        #expect(Scorecard.numbersIn("Dá 99,9 Wh.") == [99.9])
        #expect(Scorecard.numbersIn("27.000 mAh a 3,7 V") == [27000, 3.7])
        let short = TopicRules(keptShort: true)
        #expect(Scorecard.check(row(#"{"personalityId":"succinct","answer":"x"}"#), short).map(\.ok) == [true])
        #expect(Scorecard.check(row(#"{"personalityId":"detailed","answer":"x"}"#), short).map(\.ok) == [false])
    }

    @Test func aRuleAnOldRowCantAnswerDoesntCount() {
        let r = TopicRules(noFileSources: true)
        #expect(Scorecard.check(row(#"{"answer":"x"}"#), r).map(\.ok) == [nil])
        #expect(Scorecard.check(row(#"{"answer":"x","fileSources":["notes.pdf"]}"#), r).map(\.ok) == [false])
        #expect(Scorecard.check(row(#"{"answer":"x","fileSources":[]}"#), r).map(\.ok) == [true])
    }

    @Test func theScorecardAgainstThePreviousRunUpDownSame() throws {
        let now = [
            plugin("calc-battery-en", "calculator-battery", "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh."),
            plugin("calc-conversion", "calculator-conversion", "42 km = 26.1 miles (1 mile = 1.609344 km)."),
            plugin("compass-north", "compass-heading", "Your phone points east."),
        ]
        let before = [
            plugin("calc-battery-en", "calculator-battery", "wrong"),
            plugin("calc-conversion", "calculator-conversion", "42 km = 26.1 miles (1 mile = 1.609344 km)."),
            plugin("compass-north", nil, "North is that way."),
        ]
        let card = Scorecard.of(now, topics: topics, previous: before)
        let line = try #require(card.topics.first)
        #expect(card.topics.count == 1)
        #expect(line.topic == "plugins")
        #expect(line.passed == 3 && line.checked == 3)
        #expect(line.previousPassed == 1)
        #expect(line.trend == .up)
        #expect(Scorecard.of(before, topics: topics, previous: now).topics.first?.trend == .down)
        #expect(Scorecard.of(now, topics: topics, previous: now).topics.first?.trend == .same)
        #expect(Scorecard.of(now, topics: topics).topics.first?.trend == nil)
        #expect(Scorecard.text(card).contains("plugins      3/3 (was 1/3) up"))
    }

    @Test func oneLinePerModelAndPassFirstWordWholeAnswerPeakMemory() throws {
        let rows = [
            row(#"{"queryId":"a","modelId":"m1","style":"succinct","outcome":"success","ttftMs":1000,"totalLatencyMs":8000,"peakRssBytes":2.0e9}"#),
            row(#"{"queryId":"b","modelId":"m1","style":"succinct","outcome":"success","ttftMs":3000,"totalLatencyMs":10000,"peakRssBytes":2.5e9}"#),
            row(#"{"queryId":"a","modelId":"m1","style":"detailed","path":"deep","outcome":"success","ttftMs":9000,"totalLatencyMs":90000}"#),
        ]
        let models = Scorecard.of(rows, topics: topics).models
        #expect(models.map(\.pass) == ["succinct", "deep"])
        #expect(abs(try #require(models[0].firstWordMs) - 2000) <= 1e-9)
        #expect(abs(try #require(models[0].wholeAnswerMs) - 9000) <= 1e-9)
        #expect(abs(try #require(models[0].peakRssBytes) - 2.5e9) <= 1e-3)
    }
}

/// t9 1058: a failure with a known issue shows apart from a regression; a question whose plugin is off is skipped.
struct ScorecardKnownSkippedTests {
    private func row(_ id: String, _ answer: String, labs: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["queryId": .string(id), "answer": .string(answer), "outcome": "success", "topic": "t"]
        if let labs { o["labsOn"] = JSONValue(strings: labs) }
        return .object(o)
    }

    private let topic = BenchTopic(id: "t", version: 1, title: "T", questions: [
        TopicQuestion(id: "known", query: "q?", rules: TopicRules(answerHas: ["right"]), knownIssue: "a fix"),
        TopicQuestion(id: "plain", query: "q?", rules: TopicRules(answerHas: ["right"])),
        TopicQuestion(id: "lab", query: "q?", rules: TopicRules(answerHas: ["right"]), needsLab: "polyglot"),
    ])

    @Test func knownFailuresAndSkippedQuestionsAreCountedApart() throws {
        let card = Scorecard.of([row("known", "wrong"), row("plain", "right"), row("lab", "right", labs: ["calc"])], topics: ["t": topic])
        #expect(card.rows[0].verdict == .known)
        #expect(card.rows[2].verdict == .skipped)
        let line = try #require(card.topics.first)
        #expect(line.passed == 1 && line.checked == 1 && line.known == 1 && line.skipped == 1)
        #expect(Scorecard.text(card).contains("1 known issues") && Scorecard.text(card).contains("1 skipped (plugin off)"))
        // With its plugin on, the question is asked and judged.
        #expect(Scorecard.judge(row("lab", "right", labs: ["polyglot"]), ["t": topic]).verdict == .pass)
    }

    @Test func answerHasEachNeedsOneWordingOfEveryFactBrazilAndRussiasAreaRatio() throws {
        let r = try #require(BenchPresetsTests.topics["problems"]?.questions.first { $0.id == "compare-brazil-russia" }?.rules)
        // The F3's all66 answer: the right areas, the wrong ratio.
        let f3 = JSONValue(jsonString: #"{"answer":"Russia spans 17,075,400 km². Russia's area is roughly three-quarters of the size of Brazil."}"#)!
        #expect(Set(Scorecard.check(f3, r).filter { $0.ok == false }.map(\.rule)) == ["answerHasEach", "answerHasNot"])
        let right = JSONValue(jsonString: #"{"answer":"Russia (17,075,400 km²) is about twice the size of Brazil (8,515,767 km²)."}"#)!
        #expect(!Scorecard.check(right, r).contains { $0.ok == false }, "\(Scorecard.check(right, r))")
    }
}
