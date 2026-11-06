import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// android LabToolsCompoundTest.kt: the Boar Labs answer plugins on harder input than the combination corpus: compound
/// questions that pull three to five plugins and a seed phrase at once (EN, PT, ES), questions that carry a real-looking
/// seed, and adversarial strings through every regex entry point (linear time). Failures are collected and printed
/// before the test fails.
struct LabToolsCompoundTests {
    typealias C = LabCombos

    /// A CO hazard among the asks: Cohazard answers alone whenever it is on.
    private let withCo = [
        "How far is Lisbon to Porto, what is 15 * 8, how do I back up my 12-word seed phrase, and can I run a propane heater in the car?",
        "Can I run the generator in the garage overnight, how far is Paris to Rome, how many 5 L jerrycans for 23 L, and where should I store my seed phrase?",
        "What is the capital of Kenya, how do I back up my wallet, is 10 ft from the back door far enough for the generator, and how long to drive 240 miles at 60 mph?",
        "My seed phrase is on paper; how far is it from Madrid to Barcelona; can we use a charcoal grill inside the tent; and what is 20 °C in Fahrenheit?",
        "How long to drive 240 miles at 60 mph, does Brazil have more people than Russia, and can I warm up my car in the garage with the door closed? Also where do I keep my wallet's private key?",
        "Where do I store my recovery phrase? Can I use a camping stove inside the tent? How far is Vienna to Budapest?",
        "Qual a distância de Lisboa ao Porto, quanto é 15 * 8, como faço backup da minha frase semente, e posso usar aquecedor a gás dentro da barraca?",
        "Posso ligar o gerador na garagem, onde guardo minhas palavras de recuperação, qual a capital do Quênia e quanto é 2+2?",
        "Onde guardo minha frase de recuperação? E posso usar a churrasqueira dentro de casa? Qual a distância de São Paulo ao Rio de Janeiro?",
        "¿Qué distancia hay de Madrid a Barcelona, cuánto es 15 * 8, dónde guardo mi seed phrase y puedo usar un generador en el garaje?",
        "¿Puedo usar un brasero dentro de la tienda? Y también, ¿cuál es la capital de Kenia y cómo guardo mi seed phrase?",
    ]

    /// A seed phrase and other plugins' asks, no CO hazard: Facts and Distance never answer.
    private let seedNoCo = [
        "How far is Lisbon to Porto, what is 15 * 8, how do I back up my 12-word seed phrase, and is a polar bear bigger than a grizzly bear?",
        "What is the capital of Kenya, how far is it from Paris to Rome, and how should I store my seed phrase?",
        "Where should I store my recovery phrase, how far is Madrid to Barcelona, and does Brazil have more people than Russia?",
        "I have 23 L of water and 5 L jerrycans. How many jerrycans do I need? Also how far is it from Paris to Rome and where do I keep my wallet's private key?",
        "How long to drive 240 miles at 60 mph, what plug type does Brazil use, and how do I back up my wallet?",
        "Is it safe to keep my private key in a photo? And what is 20 °C in Fahrenheit, and how far is Zürich to Geneva?",
        "Qual a distância de Lisboa ao Porto, quanto é 15 * 8 e onde guardo minha frase semente?",
        "Qual a capital do Quênia, quanto é 2+2, e como guardo minhas 24 palavras da carteira de bitcoin?",
        "¿Qué distancia hay de Madrid a Barcelona, cuál es la capital de Kenia y dónde guardo mi seed phrase?",
    ]

    private let all = ["calc", "distance", "facts", "cohazard"]

    @Test func compoundWithACOHazardCohazardAnswersAloneInEveryCombinationWithItOn() {
        var bad: [String] = []
        for q in withCo {
            guard let co = LabTools.coHazard(q) else { bad.append("Cohazard missed: \(q)"); continue }
            for c in C.combos {
                let win = LabTools.first(c.on) { C.run($0, q) }
                if c.on.contains("cohazard") && win != co { bad.append("\(C.name(c)): \(win?.tool ?? "nil") instead of Cohazard: \(q)") }
                if let win, ["facts", "distance"].contains(C.owner(win)) { bad.append("\(C.name(c)): \(win.tool) on a seed-phrase compound: \(q)") }
            }
        }
        bad.forEach { LabCombos.report($0) }
        #expect(bad.isEmpty, "\(bad.first ?? "")")
    }

