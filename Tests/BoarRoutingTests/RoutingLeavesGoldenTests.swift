import Foundation
import Testing
@testable import BoarRouting

/// The routing leaves (emergency numbers, small talk, Portuguese query terms, task classification, calculators) must
/// match the TypeScript engine on every golden case (scripts/export-native-golden-routing.mjs).
@Suite struct RoutingLeavesGoldenTests {
    let g: Tree
    init() throws { g = try Golden.load("routing-leaves.json") }

    private func cases(_ name: String) -> [Tree] { g[name].array }

    @Test func emergencyNumbersAnswer() {
        var bad = Mismatches()
        let cs = cases("emergencyAnswer")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!, pt = c["pt"].bool
            let want = c["out"].string
            let got = EmergencyNumbers.emergencyNumbersAnswer(q, pt: pt)
            if want != got { bad.add(input: "emergencyNumbersAnswer(\(q), \(pt))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("emergencyAnswer")))
    }

    @Test func emergencyNumbersLine() {
        var bad = Mismatches()
        let cs = cases("emergencyLine")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!, pt = c["pt"].bool
            let want = c["out"].string
            let got = EmergencyNumbers.emergencyNumbersLine(q, pt: pt)
            if want != got { bad.add(input: "emergencyNumbersLine(\(q), \(pt))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("emergencyLine")))
    }

    @Test func smallTalkRepliesTimesAndDates() throws {
        let tz = try #require(TimeZone(identifier: g["tz"].string!))
        var bad = Mismatches()
        let cs = cases("smallTalk")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!, pt = c["pt"].bool
            let now = c["now"].int64!
            let out = c["out"]
            let want: SmallTalk.Reply? = out.isNull ? nil : SmallTalk.Reply(text: out["text"].string!, kind: out["kind"].string!)
            let got = SmallTalk.smallTalkReply(q, pt: pt, now: Date(timeIntervalSince1970: Double(now) / 1000), timeZone: tz)
            if want != got { bad.add(input: "smallTalkReply(\(q), \(pt), \(now))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("smallTalk")))
    }

    @Test func englishSearchTermsForPortugueseQuestions() {
        var bad = Mismatches()
        let cs = cases("englishSearchTerms")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!
            let want = c["out"].string
            let got = PtQuery.englishSearchTerms(q)
            if want != got { bad.add(input: "englishSearchTerms(\(q))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("englishSearchTerms")))
    }

    @Test func canonicalHealthTermsForEnglishQuestions() {
        var bad = Mismatches()
        let cs = cases("canonicalHealthTerms")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!
            let want = c["out"].string
            let got = PtQuery.canonicalHealthTerms(q)
            if want != got { bad.add(input: "canonicalHealthTerms(\(q))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("canonicalHealthTerms")))
    }

    @Test func taskClassificationAndRetrievalRelevance() {
        var bad = Mismatches()
        let cs = cases("classify")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!
            let t = Classify.classifyTask(q)
            let want = "\(c["type"].string!) irrelevant=\(c["irrelevant"].bool)"
            let got = "\(t.value) irrelevant=\(Classify.isRetrievalIrrelevant(t))"
            if want != got { bad.add(input: "classifyTask(\(q))", want: want, got: got) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("classify")))
    }

    @Test func parseNumbersLikeTheTypeScriptNumber() {
        var bad = Mismatches()
        let cs = cases("parseNumber")
        #expect(!cs.isEmpty)
        for c in cs {
            let raw = c["raw"].string!, pt = c["pt"].bool
            let n = Calculators.parseNumber(raw, pt: pt)
            let got = (n == 0 && 1.0 / n < 0) ? "-0" : JsNumber.toString(n)
            let want = c["out"].string!
            if want != got { bad.add(input: "parseNumber(\(raw), \(pt))", want: want, got: got) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("parseNumber")))
    }

    @Test func calculators() {
        var bad = Mismatches()
        let cs = cases("calculate")
        #expect(!cs.isEmpty)
        for c in cs {
            let q = c["q"].string!, pt = c["pt"].bool
            let out = c["out"]
            let want: Calculators.Calculation? = out.isNull ? nil : Calculators.Calculation(kind: out["kind"].string!, text: out["text"].string!)
            let got = Calculators.calculate(q, pt: pt)
            if want != got { bad.add(input: "calculate(\(q), \(pt))", want: want as Any, got: got as Any) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report("calculate")))
    }

    @Test func taskTypesSerializeToTheTypeScriptStrings() {
        for t in TaskType.allCases { #expect(TaskType.of(t.value) == t) }
        #expect(TaskType.conversation.value == "conversation")
        #expect(TaskType.allCases.count == 12)
    }
}
