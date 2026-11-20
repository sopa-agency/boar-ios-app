import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// The two Boar Labs timing tests (android LabToolsCombinationTest (f) and LabToolsCompoundTest's adversarial strings),
/// in a suite of their own so they run alone: `scripts/test.sh` and CI run every other suite first
/// (`swift test --skip LabTimingTests`), then these (`swift test --filter LabTimingTests`). Under the full parallel run
/// the measuring thread gets up to six times less CPU while the fuzz and combination suites run, and the 400 ms debug
/// limit failed now and then (BOAR-66); alone they keep about 3x headroom, and a quadratic pattern still goes over 100x.
/// Bodies and limits are the ones Android's tests have (times scaled by `LabCombos.timeFactor`).
struct LabTimingTests {
    typealias C = LabCombos

    // MARK: android LabToolsCombinationTest (f): each tool decides fast

    @Test func eachToolDecidesFastWarmEvenOn20000Characters() {
        var deciders: [(String, (String) -> Any?)] = C.tools.map { id in (id, { q in C.run(id, q) }) }
        deciders.append(("guard", { q in LabTools.guard(question: q, answer: C.guardAnswers[1].1) }))
        deciders.append(("guard (20k answer)", { q in LabTools.guard(question: C.take(q, 200), answer: C.guardAnswers.last!.1) }))
        let qs = C.corpus.map(\.1)
        let clock = ContinuousClock()
        var report = "\n== decision time per question, ms (min of 3, warm) ==\n"
        var slow: [String] = []
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        for (id, d) in deciders {
            for _ in 0..<2 { qs.forEach { _ = d($0) } }
            let times = qs.map { q in (q, (1...3).map { _ in ms(clock.measure { _ = d(q) }) }.min()!) }
            let sorted = times.map(\.1).sorted()
            let worst = times.max { $0.1 < $1.1 }!
            report += "\(id.padding(toLength: 20, withPad: " ", startingAt: 0)) median \(String(format: "%.3f", sorted[sorted.count / 2]))  "
                + "p95 \(String(format: "%.3f", sorted[sorted.count * 95 / 100]))  max \(String(format: "%.2f", worst.1)) "
                + "(\(worst.0.utf16.count) chars: \(C.take(C.short(worst.0), 50)))\n"
            // Over the limit: measured again, three more times, so a burst of load from the other suites doesn't fail it.
            for (q, t0) in times where t0 > 200 * C.timeFactor {
                let t = min(t0, (1...3).map { _ in ms(clock.measure { _ = d(q) }) }.min()!)
                if t <= 200 * C.timeFactor { continue }
                slow.append("\(id) \(String(format: "%.1f", t)) ms on \(q.utf16.count) chars: \(C.short(q))")
            }
        }
        LabCombos.report(report)
        #expect(slow.isEmpty, "\(LabCombos.failures(slow))")
    }

    // MARK: android LabToolsCompoundTest: every regex entry point stays linear

    /// Adversarial strings, about `n` characters each.
    private let attacks: [(String, (Int) -> String)] = [
        ("aaaa", { String(repeating: "a", count: $0) }),
        ("1,1,1", { String(repeating: "1,", count: $0 / 2) }),
        ("((((", { String(repeating: "(", count: $0) }),
        ("unclosed quote", { "\"" + String(repeating: "how far is ", count: $0 / 11) }),
        ("1.2.3.4", { n in (0..<(n / 2)).map { "\($0 % 10)." }.joined() }),
        ("spaces", { String(repeating: " ", count: $0) }),
        ("the the", { String(repeating: "the ", count: $0 / 4) }),
        ("mixed scripts", { String(repeating: "aé日ا🐗1 ש,", count: $0 / 11) }),
        ("generator garage", { String(repeating: "generator garage ", count: $0 / 17) }),
        ("how far a to b", { String(repeating: "how far is a to b ", count: $0 / 18) }),
        ("write,report", { String(repeating: "write,", count: $0 / 6) }),
        ("gerador garagem", { String(repeating: "gerador na garagem ", count: $0 / 19) }),
        ("digits L km", { String(repeating: "1 L 2 km 3 mph ", count: $0 / 15) }),
        ("seed words", { String(repeating: "seed phrase 12 words wallet ", count: $0 / 28) }),
    ]

    private static let shortAnswer = "No, astronauts did not walk on the Moon before 1970. The first human moonwalk occurred on July 20, 1969."

