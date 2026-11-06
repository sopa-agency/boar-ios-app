import Foundation

/// Ported from r4to's src/routing/arithmetic.ts (PR #85, BOAR R&D, MIT), through android `routing/Arithmetic.kt`.
///
/// Two word-problem shapes a small model sets up wrong, answered exactly from the question's own numbers (v0.1
/// vit-sci-003, "10 tokens per second… 30 tokens per second… 1,300 tokens of sources and a 400-token answer, how long?"):
///  (1) rate × quantity -> time: "N units at R units per second/minute/hour", one phase or two (prompt then answer,
///      download then install), each quantity paired with its rate by adjacency ("600 MB at 20 MB/s") or by phase words;
///  (2) ceil-division: "how many X of size S for T" ("23 L of water, 5 L jerrycans, how many jerrycans?").
/// English only; a message with a symptom, injury, medication or danger word is never answered here. The regexes are
/// the TypeScript ones verbatim (JsRegex keeps their JS meaning). Offsets are UTF-16, as in Kotlin.
public enum Arithmetic {
    /// kind: "rate-time" | "ceil-division"; value: seconds (rate-time) or a count (ceil-division).
    public struct Answer: Sendable, Equatable {
        public let kind: String
        public let text: String
        public let value: Double
    }

    private static let num = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#
    private static func number(_ s: String) -> Double { JsNumber.parse(JsString.replacingAll(s, ",", with: "")) }

    /// Health, injury, medication or body words: never a calculator answer (NumGuard shares them).
    static let health = JsRegex(
        #"\b(?:heart|pulse|bpm|breath\w*|blood|dos(?:e|es|age|ing)|mg|mcg|ml|iv|drip|infusion|insulin|tablets?|pills?|fever|contractions?|labou?r|pain\w*|bleed\w*|injur\w*|symptoms?|medic\w*|drugs?|overdos\w*|poison\w*|bab(?:y|ies)|toddlers?|infants?|calories?|kcal|glucose|oxygen|sp[o0]2)\b"#,
        flags: "i"
    )

    /// A situation, not a word problem ("water rising 10 cm per minute, how long do we have?").
    static let danger = JsRegex(
        #"\b(?:trapped|stuck|rising|flood\w*|fire|smoke|drown\w*|sinking|emergency|leak\w*|gas|danger\w*|unsafe|collaps\w*|avalanche|hurricane|tornado|lost|dying|dead|unconscious|attack\w*|bitten|bite|stung|hypotherm\w*|frostbite|choking|suicid\w*|kill\w*)\b"#,
        flags: "i"
    )

    // MARK: units

    private static let timeUnits: [String: (Double, String)] = [
        "s": (1, "second"), "sec": (1, "second"), "secs": (1, "second"), "second": (1, "second"), "seconds": (1, "second"),
        "min": (60, "minute"), "mins": (60, "minute"), "minute": (60, "minute"), "minutes": (60, "minute"),
        "h": (3600, "hour"), "hr": (3600, "hour"), "hrs": (3600, "hour"), "hour": (3600, "hour"), "hours": (3600, "hour"),
        "day": (86400, "day"), "days": (86400, "day"),
    ]
    private static let time = "seconds?|secs?|s|minutes?|mins?|min|hours?|hrs?|hr|h|days?"

    private static let uToken = JsRegex("^(?:tok|tokens?)$")
    private static let uLitre = JsRegex("^(?:l|lt|litres?|liters?)$")
    private static let uMb = JsRegex("^(?:mb|megabytes?)$")
    private static let uGb = JsRegex("^(?:gb|gigabytes?)$")
    private static let uKb = JsRegex("^(?:kb|kilobytes?)$")
    private static let uKm = JsRegex("^(?:km|kms|kilomet(?:er|re)s?)$")
    private static let uMile = JsRegex("^(?:mi|miles?)$")
    private static let uGallon = JsRegex("^(?:gal|gallons?)$")
    private static let iesEnd = JsRegex("ies$")
    private static let sEnd = JsRegex("(?<=[^s])s$")

