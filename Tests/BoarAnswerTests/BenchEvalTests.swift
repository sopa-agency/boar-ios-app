import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// The Benchmark screen's offline grading must give precheck.py's answers (Fixtures/bench/precheck-golden.jsonl, written by
/// scripts/build-bench.py --golden from the vendored Python), and its summary and traces the boar-eval shapes.
struct BenchEvalTests {
    private static func goldenCases() throws -> [JSONValue] {
        let url = Fixtures.root.appendingPathComponent("Fixtures/bench/precheck-golden.jsonl")
        return try Fixtures.text(url).split(separator: "\n").compactMap { JSONValue(jsonString: String($0)) }
    }

    @Test func precheckMatchesThePythonOnEveryGoldenCase() throws {
        let cases = try Self.goldenCases()
        #expect(cases.count > 300)
        let decoder = JSONDecoder()
        for c in cases {
            let grading = try decoder.decode(BenchGrading.self, from: Data(c["grading"]!.jsonString.utf8))
            let r = Precheck.grade(question: c["question"]!.str!, grading: grading, answer: c["answer"]!.str ?? "", declined: c["declined"]!.flag)
            #expect(r.status.rawValue == c["status"]!.str!, "\(c["itemId"]!.str!) [\(c["note"]!.str!)]")
            #expect(r.why == c["why"]!.str!, "\(c["itemId"]!.str!) [\(c["note"]!.str!)]")
        }
    }

    @Test func bundledBenchIsThePublicSplit() throws {
        let bench = try BenchFile.bundled()
        #expect(bench.sha256 == "568b3ececd8afe5cad63a7f39bffe414e6dd45bcef9d03ef112faecad2981b18")
        #expect(bench.items.count == 60)
        #expect(bench.items.count { $0.grading.checkedOnDevice } == 52)
        let sets = EvalQuestionSet.bundled()
        #expect(sets.map(\.kind) == [.quick, .bench, .smoke])
        #expect(sets[0].queries.count == 12 && sets[0].checkedOnDevice == 12)
        #expect(sets[1].setVersion == "bench-v0.1")
        #expect(sets[2].queries.count == 17 && sets[2].setVersion == "1")
    }

