import BoarRAG
import BoarRouting
import Foundation

/// Ported from src/rag/facts.ts in r4to's PR #85 (BOAR R&D, MIT), through android `rag/Facts.kt`.
///
/// FACTS: a structured-knowledge instant answer from a compact offline table (Wikidata, CC0; facts.v1.json, passed in as
/// its JSON text). Fires only when (a) the question names one or two table entities by label or alias, found with the
/// same word n-grams the pack title lookup uses (WikiPackText.titleCandidates), and (b) its wording matches exactly one
/// property template of the lexicon below. One entity: the value with unit, "as of" year and a source line; two entities
/// and a comparison word: a computed verdict. Anything else is nil and the normal path. English only; the caller keeps it
/// off health questions.
///
/// The TypeScript's review rounds (r2 to r9) are kept as written; see the Kotlin file for each. The regexes are the
/// TypeScript (and Java) ones verbatim, through JsRegex; offsets are UTF-16 as on the JVM. Lives in BoarAnswer, not
/// BoarRAG, because it needs BoarRouting's JsRegex and JsNumber.
public final class Facts: Sendable {
    public final class Entity: Sendable {
        public let q: String, n: String, a: [String], k: String, d: String?
        let pop: (Double, Double?)?
        let area: Double?, elev: Double?, height: Double?, len: Double?, depth: Double?
        let cap: [String]?, cur: [String]?, lang: [String]?, cont: [String]?, bord: [String]?, plug: [String]?
        let volt: [Double]?, hz: [Double]?
        let inc: String?, end: String?
        let loc: [String]?
        let win: [String: [String]]?
        let ctry: [String]?, t: [String]?
        /// r9: driving side ("left" / "right") and international calling codes with the part each covers ("" = whole).
        let drive: String?
        let call: [(String, String)]?
        /// r8: emergency phone numbers and their service ("" when the table names none), countries only.
        let emerg: [(String, String)]?

        init(_ o: [String: Any]) {
            func str(_ k: String) -> String? { o[k] as? String }
            func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
            func strs(_ k: String) -> [String]? { (o[k] as? [Any])?.compactMap { $0 as? String } }
            func nums(_ k: String) -> [Double]? { (o[k] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } }
            func pairs(_ k: String) -> [(String, String)]? {
                (o[k] as? [Any])?.compactMap { ($0 as? [Any]).flatMap { p in p.count >= 2 ? ((p[0] as? String) ?? "", (p[1] as? String) ?? "") : nil } }
            }
            q = str("q") ?? ""; n = str("n") ?? ""; a = strs("a") ?? []; k = str("k") ?? ""; d = str("d")
            if let p = o["pop"] as? [Any], let v = (p.first as? NSNumber)?.doubleValue {
                pop = (v, p.count > 1 ? (p[1] as? NSNumber)?.doubleValue : nil)
            } else {
                pop = nil
            }
            area = num("area"); elev = num("elev"); height = num("height"); len = num("len"); depth = num("depth")
            cap = strs("cap"); cur = strs("cur"); lang = strs("lang"); cont = strs("cont"); bord = strs("bord"); plug = strs("plug")
            volt = nums("volt"); hz = nums("hz")
            inc = str("inc"); end = str("end"); loc = strs("loc")
            win = (o["win"] as? [String: Any])?.mapValues { ($0 as? [Any])?.compactMap { $0 as? String } ?? [] }
            ctry = strs("ctry"); t = strs("t")
            drive = str("drive"); call = pairs("call"); emerg = pairs("emerg")
        }
    }

    /// `template`: "population", "area", "capital"…; `entities`: their Wikidata ids.
    public struct Answer: Sendable, Equatable {
        public let template: String
        public let entities: [String]
        public let text: String
    }

