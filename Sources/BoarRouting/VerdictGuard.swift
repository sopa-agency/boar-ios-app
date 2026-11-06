import Foundation

/// Ported from src/routing/verdictGuard.ts in r4to's PR #85 (BOAR R&D, MIT), through android `routing/VerdictGuard.kt`.
///
/// VG, the verdict guard (cut 3 dev; coordinator 4B-LOSS-ANATOMY, arm 1). The 4B commits to its first-sentence verdict
/// before it states the facts, and the facts are often right: "No, astronauts did not walk on the Moon before 1970. The
/// first human moonwalk occurred on July 20, 1969". A pure check of question + answer after generation. English only; run
/// on model answers only (never health, cards, calculators).
///  (a) date: a yes/no question with "before / after / by YYYY"; the Yes/No disagrees with the year of the answer's own
///      "first …" fact (within the two sentences after the verdict).
///  (b) compare: "Which <is more X>, A or B" / "Is A <more X> than B"; both entities get a number of the compared quantity
///      (density, people, area, length, mass, age) in the same unit, the ranges don't overlap, and the verdict names the
///      other one (or says the wrong Yes/No). Ambiguous, mixed units or a missing quantity: no flag.
///  (c) rank: "Which <things> are bigger than X" answered "No <thing> is bigger…" next to "X … the Nth-largest" (N > 1),
///      and any list the answer gives has N - 1 items.
/// Repair is a template from the parsed facts (plus the difference and ratio when the question asks "by how much"); the
/// model's self-correction notes and restatements of the old verdict are dropped. No regeneration. v3 abstains when a
/// number may belong to someone else, on a non-world rank scope or a subject inside another name, and on a "first …"
/// sentence with two years. An answer that isn't flagged gives nil: nothing about it changes. The regexes are the
/// TypeScript ones verbatim, through JsRegex; offsets are UTF-16, as in Kotlin.
public enum VerdictGuard {
    /// `kind`: "date", "compare" or "rank".
    public struct Result: Sendable, Equatable {
        public let kind: String
        public let text: String
        public init(kind: String, text: String) { self.kind = kind; self.text = text }
    }

    // MARK: text segments (sentences and list lines), kept with their separators so a repair only touches what it drops

    private final class Seg {
        let text: String
        var sep: String
        init(_ text: String, _ sep: String) { self.text = text; self.sep = sep }
    }

    private static func re(_ s: String, _ flags: String = "") -> JsRegex { JsRegex(s, flags: flags) }

    private static func sub(_ s: String, _ from: Int, _ to: Int? = nil) -> String {
        let ns = s as NSString
        let end = to ?? ns.length
        return ns.substring(with: NSRange(location: from, length: end - from))
    }

    private static func len(_ s: String) -> Int { s.utf16.count }

