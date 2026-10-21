import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// The follow-up search rule must match src/routing/followUp.ts exactly (scripts/export-native-golden-followup.mjs).
struct FollowUpGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("followup.json") }

    @Test func searchPlan() throws {
        let cases = try req(g["plans"]).arr
        #expect(cases.count > 300)
        var failed = 0
        for c in cases {
            let q = c["query"]!.str!
            let p = c["plan"]!
            let want = FollowUp.Plan(direct: p["direct"]?.str, previous: p["previous"]?.str, fallback: p["fallback"]?.str)
            let got = FollowUp.plan(q, goldenHistory(c["history"]))
            if got != want {
                failed += 1
                if failed <= 10 { Issue.record("\"\(q)\" after \(c["history"]?.jsonString ?? "null"): want \(want), got \(got)") }
            }
        }
        #expect(failed == 0)
    }

    @Test func searchesRunInTheSameOrderAndKeepTheSameWords() async throws {
        let cases = try req(g["runs"]).arr
        #expect(cases.count > 700)
        var failed = 0
        for c in cases {
            let q = c["query"]!.str!
            let finds = Set(c["finds"]!.strs)
            let calls = Log<String>()
            let filtered = c["filtered"]?.str == "true"
            let r: FollowUp.Found<String>
            if filtered {
                r = try await FollowUp.search(q, history: goldenHistory(c["history"]), textOf: { (s: String) in s }) { text in
                    calls.add(text); return finds.contains(text) ? ["hit:\(text)", "Volcanoes erupt molten rock"] : []
                }
            } else {
                r = try await FollowUp.search(q, history: goldenHistory(c["history"])) { (text: String) -> [String] in
                    calls.add(text); return finds.contains(text) ? ["hit:\(text)"] : []
                }
            }
            let ok = calls.all == c["calls"]!.strs && r.chunks == c["chunks"]!.strs && r.searchedFor == c["searchedFor"]!.str!
            if !ok {
                failed += 1
                if failed <= 10 { Issue.record("\"\(q)\" finds \(finds): calls \(calls.all) chunks \(r.chunks) for \(r.searchedFor); want \(c["calls"]!.strs) \(c["chunks"]!.strs) \(c["searchedFor"]!.str!)") }
            }
        }
        #expect(failed == 0)
    }
}
