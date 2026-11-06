import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// android LabToolsCombinationTest.kt: the Boar Labs answer plugins together. Every subset of {calc, distance, facts,
/// cohazard} with Boar Guard on and off (32 combinations), over Fixtures/labs (Android's src/test/resources/labs: EN and PT
/// questions, crazy ones, fake model answers) and 5,000 fuzzed strings. Each invariant names its letter: (a) no
/// exception (a Swift crash fails the run on its own), (b) one deterministic winner, (c) health, seed, PT and ES kept from
/// the tools that must not take them, (d) Cohazard wins its questions (EN, PT and ES), (e) Guard only on model answers,
/// sound and idempotent, (f) each tool decides fast, (g) no leaked placeholders, type names or non-finite numbers.
/// Failures are collected and printed before the test fails, so one run shows every broken combination.
enum LabCombos {
    /// The suites' reports (Kotlin prints them to the test log): only with BOAR_TEST_REPORT set, so a normal
    /// `swift test` stays quiet. Failures carry their own lines in the #expect message.
    static func report(_ text: String) {
        if ProcessInfo.processInfo.environment["BOAR_TEST_REPORT"] != nil { print(text) }
    }

    static let distanceTable: TravelDistance = {
        // swiftlint:disable:next force_try
        try! TravelDistance(json: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Data/lab_distance_world_cities_v1.json")))
    }()
    static let factsTable: Facts = {
        // swiftlint:disable:next force_try
        try! Facts(json: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Data/lab_facts_facts_v1.json")))
    }()

    /// "category | text" lines; \n, \t and \uXXXX decoded.
    static func load(_ name: String) -> [(String, String)] {
        // swiftlint:disable:next force_try
        let text = try! Fixtures.text(Fixtures.root.appending(path: "Fixtures/labs/\(name)"))
        return JsString.split(text, "\n").filter { !JsString.trim($0).isEmpty && !$0.hasPrefix("#") }.map { line in
            let ns = line as NSString
            let i = ns.range(of: " |").location
            var rest = ns.substring(from: i + 2)
            if rest.hasPrefix(" ") { rest.removeFirst() }
            return (JsString.trim(ns.substring(to: i)), decode(rest))
        }
    }

    private static let unicodeEscape = JsRegex(#"\\u([0-9A-Fa-f]{4})"#, flags: "g")
    private static func decode(_ s: String) -> String {
        let plain = JsString.replacingAll(JsString.replacingAll(s, "\\n", with: "\n"), "\\t", with: "\t")
        return unicodeEscape.replace(in: plain) { m in String(decoding: [UInt16(m.groupValue(1), radix: 16)!], as: UTF16.self) }
    }

    static func take(_ s: String, _ n: Int) -> String {
        let ns = s as NSString
        return ns.length <= n ? s : ns.substring(to: n)
    }

    static let corpus: [(String, String)] = {
        let base = load("combination-corpus.txt")
        // Built here, not written out: three 20,000-character questions.
        let words = base.flatMap { JsString.split($0.1, " ") }.filter { !JsString.trim($0).isEmpty }
        var sentence = ""
        var k = 0
        while sentence.utf16.count < 20_000 {
            sentence += words[k % words.count] + " "
            k += 1
        }
        return base + [
            ("crazy", take(sentence, 20_000)),
            ("crazy", String(repeating: "a", count: 20_000)),
            ("crazy", String(repeating: "1+", count: 10_000)),
            // A long run of digits made the calculator's number patterns quadratic (fix(labs) on Calculators.NUM).
            ("crazy", String(repeating: "9", count: 20_000)),
            ("crazy", String(repeating: "9", count: 19_990) + " L per 100 km in mpg?"),
            ("crazy", "I have " + String(repeating: "1", count: 5_000) + " L of water and 5 L jerrycans. How many jerrycans do I need?"),
            ("cohazard", "Can I run my portable generator in the attached garage if I keep the door open? " + String(repeating: "Please answer. ", count: 1_300)),
        ]
    }()

    static let guardAnswers: [(String, String)] = load("guard-answers.txt") + [
        ("Did astronauts walk on the Moon before 1970?",
         String(repeating: "No, astronauts did not walk on the Moon before 1970. The first human moonwalk occurred on July 20, 1969. ", count: 250)),
    ]

    static let tools = ["calc", "distance", "facts", "cohazard"]

    /// The labs in the order the tool slot tries them: LabTools.slotRank, then the grid's (plugin.properties order: calc
    /// 65, distance 66, facts 67, cohazard 69, as in the iOS registry).
    static let slotOrder: [String] = {
        let order = ["calc": 65, "distance": 66, "facts": 67, "cohazard": 69]
        return tools.sorted { order[$0]! < order[$1]! }.enumerated()
            .sorted { (LabTools.slotRank($0.element), $0.offset) < (LabTools.slotRank($1.element), $1.offset) }.map(\.element)
    }()

    static func run(_ id: String, _ q: String, _ turns: [String] = []) -> LabTools.Hit? {
        switch id {
        case "calc": LabTools.calc(q, userTurns: turns)
        case "distance": LabTools.distance(distanceTable, q, userTurns: turns)
        case "facts": LabTools.facts(factsTable, q, userTurns: turns)
        case "cohazard": LabTools.coHazard(q)
        default: fatalError(id)
        }
    }

    static let toolPrefix = ["calc": ["calculator-", "temperature-"], "distance": ["calculator-travel-distance"], "facts": ["facts-"],
                             "cohazard": ["safety-fact-co-hazard"]]

    static func owner(_ hit: LabTools.Hit) -> String {
        if hit.tool == "calculator-travel-distance" { return "distance" }
        if hit.tool.hasPrefix("facts-") { return "facts" }
        if hit.tool == "safety-fact-co-hazard" { return "cohazard" }
        return "calc"
    }

    /// Kotlin's time limits are for a warm JVM. A Swift debug build, with every other suite running in parallel, takes about
    /// twice as long on the same regexes (Cohazard on 20,000 characters: 150 ms alone, 250 ms under load), so debug runs
    /// get twice the limit; a release build (`swift test -c release`) gets Kotlin's.
    #if DEBUG
    static let timeFactor = 2.0
    #else
    static let timeFactor = 1.0
    #endif

    struct Combo { let on: [String]; let guardOn: Bool }

    /// Every combination: a subset of the tools (in slot order) and Guard on or off.
    static let combos: [Combo] = (0..<16).flatMap { mask -> [Combo] in
        let on = slotOrder.filter { (mask >> tools.firstIndex(of: $0)!) & 1 == 1 }
        return [Combo(on: on, guardOn: false), Combo(on: on, guardOn: true)]
    }

    static func name(_ c: Combo) -> String { (c.on.isEmpty ? "none" : c.on.joined(separator: "+")) + (c.guardOn ? " +guard" : "") }

    /// Kotlin's list, plus Swift's own leaks ("Optional(", a bare nil).
    private static let leakWords = ["null", "NaN", "Infinity", "{{", "}}", "Exception", "undefined", "Optional("]
    private static let bareNil = JsRegex(#"\bnil\b"#)
    private static let typeName = JsRegex(#"team\.sopa|Swift\.|Foundation\.|\b(?:Hit|Answer|City|Entity|Result|Quantity|Seg|SplitThinking|Repair|ToolResult)\(|0x[0-9a-f]{6,}\b"#)
    /// A raw Double ("1e+308") or a non-finite number.
    private static let rawNumber = JsRegex(#"\d(?:\.\d+)?e[+-]\d|∞"#)

    /// (g): what in `text` is a leak, ignoring what `input` already says (a question that says "null" may be echoed).
    static func leaks(_ text: String, _ input: String) -> [String] {
        var out = leakWords.filter { text.contains($0) && !input.contains($0) }
        if bareNil.containsMatch(in: text) && !bareNil.containsMatch(in: input) { out.append("nil") }
        if let v = typeName.find(in: text)?.value, !input.contains(v) { out.append(v) }
        if let v = rawNumber.find(in: text)?.value, !input.contains(v) { out.append(v) }
        if JsString.trim(text).isEmpty { out.append("blank") }
        return out
    }

    static func short(_ q: String) -> String {
        let s = JsString.replacingAll(JsString.replacingAll(q, "\n", with: "\\n"), "\t", with: "\\t")
        return s.utf16.count > 90 ? take(s, 87) + "…" : s
    }

    /// SplitMix64, for the fuzz and the shuffles (Kotlin uses kotlin.random.Random with the same seeds).
    struct Rng: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ lo: Int, _ hi: Int) -> Int { Int(next() % UInt64(hi - lo)) + lo }
    }

    /// Failures by combination and invariant, printed as a table.
    final class Failures {
        var byCombo: [String: [Character: Int]] = [:]
        var order: [String] = []
        var lines: [String] = []

        func add(_ combo: String, _ inv: Character, _ detail: String) {
            if byCombo[combo] == nil { order.append(combo) }
            byCombo[combo, default: [:]][inv, default: 0] += 1
            if lines.count < 200 { lines.append("[\(inv)] \(combo): \(detail)") }
        }

        func report(_ title: String, _ invariants: String) {
            var sb = "\n== \(title) ==\n" + "combination".padding(toLength: 30, withPad: " ", startingAt: 0)
                + invariants.map { "  \($0) " }.joined() + "\n"
            for c in LabCombos.combos {
                let f = byCombo[LabCombos.name(c)]
                sb += LabCombos.name(c).padding(toLength: 30, withPad: " ", startingAt: 0)
                sb += invariants.map { inv in
                    let cell = f?[inv].map { "F\($0)" } ?? "ok"
                    return String(repeating: " ", count: max(0, 4 - cell.count)) + cell
                }.joined() + "\n"
            }
            for k in order where !LabCombos.combos.contains(where: { LabCombos.name($0) == k }) {
                sb += k.padding(toLength: 30, withPad: " ", startingAt: 0) + "\(byCombo[k]!)\n"
            }
            LabCombos.report(sb)
            lines.forEach { LabCombos.report($0) }
        }
    }
}

struct LabToolsCombinationTests {
    typealias C = LabCombos

    /// Each tool on its own, outside the slot.
    private func direct(_ q: String, _ turns: [String]) -> [String: LabTools.Hit] {
        var out: [String: LabTools.Hit] = [:]
        for id in C.tools { out[id] = C.run(id, q, turns) }
        return out
    }

    private let modelAnswers = [
        "Yes.", "No, it is not. The first one was in 1969, before 1970.", "<think>2+2 is 4</think>The answer is 4.", "",
        "Não sei. Pergunte de novo.",
    ]

    @Test func everyCombinationOverTheCorpusKeepsInvariantsBCDEG() {
        let f = C.Failures()
        for (cat, q) in C.corpus {
            let hits = direct(q, [])
            // (b): a tool gives the same answer twice in a row.
            for id in C.tools where C.run(id, q) != hits[id] { f.add("tool \(id)", "b", "not repeatable: \(C.short(q))") }
            // (g) on every tool's own answer, and its code belongs to it.
            for (id, h) in hits {
                let l = C.leaks(h.text, q)
                if !l.isEmpty { f.add("tool \(id)", "g", "\(C.short(q)) -> \(l)") }
                if !C.toolPrefix[id]!.contains(where: { h.tool.hasPrefix($0) }) { f.add("tool \(id)", "g", "code \(h.tool) for \(C.short(q))") }
            }
            // Each tool's own questions: with only it switched on, it answers (the corpus really exercises it).
            if C.tools.contains(cat) && hits[cat] == nil { f.add("tool \(cat)", "x", "own question not answered: \(C.short(q))") }

            for c in C.combos {
                let combo = C.name(c)
                // (b): the slot's pick, three times, equals the first enabled tool with an answer.
                let picks = (1...3).map { _ in LabTools.first(c.on) { C.run($0, q) } }
                let expected = c.on.lazy.compactMap { hits[$0] }.first
                if picks.contains(where: { $0 != picks[0] }) || picks[0] != expected {
                    f.add(combo, "b", "\(C.short(q)) -> \(picks.map { $0?.tool ?? "-" }), expected \(expected?.tool ?? "-")")
                }
                let win = picks[0]
                let by = win.map(C.owner)
                if let by, !c.on.contains(by) { f.add(combo, "b", "\(C.short(q)) answered by switched-off \(by)") }
                // (c)
                switch cat {
                case "health": if let by, ["facts", "distance", "calc"].contains(by) { f.add(combo, "c", "health taken by \(by): \(C.short(q))") }
                case "seed": if let by, ["facts", "distance"].contains(by) { f.add(combo, "c", "seed taken by \(by): \(C.short(q))") }
                case "pt", "es": if let by, ["facts", "distance", "cohazard"].contains(by) { f.add(combo, "c", "\(cat) taken by \(by): \(C.short(q))") }
                case "cohazard-pt", "cohazard-es": if let by, ["facts", "distance"].contains(by) { f.add(combo, "c", "\(cat) taken by \(by): \(C.short(q))") }
                default: break
                }
                // (d): CO questions in English, Portuguese and Spanish.
                if cat.hasPrefix("cohazard") && c.on.contains("cohazard") && by != "cohazard" {
                    f.add(combo, "d", "CO question taken by \(by ?? "the model"): \(C.short(q))")
                }
                // (e): the check slot never reads an instant answer; with Guard off a model answer stays as written.
                if win != nil {
                    if LabTools.checksAnswer(instant: true, stopped: false, timedOut: false, failed: false, path: nil, blank: false) {
                        f.add(combo, "e", "check slot reads an instant answer")
                    }
                } else {
                    for a in modelAnswers + C.guardAnswers.filter({ $0.0 == q }).map(\.1) {
                        let checks = c.guardOn ? ["guard"] : []
                        let applies = LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: nil, blank: JsString.trim(a).isEmpty)
                        let repair = applies ? LabTools.first(checks) { _ in LabTools.guard(question: q, answer: a) } : nil
                        if !c.guardOn && repair != nil { f.add(combo, "e", "repair with Guard off: \(C.short(q))") }
                        if let repair {
                            let l = C.leaks(repair.text, q + a)
                            if !l.isEmpty { f.add(combo, "g", "guard \(C.short(q)) -> \(l)") }
                        }
                    }
                }
            }
        }
        // (c) over history: an earlier user turn about health keeps every tool but Cohazard off a later question.
        let healthTurns = ["My son was bitten by a snake, what do I do?"]
        for (_, q) in C.corpus.filter({ ["calc", "distance", "facts"].contains($0.0) }) {
            for (id, _) in direct(q, healthTurns) where id != "cohazard" { f.add("tool \(id)", "c", "after a health turn: \(C.short(q))") }
        }
        f.report("corpus: \(C.corpus.count) questions x \(C.combos.count) combinations", "bcdegx")
        #expect(f.lines.isEmpty, "\(f.lines.count) failures, first: \(f.lines.first ?? "")")
    }

    @Test func theWinnerDependsOnlyOnTheSwitchedOnSetInAnyQuestionOrder() {
        let f = C.Failures()
        var first: [String: LabTools.Hit?] = [:]
        for c in C.combos {
            // .some: assigning a nil Hit? would remove the key.
            for (i, (_, q)) in C.corpus.enumerated() { first["\(C.name(c))#\(i)"] = .some(LabTools.first(c.on) { C.run($0, q) }) }
        }
        // Again, combinations and questions in another order.
        var rng = C.Rng(state: 7)
        let shuffled = Array(C.corpus.enumerated()).shuffled(using: &rng)
        for c in C.combos.reversed() {
            for (i, (_, q)) in shuffled {
                let again = LabTools.first(c.on) { C.run($0, q) }
                if again != first["\(C.name(c))#\(i)"]! { f.add(C.name(c), "b", "order-dependent: \(C.short(q))") }
            }
        }
        f.report("order independence", "b")
        #expect(f.lines.isEmpty, "\(f.lines.first ?? "")")
    }

    @Test func guardIsSoundKeepsThinkingBlocksAndIsIdempotent() {
        let f = C.Failures()
        var seen = Set<String>()
        let questions = (C.guardAnswers.map(\.0) + C.corpus.map(\.1)).filter { seen.insert($0).inserted }
        seen = []
        let answers = C.guardAnswers.map(\.1).filter { seen.insert($0).inserted }
        var repaired = 0
        let markers = ["<think>", "</think>", "<|channel>thought", "<channel|>"]
        for q in questions {
            for a in answers {
                guard let r = LabTools.guard(question: q, answer: a) else { continue }
                repaired += 1
                if JsString.trim(r.text).isEmpty { f.add("guard", "e", "empty repair: \(C.short(q)) / \(C.short(a))") }
                if !r.tool.hasPrefix("verdict-guard-") { f.add("guard", "e", "code \(r.tool)") }
                let before = AnswerText.splitThinking(a)
                let after = AnswerText.splitThinking(r.text)
                if before.thinking != after.thinking || before.thinkingInProgress != after.thinkingInProgress
                    || markers.contains(where: { JsString.split(a, $0).count != JsString.split(r.text, $0).count }) {
                    f.add("guard", "e", "thinking block changed: \(C.short(a)) -> \(C.short(r.text))")
                }
                if QueryContext.isHealthQuestion(q) || QueryContext.isPortugueseQuestion(q) || QueryContext.isSpanishQuestion(q) {
                    f.add("guard", "e", "repaired a health/PT/ES question: \(C.short(q))")
                }
                if let again = LabTools.guard(question: q, answer: r.text), again.text != r.text {
                    f.add("guard", "e", "not idempotent: \(C.short(q)) / \(C.short(a))\n  1: \(C.short(r.text))\n  2: \(C.short(again.text))")
                }
                let l = C.leaks(r.text, q + a)
                if !l.isEmpty { f.add("guard", "g", "\(C.short(q)) / \(C.short(a)) -> \(l)") }
            }
        }
        // Not reachable through the slot (the check slot skips instant answers), counted for the record.
        let wouldTouch = C.corpus.reduce(0) { n, item in
            n + C.tools.compactMap { C.run($0, item.1) }.filter { LabTools.guard(question: item.1, answer: $0.text) != nil }.count
        }
        LabCombos.report("guard: \(questions.count) questions x \(answers.count) answers, \(repaired) repaired; tool answers it would change if it read them: \(wouldTouch)")
        f.lines.forEach { LabCombos.report($0) }
        #expect(f.lines.isEmpty, "\(f.lines.first ?? "")")
    }

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
        slow.forEach { LabCombos.report($0) }
        #expect(slow.isEmpty, "\(slow.joined(separator: "\n"))")
    }

    @Test func fuzzedStringsThroughAllCombinationsKeepBAndG() {
        var rnd = C.Rng(state: 20_261_018)
        var seen = Set<String>()
        let words = C.corpus.filter { $0.1.utf16.count < 400 }
            .flatMap { $0.1.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init) }
            .filter { !JsString.trim($0).isEmpty && seen.insert($0).inserted }
        let bits = [
            "+", "-", "*", "/", "^", "!", "%", "(", ")", "=", ".", ",", "?", "0", "1e308", "-1", "0.0", "999999999999", "1/0", "0/0",
            "km", "L", "mph", "°C", "°F", "ft", "m", "mAh", "V", "Wh", "kg", "from", "to", "and back", "how far", "how long", "how many",
            "generator", "garage", "tent", "charcoal", "stove", "indoors", "Paris", "Rome", "São Paulo", "Zürich", "Brazil", "population",
            "é", "ã", "ç", "ü", "🐗", "\u{200B}", "\u{200D}", "\u{202E}", "ا", "ש", "日本", "\n", "\t", " ", "  ", "\"", "'", "{{", "}}", "<think>", "</think>",
        ]
        let f = C.Failures()
        for n in 0..<5_000 {
            let count = rnd.int(1, 40)
            let sep = rnd.int(0, 4) == 0 ? "" : " "
            let q = (0..<count).map { _ in rnd.int(0, 3) == 0 ? bits[rnd.int(0, bits.count)] : words[rnd.int(0, words.count)] }.joined(separator: sep)
            let hits = direct(q, [])
            for id in C.tools where C.run(id, q) != hits[id] { f.add("tool \(id)", "b", "fuzz #\(n) not repeatable: \(C.short(q))") }
            for (id, h) in hits {
                let l = C.leaks(h.text, q)
                if !l.isEmpty { f.add("tool \(id)", "g", "fuzz #\(n) \(C.short(q)) -> \(l)") }
            }
            if let r = LabTools.guard(question: q, answer: q) {
                let l = C.leaks(r.text, q)
                if !l.isEmpty { f.add("guard", "g", "fuzz #\(n) -> \(l)") }
            }
            // The slot over the answers just computed: its pick is the first enabled tool's, and only an enabled one's.
            for c in C.combos {
                let win = LabTools.first(c.on) { hits[$0] }
                if win != c.on.lazy.compactMap({ hits[$0] }).first || (win.map { !c.on.contains(C.owner($0)) } ?? false) {
                    f.add(C.name(c), "b", "fuzz #\(n) \(C.short(q))")
                }
            }
        }
        f.report("fuzz: 5,000 strings x \(C.combos.count) combinations", "bg")
        #expect(f.lines.isEmpty, "\(f.lines.count) failures, first: \(f.lines.first ?? "")")
    }

    struct Boom: Error {}

    @Test func theSlotSkipsAToolThatThrowsAndKeepsGoing() {
        let hit = LabTools.Hit(tool: "t", text: "x")
        let items: [() throws -> LabTools.Hit?] = [{ throw Boom() }, { nil }, { hit }]
        #expect(LabTools.first(items) { try $0() } == hit)
    }
}
