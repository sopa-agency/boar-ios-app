import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// The device evaluation protocol must answer scripts/eval-device.mjs as the Expo app does (device-eval.json).
struct DeviceEvalGoldenTests {
    let g: JSONValue
    let sets: EvalSets

    init() throws {
        g = try Fixtures.golden("device-eval.json")
        sets = try EvalSets.bundled()
    }

    private func strings(_ v: JSONValue?) -> [String]? { v.flatMap { $0.isNullValue ? nil : $0.strs } }

    @Test func requestParsingAndItsErrors() throws {
        let cases = try req(g["parse"]).arr
        #expect(!cases.isEmpty)
        for c in cases {
            let text = c["text"]!.str!
            let got: String
            do {
                let r = try DeviceEval.parseRequest(text)
                got = "ok \(r.requestId) \(r.models.map { "\($0)" } ?? "nil") \(r.adaptive.map(String.init) ?? "nil") \(r.queries.map { "\($0)" } ?? "nil") \(r.pipeline ?? "nil")"
            } catch let e as EvalRequestError {
                got = "error \(e.message)"
            }
            let want: String
            if let o = c.opt("ok") {
                want = "ok \(o["requestId"]!.str!) \(strings(o["models"]).map { "\($0)" } ?? "nil") \(o.opt("adaptive").map { String($0.flag) } ?? "nil") \(strings(o["queries"]).map { "\($0)" } ?? "nil") \(o["pipeline"]?.str ?? "nil")"
            } else {
                want = "error \(c["error"]!.str!)"
            }
            #expect(got == want, "\(text)")
        }
    }

    @Test func modelMatchingConfigsAndQueries() throws {
        let installedSets = try req(g["misc"]!["installedSets"]).arr.map { $0.arr.map { ModelRef(id: $0["id"]!.str!, label: $0["label"]!.str!) } }
        let cases = try req(g["resolve"]).arr
        #expect(!cases.isEmpty)
        for c in cases {
            let models = c["models"]!.strs
            let request = EvalRequest(requestId: "r", models: models.isEmpty ? nil : models, adaptive: c.opt("adaptive").map(\.flag), queries: strings(c["queries"]))
            let got: String
            switch DeviceEval.resolve(request, installed: installedSets[c["installed"]!.int], evalSet: sets.evalSet, adaptiveLabel: "Adaptive (balanced)", extraSets: sets.extraSets) {
            case .ok(let configs, let queries):
                got = "configs \(configs.map { "\($0.id)/\($0.label)" }) queries \(queries.map(\.id))"
            case .err(let e):
                got = "error \(e)"
            }
            let o = c["out"]!
            let want: String
            if let e = o.opt("error") {
                want = "error \(e.str!)"
            } else {
                want = "configs \(o["configs"]!.arr.map { "\($0["id"]!.str!)/\($0["label"]!.str!)" }) queries \(o["queries"]!.strs)"
            }
            #expect(got == want, "\(c.jsonString.prefix(200))")
        }
    }

    @Test func runIdsExpectedArticlesSpeedPlanCodes() throws {
        let m = try req(g["misc"])
        for c in m["runIds"]!.arr { #expect(DeviceEval.newRunId(nowMs: c["t"]!.i64) == c["id"]!.str!) }
        for c in m["kbHit"]!.arr { #expect(DeviceEval.expectedKbHit(c["e"]!.strs, retrieved: c["r"]!.strs) == c.opt("out")?.boolValue) }
        for c in m["tps"]!.arr {
            let got = DeviceEval.tokensPerSecond(tokens: c["t"]!.int, generationLatencyMs: c.opt("ms")?.doubleValue)
            #expect(got == c.opt("out")?.doubleValue)
        }
        for c in m["plan"]!.arr { #expect(DeviceEval.fixedPlanReasonCodes(retrieve: c["retrieve"]!.flag, modelId: "m1") == c["codes"]!.strs) }
    }

    @Test func requestIdOfAMalformedRequest() {
        #expect(DeviceEval.requestId(of: #"{"requestId" : "run-1", "models": 3"#) == "run-1")
        #expect(DeviceEval.requestId(of: "nonsense") == "invalid")
    }
}
