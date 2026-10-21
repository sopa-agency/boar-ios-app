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
}
#endif