    private let snapshot: String
    private let entities: [Entity]
    private let index: [String: [Entity]]
    private let lowerOk: Set<String>

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let list = root["entities"] as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        snapshot = root["snapshot"] as? String ?? ""
        entities = list.map(Entity.init)
        var index: [String: [Entity]] = [:]
        func add(_ key: String, _ e: Entity) {
            if !(index[key]?.contains { $0 === e } ?? false) { index[key, default: []].append(e) }
        }
        for e in entities {
            for name in [e.n] + e.a + (Self.r3Aliases[e.q] ?? []) {
                let key = name.lowercased()
                // Short aliases ("US", "UK", "PRC") only as the question's own upper-case token (checked at lookup).
                if key.utf16.count < 2 { continue }
                add(key, e)
                // "U.S." is typed as the word "U.S" (titleCandidates drops a trailing dot).
                if key.hasSuffix(".") {
                    var trimmed = key
                    while trimmed.hasSuffix(".") { trimmed.removeLast() }
                    add(trimmed, e)
                }
            }
        }
        self.index = index
        // r3 gate 1: one-word country and capital labels may be typed lowercase, unless the word is on the risk list.
        let capitals = Set(entities.filter { $0.k == "country" }.flatMap { ($0.cap ?? []).map { $0.lowercased() } })
        let names = entities.filter { e in !e.n.unicodeScalars.contains(where: JsString.isSpace) && (e.k == "country" || (e.k == "city" && capitals.contains(e.n.lowercased()))) }
            .map { $0.n.lowercased() }
        lowerOk = Set((names + Self.lowerAliases).filter { !Self.lowerRisk.contains($0) })
    }

    private struct Resolved {
        let ents: [Entity]
        let ambiguous: Bool
        let starts: [Int]
    }

    private struct Tok {
        let w: String, s: Int, e: Int
    }

    private struct Span {
        let e: Entity
        let words: [String]
    }

    /// Entities the question names, in question order, longest n-gram first; a word inside a found name never counts again.
    public func factEntities(_ query: String) -> [Entity] { resolve(query).ents }

    private static func sub(_ s: String, _ from: Int, _ to: Int) -> String {
        (s as NSString).substring(with: NSRange(location: from, length: max(0, to - from)))
    }

    private static func replacing(_ s: String, _ range: NSRange, with w: String) -> String {
        (s as NSString).replacingCharacters(in: range, with: w)
    }

    /// As factEntities, plus whether any name resolved to two or more entities (r2 gate 3: then no answer).
    private func resolve(_ query: String) -> Resolved {
        // r4 rule 2: each "the" typo is read as "the" only if, so read, a resolved name starts at the next word.
        let typos = Self.theTypos.findAll(in: query)
        if typos.isEmpty { return resolveTyped(query) }
        func tokenAt(_ q: String, _ offset: Int) -> Int { Self.token.findAll(in: (q as NSString).substring(to: offset)).count }
        let accepted = typos.filter { m in
            let q2 = Self.replacing(query, m.range, with: "the")
            return resolveTyped(q2).starts.contains(tokenAt(query, m.range.location) + 1)
        }
        var q = query
        for m in accepted.reversed() { q = Self.replacing(q, m.range, with: "the") }
        return resolveTyped(q)
    }

    private func resolveTyped(_ query: String) -> Resolved {
        var ambiguous = false
        let opening = (Self.word.find(in: query)?.value ?? "").lowercased()
        var used: [String] = []
        var found: [(e: Entity, at: Int, tok: Int)] = []
        var spans: [Span] = []
        let low = query.lowercased()
        // Word tokens with offsets, split exactly like titleCandidates (r3: neighbours of a name, a leading "the").
        let toks = Self.token.findAll(in: query).map {
            Tok(w: Self.tokenTrail.replace(in: $0.value, with: ""), s: $0.range.location, e: $0.range.location + $0.range.length)
        }
        func span(_ words: [String]) -> Int {
            if toks.count >= words.count {
                for i in 0...(toks.count - words.count) where words.indices.allSatisfy({ toks[i + $0].w.lowercased() == words[$0] }) { return i }
            }
            return -1
        }
        func glued(_ a: Int, _ b: Int) -> Bool {
            let between = Self.sub(query, toks[a].e, toks[b].s)
            return !between.isEmpty && between.unicodeScalars.allSatisfy(JsString.isSpace)
        }
        // r3 gate 2: "US" is a stopword ("us") for titleCandidates; typed upper-case it is the country.
        var cands = WikiPackText.titleCandidates(query)
        if toks.contains(where: { $0.w == "US" }) { cands.append("US") }
        for cand in cands {
            var lower = cand.lowercased()
            if used.contains(where: { Self.has($0, lower) }) { continue }
            let single = !cand.contains(" ")
            let words = Self.spaces.split(lower)
            let at = span(words)
            let prev: Tok? = at > 0 && glued(at - 1, at) ? toks[at - 1] : nil
            // r3 gate 1: a one-word country/capital name may be typed lowercase ("what is the population of canada").
            let lowerName = single && !Self.upperStart.containsMatch(in: cand) && lowerOk.contains(lower)
            // r4 rule 1 / r5 rule C: a lowercase or mixed-case name of 2+ words resolves when, case-folded, it names exactly
            // one entity (with an optional typed "the" before it); the known outside homonym still blocks it.
            var safeList: [Entity]?
            if !single && !Self.typedAsName(cand) && !words.contains(where: Self.homonyms.contains) {
                let l = index[lower] ?? (prev?.w.lowercased() == "the" ? index["the \(lower)"] : nil)
                if l?.count == 1 { safeList = l }
            }
            // r3: otherwise a lowercase multi-word name ("south sudan") still needs capitals, and its inner word must not
            // answer for it ("sudan"): the question is not answered.
            if safeList == nil && !single && !Self.typedAsName(cand) && index[lower] != nil && words.contains(where: lowerOk.contains) {
                used.append(lower)
                ambiguous = true
                continue
            }
            // A lone word must be written as a name (capitalized), and never be the sentence's opening word.
            if single && ((!Self.upperStart.containsMatch(in: cand) && !lowerName) || lower == opening) { continue }
            if cand.utf16.count <= 3 && cand != cand.uppercased() && !lowerName { continue }
            if !lowerName && safeList == nil && !Self.typedAsName(cand) { continue }
            var list = index[lower]
            // r3 gate 2: "the UK", "the Amazon": an alias with a leading "the" matches when the question types the "the".
            if list == nil && prev?.w.lowercased() == "the" {
                lower = "the \(lower)"
                list = index[lower]
            }
            guard let list else { continue }
            // r3: a lowercase one-word name after "south"/"new" is another place.
            if lowerName, let prev, Self.modifiers.contains(prev.w.lowercased()) {
                used.append(lower)
                ambiguous = true
                continue
            }
            // Same name, several entities: the exact label wins; two same-label entities (Bandung city/regency) -> ambiguous.
            let exact = list.filter { $0.n.lowercased() == lower }
            let pool = exact.isEmpty ? list : exact
            used.append(lower)
            if pool.count > 1 || Self.homonyms.contains(lower) {
                ambiguous = true
                continue
            }
            let pick = pool[0]
            spans.append(Span(e: pick, words: words))
            if !found.contains(where: { $0.e === pick }) {
                let r = (low as NSString).range(of: lower)
                found.append((pick, r.location == NSNotFound ? -1 : r.location, at))
            }
        }
        if !ambiguous && neighbourBlocked(toks, spans) { ambiguous = true }
        let sorted = found.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element.e)
        return Resolved(ents: sorted, ambiguous: ambiguous, starts: found.map(\.tok))
    }

    /// r5 rule A: true when some resolved name (every occurrence, any casing) has a disallowed neighbour on either side.
    private func neighbourBlocked(_ toks: [Tok], _ spans: [Span]) -> Bool {
        let lw = toks.map { $0.w.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") }
        func at(_ i: Int) -> String? { i >= 0 && i < lw.count ? lw[i] : nil }
        func starts(_ words: [String]) -> [Int] { lw.indices.filter { i in words.indices.allSatisfy { at(i + $0) == words[$0] } } }
        var owner: [Int: Entity] = [:]
        for s in spans {
            for i in starts(s.words) { for j in s.words.indices { owner[i + j] = s.e } }
        }
        func inPhrase(_ j: Int) -> Bool {
            Self.r5Phrases.contains { ph in ph.indices.contains { k in ph.indices.allSatisfy { m in at(j - k + m) == ph[m] } } }
        }
        func ok(_ start: Int, _ dir: Int, _ e: Entity) -> Bool {
            var j = start
            if j >= 0 && j < lw.count && Self.feature[lw[j]] == e.k { j += dir }
            while j >= 0 && j < lw.count && (Self.r5Skip.contains(lw[j]) || Self.numberStart.containsMatch(in: lw[j])) { j += dir }
            if j < 0 || j >= lw.count { return true }
            if let o = owner[j], o !== e { return true }
            return Self.r5Allowed(lw[j]) || inPhrase(j)
        }
        return spans.contains { s in starts(s.words).contains { i in !ok(i - 1, -1, s.e) || !ok(i + s.words.count, 1, s.e) } }
    }

    private func source(_ asOf: Double?) -> String {
        "\n\nSource: Wikidata (CC0), offline table as of \(snapshot)\(asOf.map { $0 != 0 ? "; figure dated \(JsNumber.toString($0))" : "" } ?? "")."
    }

    private struct Num {
        let v: Double
        let text: String
        let asOf: Double?
    }

    private static func nonZero(_ x: Double?) -> Double? { x.flatMap { $0 != 0 ? $0 : nil } }

    /// The numeric value of a template for an entity, with its phrase; nil when the table has none.
    private func numeric(_ t: String, _ e: Entity) -> Num? {
        switch t {
        case "population":
            // r3 gate 5: a figure dated before 2023 says so ("(dated 2021)").
            guard let pop = e.pop else { return nil }
            let (v, y) = pop
            let dated = y.map { $0 != 0 ? ($0 < 2023 ? " (dated \(JsNumber.toString($0)))" : " (\(JsNumber.toString($0)))") : "" } ?? ""
            return Num(v: v, text: "\(Self.millions(v))\(dated)", asOf: y)
        case "area": return Self.nonZero(e.area).map { Num(v: $0, text: "\(Self.fmt($0)) km² (\(Self.fmt($0 / 2.58999)) sq mi)", asOf: nil) }
        case "height": return Self.nonZero(e.height ?? e.elev).map { Num(v: $0, text: "\(Self.fmt($0)) m (\(Self.fmt($0 * 3.28084)) ft)", asOf: nil) }
        case "length": return Self.nonZero(e.len).map { Num(v: $0, text: "\(Self.fmt($0)) km (\(Self.fmt($0 / 1.609344)) mi)", asOf: nil) }
        case "depth": return Self.nonZero(e.depth).map { Num(v: $0, text: "\(Self.fmt($0)) m", asOf: nil) }
        default: return nil
        }
    }

    private static func nonEmpty<T>(_ xs: [T]?) -> [T]? { xs.flatMap { $0.isEmpty ? nil : $0 } }

    /// One entity, one template -> the value line; nil when the entity has no value for it.
    private func single(_ t: String, _ e: Entity, _ query: String) -> String? {
        let name = e.n
        let where_ = Self.nonEmpty(e.ctry).flatMap { c in c.contains { e.d?.contains($0) == true } ? nil : Self.list(c) } ?? ""
        let types = (e.t ?? []).filter { e.d?.contains($0) != true }
        let inner = [[e.d, where_].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "), types.isEmpty ? "" : "type: \(types.joined(separator: ", "))"]
            .filter { !$0.isEmpty }.joined(separator: "; ")
        let head = inner.isEmpty ? name : "\(name) (\(inner))"
        if let num = numeric(t, e) {
            let what = t == "height" && Self.nonZero(e.height) == nil ? "elevation" : Self.noun[t]!
            return "\(head): \(what) \(num.text).\(source(num.asOf))"
        }
        switch t {
        case "capital": return Self.nonEmpty(e.cap).map { "The capital of \(name) is \(Self.list($0)).\(source(nil))" }
        case "currency": return Self.nonEmpty(e.cur).map { "\(name)'s currency: \(Self.list($0)).\(source(nil))" }
        case "languages": return Self.nonEmpty(e.lang).map { "Official language\($0.count > 1 ? "s" : "") of \(name): \(Self.list($0)).\(source(nil))" }
        case "continent": return Self.nonEmpty(e.cont).map { "\(name) is in \(Self.list($0)).\(source(nil))" }
        case "borders": return Self.nonEmpty(e.bord).map { "\(name) borders \(Self.list($0)).\(source(nil))" }
        case "dates":
            guard let inc = e.inc, !inc.isEmpty else { return nil }
            let end = e.end.flatMap { $0.isEmpty ? nil : "; it ended (came down / was dissolved) on \(Self.date($0))" } ?? ""
            return "\(head): built/founded \(Self.date(inc))\(end).\(source(nil))"
        case "electricity":
            if Self.nonEmpty(e.plug) == nil && Self.nonEmpty(e.volt) == nil { return nil }
            let parts = [
                Self.nonEmpty(e.plug).map { "plug type\($0.count > 1 ? "s" : "") \(Self.list($0))" } ?? "",
                Self.nonEmpty(e.volt).map { "mains voltage \($0.map { "\(JsNumber.toString($0)) V" }.joined(separator: " / "))" } ?? "",
                Self.nonEmpty(e.hz).map { $0.map { "\(JsNumber.toString($0)) Hz" }.joined(separator: " / ") } ?? "",
            ].filter { !$0.isEmpty }
            let regional = (e.volt?.count ?? 0) > 1 || (e.hz?.count ?? 0) > 1
            let note = regional ? " Where two values are listed, it differs by region: check the socket or ask locally." : ""
            return "\(name): \(parts.joined(separator: ", ")).\(note)\(source(nil))"
        case "emergency":
            return Self.nonEmpty(e.emerg).map { nums in
                "Emergency numbers in \(name): \(Self.list(nums.map { $0.1.isEmpty ? $0.0 : "\($0.1) \($0.0)" })). In a life-threatening emergency, call now.\(source(nil))"
            }
        case "driving":
            guard let side = e.drive, !Self.driveVeto.containsMatch(in: query) else { return nil }
            let low = query.lowercased()
            let left = Self.leftWord.containsMatch(in: low)
            let right = Self.rightWord.containsMatch(in: low)
            let lead = Self.yesNo.containsMatch(in: JsString.trim(query)) && left != right ? ((left ? "left" : "right") == side ? "Yes. " : "No. ") : ""
            return "\(lead)In \(name), traffic drives on the \(side).\(source(nil))"
        case "calling":
            guard let codes = Self.nonEmpty(e.call), !Self.callVeto.containsMatch(in: query) else { return nil }
            func nanp(_ c: String) -> String {
                Self.nanp.containsMatch(in: c) ? "\(c) (country code +1, then area code \((c as NSString).substring(from: 3)))" : c
            }
            if codes.count == 1 && codes[0].1.isEmpty { return "The international calling code for \(name) is \(nanp(codes[0].0)).\(source(nil))" }
            return "International calling codes for \(name): \(Self.list(codes.map { $0.1.isEmpty ? $0.0 : "\($0.1) \($0.0)" })).\(source(nil))"
        case "host": return Self.nonEmpty(e.loc).map { "\(name): held in \(Self.list($0)).\(source(nil))" }
        case "winner":
            guard let y = Self.winnerYear.find(in: query)?.group(1), let w = Self.nonEmpty(e.win?[y]) else { return nil }
            return "\(name), \(y): \(Self.list(w)).\(source(nil))"
        default: return nil
        }
    }

    /// Two entities and a numeric template -> the computed verdict; nil when either value is missing or they tie.
    private func compare(_ t: String, _ a: Entity, _ b: Entity, _ query: String) -> String? {
        guard let x = numeric(t, a), let y = numeric(t, b), x.v != y.v else { return nil }
        let low = query.lowercased()
        let asOf = Self.nonZero(max(x.asOf ?? 0, y.asOf ?? 0))
        let verdict = "\(x.v > y.v ? a.n : b.n) \(Self.more[t]!) \(x.v > y.v ? b.n : a.n): \(a.n) \(x.text) vs \(b.n) \(y.text)."
        if Self.yesNo.containsMatch(in: JsString.trim(query)) {
            let greater = Self.greater.contains { Self.has(low, $0) }
            let lesser = Self.lesser.contains { Self.has(low, $0) }
            if greater == lesser { return nil }
            let yes = greater ? x.v > y.v : x.v < y.v
            return "\(yes ? "Yes" : "No"). \(verdict)\(source(asOf))"
        }
        return "\(verdict)\(source(asOf))"
    }

    /// Height of one entity against the depth of a lake: would it stick out of the water?
    private func fit(_ tall: Entity, _ lake: Entity, _ query: String) -> String? {
        guard let h = Self.nonZero(tall.height ?? tall.elev), let d = Self.nonZero(lake.depth) else { return nil }
        let low = query.lowercased()
        let above = h > d
        let gap = abs(h - d)
        let asksOut = Self.asksOut.containsMatch(in: low)
        let asksUnder = Self.asksUnder.containsMatch(in: low)
        let lead = asksOut ? (above ? "Yes. " : "No. ") : (asksUnder ? (above ? "No. " : "Yes. ") : "")
        let kind = Self.nonZero(tall.height) != nil ? "tall" : "high"
        let top = above ? "about \(Self.fmt(gap)) m above the surface" : "about \(Self.fmt(gap)) m below the surface (fully submerged)"
        return "\(lead)\(tall.n) is \(Self.fmt(h)) m \(kind); \(lake.n) is \(Self.fmt(d)) m deep at its deepest point, so its top would be \(top).\(source(nil))"
    }

    /// r6 fix 3: a place whose countries include exactly one table country, which is on exactly one continent.
    private func placeContinent(_ e: Entity) -> String? {
        guard e.k != "country", let ctry = Self.nonEmpty(e.ctry) else { return nil }
        let c = entities.filter { $0.k == "country" && ctry.contains($0.n) }
        // A country on several continents (Egypt, France with its overseas regions) does not tell where the place is.
        guard c.count == 1, let cont = c[0].cont, cont.count == 1 else { return nil }
        return "\(e.n) is in \(c[0].n), which is in \(cont[0]).\(source(nil))"
    }

    /// r6 fix 5: "which is taller/higher, X or Y" / "is X taller/higher than Y" where each side, case-folded and with an
    /// optional leading "the", is exactly one label or alias of exactly one entity, both of the same height class.
    private func tallerFrame(_ q: String) -> Answer? {
        for re in Self.r6Taller {
            guard let m = re.find(in: q) else { continue }
            func side(_ s: String) -> Entity? {
                index[s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")].flatMap { $0.count == 1 ? $0[0] : nil }
            }
            guard let a = side(m.groupValue(1)), let b = side(m.groupValue(2)), a !== b,
                  let ca = Self.tallClass[a.k], ca == Self.tallClass[b.k] else { return nil }
            return compare("height", a, b, q).map { Answer(template: "height", entities: [a.q, b.q], text: $0) }
        }
        return nil
    }

    /// The FACTS instant answer, or nil (the question takes the normal path). English questions only.
    public func answer(_ query: String) -> Answer? {
        var q = JsString.trim(query)
        // r6 fix 1: an opener typo is read as "what" / "how".
        for (re, w) in Self.openerTypos { q = re.replaceFirst(in: q, with: w) }
        // r6 fix 4: "what country surrounds X" is read as "what country borders X".
        if let m = Self.r6Surround.find(in: q) { q = Self.replacing(q, m.range, with: "\(m.groupValue(1)) \(m.groupValue(2)) border") }
        if q.isEmpty || !(Self.question.containsMatch(in: q) || Self.questionOpeners.containsMatch(in: q) || Self.r6Openers.containsMatch(in: q)
            || Self.r9Openers.containsMatch(in: q)) { return nil }
        let low = Self.apostrophes.replace(in: q.lowercased(), with: "'")
        if Self.veto.contains(where: { Self.has(low, $0) }) { return nil }
        let templates = Self.templates(q)
        guard templates.count == 1 else { return nil }
        let t = templates[0]
        if t == "height", let a = tallerFrame(q) { return a }
        let r = resolve(q)
        let ents = r.ents
        if r.ambiguous || ents.isEmpty || ents.count > 2 { return nil }
        func done(_ text: String?) -> Answer? { text.map { Answer(template: t, entities: ents.map(\.q), text: $0) } }
        let comparing = Self.compareWords.contains { Self.has(low, $0) }
        // r6 fix 3: "what continent is <place> in/on" -> the continent of the place's one country.
        if ents.count == 1 && t == "continent" && ents[0].cont == nil && Self.r6Continent.containsMatch(in: q) { return done(placeContinent(ents[0])) }
        // r9: "do they drive on the left or the right in X" is not a comparison.
        if ents.count == 1 { return comparing && t != "driving" ? nil : done(single(t, ents[0], q)) }
        // Two entities: a comparison of one numeric value, or a height against a lake's depth.
        if t == "depth" {
            let lake = ents.first { Self.nonZero($0.depth) != nil }
            let tall = ents.first { $0 !== lake && Self.nonZero($0.height ?? $0.elev) != nil }
            if let lake, let tall, Self.nonZero(tall.depth) == nil { return done(fit(tall, lake, q)) }
        }
        return comparing && Self.noun[t] != nil ? done(compare(t, ents[0], ents[1], q)) : nil
    }

    // MARK: lexicon and gates

    /// Property lexicon: the wording that asks for each template (lowercase; whole words/phrases), in the TypeScript's order.
    public static let lexicon: [(String, [String])] = [
        ("population", ["population", "populous", "inhabitants", "residents", "how many people", "more people", "fewer people", "less people", "people live", "people living"]),
        ("area", ["area", "how big", "size of", "square kilometres", "square kilometers", "square km", "sq km", "km2", "km²", "square miles", "sq mi"]),
        ("capital", ["capital", "capital city"]),
        ("currency", ["currency", "currencies"]),
        ("languages", ["language", "languages", "official language", "official languages", "spoken"]),
        ("continent", ["continent", "which continent"]),
        ("borders", ["border", "borders", "bordering", "neighbouring countries", "neighboring countries", "neighbours", "neighbors"]),
        ("height", ["how high", "how tall", "height", "elevation", "taller", "higher", "tallest", "highest"]),
        ("length", ["how long is", "how long are", "length", "longer", "longest", "km long", "miles long"]),
        ("depth", ["how deep", "depth", "deepest", "deeper", "deep"]),
        ("dates", ["built", "founded", "established", "constructed", "erected", "inception", "came down", "come down", "fell", "fall of", "torn down", "demolished", "dissolved"]),
        ("emergency", ["emergency number", "emergency numbers", "emergency phone number", "emergency telephone number", "emergency services number", "ambulance number", "police number", "fire brigade number", "fire department number", "number for an ambulance", "number for the police", "number for emergencies", "number to call in an emergency"]),
        ("electricity", ["plug", "plugs", "plug type", "socket", "sockets", "outlet", "outlets", "voltage", "volts", "mains", "adapter", "adaptor", "power adapter", "travel adapter", "plug adapter", "power plug", "power socket", "wall socket", "power outlet", "electrical outlet", "hz", "hertz", "mains frequency"]),
        ("driving", ["drive on the left", "drive on the right", "drives on the left", "drives on the right", "driving on the left", "driving on the right", "drive on which side", "drive on what side", "driving side", "side of the road", "left-hand traffic", "right-hand traffic"]),
        ("calling", ["country code", "calling code", "country calling code", "international calling code", "dialing code", "dialling code", "international dialing code", "international dialling code", "international code", "phone code", "telephone code", "dial code"]),
        ("host", ["host", "hosted", "hosting", "held"]),
        ("winner", ["won", "win", "winner", "winners", "received", "awarded", "laureate"]),
    ]

    /// Slots the table cannot answer, and explanation wording: any of these -> no fire (the model answers).
    private static let veto = [
        "density", "densely", "gdp", "economy", "time zone", "timezone", "climate", "weather", "religion",
        "president", "prime minister", "leader", "government", "history", "historically", "known for", "why", "explain", "describe",
        "overview", "tell me about", "essentials", "key facts", "how did", "independent", "independence", "safe", "sick", "sickness",
        "danger", "dangerous", "visa", "flight", "take", "stay", "per capita",
    ]
    /// r3: comparative wording that asks for area only when no other property is named.
    private static let weakArea = ["bigger than", "larger than", "smaller than", "which is bigger", "which is larger"]
    /// r3: compound phrases whose property word is not the property ("area code"): removed before matching.
    private static let stopPhrases = [
        "area code", "area codes", "area of expertise", "area of study", "area of interest", "area of focus", "area of research",
        "capital letter", "capital letters", "capital gains", "capital punishment",
    ].map { JsRegex(#"\b\#($0)\b"#, flags: "g") }
    private static let compareWords = ["more", "less", "fewer", "than", "bigger", "larger", "smaller", "higher", "taller", "longer", "shorter", "deeper", "shallower", "or", "compare", "compared", "versus", "vs"]
    private static let greater = ["more", "bigger", "larger", "higher", "taller", "longer", "deeper"]
    private static let lesser = ["less", "fewer", "smaller", "lower", "shorter", "shallower"]
    private static let yesNo = JsRegex(#"^(is|are|does|do|did|has|have|was|were|can|could|would|will)\b"#, flags: "i")
    private static let question = JsRegex(#"\?\s*$|^(what|which|who|when|where|how|is|are|does|do|did|has|have|was|were|can|could|would|will|if|tell|give|list|name)\b"#, flags: "i")
    /// r5 rule B: question openers typed without "?".
    private static let questionOpeners = JsRegex(#"^(whats|what['’]s|hows|how['’]s|wheres|where['’]s)(?![\p{L}\p{N}])|^(size|capital|population|elevation|height|length) of\b"#, flags: "iu")
    /// r6 fix 1: typos of the opening "what" / "how", read as the word they stand for.
    private static let openerTypos: [(JsRegex, String)] = [
        (JsRegex(#"^(whta|waht|wat)(?![\p{L}\p{N}'’])"#, flags: "iu"), "what"),
        (JsRegex(#"^hwo(?![\p{L}\p{N}'’])"#, flags: "iu"), "how"),
        (JsRegex(#"^whats['’](?![\p{L}\p{N}])"#, flags: "iu"), "whats"),
    ]
    /// r6 fix 2: property-first openers typed without "?".
    private static let r6Openers = JsRegex(#"^(official languages?|continent) of\b"#, flags: "iu")
    /// r9: travel property-first openers typed without "?".
    private static let r9Openers = JsRegex(#"^(voltage|mains voltage|plug types?|plugs?|socket types?|sockets?|driving side|calling code|country code|dialing code|dialling code|emergency numbers?) (in|of|for)\b"#, flags: "iu")
    /// r9: a driving question about something else than the side of the road: no answer.
    private static let driveVeto = JsRegex(#"\b(licen[cs]es?|permits?|rent|rental|renting|hire|speed|tolls?|insurance|age)\b"#, flags: "i")
    /// r9: a code that is not the telephone calling code: no answer.
    private static let callVeto = JsRegex(#"\b(iso|alpha|letters?|domain|internet|tld|postal|postcode|zip|airport|iata|plates?|currency code)\b"#, flags: "i")
    private static let nanp = JsRegex(#"^\+1 \d{3}$"#)
    private static let leftWord = JsRegex(#"\bleft\b"#)
    private static let rightWord = JsRegex(#"\bright\b"#)
    /// r6 fix 3: "what continent is X in/on".
    private static let r6Continent = JsRegex(#"^(what|which) continent (is|are)\b.*\b(in|on)\s*\??\s*$"#, flags: "iu")
    /// r6 fix 4: "what country/countries surround(s) X" asks for borders.
    private static let r6Surround = JsRegex(#"^(what|which) (country|countries) (?:surround|surrounds)\b"#, flags: "iu")
    /// r6 fix 5: the two height-comparison frames; each side must be one whole name.
    private static let r6Taller = [
        JsRegex(#"^(?:which|what)(?: one)? is (?:taller|higher)\s*[,:]?\s+(?:the\s+)?(.+?)\s+or\s+(?:the\s+)?(.+?)\s*\??\s*$"#, flags: "iu"),
        JsRegex(#"^is (?:the\s+)?(.+?) (?:taller|higher) than (?:the\s+)?(.+?)\s*\??\s*$"#, flags: "iu"),
    ]
    /// r6 fix 5: kinds compared by height in those frames.
    private static let tallClass = ["mountain": "mountain", "building": "structure", "dam": "structure"]

    /// The cue as a whole word or phrase of `low` (letters and digits around it end it).
    static func has(_ low: String, _ cue: String) -> Bool {
        let s = low as NSString
        let length = s.length
        var from = 0
        while from <= length {
            let r = s.range(of: cue, options: .literal, range: NSRange(location: from, length: length - from))
            if r.location == NSNotFound { return false }
            if !letterOrDigit(before: r.location, in: s) && !letterOrDigit(at: r.location + r.length, in: s) { return true }
            from = r.location + 1
        }
        return false
    }

    private static func scalar(_ s: NSString, at i: Int) -> Unicode.Scalar? {
        let u = s.character(at: i)
        if UTF16.isLeadSurrogate(u), i + 1 < s.length { return Unicode.Scalar(UInt32(0x10000) + (UInt32(u - 0xD800) << 10) + UInt32(s.character(at: i + 1) - 0xDC00)) }
        return Unicode.Scalar(u)
    }

    /// Java's `[\p{L}\p{N}]`.
    private static func isLN(_ c: Unicode.Scalar?) -> Bool {
        switch c?.properties.generalCategory {
        case .uppercaseLetter?, .lowercaseLetter?, .titlecaseLetter?, .modifierLetter?, .otherLetter?,
             .decimalNumber?, .letterNumber?, .otherNumber?: true
        default: false
        }
    }

    private static func letterOrDigit(at i: Int, in s: NSString) -> Bool { i < s.length && isLN(scalar(s, at: i)) }

    private static func letterOrDigit(before i: Int, in s: NSString) -> Bool {
        guard i > 0 else { return false }
        let u = s.character(at: i - 1)
        if UTF16.isTrailSurrogate(u), i >= 2 { return isLN(scalar(s, at: i - 2)) }
        return isLN(Unicode.Scalar(u))
    }

    /// r3: everyday short names the Wikidata aliases lack.
    private static let r3Aliases: [String: [String]] = [
        "Q148": ["China"],
        "Q145": ["UK", "U.K.", "the UK", "Britain"],
        "Q30": ["US", "U.S.", "USA", "the USA", "America"],
        "Q3783": ["the Amazon"],
    ]
    /// r3: one-word country/capital names that are also common words, first names or part of other places.
    private static let lowerRisk: Set<String> = [
        "georgia", "turkey", "chad", "jordan", "guinea", "chile", "china", "america", "us", "wellington", "victoria", "sofia",
        "israel", "santiago", "kingston", "nice", "reading", "male", "malé",
    ]
    /// r4 rule 2: typos of "the", read as "the" only when a resolved name follows right after.
    private static let theTypos = JsRegex(#"(?<![\p{L}\p{N}'’.-])(thw|teh|hte|tje|th)(?![\p{L}\p{N}'’.-])"#, flags: "gu")
    /// r3: r3 aliases that may be typed lowercase.
    private static let lowerAliases = ["uk", "u.k", "britain", "usa", "u.s"]
    /// r3: a lowercase name right after one of these is part of another place: no answer.
    private static let modifiers: Set<String> = ["north", "south", "east", "west", "northern", "southern", "eastern", "western", "central", "new", "latin", "equatorial", "american", "papua", "upper", "lower", "great", "french", "british", "dutch"]

    /// r5 rule A: skipped when looking for a name's neighbour.
    private static let r5Skip: Set<String> = ["the", "a", "an", "of", "in", "at", "on", "for", "to", "and", "or"]
    private static let r5Question: Set<String> = [
        "what", "whats", "what's", "which", "who", "whom", "whose", "when", "where", "wheres", "where's", "why", "how", "hows", "how's",
        "is", "isn't", "are", "aren't", "was", "wasn't", "were", "weren't", "am", "be", "been", "being", "does", "doesn't", "do", "don't",
        "did", "didn't", "has", "have", "had", "having", "can", "could", "would", "will", "shall", "should", "may", "might", "must",
        "i", "i'm", "you", "we", "they", "he", "she", "it", "it's", "its", "their", "there", "there's", "this", "that", "these", "those",
        "me", "my", "your", "our", "us", "if", "tell", "give", "list", "name", "show", "know", "wonder", "by", "with", "from", "into",
        "as", "so", "but", "not", "no", "yes", "any", "some", "all", "both", "each", "also", "just", "really", "very", "much", "many",
        "more", "most", "less", "fewer", "then", "compare", "above", "below", "over", "under", "up", "down",
        "use", "uses", "used", "using", "speak", "speaks", "spoken", "speaking", "live", "lives", "living", "located",
        "stand", "stands", "stood", "put", "placed",
        "need", "needs", "bring", "pack", "buy",
        "drive", "drives", "driving", "side", "road", "traffic", "left", "right", "dial", "call", "calling", "electricity", "power",
    ]
    private static let r5Property: Set<String> = Set([
        "tall", "high", "big", "long", "deep", "population", "people", "capital", "currency", "language", "languages", "official",
        "continent", "border", "borders", "area", "size", "elevation", "height", "length", "depth", "bigger", "larger", "smaller",
        "taller", "longer", "shorter", "higher", "lower", "deeper", "shallower", "biggest", "largest", "smallest", "tallest",
        "longest", "highest", "deepest", "lowest", "point", "top", "peak", "summit", "total",
    ]).union(lexicon.flatMap(\.1).filter { !$0.contains(" ") })
    private static let r5Hedge: Set<String> = ["roughly", "about", "approximately", "approx", "around", "exactly", "today", "now", "currently", "called", "please", "again", "anyway", "days", "nowadays"]
    private static let r5Units: Set<String> = ["m", "km", "feet", "ft", "foot", "miles", "mile", "mi", "sqkm", "sq", "square", "km2", "km²", "meters", "metres", "meter", "metre", "kilometres", "kilometers", "kilometre", "kilometer"]
    private static let r5Compare: Set<String> = ["or", "than", "vs", "versus", "compared"]
    private static let r5Phrases: [[String]] = lexicon.flatMap(\.1).filter { $0.contains(" ") }.map { $0.components(separatedBy: " ") }
    private static func r5Allowed(_ w: String) -> Bool {
        r5Question.contains(w) || r5Property.contains(w) || r5Hedge.contains(w) || r5Units.contains(w) || r5Compare.contains(w)
    }
    /// r3: a feature word glued to a name of that kind is the same place ("Mount Kilimanjaro", "Danube River").
    private static let feature = ["mount": "mountain", "mt": "mountain", "mountain": "mountain", "river": "river", "lake": "lake"]

    /// Words of a name that may stay lowercase when the name is typed ("Nobel Prize in Literature").
    private static let nameStop: Set<String> = ["the", "of", "and", "de", "del", "da", "do", "dos", "das", "du", "des", "la", "le", "les", "el", "in", "on", "at", "y", "e", "a", "an", "to", "for", "by", "von", "van", "der", "den", "di", "al"]
    private static let nameStart = JsRegex(#"^[\p{Lu}\p{N}]"#)
    private static let nameElided = JsRegex(#"^\p{Ll}{1,2}['’]\p{Lu}"#)
    /// Every non-stopword of the name must be capitalised as typed (r2 gate 4).
    private static func typedAsName(_ cand: String) -> Bool {
        spaces.split(cand).allSatisfy { nameStop.contains($0.lowercased()) || nameStart.containsMatch(in: $0) || nameElided.containsMatch(in: $0) }
    }
    /// Names shared with a well-known place that is not in the table (the US state Georgia): never answered.
    private static let homonyms: Set<String> = ["georgia"]

    private static let token = JsRegex(#"[\p{L}\p{N}][\p{L}\p{N}'’.-]*"#)
    private static let tokenTrail = JsRegex(#"[.'’-]+$"#)
    private static let word = JsRegex(#"[\p{L}\p{N}]+"#)
    private static let spaces = JsRegex(#"\s+"#)
    private static let upperStart = JsRegex(#"^\p{Lu}"#)
    private static let numberStart = JsRegex(#"^\p{N}"#)
    private static let apostrophes = JsRegex(#"[’']"#)
    private static let winnerYear = JsRegex(#"\b(1[89]\d\d|20\d\d)\b"#)
    private static let asksOut = JsRegex(#"\b(stick|poke|rise|be|show) (out|above)|\breach the surface|\babove the (water|surface)|\bbreak the surface"#)
    private static let asksUnder = JsRegex(#"\b(submerged|underwater|under water|covered|disappear)"#)

    private static let noun = ["population": "population", "area": "area", "height": "height", "length": "length", "depth": "maximum depth"]
    private static let more = ["population": "has more people than", "area": "is larger by area than", "height": "is taller than", "length": "is longer than", "depth": "is deeper than"]

    /// The templates whose wording the question uses.
    public static func templates(_ query: String) -> [String] {
        var low = apostrophes.replace(in: query.lowercased(), with: "'")
        // r3 gate 4: the property word must stand alone ("area code" is not an area).
        for p in stopPhrases { low = p.replace(in: low, with: " ") }
        let found = lexicon.filter { $0.1.contains { has(low, $0) } }.map(\.0)
        // r3 gate 3: "bigger than" / "which is larger" ask for area when nothing else is named.
        return !found.isEmpty || !weakArea.contains(where: { has(low, $0) }) ? found : ["area"]
    }

    private static func fmt(_ n: Double, _ d: Int = 0) -> String { JsNumber.locale(n, pt: false, maxFractionDigits: d) }
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static func n(_ s: String) -> String { JsNumber.toString(JsNumber.parse(s)) }
    // Years < 1000 print without a leading zero ("476", not "0476").
    private static func date(_ s: String) -> String {
        let ns = s as NSString
        if ns.length >= 10 {
            return "\(n(ns.substring(with: NSRange(location: 8, length: 2)))) \(months[Int(JsNumber.parse(ns.substring(with: NSRange(location: 5, length: 2)))) - 1]) \(n(ns.substring(to: 4)))"
        }
        return n(ns.substring(to: min(4, ns.length)))
    }
    private static func list(_ xs: [String]) -> String {
        xs.count <= 1 ? xs.joined() : "\(xs.dropLast().joined(separator: ", ")) and \(xs.last!)"
    }
    private static func millions(_ n: Double) -> String {
        if n >= 1e9 { return "\(fmt(n / 1e9, 2)) billion" }
        if n >= 1e6 { return "\(fmt(n / 1e6, 1)) million" }
        return fmt(n)
    }
}