    /// Inline self-correction notes: "(Note: This response contains a factual error…)", "[Note: …]".
    private static let inlineNote = re(#"\s*[(\[]\s*note:[^)\]]*[)\]]"#, "gi")
    private static let meta = re(
        #"^(?:wait\b|correct(?:ed|ion|ing)?\s*:|\(?\[?note\s*:)|\bthis (?:response|answer) contains (?:a |an )?(?:factual )?error\b|\bcontradicts the previous\b"#,
        "i"
    )
    private static let splitRe = re(#"((?<=[.!?:])[ \t]+(?=["'(\[*A-Z-])|\s*\n+\s*)"#)

    private static func segments(_ text: String) -> [Seg] {
        // String.prototype.split with a capturing separator: text, separator, text, …
        var parts: [String] = []
        var at = 0
        for m in splitRe.findAll(in: text) {
            parts.append(sub(text, at, m.range.location))
            parts.append(m.value)
            at = m.range.location + m.range.length
        }
        parts.append(sub(text, at))
        var out: [Seg] = []
        var i = 0
        while i < parts.count {
            let t = parts[i]
            let sep = i + 1 < parts.count ? parts[i + 1] : ""
            if JsString.trim(t).isEmpty {
                if let last = out.last { last.sep += sep }
            } else {
                out.append(Seg(t, sep))
            }
            i += 2
        }
        return out
    }

    private static func join(_ segs: [Seg]) -> String {
        JsString.trim(segs.enumerated().map { i, s in s.text + (i < segs.count - 1 ? s.sep : "") }.joined())
    }

    private static func isMeta(_ s: String) -> Bool { meta.containsMatch(in: JsString.trim(s)) }

    // MARK: numbers

    private static let num = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#
    private static let scaleWords: [String: Double] = ["thousand": 1e3, "million": 1e6, "billion": 1e9, "trillion": 1e12]
    private static let numberRe = re("\(num)(?:\\s*(?:–|—|-|to)\\s*\(num))?(?:\\s+(thousand|million|billion|trillion)\\b)?", "gi")
    private static func number(_ s: String) -> Double { JsNumber.parse(JsString.replacingAll(s, ",", with: "")) }

    private struct Quantity {
        let lo: Double, hi: Double
        let unit: String
        let index: Int
    }

    private static let unitStop: Set<String> = ["while", "and", "whereas", "compared", "than", "which", "in", "on", "at", "for", "but", "making", "so", "or", "as", "with", "versus", "vs"]
    private static let unitHead = re(#"^\s*([^,;.()\[\]]{0,48})"#)
    private static let unitRules: [(JsRegex, String)] = [
        (re(#"\b(?:square|sq\.?)\s+(?:kilomet(?:er|re)s?|km)\b|\bkm²|\bkm2\b"#, "g"), "km2"),
        (re(#"\b(?:square|sq\.?)\s+miles?\b|\bmi²"#, "g"), "mi2"),
        (re(#"\bkilomet(?:er|re)s?\b"#, "g"), "km"),
        (re(#"\bmet(?:er|re)s?\b"#, "g"), "m"),
        (re(#"\b(?:pounds?|lbs?)\b"#, "g"), "lb"),
        (re(#"\bkilo(?:gram)?s?\b|\bkgs\b"#, "g"), "kg"),
        (re(#"\b(?:feet|foot)\b"#, "g"), "ft"),
        (re(#"\bpersons\b"#, "g"), "people"),
    ]
    private static let spaces = re(#"\s+"#)

    /// "people per square kilometer, while…" -> "people per km2"; "lb (700 kg)" -> "lb".
    private static func unitSig(_ rest: String) -> String {
        var head = (unitHead.find(in: rest)?.groupValue(1) ?? "").lowercased()
        for (r, to) in unitRules { head = r.replace(in: head, with: to) }
        var words: [String] = []
        for w in spaces.split(head) where !w.isEmpty {
            if unitStop.contains(w) || words.count >= 4 { break }
            words.append(w)
        }
        return words.joined(separator: " ")
    }

    private static let fourDigits = re(#"^\d{4}$"#)
    private static let notAMeasure = re(#"^\s*(?:%|st\b|nd\b|rd\b|th\b)"#)

    /// Every number (or range) in `s`, with its scale and unit, in order. Bare years (1500-2100, no unit), percentages and
    /// ranks ("7th") are skipped.
    private static func allQuantities(_ s: String) -> [Quantity] {
        var out: [Quantity] = []
        for m in numberRe.findAll(in: s) {
            let g1 = m.groupValue(1)
            let g2 = m.group(2)
            let g3 = m.group(3)
            let scale = g3.map { scaleWords[$0.lowercased()]! } ?? 1.0
            let a = number(g1) * scale
            let b = g2.map { number($0) * scale } ?? a
            let after = sub(s, m.range.location + m.range.length)
            let unit = (g3.map { "\($0.lowercased()) " } ?? "") + unitSig(after)
            let yearLike = g2 == nil && g3 == nil && fourDigits.containsMatch(in: g1) && a >= 1500 && a <= 2100 && unitSig(after).isEmpty
            if yearLike { continue }
            // A percentage or a rank ("7th") is not a measurement of the entity.
            if notAMeasure.containsMatch(in: after) { continue }
            out.append(Quantity(lo: min(a, b), hi: max(a, b), unit: JsString.trim(unit), index: m.range.location))
        }
        return out
    }

    // MARK: the compared quantity (VG v2: the number tied to the question's quantity, never just the first)

    private static let qDensity = re(#"\bdens(?:e|ely|er|est|ity)\b"#, "i")
    private static let qPeople = re(#"\b(?:more|fewer|less) (?:people|inhabitants|residents)\b|\bpopul(?:ous|ation)\b"#, "i")
    private static let qAge = re(#"\b(?:older|younger)\b"#, "i")
    private static let qArea = re(#"\barea\b|\bsquare\b"#, "i")
    private static let qLength = re(#"\b(?:taller|higher|longer|deeper|shallower)\b"#, "i")
    private static let qMass = re(#"\b(?:heavier|lighter|weighs?|weight)\b"#, "i")
    private static let qSize = re(#"\b(?:bigger|larger|smaller|greater)\b"#, "i")

    /// The quantity a comparison question is about; nil = unclear (no flag). Generic size words allow area, mass or length.
    private static func questionClasses(_ q: String) -> [String]? {
        if qDensity.containsMatch(in: q) { return ["density"] }
        if qPeople.containsMatch(in: q) { return ["people"] }
        if qAge.containsMatch(in: q) { return ["age"] }
        if qArea.containsMatch(in: q) { return ["area"] }
        if qLength.containsMatch(in: q) { return ["length"] }
        if qMass.containsMatch(in: q) { return ["mass"] }
        if qSize.containsMatch(in: q) { return ["area", "mass", "length"] }
        return nil
    }

    private static let uDensity = re(#"\bper (?:km2|mi2)\b|\/ ?(?:km2|mi2)\b"#)
    private static let uAge = re(#"\b(?:years? old|year-old|years of age)\b"#)
    private static let uArea = re(#"\b(?:km2|mi2|hectares?|acres?)\b"#)
    private static let uScale = re(#"^(?:thousand|million|billion|trillion) "#)
    private static let uMass = re(#"^(?:kg|lb|g|tons?|tonnes?|t|grams?|ounces?|oz)$"#)
    private static let uLength = re(#"^(?:m|km|ft|mi|miles?|cm|mm|inch(?:es)?|in|yards?|yd)$"#)
    private static let uPeople = re(#"\b(?:people|inhabitants|residents|citizens)\b"#)
    private static let uPeopleScale = re(#"^(?:thousand|million|billion)$"#)

    private static func unitClass(_ unit: String) -> String? {
        if uDensity.containsMatch(in: unit) { return "density" }
        if uAge.containsMatch(in: unit) { return "age" }
        if uArea.containsMatch(in: unit) { return "area" }
        let first = JsString.split(uScale.replaceFirst(in: unit, with: ""), " ")[0]
        if uMass.containsMatch(in: first) { return "mass" }
        if uLength.containsMatch(in: first) { return "length" }
        if uPeople.containsMatch(in: unit) || uPeopleScale.containsMatch(in: unit) { return "people" }
        return nil
    }

    // MARK: comparatives

    private static let moreWords =
        "more|bigger|larger|greater|higher|denser|older|taller|longer|heavier|deeper|hotter|warmer|faster|richer|wider|farther|further|stronger|wealthier|busier|louder|brighter"
    private static let lessWords = "less|fewer|smaller|lower|younger|shorter|lighter|shallower|colder|cooler|slower|poorer|narrower|weaker|cheaper"
    private static let more = re("\\b(?:\(moreWords))\\b", "i")
    private static let less = re("\\b(?:\(lessWords))\\b", "i")
    private static let lessAll = re("\\b(?:\(lessWords))\\b", "gi")
    private static let moreWord = re(#"\bmore\b"#, "i")
    private static let lessOrFewer = re(#"\b(?:less|fewer)\b"#, "i")
    private static let comparative = "(?:\(moreWords)|\(lessWords))"

    /// "max" when the bigger number wins ("more densely populated"), "min" for "smaller / fewer", nil when unclear.
    private static func polarity(_ s: String) -> String? {
        let isLess = less.containsMatch(in: s)
        let isMore = more.containsMatch(in: s)
        if isLess && !moreWord.containsMatch(in: lessAll.replace(in: s, with: "")) { return "min" }
        if lessOrFewer.containsMatch(in: s) { return "min" }
        if isMore { return "max" }
        return nil
    }

    private static let entityStop: Set<String> = ["the", "a", "an", "of", "adult", "male", "female", "average", "on", "in", "typical", "common", "wild"]
    private static let word = re(#"[\p{L}\p{N}]+"#)
    private static func words(_ s: String) -> [String] { word.findAll(in: s.lowercased()).map(\.value) }

    /// Words that tell the two entities apart ("saltwater" vs "nile"; "moose" vs "american", "bison").
    private static func entityKeys(_ a: String, _ b: String) -> ([String], [String]) {
        let wa = words(a).filter { !entityStop.contains($0) }
        let wb = words(b).filter { !entityStop.contains($0) }
        return (wa.filter { !wb.contains($0) }, wb.filter { !wa.contains($0) })
    }

    private static func mentionRe(_ keys: [String]) -> JsRegex {
        let alt = keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return JsRegex("(?<![\\p{L}])(?:\(alt))(?:'s|’s|s|es)?(?![\\p{L}])", flags: "iu")
    }

    private struct Mention {
        let who: Int, index: Int, end: Int
    }

    private static func mentions(_ s: String, _ res: [JsRegex]) -> [Mention] {
        var out: [Mention] = []
        for who in 0...1 {
            for m in res[who].findAll(in: s) { out.append(Mention(who: who, index: m.range.location, end: m.range.location + m.range.length)) }
        }
        // Kotlin's sortedBy is stable: ties keep entity 0's mention first.
        return out.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }.map(\.element)
    }

    /// After a possessive mention ("Germany's …"), the words before the number must name the compared quantity itself.
    private static let ownMeasure = re(
        #"^\s*(?:(?:total|land|average|overall|population|surface|estimated|current|mean|peak|summit|official)\s+)*(?:population density|density|population|area|size|height|elevation|altitude|length|weight|mass|diameter|width|age)\b|^\s*(?:is|was|are|were|of|stands|sits|reaches|averages|measures|weighs|covers)\b"#,
        "i"
    )
    private static let capitalised = re(#"(?<![\p{L}\p{N}])\p{Lu}[\p{L}-]*"#)
    private static let possessiveEnd = re(#"['’]s$"#, "i")

    /// A capitalised word (not the entities' own key words) or "in <Name>" between an entity's mention and its number.
    private static func otherOwner(_ between: String, _ keys: [String]) -> Bool {
        let own = Set(keys.map { $0.lowercased() })
        return capitalised.findAll(in: between).contains { !own.contains(possessiveEnd.replace(in: $0.value.lowercased(), with: "")) }
    }

    /// Each entity's stated quantity of the compared kind: from its mention to the other entity's next mention, within one
    /// segment, the numbers whose unit fits the question's quantity. Two different same-unit values in one window: ambiguous.
    private static func quantities(_ segs: [Seg], _ res: [JsRegex], _ classes: [String], _ keys: [String]) -> [Quantity?]? {
        var found: [Quantity?] = [nil, nil]
        for seg in segs {
            let text = seg.text
            let ms = mentions(text, res)
            for i in ms.indices {
                let m = ms[i]
                if found[m.who] != nil { continue }
                let nextOther = ms[(i + 1)...].first { $0.who != m.who }
                let window = sub(text, m.index, nextOther?.index ?? len(text))
                let fit = allQuantities(window).filter { q in unitClass(q.unit).map { classes.contains($0) } == true }
                guard let f0 = fit.first else { continue }
                // VG v3 F1: the number must be the entity's own. Abstain when a capitalised name or an "in <Name>" phrase
                // sits between the mention and the number, or the mention is a possessive of something other than the
                // compared quantity ("Saturn's rings are 282,000 km wide").
                let from = m.end - m.index
                let between = from <= f0.index ? sub(window, from, f0.index) : ""
                if otherOwner(between, keys) { return nil }
                if possessiveEnd.containsMatch(in: sub(text, m.index, m.end)) && !ownMeasure.containsMatch(in: between) { return nil }
                if fit.contains(where: { $0.unit == f0.unit && ($0.lo != f0.lo || $0.hi != f0.hi) }) { return nil }
                found[m.who] = f0
            }
            if found[0] != nil && found[1] != nil { break }
        }
        return found
    }

    // MARK: formatting

    private static func fmt(_ n: Double) -> String { JsNumber.locale(n, pt: false, maxFractionDigits: n >= 100 ? 0 : n >= 10 ? 1 : 2) }
    private static func capitalize(_ s: String) -> String { s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst() }
    private static let cardinals = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
    private static let ordinals: [String: Int] = [
        "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20,
    ]

    /// A shown entity name: the question's own words, article kept.
    private static func display(_ s: String) -> String { spaces.replace(in: JsString.trim(s), with: " ") }

    // MARK: (a) date threshold

    private static let yesNoQ = re(#"^\s*(?:did|was|were|has|have|had|is|are|do|does)\b"#, "i")
    private static let threshold = re(#"\b(before|after|by)\s+(?:the\s+(?:year\s+)?)?(1\d{3}|20\d{2})\b"#, "i")
    private static let verdictRe = re(#"^\s*(yes|no)\b[,.!:;—–-]?\s*"#, "i")
    private static let negation = re(#"\b(did|was|were|had|has|have|is|are|could|would)(?:\s+not\b|n't\b)"#, "i")
    private static let negationAll = re(#"\b(did|was|were|had|has|have|is|are|could|would)(?:\s+not\b|n't\b)"#, "gi")
    private static let firstRe = re(#"\bfirst\b"#, "i")
    private static let year = re(#"\b(?:1\d{3}|20\d{2})\b"#)
    private static let yearAll = re(#"\b(?:1\d{3}|20\d{2})\b"#, "g")
    private static let yearGroup = re(#"\b(1\d{3}|20\d{2})\b"#)
    private static let absolute = re(#"\b(?:never|no|none|nobody)\b"#, "i")
    private static let denies = re(#"\b(?:no|not|never|none|n't)\b"#, "i")

    private static func checkDate(_ question: String, _ segs: [Seg]) -> Result? {
        guard yesNoQ.containsMatch(in: question), let t = threshold.find(in: question) else { return nil }
        let rel = t.groupValue(1).lowercased()
        let limit = Int(t.groupValue(2))!
        guard let v = verdictRe.find(in: segs[0].text) else { return nil }
        let said = v.groupValue(1).lowercased() == "yes"
        guard let factAt = segs.indices.first(where: { (1...2).contains($0) && firstRe.containsMatch(in: segs[$0].text) && year.containsMatch(in: segs[$0].text) })
        else { return nil }
        // VG v3 F3: a "first …" sentence with more than one year ("first plans from 1802, but it opened in 1994") can't
        // say which year is the event's: abstain.
        if Set(yearAll.findAll(in: segs[factAt].text).map(\.value)).count > 1 { return nil }
        let first = Int(yearGroup.find(in: segs[factAt].text)!.groupValue(1))!
        // The first time it happened decides "before / by" both ways; "after" only when the first time is already after.
        let truth: Bool? = switch rel {
        case "before": first < limit
        case "by": first <= limit
        default: first > limit ? true : nil
        }
        guard let truth, truth != said else { return nil }

        let rest = sub(segs[0].text, len(v.value))
        let verdict: String
        if truth {
            if negationAll.findAll(in: rest).count == 1 && !absolute.containsMatch(in: rest), let n = negation.find(in: rest) {
                // Kotlin replaceFirst(rest, "$1"): the negated auxiliary without its "not".
                verdict = "Yes, " + sub(rest, 0, n.range.location) + n.groupValue(1) + sub(rest, n.range.location + n.range.length)
            } else {
                verdict = "Yes."
            }
        } else {
            verdict = "No."
        }
        let alt = switch rel {
        case "before": "pre-"
        case "after": "post-"
        default: "x^"
        }
        let phrase = re("\\b(?:\(t.groupValue(1))\\s+(?:the\\s+(?:year\\s+)?)?|\(alt))\(t.groupValue(2))\\b", "i")
        let kept = segs.dropFirst().filter { !isMeta($0.text) && !(phrase.containsMatch(in: $0.text) && denies.containsMatch(in: $0.text)) }
        return Result(kind: "date", text: join([Seg(verdict, segs[0].sep)] + kept))
    }

    // MARK: (b) two-entity numeric comparison

    private static let whichQ = re(
        "^\\s*(?:which|who|what)\\s+(.*?\\b\(comparative)\\b.*?)\\s*[,:]\\s*(.+?)\\s+or\\s+(.+?)(?:\\s*,\\s*and\\b.*?|\\s+and\\s+by\\s+how\\s+much.*?)?\\s*\\?\\s*$",
        "i"
    )
    private static let yesNoCmpQ = re(
        "^\\s*(?:is|are|was|were|does|do|did|has|have)\\s+(.+?)\\s+((?:have\\s+|has\\s+)?(?:a\\s+)?\(comparative)\\b.*?)\\s+than\\s+(.+?)\\s*\\?\\s*$",
        "i"
    )
    private static let byHowMuch = re(#"\bby how much\b|\bhow much (?:more|less|bigger|larger|denser)\b|\bhow many more\b"#, "i")
    private static let thanRe = re(#"\bthan\b"#, "i")
    private static let whileRe = re(#"\bwhile\b|\bwhereas\b"#, "i")
    private static let digit = re(#"\d"#)
    private static let km2 = re(#"\bkm2\b"#)
    private static let mi2 = re(#"\bmi2\b"#)

    private static func checkCompare(_ question: String, _ segs: [Seg]) -> Result? {
        let which = whichQ.find(in: question)
        let yesno = which == nil ? yesNoCmpQ.find(in: question) : nil
        guard let q = which ?? yesno else { return nil }
        let vp = which != nil ? q.groupValue(1) : q.groupValue(2)
        let a = which != nil ? q.groupValue(2) : q.groupValue(1)
        let b = q.groupValue(3)
        guard let pol = polarity(vp) else { return nil }
        let (ka, kb) = entityKeys(a, b)
        if ka.isEmpty || kb.isEmpty { return nil }
        let res = [mentionRe(ka), mentionRe(kb)]
        guard let classes = questionClasses(question) else { return nil }
        let content = segs.filter { !isMeta($0.text) }
        guard let qs = quantities(content, res, classes, ka + kb), let qa = qs[0], let qb = qs[1] else { return nil }
        if qa.unit != qb.unit { return nil }
        if qa.lo <= qb.hi && qb.lo <= qa.hi { return nil } // overlapping ranges: no decision
        let aWins = pol == "max" ? qa.lo > qb.hi : qa.hi < qb.lo

        func both(_ s: String) -> Bool {
            let ms = mentions(s, res)
            return ms.contains { $0.who == 0 } && ms.contains { $0.who == 1 }
        }
        let v0 = segs[0].text
        if yesno != nil {
            guard let v = verdictRe.find(in: v0) else { return nil }
            if (v.groupValue(1).lowercased() == "yes") == aWins { return nil }
            let verdict = aWins ? "Yes." : "No."
            let kept = segs.dropFirst().filter { !isMeta($0.text) && !(both($0.text) && polarity($0.text) != nil && !digit.containsMatch(in: $0.text)) }
            return Result(kind: "compare", text: join([Seg(verdict, segs[0].sep)] + kept))
        }

        // Which-form: whom does the verdict sentence name as the winner?
        let ms = mentions(v0, res)
        if ms.isEmpty { return nil }
        guard let vpol = polarity(v0) else { return nil }
        let named: Int
        if let than = thanRe.find(in: v0), ms.contains(where: { $0.index < than.range.location }), ms.contains(where: { $0.index > than.range.location }) {
            named = ms.first { $0.index < than.range.location }!.who
        } else if Set(ms.map(\.who)).count == 1 {
            named = ms[0].who
        } else {
            return nil
        }
        let claimedA = vpol == pol ? named == 0 : named == 1
        if claimedA == aWins { return nil }

        let (w, l) = aWins ? (a, b) : (b, a)
        let (qw, ql) = aWins ? (qa, qb) : (qb, qa)
        let verb = spaces.replace(in: JsString.trim(vp), with: " ")
        var verdict = "\(capitalize(display(w))) \(verb) than \(display(l))"
        // Difference and ratio only for two single positive values (VG v2: never for ranges).
        if byHowMuch.containsMatch(in: question) && qw.lo == qw.hi && ql.lo == ql.hi && ql.lo > 0 {
            let diff = abs(qw.lo - ql.lo)
            let ratio = max(qw.lo, ql.lo) / min(qw.lo, ql.lo)
            let unit = mi2.replaceFirst(in: km2.replaceFirst(in: qw.unit, with: "km²"), with: "mi²")
            verdict += ", by about \(fmt(diff))\(unit.isEmpty ? "" : " \(unit)") (\(fmt(qw.lo)) versus \(fmt(ql.lo)), about \(TravelDistance.toFixed(ratio, 1)) times as much)"
        }
        verdict += "."
        // Restatements of the verdict (both entities and a comparative, no figures) go; the figures stay.
        let kept = segs.dropFirst().filter { !isMeta($0.text) && !(both($0.text) && polarity($0.text) != nil && !whileRe.containsMatch(in: $0.text)) }
        return Result(kind: "compare", text: join([Seg(verdict, segs[0].sep)] + kept))
    }

    // MARK: (c) rank

    private static let rankQ = re(#"^\s*which\s+([\p{L} ]+?)\s+(are|is)\s+((?:bigger|larger|greater)\b.*?)\s*\?\s*$"#, "iu")
    private static let denial = re(
        #"\b(?:no|none of the)\s+[\p{L}]+(?:\s+[\p{L}]+)?\s+(?:is|are|has|have)\s+(?:any\s+)?(?:bigger|larger|greater)\b|\bthere (?:is|are) no\s+[\p{L}]+(?:\s+[\p{L}]+)?\s+(?:bigger|larger|greater)\b"#,
        "iu"
    )
    private static let rank = re(
        #"\b(second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|(\d{1,2})(?:st|nd|rd|th))[- ](?:largest|biggest)\b"#,
        "i"
    )
    private static let list = re(
        #"\b(?:after|following|behind)\s+((?:the\s+)?[A-Z][\p{L}.]*(?:\s+[A-Z][\p{L}.]*)*(?:\s*,\s*(?:and\s+)?(?:the\s+)?[A-Z][\p{L}.]*(?:\s+[A-Z][\p{L}.]*)*)+)"#,
        "u"
    )
    private static let includeList = re(
        #"\b(?:include|includes|including)\s*:?\s+((?:the\s+)?[A-Z][\p{L}.]*(?:\s+[A-Z][\p{L}.]*)*(?:\s*,\s*(?:and\s+)?(?:the\s+)?[A-Z][\p{L}.]*(?:\s+[A-Z][\p{L}.]*)*)+)"#,
        "u"
    )
    private static let bullet = re(#"^\s*(?:[-*•]|\d{1,2}[.)])\s+\S"#)
    private static let subject = re(#"\bthan\s+(?:the\s+)?(.+?)(?:\s+(?:by|in|when|on)\b.*)?$"#, "i")
    private static let otherScope = re(#"\b(?:in|of|within)\s+(?:the\s+)?(?!world\b)(?:\p{Lu}[\p{L}-]*|EU|continent|region|hemisphere)"#, "u")
    /// The TypeScript's lookbehind (?<![\p{Lu}][\p{L}.-]*\s+), as a test of the text before the subject.
    private static let afterName = re(#"\p{Lu}[\p{L}.-]*\s+\z"#)
    private static let letterOrNumber = re(#"^[\p{L}\p{N}]$"#)
    private static let itemSplit = re(#"\s*,\s*(?:and\s+)?|\s+and\s+"#)
    private static let trailingDots = re(#"[.]+$"#)
    private static let ies = re("ies$", "i")
    private static let pluralS = re("(?<!s)s$", "i")

    /// `subject` on word boundaries and not right after another capitalised word ("South Sudan" is not "Sudan").
    private static func namesSubject(_ text: String, _ subject: String) -> Bool {
        let ns = text as NSString
        let units = Array(text.utf16)
        func isLetterOrNumber(_ at: Int) -> Bool {
            guard at >= 0, at < units.count else { return false }
            return letterOrNumber.containsMatch(in: String(decoding: [units[at]], as: UTF16.self))
        }
        var from = 0
        while from <= ns.length {
            let r = ns.range(of: subject, options: .literal, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { return false }
            let i = r.location
            from = i + 1
            if isLetterOrNumber(i - 1) || isLetterOrNumber(i + len(subject)) { continue }
            if afterName.containsMatch(in: sub(text, 0, i)) { continue }
            return true
        }
        return false
    }

    private static func checkRank(_ question: String, _ segs: [Seg]) -> Result? {
        guard let q = rankQ.find(in: question) else { return nil }
        if !segs.contains(where: { denial.containsMatch(in: $0.text) }) { return nil }
        // VG v2: the rank must be the subject's own ("India is the seventh-largest").
        let subj = subject.find(in: q.groupValue(3)).map { JsString.trim($0.groupValue(1)) } ?? ""
        if subj.isEmpty { return nil }
        // VG v3 F2: and it must be a world rank: any other scope ("in Africa", "in the EU") abstains.
        guard let rankSeg = segs.first(where: { rank.containsMatch(in: $0.text) && namesSubject($0.text, subj) }) else { return nil }
        let r = rank.find(in: rankSeg.text)!
        if otherScope.containsMatch(in: sub(rankSeg.text, r.range.location)) { return nil }
        guard let n = r.group(2).flatMap({ Int($0) }) ?? ordinals[r.groupValue(1).lowercased()] else { return nil }
        if !(n > 1 && n <= 50) { return nil }
        let count = n - 1
        var noun = JsString.trim(q.groupValue(1))
        let be: String
        if count == 1 {
            noun = pluralS.replaceFirst(in: ies.replaceFirst(in: noun, with: "y"), with: "")
            be = "is"
        } else {
            be = "are"
        }
        var verdict = "\(capitalize(count <= 20 ? cardinals[count] : String(count))) \(noun) \(be) \(JsString.trim(q.groupValue(3)))"
        // VG v2: the answer's own list must agree with the new count, else no flag. A bulleted or numbered list, or a prose
        // list ("after A, B and C", "include A, B and C").
        let bullets = segs.filter { bullet.containsMatch(in: $0.text) }.count
        if bullets > 0 && bullets != count { return nil }
        for s in segs {
            guard let l = list.find(in: s.text) ?? includeList.find(in: s.text) else { continue }
            let items = itemSplit.split(l.groupValue(1)).map { trailingDots.replace(in: JsString.trim($0), with: "") }.filter { !$0.isEmpty }
            if items.count != count { return nil }
            verdict += ": \(items.dropLast().joined(separator: ", ")) and \(items.last!)"
            break
        }
        verdict += "."
        let kept = segs.enumerated().filter { i, s in i != 0 && !isMeta(s.text) && !denial.containsMatch(in: s.text) }.map(\.element)
        return Result(kind: "rank", text: join([Seg(verdict, segs[0].sep)] + kept))
    }

    /// The verdict guard: nil when the answer is not flagged (it stays byte-identical), else the repaired text and which
    /// check fired. English questions only (the caller checks the language).
    public static func check(_ question: String, _ answer: String) -> Result? {
        if JsString.trim(question).isEmpty || JsString.trim(answer).isEmpty { return nil }
        let segs = segments(inlineNote.replace(in: answer, with: ""))
        if segs.isEmpty { return nil }
        return checkDate(question, segs) ?? checkCompare(question, segs) ?? checkRank(question, segs)
    }
}
