#if DEBUG
import BoarAnswer
import BoarCore
import Foundation

/// A finished two-model Quick check for the UI audit (`-uiDemo -uiScreen evaluation`): made-up numbers in the shape of
/// real rows, never saved or shared as a result.
enum EvalDemo {
    private static let models = [
        (id: "qwen2.5-1.5b-instruct-q4km", label: "Qwen2.5-1.5B-Instruct (Q4_K_M)", seconds: 21.0, rate: 14.2, peak: 1_450_000_000 as Int64, load: 1_480.0,
         checks: ["pass", "pass", "fail-missing", "pass", "confident-wrong", "pass", "fail-missing", "pass", "pass", "refused", "fail-missing", "pass"]),
        (id: "qwen3-4b-instruct-2507-q4km", label: "Qwen3-4B-Instruct-2507 (Q4_K_M)", seconds: 44.0, rate: 6.6, peak: 3_050_000_000 as Int64, load: 4_210.0,
         checks: ["pass", "pass", "pass", "pass", "fail-missing", "pass", "pass", "pass", "pass", "refused", "pass", "pass"]),
    ]

    static func run(queries: [EvalQuery]) -> (configs: [EvalConfig], rows: [JSONValue]) {
        let runId = "eval-2026-10-16T19-40-00-000Z"
        var rows: [JSONValue] = []
        for (mi, m) in models.enumerated() {
            for (qi, q) in queries.enumerated() {
                let check = m.checks[qi % m.checks.count]
                let total = (m.seconds + Double((qi * 7 + mi * 3) % 11) * 1.7) * 1000
                let why = switch check {
                case "fail-missing": q.grading?.mustAny.first?.first ?? ""
                case "confident-wrong": q.grading?.forbid.first?.first ?? ""
                case "refused": "ok"
                default: ""
                }
                let hit: JSONValue? = q.referenceTitles.isEmpty ? nil : .bool((qi + mi) % 3 != 0)
                let o: [String: JSONValue?] = [
                    "runId": .string(runId), "configId": .string("model:\(m.id)"), "configLabel": .string(m.label), "modelId": .string(m.id),
                    "queryId": .string(q.id), "query": .string(q.query), "category": .string(q.category), "outcome": "success",
                    "answer": "Demo answer: the audit build shows the layout with made-up results.", "totalLatencyMs": .double(total),
                    "ttftMs": .double(total * 0.22), "tokPerSec": .double(m.rate + Double(qi % 3) * 0.4), "tokensGenerated": 180,
                    "peakRssBytes": .int(m.peak), "modelLoadMs": .double(qi == 0 ? m.load : 0), "retrievalUsed": true,
                    "retrievedTitles": JSONValue(strings: Array(q.referenceTitles.prefix(1))), "taskType": "explanation",
                    "benchSet": .string(q.setVersion), "check": .string(check), "checkWhy": .string(why),
                    "checkPassed": .bool(check == "pass" || check == "refused"), "sourceHit": hit,
                ]
                rows.append(.object(o.compactMapValues { $0 }))
            }
        }
        return (models.map { .model(modelId: $0.id, label: $0.label) }, rows)
    }

    /// A finished Fast · plugins run (`-uiScreen evaluation-preset`): each question answered as its topic's rule wants,
    /// a few wrong ones, and the run before it with more wrong, so the scorecard shows a trend.
    static func preset(_ plan: BenchPlan, topics: [String: BenchTopic], appVersion: String)
        -> (runId: String, rows: [JSONValue], previous: [JSONValue], saved: [RunMeta]) {
        let runId = "eval-2026-11-24T21-05-00-000Z"
        let model = plan.models.first ?? ModelRef(id: BenchPresets.smallModel, label: "Qwen3-1.7B")
        func rows(wrong: Set<Int>) -> [JSONValue] {
            plan.queries.enumerated().map { i, q in
                let topic = plan.topicOf[q.id]
                let rules = topic.flatMap { topics[$0]?.question(q.id)?.rules }
                var answer = rules?.answerIs ?? rules?.answerStartsWith.map { $0 + ", in 1969 and 1972 (Apollo 11 to 17)." }
                    ?? rules?.answerHas.joined(separator: " · ") ?? "Demo answer: the audit build shows the layout with made-up results."
                var tool = rules?.tool
                if wrong.contains(i) {
                    answer = "Demo answer written by the model instead of the plugin."
                    tool = nil
                }
                let ms = tool != nil ? 40.0 + Double(i % 5) * 12 : 6_800.0 + Double(i % 4) * 900
                let o: [String: JSONValue?] = [
                    "runId": .string(runId), "configId": .string("model:\(model.id)"), "configLabel": .string(model.label),
                    "modelId": .string(model.id), "queryId": .string(q.id), "query": .string(q.query), "category": .string(q.category),
                    "outcome": "success", "answer": .string(answer), "tool": tool.map(JSONValue.string), "totalLatencyMs": .double(ms),
                    "ttftMs": .double(tool != nil ? ms : ms * 0.2), "tokPerSec": tool != nil ? nil : .double(13.8 + Double(i % 3) * 0.5),
                    "tokensGenerated": tool != nil ? 0 : 90, "peakRssBytes": .int(1_520_000_000 + Int64(i % 4) * 30_000_000),
                    "modelLoadMs": .double(i == 0 ? 1_950 : 0), "retrievalUsed": false, "retrievedTitles": .array([]),
                    "reasonCodes": tool.map { JSONValue(strings: ["answer:\($0)"]) }, "taskType": "factual", "personalityId": "succinct",
                    "style": "succinct", "level": .string(plan.preset.level.id), "topic": topic.map(JSONValue.string),
                    "labsOn": plan.labs.map { JSONValue(strings: $0) }, "appVersion": .string(appVersion),
                ]
                return .object(o.compactMapValues { $0 })
            }
        }
        let now = rows(wrong: [6, 13])
        let before = rows(wrong: [2, 6, 9, 13, 17])
        let saved = [
            RunMeta(runId: runId, createdAt: 1_795_554_300_000, appVersion: appVersion, models: [model.id], level: plan.preset.level.id,
                    topics: plan.preset.topics, passes: plan.passes.map(\.key), state: RunMeta.stateDone, rows: now.count),
            RunMeta(runId: "eval-2026-11-23T18-12-00-000Z", createdAt: 1_795_457_520_000, appVersion: appVersion, models: [model.id],
                    level: plan.preset.level.id, topics: plan.preset.topics, passes: ["succinct"], state: RunMeta.stateDone, rows: before.count),
            RunMeta(runId: "eval-2026-11-22T09-30-00-000Z", createdAt: 1_795_339_800_000, appVersion: appVersion,
                    models: [model.id, BenchPresets.largeModel], level: BenchLevel.medium.id, topics: [BenchPresets.core], passes: ["succinct"],
                    source: "request", requestId: "medium-core", state: RunMeta.stateStopped, rows: 21),
            RunMeta(runId: "eval-2026-11-20T16-45-00-000Z", createdAt: 1_795_193_100_000, appVersion: "2.0.0-rc3", models: [model.id],
                    state: RunMeta.stateInterrupted, rows: 9),
        ]
        return (runId, now, before, saved)
    }
}
#endif