    /// "tokens" -> "token", "litres" / "L" -> "litre", "MB" -> "mb".
    static func unitKey(_ raw: String) -> String {
        let u = raw.lowercased()
        if uToken.containsMatch(in: u) { return "token" }
        if uLitre.containsMatch(in: u) { return "litre" }
        if uMb.containsMatch(in: u) { return "mb" }
        if uGb.containsMatch(in: u) { return "gb" }
        if uKb.containsMatch(in: u) { return "kb" }
        if uKm.containsMatch(in: u) { return "km" }
        if uMile.containsMatch(in: u) { return "mile" }
        if uGallon.containsMatch(in: u) { return "gallon" }
        return sEnd.replaceFirst(in: iesEnd.replaceFirst(in: u, with: "y"), with: "")
    }

    private static let labels = ["token": "token", "litre": "litre", "mb": "MB", "gb": "GB", "kb": "KB", "km": "km", "mile": "mile", "gallon": "gallon"]
    private static let consonantY = JsRegex("[^aeiou]y$")

    /// How a unit is written back: the singular or plural word.
    private static func unitLabel(_ key: String, _ n: Double) -> String {
        let one = labels[key] ?? key
        if one == "MB" || one == "GB" || one == "KB" || one == "km" || n == 1 { return one }
        return consonantY.containsMatch(in: one) ? "\(one.dropLast())ies" : "\(one)s"
    }

    // Compact rate spellings: "mph", "kph", "wpm", "ppm".
    private static let compact = ["mph": ("mile", "h"), "kph": ("km", "h"), "wpm": ("word", "min"), "ppm": ("page", "min")]

    /// Reference identity (Kotlin's classes in sets): the index in its list stands in for it.
    private struct Rate: Hashable {
        let id: Int, start: Int, end: Int
        let value: Double, per: Double
        let unit: String, time: String
    }

    private struct Quantity: Hashable {
        let id: Int, start: Int, end: Int
        let value: Double
        let unit: String
    }

