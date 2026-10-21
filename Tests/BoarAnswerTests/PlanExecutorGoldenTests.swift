import BoarCore
import BoarRAG
import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// The adaptive-routing executor must load, prompt and report as src/routing/executor.ts does
/// (scripts/export-native-golden-executor.mjs: real plans, recording stand-ins for the engine and retrieval).
struct PlanExecutorGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("executor.json") }

    private func plan(_ o: JSONValue) throws -> Router.RoutingPlan {
        Router.RoutingPlan(
            steps: try o["steps"]!.arr.map { s in
                Router.RoutingStep(
                    id: s["id"]!.str!, type: try #require(RoutingStepType.of(s["type"]!.str!)), modelId: s["modelId"]?.str, required: s["required"]!.flag,
                    maxTokens: s.opt("maxTokens")?.intValue, timeoutMs: s.opt("timeoutMs")?.int64Value
                )
            },
            selectedModelIds: o["selectedModelIds"]!.strs,
            estimatedCost: Router.CostEstimate(modelSwitches: o["estimatedCost"]!["modelSwitches"]!.int),
            fallbackPolicy: try #require(Router.FallbackPolicy(rawValue: o["fallbackPolicy"]!.str!)),
            reasonCodes: o["reasonCodes"]!.strs
        )
    }

    /// Replays one recorded execution's engine calls and checks each against the recording.
    final class RecordedEngine: StepEngine, @unchecked Sendable {
        let hasChatTemplate: Bool
        let calls: [JSONValue]
        let where_: String
        let n = Cursor()
        init(template: Bool, calls: [JSONValue], where_: String) { hasChatTemplate = template; self.calls = calls; self.where_ = where_ }

        func generate(_ req: GenRequest, onToken: (@Sendable (String) -> Void)?) async throws -> GenResult {
            let i = n.next()
            guard i < calls.count else { Issue.record("\(where_): unexpected call \(i + 1)"); return GenResult(text: "") }
            let want = calls[i]
            let msgs = want.opt("messages").map { $0.arr.map { "\($0["role"]!.str!): \($0["content"]!.str!)" } }
            #expect(req.messages.map { $0.map { "\($0.role): \($0.content)" } } == msgs, "\(where_) call \(i + 1) messages")
            #expect(req.prompt == want["prompt"]?.str, "\(where_) call \(i + 1) prompt")
            #expect(req.nPredict == want["nPredict"]!.int, "\(where_) call \(i + 1) nPredict")
            #expect(abs(Double(req.temperature) - want["temperature"]!.dbl) < 1e-6, "\(where_) call \(i + 1) temperature")
            // The recorder sits in front of LlamaEngine, which adds DEFAULT_STOP_SEQUENCES to a plain prompt itself.
            let stops = want.opt("stop").map(\.strs) ?? (req.prompt != nil ? AnswerPipeline.defaultStopSequences : [])
            #expect(req.stops == stops, "\(where_) call \(i + 1) stops")
            let reply = want["reply"]!.str!
            onToken?(reply)
            return GenResult(text: reply)
        }
    }

    final class RecordedHost: ModelHost, @unchecked Sendable {
        private let lock = NSLock()
        private var resident: String?
        private(set) var loads: [String] = []
        let missing: String?
        let engine: RecordedEngine
        init(resident: String?, missing: String?, engine: RecordedEngine) { self.resident = resident; self.missing = missing; self.engine = engine }

        func residentFilename() async -> String? { lock.withLock { resident } }
        func filenameOf(_ modelId: String) async -> String? { modelId == missing ? nil : "models/\(modelId).gguf" }
        func load(_ modelId: String) async throws -> (any StepEngine)? {
            let f = "models/\(modelId).gguf"
            // The TS engine loads only when the model isn't resident; a resident one is just used.
            lock.withLock { if resident != f { loads.append(f); resident = f } }
            return engine
        }
        var loaded: [String] { lock.withLock { loads } }
    }

    @Test func loadsPromptsAndResultsOnEveryRecordedExecution() async throws {
        let cases = try req(g["cases"]).arr
        #expect(!cases.isEmpty)
        for (ci, c) in cases.enumerated() {
            let input = c["input"]!
            let where_ = "case \(ci) \(input["query"]!.str!)"
            let calls = c["calls"]!.arr
            let retrievals = c["retrievals"]!.arr
            let k = Cursor()
            let engine = RecordedEngine(template: c["template"]!.flag, calls: calls, where_: where_)
            let host = RecordedHost(resident: c["resident"]?.str, missing: c["missing"]?.str, engine: engine)
            let retrieve: @Sendable (String, Int) async throws -> [Chunk] = { q, topK in
                let i = k.next()
                guard i < retrievals.count else { Issue.record("\(where_): unexpected retrieval"); return [] }
                #expect(q == retrievals[i]["query"]!.str!, "\(where_) retrieval")
                #expect(topK == retrievals[i]["k"]!.int)
                return retrievals[i]["chunks"]!.arr.map(goldenChunk)
            }
            let r = try await PlanExecutor(host: host, retrieve: retrieve, classify: { Classify.classifyTask($0).value }).execute(
                plan: plan(c["plan"]!), input: PipelineInput(query: input["query"]!.str!, systemPrompt: input["systemPrompt"]?.str, styleReminder: input["styleReminder"]?.str)
            )
            let want = c["result"]!
            #expect(engine.n.value == calls.count, "\(where_) calls")
            #expect(host.loaded == c["loads"]!.strs, "\(where_) loads")
            #expect(r.answer == want["answer"]!.str!, "\(where_) answer")
            #expect(r.citations.map { "\($0.chunkId) | \($0.body)" } == want["citations"]!.strs, "\(where_) citations")
            let ver = want["verification"]!
            #expect(r.verification == Verification(status: ver["status"]!.str!, note: ver["note"]?.str), "\(where_) verification")
            #expect(r.warnings == want["warnings"]!.strs, "\(where_) warnings")
            #expect(r.stepsExecuted == want["stepsExecuted"]!.int, "\(where_) steps")
            #expect(r.modelSwitches == want["modelSwitches"]!.int, "\(where_) switches")
            #expect(r.crossMessageModelSwitch == want["crossMessageModelSwitch"]!.flag, "\(where_) cross")
            #expect(r.modelResidency == want["modelResidency"]?.str, "\(where_) residency")
            #expect(r.promptFormat == want["promptFormat"]?.str, "\(where_) format")
            #expect(r.contextTokensBefore == want.opt("contextTokensBefore")?.intValue, "\(where_) ctx")
            #expect(r.contextTokensAfter == want.opt("contextTokensAfter")?.intValue, "\(where_) ctx after")
        }
    }

    @Test func verdictParsing() throws {
        let cases = try req(g["parse"]).arr
        #expect(!cases.isEmpty)
        for p in cases {
            let o = p["out"]!
            #expect(Verify.parse(p["t"]!.str!) == Verification(status: o["status"]!.str!, note: o["note"]?.str), "\(p["t"]!.str!)")
        }
    }
}