    @Test func benchIdsResolveInDeviceRequests() throws {
        let bench = try BenchFile.bundled().queries
        let request = try DeviceEval.parseRequest(#"{"requestId":"r1","models":["a"],"queries":["lan-exp-001","crypto"]}"#)
        let installed = [ModelRef(id: "a", label: "A")]
        guard case .ok(_, let queries) = DeviceEval.resolve(request, installed: installed, evalSet: [], adaptiveLabel: "x", extraSets: bench) else {
            Issue.record("did not resolve")
            return
        }
        #expect(queries.first?.id == "lan-exp-001")
        #expect(queries.count == 1 + bench.count { $0.category == "crypto" })
    }

    @Test func sourceHitComparesTitlesLoosely() {
        #expect(BenchCheck.sourceHit(reference: [], retrieved: ["X"]) == nil)
        #expect(BenchCheck.sourceHit(reference: ["Mozi"], retrieved: ["mozi "]) == true)
        #expect(BenchCheck.sourceHit(reference: ["São Paulo"], retrieved: ["Sao Paulo"]) == true)
        #expect(BenchCheck.sourceHit(reference: ["Mozi"], retrieved: ["Mohism"]) == false)
    }

    private func row(_ config: String, _ category: String, outcome: String = "success", check: String? = "pass", passed: Bool = true,
                     hit: Bool? = nil, total: Double = 1000, tps: Double = 10) -> JSONValue {
        var o: [String: JSONValue] = ["configId": .string(config), "configLabel": .string(config), "category": .string(category),
                                      "outcome": .string(outcome), "totalLatencyMs": .double(total), "tokPerSec": .double(tps),
                                      "ttftMs": .double(total / 4), "peakRssBytes": .int(100), "modelLoadMs": .double(50)]
        if let check { o["check"] = .string(check); o["checkPassed"] = .bool(passed) }
        if let hit { o["sourceHit"] = .bool(hit) }
        return .object(o)
    }

    @Test func summaryGroupsByModelAndCategory() {
        let rows = [
            row("m:a", "explanation", total: 1000, tps: 10), row("m:a", "explanation", check: "confident-wrong", passed: false, hit: true, total: 3000),
            row("m:a", "reasoning", check: "refused", passed: true, hit: false, total: 2000),
            row("m:a", "venue", check: nil, total: 4000), row("m:a", "venue", outcome: "failure", check: "empty", passed: false, total: 9),
            row("m:b", "explanation", outcome: "cancelled", check: nil, hit: true),
        ]
        let s = EvalSummary(rows: rows)
        #expect(s.configs.map(\.configId) == ["m:a", "m:b"])
        let a = s.configs[0].overall
        #expect(a.answers == 5 && a.failed == 1 && a.checked == 4 && a.passed == 2 && a.wrong == 1 && a.refused == 1)
        #expect(a.sourceItems == 2 && a.sourceHits == 1)
        #expect(a.totalP50Ms == 2500 && a.totalP90Ms == 4000)
        #expect(s.configs[0].categories.map(\.category) == ["explanation", "reasoning", "venue"])
        #expect(s.configs[0].categories[0].stats.passRate == 0.5)
        let b = s.configs[1].overall
        #expect(b.cancelled == 1 && b.checked == 0 && b.sourceItems == 0 && b.totalP50Ms == nil)
    }

    @Test func percentiles() {
        #expect(EvalSummary.median([3, 1, 2]) == 2)
        #expect(EvalSummary.median([4, 1, 2, 3]) == 2.5)
        #expect(EvalSummary.nearestRank(Array(1...10).map(Double.init), 0.9) == 9)
        #expect(EvalSummary.nearestRank(Array(1...20).map(Double.init), 0.9) == 18)
        #expect(EvalSummary.nearestRank([5], 0.9) == 5)
        #expect(EvalSummary.median([]) == nil)
    }

    @Test func traceHasTheProtocolShape() throws {
        let row: JSONValue = [
            "runId": "eval-x", "queryId": "lan-exp-001", "query": "Q?", "modelId": "qwen", "configId": "model:qwen", "answer": "A [1]",
            "retrievedTitles": ["Singapore"], "taskType": "explanation", "reasonCodes": ["eval:fixed-model"], "outcome": "success",
            "ttftMs": 1200.5, "totalLatencyMs": 9000, "tokPerSec": 9.5, "tokensGenerated": 80, "peakRssBytes": 2_097_152,
            "createdAt": 1_760_000_000_123, "appVersion": "0.1.0", "maxTokens": 400,
        ]
        let ctx = EvalTraceExport.Context(appVersion: "0.1.0", build: "1", host: "iPhone14,5 iOS 26.6", ramBytes: 4 * 1_073_741_824)
        let t = EvalTraceExport.trace(row, ctx)
        #expect(t["protocol"]?.str == "1.0.0")
        #expect(t["itemId"]?.str == "lan-exp-001")
        #expect(t["engine"]?["commit"]?.str == "ios-0.1.0+1")
        #expect((t["engine"]?["commit"]?.str?.count ?? 0) >= 7)
        #expect(t["runtime"]?["adapter"]?.str == "ios-app")
        #expect(t["config"]?["device"]?["ramGb"]?.dbl == 4)
        #expect(t["retrieval"]?["kept"]?.arr.first?["title"]?.str == "Singapore")
        #expect(t["answer"]?["declined"]?.boolValue == false)
        #expect(t["timing"]?["outputTokens"]?.int == 80)
        #expect(t["timing"]?["prefillMs"]?.isNullValue == true)
        #expect(t["resources"]?["peakRssMb"]?.dbl == 2)
        #expect(t["error"]?.isNullValue == true)
        #expect(t["createdAt"]?.str == "2025-10-09T08:53:20.123Z")
        for k in ["question", "route", "events"] { #expect(t[k] != nil, "\(k)") }
        // Every versions value is a string (z.record(z.string(), z.string())).
        #expect(t["runtime"]?["versions"]?.obj.values.allSatisfy { $0.stringValue != nil } == true)

        var failed = row.objectValue!
        failed["outcome"] = "failure"
        failed["errorMessage"] = "model failed to load"
        #expect(EvalTraceExport.trace(.object(failed), ctx)["error"]?["code"]?.str == "device-failure")
        // BOAR_TRACE_OUT=<file>: writes the sample traces for `node harness/validate.mjs` in boar-eval.
        if let out = ProcessInfo.processInfo.environment["BOAR_TRACE_OUT"] {
            try EvalTraceExport.jsonl([row, .object(failed)], configId: "model:qwen", ctx).write(toFile: out, atomically: true, encoding: .utf8)
        }
        let two = EvalTraceExport.jsonl([row, .object(failed.merging(["configId": "model:other"]) { $1 })], configId: "model:qwen", ctx)
        #expect(two.split(separator: "\n").count == 1)
    }
}