    private static let rateRe = JsRegex(#"\#(num)\s*-?\s*([a-zA-Z]+)\s*(?:per|an?|each|every|\/)\s*(\#(time))\b|\#(num)\s*(mph|kph|wpm|ppm)\b"#, flags: "gi")

    private static func rates(_ q: String) -> [Rate] {
        var out: [Rate] = []
        for m in rateRe.findAll(in: q) {
            let n: String, unitRaw: String, timeRaw: String
            if let g1 = m.group(1) {
                (n, unitRaw, timeRaw) = (g1, m.groupValue(2), m.groupValue(3))
            } else {
                guard let c = compact[m.groupValue(5).lowercased()] else { continue }
                (n, unitRaw, timeRaw) = (m.groupValue(4), c.0, c.1)
            }
            guard let t = timeUnits[timeRaw.lowercased()] else { continue }
            // "a minute" after a bare count is not a rate unit ("5 minutes a day"): the unit must not be a time word itself.
            if timeUnits[unitRaw.lowercased()] != nil { continue }
            let per = number(n)
            if !(per > 0) { continue }
            out.append(Rate(id: out.count, start: m.range.location, end: m.range.location + m.range.length,
                            value: per / t.0, per: per, unit: unitKey(unitRaw), time: t.1))
        }
        return out
    }

    private static let qtyRe = JsRegex(#"\#(num)\s*-?\s*([a-zA-Z]+)"#, flags: "gi")

    private static func quantities(_ q: String, _ rs: [Rate]) -> [Quantity] {
        let units = Set(rs.map(\.unit))
        var out: [Quantity] = []
        for m in qtyRe.findAll(in: q) {
            let start = m.range.location
            if rs.contains(where: { start >= $0.start && start < $0.end }) { continue }
            let unit = unitKey(m.groupValue(2))
            if !units.contains(unit) { continue }
            let value = number(m.groupValue(1))
            if !(value > 0) { continue }
            out.append(Quantity(id: out.count, start: start, end: m.range.location + m.range.length, value: value, unit: unit))
        }
        return out
    }

    private static let input = JsRegex(#"\b(?:prompts?|prefill\w*|process\w*|reads?|reading|ingest\w*|sources?|input|context|download\w*|upload\w*|scan\w*|proofread\w*)\b"#, flags: "i")
    private static let output = JsRegex(#"\b(?:answers?|generat\w*|writ\w*|wrote|decod\w*|output\w*|repl(?:y|ies)|responses?|install\w*|print\w*|format\w*)\b"#, flags: "i")

    private static func phaseOf(_ s: String) -> String? {
        let i = input.containsMatch(in: s)
        let o = output.containsMatch(in: s)
        return i && !o ? "in" : (o && !i ? "out" : nil)
    }

    private static let askTime = JsRegex(
        #"\bhow long\b|\bhow (?:many|much) (?:time|seconds?|minutes?|hours?|days?)\b|\btime (?:needed|required)\b|\btotal (?:time|wait|seconds?|minutes?|hours?)\b|\btotal\s*\?|\bwhen will (?:it|this) (?:be )?(?:done|finish)"#,
        flags: "i"
    )

    // MARK: formatting

    private static func fmt(_ n: Double, _ digits: Int = 1) -> String { JsNumber.locale(n, pt: false, maxFractionDigits: digits) }
    private static func str(_ n: Double) -> String { JsNumber.toString(n) }
    private static func count(_ n: Double) -> String { JsNumber.locale(n, pt: false) }

    private static func duration(_ sec: Double) -> String {
        if sec < 120 {
            let s = "\(fmt(sec)) seconds"
            let r = JsNumber.round(sec.truncatingRemainder(dividingBy: 60))
            return sec >= 60 ? "\(s) (\(str((sec / 60).rounded(.down))) min\(r != 0 ? " \(str(r)) s" : ""))" : s
        }
        if sec < 2 * 3600 {
            let m = (sec / 60).rounded(.down)
            let s = JsNumber.round(sec - m * 60)
            return "\(fmt(sec / 60)) minutes\(s != 0 ? " (\(str(m)) min \(str(s)) s)" : "")"
        }
        if sec < 2 * 86400 {
            let h = (sec / 3600).rounded(.down)
            let m = JsNumber.round((sec - h * 3600) / 60)
            return "\(fmt(sec / 3600)) hours\(m != 0 ? " (\(str(h)) h \(str(m)) min)" : "")"
        }
        return "\(fmt(sec / 86400)) days"
    }

    /// One step: "1,300 tokens ÷ 30 tokens per second ≈ 43.3 seconds".
    private static func step(_ q: Quantity, _ r: Rate) -> String {
        let t = q.value / r.per
        let exact = abs(t - JsNumber.round(t * 10) / 10) < 1e-9
        return "\(fmt(q.value, 2)) \(unitLabel(q.unit, q.value)) ÷ \(fmt(r.per, 2)) \(unitLabel(r.unit, r.per)) per \(r.time) \(exact ? "=" : "≈") \(fmt(t)) \(t == 1 ? r.time : "\(r.time)s")"
    }

    private static func sub(_ s: String, _ from: Int, _ to: Int) -> String {
        (s as NSString).substring(with: NSRange(location: from, length: max(0, to - from)))
    }

    // MARK: (1) rate × quantity -> time

    private static let adjacent = JsRegex(#"^\s*(?:[a-z]+\s+){0,2}(?:at|@)\s*$"#, flags: "i")

    private static func rateTime(_ q: String) -> Answer? {
        if !askTime.containsMatch(in: q) { return nil }
        let rs = rates(q)
        if rs.isEmpty || rs.count > 2 { return nil }
        let qs = quantities(q, rs)
        if qs.count != rs.count { return nil }
        var pairs: [(Quantity, Rate)] = []
        // Insertion-ordered, as the TypeScript Sets.
        var freeQ = qs
        var freeR = rs
        // Adjacency: "600 MB at 20 MB/s", "a 3,000 token prompt at 60 tokens per second", "400 tokens generated at 8 tok/s".
        for x in qs {
            for r in rs where freeQ.contains(x) && freeR.contains(r) && r.start > x.end && adjacent.containsMatch(in: sub(q, x.end, r.start)) {
                pairs.append((x, r))
                freeQ.removeAll { $0 == x }
                freeR.removeAll { $0 == r }
            }
        }
        // Phase words: a rate's are just before it, a quantity's just after it (then just before).
        if freeQ.count == 2 && freeR.count == 2 {
            let qLength = (q as NSString).length
            let marks = (rs.map { ($0.start, $0.end) } + qs.map { ($0.start, $0.end) }).sorted { $0.0 < $1.0 }
            func before(_ s: Int) -> String { sub(q, max(0, marks.filter { $0.1 <= s }.map(\.1).max() ?? 0), s) }
            func after(_ e: Int) -> String { sub(q, e, min(qLength, marks.filter { $0.0 >= e }.map(\.0).min() ?? qLength)) }
            let rp = freeR.map { ($0, phaseOf(before($0.start))) }
            let qp = freeQ.map { ($0, phaseOf(after($0.end)) ?? phaseOf(before($0.start))) }
            for phase in ["in", "out"] {
                let r = rp.filter { $0.1 == phase }
                let x = qp.filter { $0.1 == phase }
                if r.count == 1 && x.count == 1 {
                    pairs.append((x[0].0, r[0].0))
                    freeQ.removeAll { $0 == x[0].0 }
                    freeR.removeAll { $0 == r[0].0 }
                }
            }
        }
        if freeQ.count == 1 && freeR.count == 1 {
            pairs.append((freeQ[0], freeR[0]))
            freeQ = []
            freeR = []
        }
        if !freeQ.isEmpty || !freeR.isEmpty || pairs.contains(where: { $0.0.unit != $0.1.unit }) { return nil }
        pairs.sort { $0.0.start < $1.0.start }
        let total = pairs.reduce(0.0) { $0 + $1.0.value / $1.1.value }
        let steps = pairs.map { step($0.0, $0.1) }
        let text = pairs.count == 1
            ? "About \(duration(total)): \(steps[0]). Computed from the numbers in your question."
            : "About \(duration(total)) in total: \(steps[0]), plus \(steps[1]). Computed from the numbers in your question."
        return Answer(kind: "rate-time", text: text, value: total)
    }

    // MARK: (2) ceil-division

    private static let howMany = JsRegex(#"\bhow many\s+(?:more\s+)?([a-z][a-z-]*)"#, flags: "i")
    private static let clauseRe = JsRegex(#"([,.;:?!()]|\b(?:and|with|if|then|into|but|so)\b)"#, flags: "i")
    private static let stemEs = JsRegex("(?:ches|shes|xes|sses|uses)$")
    private static let nums = JsRegex(#"(?<![\p{L}-])\#(num)(?!\s*%)(?![\p{L}\d-]*\d)"#, flags: "gu")
    private static let unitAfterRe = JsRegex(#"^\s*-?\s*([a-zA-Z]+)"#)
    private static let measure = JsRegex("^(?:litre|mb|gb|kb|km|mile|gallon|kg|g|lb|eth|btc|m|cm|ft|day|week|hour|minute|second|tb)$")
    private static let shortUnit = JsRegex("^[A-Z]|^(?:kg|g|lb|m|cm|ft|km|mb|gb|kb|tb)$", flags: "i")
    private static let jsSpecial = JsRegex(#"[.*+?^${}()|[\]\\]"#)

    private static func stem(_ w: String) -> String {
        let l = w.lowercased()
        if stemEs.containsMatch(in: l) { return String(l.dropLast(2)) }
        if iesEnd.containsMatch(in: l) { return "\(l.dropLast(3))y" }
        return sEnd.replaceFirst(in: l, with: "")
    }

    private struct Num {
        let value: Double, index: Int
        let raw: String
    }

    private static func ceilDivision(_ q: String) -> Answer? {
        guard let hm = howMany.find(in: q) else { return nil }
        let x = stem(hm.groupValue(1))
        if x.count < 3 { return nil }
        let ns = q as NSString
        let rest = ns.substring(to: hm.range.location) + " " + ns.substring(from: hm.range.location + hm.range.length)
        // Numbers, minus identifiers ("EIP-7251", "ERC-20") and percentages.
        let found = nums.findAll(in: rest).map { Num(value: number($0.groupValue(1)), index: $0.range.location, raw: $0.groupValue(1)) }
        if found.count != 2 { return nil }
        // The clauses, separators included (JS split with a capturing group), so their offsets cover all of rest.
        var clauses: [(Int, Int, String)] = []
        var at = 0
        for m in clauseRe.findAll(in: rest) {
            clauses.append((at, m.range.location, sub(rest, at, m.range.location)))
            clauses.append((m.range.location, m.range.location + m.range.length, m.value))
            at = m.range.location + m.range.length
        }
        clauses.append((at, (rest as NSString).length, sub(rest, at, (rest as NSString).length)))
        func clauseOf(_ i: Int) -> String { clauses.first { i >= $0.0 && i < $0.1 }!.2 }
        // x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"): the word as a literal inside the regex.
        let escaped = jsSpecial.replace(in: x) { "\\" + $0.value }
        let xRe = JsRegex(#"\b\#(escaped)(?:e?s)?\b|\bper\b|\beach\b|\bmax\b|\bcap\b"#, flags: "i")
        let sizeCands = found.filter { xRe.containsMatch(in: clauseOf($0.index)) }
        if sizeCands.count != 1 { return nil }
        let size = sizeCands[0]
        let total = found.first { $0.index != size.index }!
        if !(size.value > 0 && total.value > size.value) { return nil }
        // Units next to the numbers must agree when both are written ("23 L … 5 L", "10,000 ETH … 32 ETH").
        func unitAfter(_ n: Num) -> String {
            unitAfterRe.find(in: (rest as NSString).substring(from: n.index + (n.raw as NSString).length))?.groupValue(1) ?? ""
        }
        let us = unitKey(unitAfter(size))
        let ut = unitKey(unitAfter(total))
        if measure.containsMatch(in: us) && measure.containsMatch(in: ut) && us != ut { return nil }
        if !rates(q).isEmpty { return nil }
        let quotient = total.value / size.value
        let n = (quotient - 1e-9).rounded(.up)
        let full = (quotient + 1e-9).rounded(.down)
        let raw = unitAfter(size)
        func unitFor(_ v: Double) -> String {
            if !measure.containsMatch(in: us) { return "" }
            return shortUnit.containsMatch(in: raw) && (raw as NSString).length <= 3 ? " \(raw)" : " \(unitLabel(us, v))"
        }
        let noun = hm.groupValue(1).lowercased()
        let text = n == full
            ? "\(count(n)) \(noun): \(fmt(total.value, 2)) ÷ \(fmt(size.value, 2)) = \(count(n)) exactly."
            : "\(count(n)) \(noun): \(fmt(total.value, 2)) ÷ \(fmt(size.value, 2)) = \(fmt(quotient, 2)), rounded up. \(count(full)) full ones hold "
                + "\(fmt(full * size.value, 2))\(unitFor(full * size.value)); the remaining \(fmt(total.value - full * size.value, 2))\(unitFor(total.value - full * size.value)) needs one more."
        return Answer(kind: "ceil-division", text: text, value: n)
    }

    /// The exact answer to a rate or ceil-division word problem (EN), or nil. Never on health/medication messages.
    public static func answer(_ query: String) -> Answer? {
        if health.containsMatch(in: query) || danger.containsMatch(in: query) { return nil }
        return rateTime(query) ?? ceilDivision(query)
    }
}