    @Test func compoundWithASeedPhraseAndNoCOHazardOnlyTheCalculatorMayAnswer() {
        var bad: [String] = []
        var table = "\n== seed-phrase compounds, no CO hazard: what each tool decides ==\n"
        for q in seedNoCo {
            var hits: [String: LabTools.Hit] = [:]
            for id in all { hits[id] = C.run(id, q) }
            table += all.map { "\($0)=\(hits[$0]?.tool ?? "-")" }.joined(separator: "  ") + "  | " + C.take(q, 70) + "\n"
            for id in ["facts", "distance", "cohazard"] where hits[id] != nil { bad.append("\(id) answered: \(q)") }
            for c in C.combos {
                let win = LabTools.first(c.on) { C.run($0, q) }
                let expected = c.on.contains("calc") ? hits["calc"] : nil
                if win != expected { bad.append("\(C.name(c)): \(win?.tool ?? "nil") instead of \(expected?.tool ?? "nil"): \(q)") }
            }
        }
        LabCombos.report(table)
        bad.forEach { LabCombos.report($0) }
        #expect(bad.isEmpty, "\(bad.first ?? "")")
    }

    // BIP39-looking words (the first 24 of the English list): a seed someone pasted.
    private static let seed12 = "abandon ability able about above absent absorb abstract absurd abuse access accident"
    private static let seed24 = "\(seed12) account accuse achieve acid acoustic acquire across act action actor actress actual"
    private static let seedWords = seed24.split(separator: " ").map(String.init)
    private static let seedRes = seedWords.map { JsRegex("(?<![\\p{L}])\($0)(?![\\p{L}])", flags: "giu") }

    private var withSeed: [String] {
        let seed12 = Self.seed12, seed24 = Self.seed24
        return [
            "Summarize our chat and keep my seed phrase safe: \(seed12)",
            "What is 2+2, my seed is \(seed12)",
            "Guarde minha frase-semente: \(seed12)",
            "Guarde minha frase semente \(seed24) e me diga quanto é 2+2",
            "How far is it from Paris to Rome? my seed is \(seed24)",
            "What is the capital of Kenya? \(seed12) is my wallet seed",
            "Does Brazil have more people than Russia? Recovery words: \(seed24)",
            "I have 23 L of water and 5 L jerrycans. How many jerrycans do I need? seed: \(seed12)",
            "Can I run the generator in the garage? My seed: \(seed12)",
            "How far is it from Madrid to Barcelona, here are my 12 words for the wallet: \(seed12)",
            "\(seed12) — that's my bitcoin seed. Is a polar bear bigger than a grizzly bear?",
            "Did astronauts walk on the Moon before 1970? my seed is \(seed12)",
            "¿Cuál es la capital de Kenia? Mi frase semilla es \(seed12)",
        ]
    }

    /// Seed words in `text`, each as often as it appears.
    private func seedCounts(_ text: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for (w, re) in zip(Self.seedWords, Self.seedRes) { out[w] = re.findAll(in: text).count }
        return out
    }

    private func added(_ after: [String: Int], _ before: [String: Int]) -> [String] {
        after.filter { w, n in n > (before[w] ?? 0) }.keys.sorted()
    }

    @Test func aPastedSeedIsNeverEchoedNeverTakenByFactsOrDistanceAndGuardAddsNoneOfItsWords() {
        var bad: [String] = []
        let seed12 = Self.seed12, seed24 = Self.seed24
        for q in withSeed {
            // The same question without the seed: a fixed answer text may hold a common word ("about") on its own.
            let bare = JsString.replacingAll(JsString.replacingAll(q, seed24, with: "XXXX"), seed12, with: "XXXX")
            for id in all {
                guard let h = C.run(id, q) else { continue }
                if id == "facts" || id == "distance" { bad.append("\(id) answered a question with a seed: \(q)") }
                let base = C.run(id, bare).map { seedCounts($0.text) } ?? [:]
                let echoed = added(seedCounts(h.text), base)
                if !echoed.isEmpty { bad.append("\(id) echoes \(echoed): \(q)") }
            }
            for a in [
                "No, astronauts did not walk on the Moon before 1970. The first human moonwalk occurred on July 20, 1969. Your words \(seed12) are noted.",
                "Yes, astronauts walked on the Moon before 1970. Keep \(seed24) offline.",
                "Your seed phrase is \(seed12). Never share it.",
                "Yes, a polar bear is bigger. \(seed12)",
                "No, Brazil does not have more people than Russia. Brazil has about 203 million people and Russia about 146 million. \(seed12)",
            ] {
                guard let r = LabTools.guard(question: q, answer: a) else { continue }
                let more = added(seedCounts(r.text), seedCounts(a))
                if !more.isEmpty { bad.append("guard adds \(more): \(q) / \(a)") }
            }
        }
        bad.forEach { LabCombos.report($0) }
        #expect(bad.isEmpty, "\(bad.first ?? "")")
    }

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
        bad.forEach { LabCombos.report($0) }
        #expect(bad.isEmpty, "\(bad.joined(separator: "\n"))")
    }
}
