import Foundation
import Testing

@testable import BoarAnswer

/// Android's BenchLogTest and BenchVitalsTest (adam, Nov 12 and 14), on the Benchmark screen: iOS has no BenchActivity,
/// so the log and the vitals card sit on top of the Benchmark screen while a run goes.
struct BenchLogTests {
    @Test func newestLineFirstTheLastSixtyAndTheClock() {
        let lines = (1...70).map { "line \($0)" }
        let shown = BenchLog.newestFirst(lines)
        #expect(shown.count == BenchLog.max)
        #expect(shown.first == "line 70")
        #expect(shown.last == "line 11")
        #expect(BenchLog.newestFirst(["a", "b"]) == ["b", "a"])
        #expect(BenchLog.since(ms: 42_400) == (nil, 42))
        #expect(BenchLog.since(ms: 125_000) == (2, 5))
        #expect(BenchLog.since(ms: -5) == (nil, 0))
    }

    @Test func theVitalsAndTheLogAreTheFirstSectionsWhileItRuns() throws {
        let screen = try AppSource.text("App/Features/Evaluation/EvaluationScreen.swift")
        let vitals = try #require(screen.range(of: "EvalVitalsSection()")?.lowerBound)
        let log = try #require(screen.range(of: "EvalLogSection(controller: controller)")?.lowerBound)
        let preset = try #require(screen.range(of: "EvalPresetSection(controller: controller)")?.lowerBound)
        #expect(vitals < log && log < preset)
        let section = try AppSource.text("App/Features/Evaluation/EvalLogSection.swift")
        #expect(section.contains("BenchLog.newestFirst(controller.log)") && section.contains("BenchLog.since(ms:"))
    }

    @Test func eachQuestionSaysItStarted() throws {
        let runner = try AppSource.text("App/Features/Evaluation/EvalRunner.swift")
        let said = try #require(runner.range(of: #"say("[EVAL] \(q.id): answering on \(modelId) (\(pass.key))…")"#)?.lowerBound)
        let answered = try #require(runner.range(of: "var r = pass.deep")?.lowerBound)
        #expect(said < answered)
    }

    @Test func theVitalsReadHeatBatteryAndMemoryEverySecondWithNoPlugin() throws {
        let vitals = try AppSource.text("App/Features/Evaluation/EvalLogSection.swift")
        for k in ["PhoneReads.readPhone()", "AppMemory.footprintBytes()", ".seconds(1)", "heatLevel", "batteryPct", "ramFreeMb"] {
            #expect(vitals.contains(k), "\(k)")
        }
        #expect(!vitals.contains("Labs.shared"))
    }
}

/// The runner's preset passes (DeviceEvalRunner, Nov 14): each pass's style and length, the chat's short-answer rules,
/// the plugins slot as in the chat, and every row saying its style, level and topic.
struct BenchRunnerWiringTests {
    private let runner = (try? AppSource.text("App/Features/Evaluation/EvalRunner.swift")) ?? ""

    @Test func eachPassAnswersInItsStyleWithTheChatsRules() {
        for k in ["AppSettings.autoMaxTokens(personalityId: runStyle)", "ShortAnswer.reason(chosenStyle: runStyle",
                  "personalities.promptFor(style, customPrompt: nil, smallModel: small)", "Personalities.smallModelBytes",
                  "ShortAnswer.isSmallTalk(q.query) ? min(maxTokens, AppSettings.defaultMaxTokens) : maxTokens"] {
            #expect(runner.contains(k), "\(k)")
        }
    }

    @Test func thePluginsAnswerAsInTheChat() {
        for k in ["PhoneReads.prepare(query: q.query, active: labs.active)", "AnswerTools.run(labs.tools", "case .instant(let code, let text)? = tool",
                  #"("reasonCodes", JSONValue(strings: ["answer:\(tool)"]))"#, "AnswerTools.systemPrompt(systemPrompt, tool)",
                  "AnswerChecks.run(labs.checks"] {
            #expect(runner.contains(k), "\(k)")
        }
    }

    @Test func everyRowSaysItsStyleLevelAndTopicAndTheRunIsKept() {
        for k in [#"("style", .string(runStyle))"#, #"("level", .string(plan.preset.level.id))"#, #"("topic", .string(t))"#,
                  #"("labsOn", JSONValue(strings: ids))"#, "store.writeMeta(meta)", "store.scorecardFile(runId)", "store.previous(meta"] {
            #expect(runner.contains(k), "\(k)")
        }
    }

    @Test func completeRunsDeepResearchAsTheChatDoes() {
        for k in ["DeepResearch(generator: SessionEngine(s), retriever: services.retriever)", #"("path", .string(BenchPass.pathDeep))"#,
                  "AnswerLanguage.line(AnswerLanguage.of(q.query), withSources: true)"] {
            #expect(runner.contains(k), "\(k)")
        }
    }
}

/// Android's SearchOnlyRequestTest, the wiring half (t9 0321): only a device request reaches search-only; the Benchmark
/// screen never does.
struct SearchOnlyWiringTests {
    @Test func onlyADeviceRequestReachesItTheBenchmarkScreenNeverDoes() throws {
        let runner = try AppSource.text("App/Features/Evaluation/EvalRunner.swift")
        let controller = try AppSource.text("App/Features/Evaluation/EvaluationController.swift")
        #expect(controller.contains("searchOnly: request.searchOnly == true"))
        #expect(runner.contains("if searchOnly {\n") && runner.contains("row = await searchRow("))
        // The row: every source with its similarity, score, match and kind; no answer.
        for k in [#"("retrievedSources", .array(sources))"#, #""kind""#, #""similarity""#, #"("path", "search-only")"#, #"("answer", "")"#] {
            #expect(runner.contains(k), "\(k)")
        }
        let screens = try AppSource.swiftFiles(under: "App").filter { !$0.hasSuffix("EvalRunner.swift") && !$0.hasSuffix("EvaluationController.swift") }
        #expect(try screens.allSatisfy { try !AppSource.text($0).contains("searchOnly") })
    }
}