    private let entries: [(String, (String) -> Any?)] = [
        ("LabTools.calc", { LabTools.calc($0, userTurns: []) }),
        ("LabTools.distance", { LabTools.distance(C.distanceTable, $0, userTurns: []) }),
        ("LabTools.facts", { LabTools.facts(C.factsTable, $0, userTurns: []) }),
        ("LabTools.coHazard", { LabTools.coHazard($0) }),
        ("LabTools.guard(q)", { LabTools.guard(question: $0, answer: shortAnswer) }),
        ("LabTools.guard(answer)", { LabTools.guard(question: "Did astronauts walk on the Moon before 1970?", answer: $0) }),
        ("VerdictGuard.check(q)", { VerdictGuard.check($0, shortAnswer) }),
        ("VerdictGuard.check(answer)", { VerdictGuard.check("Is a polar bear bigger than a grizzly bear?", $0) }),
        ("CoHazard.isCoHazardQuestion", { CoHazard.isCoHazardQuestion($0) }),
        ("CoHazard.coHazardAnswer", { CoHazard.coHazardAnswer($0) }),
        ("CoHazard.coHazardLanguage", { CoHazard.coHazardLanguage($0) }),
        ("QueryContext.isHealthQuestion", { QueryContext.isHealthQuestion($0) }),
        ("QueryContext.isSeedPhraseQuestion", { QueryContext.isSeedPhraseQuestion($0) }),
        ("QueryContext.isPortugueseQuestion", { QueryContext.isPortugueseQuestion($0) }),
        ("QueryContext.isSpanishQuestion", { QueryContext.isSpanishQuestion($0) }),
        ("NumGuard.healthLexicon", { NumGuard.healthLexicon($0) }),
        ("DeepResearch.isConversationRecap", { DeepResearch.isConversationRecap($0) }),
        // Boar Polyglot's gate (iOS addition: Android's test predates it).
        ("LanguageGate.decide", { LanguageGate.decide($0, [("fr", 0.97)]) }),
    ]

    private func time(_ f: (String) -> Any?, _ s: String) -> Double {
        let clock = ContinuousClock()
        for _ in 0..<2 { _ = f(s) }
        return (1...5).map { _ in
            let d = clock.measure { _ = f(s) }
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }.min()!
    }

    @Test func everyRegexEntryPointStaysLinearOnAdversarialStrings() {
        var bad: [String] = []
        var out = "\n== adversarial strings: worst attack per entry point, ms (min of 5, warm) ==\n"
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }
        // Ten times the input: about 10x the time when linear, about 100x when quadratic. Kotlin fails at 25x; a debug build
        // with every other suite running jitters more (Cohazard on "((((" measured 31x once under load, 10x alone), so the
        // limit scales with the time factor and still catches a quadratic pattern.
        let maxRatio = 25 * C.timeFactor
        for (entry, f) in entries {
            var worst: (String, Double, Double)?
            for (attack, make) in attacks {
                var t2 = time(f, make(2_000))
                var t20 = time(f, make(20_000))
                // Below 0.05 ms the clock, not the regex, sets the ratio.
                var ratio = t20 / max(t2, 0.05)
                // Over a limit: measured again (up to three more times, keeping the fastest), so a burst of load from the
                // other suites or a parallel build doesn't fail it. A quadratic pattern stays over the limit every time.
                for _ in 0..<3 where ratio >= maxRatio || t20 >= 300 * C.timeFactor {
                    t2 = min(t2, time(f, make(2_000)))
                    t20 = min(t20, time(f, make(20_000)))
                    ratio = t20 / max(t2, 0.05)
                }
                if ratio >= maxRatio || t20 >= 300 * C.timeFactor {
                    bad.append("\(entry) on \(attack): 2k \(String(format: "%.3f", t2)) ms, 20k \(String(format: "%.3f", t20)) ms, ratio \(String(format: "%.1f", ratio))")
                }
                if worst == nil || t20 > worst!.2 { worst = (attack, t2, t20) }
            }
            let (attack, t2, t20) = worst!
            out += pad(entry, 36) + pad(attack, 18) + String(format: "%9.3f%9.3f%8.1f", t2, t20, t20 / max(t2, 0.05)) + "\n"
        }
        // The sizes the plan names, once each.
        out += "\n== large inputs, ms ==\n"
        for (label, s) in [
            ("aaaa x 50k", String(repeating: "a", count: 50_000)),
            ("generator garage x 5k", String(repeating: "generator garage ", count: 5_000)),
            ("how far is a to b x 2k", String(repeating: "how far is a to b ", count: 2_000)),
            ("the x 20k", String(repeating: "the ", count: 20_000)),
            ("spaces x 20k", String(repeating: " ", count: 20_000)),
        ] {
            for (entry, f) in entries {
                let t = time(f, s)
                if t >= 1_000 * C.timeFactor { bad.append("\(entry) on \(label): \(String(format: "%.1f", t)) ms") }
                if t >= 10 { out += "\(pad(label, 24)) \(pad(entry, 36)) \(String(format: "%.1f", t))\n" }
            }
        }
        LabCombos.report(out)
        #expect(bad.isEmpty, "\(LabCombos.failures(bad))")
    }
}
