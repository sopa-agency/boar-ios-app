import Foundation

/// Arithmetic questions answered exactly, with the formula, instead of by a model (port of src/routing/calculators.ts;
/// the compact model got fuel economy, Naismith's rule, currency with a given rate, a battery's watt-hours for a flight
/// and a heat warning wrong). Pure: the question in, the answer text out (or nil). Numbers are printed as JavaScript's
/// toLocaleString does for en-US / pt-BR.
public enum Calculators {
    /// kind: "temperature" | "fuel-economy" | "naismith" | "currency" | "battery" | "water" | "conversion".
    public struct Calculation: Sendable, Equatable {
        public var kind: String
        public var text: String
        public init(kind: String, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    // Starts only where a run of digits starts: from every digit inside a long run, \d+ backtracked over the rest of it,
    // so 4,000 digits took 5 s and 20,000 over two minutes (the TypeScript has the same pattern).
    private static let num = #"(?<!\d)(\d{1,3}(?:[.\s]\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)"#

    private static let wsAny = JsRegex(#"\s"#)
    private static let comma3End = JsRegex(#",\d{3}$"#)
    private static let dot3End = JsRegex(#"\.\d{3}$"#)

    /// "7,5" / "7.5" / "2.450" (PT thousands) / "1,200.5" / "18" -> number (NaN when it isn't one, as Number()).
    public static func parseNumber(_ raw: String, pt: Bool) -> Double {
        let s = wsAny.replace(in: raw, with: "")
        let hasComma = s.utf16.contains(44)
        let hasDot = s.utf16.contains(46)
        if hasComma && hasDot {
            let lastComma = s.utf16.lastIndex(of: 44)!
            let lastDot = s.utf16.lastIndex(of: 46)!
            if lastComma > lastDot {
                return JsNumber.parse(JsString.replacingFirst(JsString.replacingAll(s, ".", with: ""), ",", with: "."))
            }
            return JsNumber.parse(JsString.replacingAll(s, ",", with: ""))
        }
        if hasComma {
            return comma3End.containsMatch(in: s) && !pt
                ? JsNumber.parse(JsString.replacingAll(s, ",", with: ""))
                : JsNumber.parse(JsString.replacingFirst(s, ",", with: "."))
        }
        if hasDot {
            return dot3End.containsMatch(in: s) && pt ? JsNumber.parse(JsString.replacingAll(s, ".", with: "")) : JsNumber.parse(s)
        }
        return JsNumber.parse(s)
    }

    /// The question's decimal mark, read from its own numbers before its language (t9 0330: "27.000 mAh 3,7 V no avião"
    /// wasn't detected as Portuguese and 27.000 read as 27). A comma before 1, 2 or 4+ digits ("3,7") or after a dot
    /// ("1.200,5") says the comma is decimal; the same for the dot ("3.7", "1,200.5"). Exactly one of the two decides
    /// every "N.NNN" and "N,NNN" in the question; both or neither: nil, the language decides.
    public static func decimalMark(_ q: String) -> Character? {
        var marks = Set<Character>()
        for m in numberToken.findAll(in: q) {
            let t = m.value
            if isDate(q, m) { continue }
            let seps = t.filter { $0 == "." || $0 == "," }
            if Set(seps).count == 2 { marks.insert(seps.last!); continue }
            if seps.count == 1 {
                let after = t.drop { $0 != seps.first! }.dropFirst()
                if after.count != 3 { marks.insert(seps.first!) }
            }
        }
        return marks.count == 1 ? marks.first : nil
    }

    /// Longer than any calculator question; the number patterns cost too much past it (validator B-5).
    public static let maxQuery = 2000

    /// A date, never a decimal mark (validator B-1: "2.450 baht no dia 14.11" read 2.45): "14.11.2026", or
    /// "14.11" right after a date word ("no dia 14.11", "on 14.11", "until 3.12"). A day up to 31, a month up to 12.
    /// "3.7 V" and "on 12.50" are not dates.
    private static func isDate(_ q: String, _ m: JavaRegex.Match) -> Bool {
        guard let d = dateRe.matchEntire(m.value) else { return false }
        let day = Int(d.groupValue(1))!
        let month = Int(d.groupValue(2))!
        if !(1...31).contains(day) || !(1...12).contains(month) { return false }
        if !d.groupValue(3).isEmpty { return true }
        let units = Array((q as NSString).substring(to: m.range.location).utf16)
        let before = String(decoding: units.suffix(14), as: UTF16.self)
        let twoDigits = d.groupValue(1).utf16.count == 2 && d.groupValue(2).utf16.count == 2
        return dayWord.containsMatch(in: before) || (twoDigits && dateWord.containsMatch(in: before))
    }
    private static let dateRe = JavaRegex(#"(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?"#)
    /// Words that make what follows a date even when it's "3.12".
    private static let dayWord = JavaRegex(#"(?<![\p{L}])(?:dia|day|date|data|dated|datado|vencimento|due)\s*:?\s*$"#, ignoreCase: true)
    /// Words that make a two-digit "14.11" a date.
    private static let dateWord = JavaRegex(#"(?<![\p{L}])(?:on|em|de|until|till|até|from|desde|by|since|before|after|antes de|depois de)\s*$"#, ignoreCase: true)

    /// Read "N,NNN" / "N.NNN" with a decimal comma: the question's own mark first ([decimalMark]), else [pt].
    public static func readsComma(_ q: String, pt: Bool) -> Bool { decimalMark(q).map { $0 == "," } ?? pt }

    private static let numberToken = JavaRegex(#"(?<![\d.,])\d+(?:[.,]\d+)+"#)
    private static let thousands = JavaRegex(#"\d{1,3}(?:[.,]\d{3})+"#)

    /// A whole count written with thousands marks, "27.000" or "27,000": 27000 in every language (a battery's mAh).
    private static func wholeNumber(_ raw: String) -> Double? {
        let t = UnitBridge.kotlinTrim(raw)
        guard thousands.matches(t) else { return nil }
        return Double(t.filter { $0.isASCII && $0.isNumber })
    }

    /// Portuguese in the rules' own words (t9 0330), for the answer's language when the detector misses a short question:
    /// "27.000 mAh 3,7 V no avião" has no question word. QueryContext is not touched.
    private static let ptWords = JsRegex(#"\b(?:avi[ãa]o|voo|voar|bagagem|companhia|litros?|milhas?|gal[ãa]o|gal[õo]es|quil[ôo]metros?|quanto|quantos|quantas|posso|pode|levar|meu|minha|tenho|preciso|gorjeta|c[âa]mbio)\b"#, flags: "i")

    private static func fmt(_ n: Double, _ pt: Bool, _ digits: Int = 2) -> String { JsNumber.locale(n, pt: pt, maxFractionDigits: digits) }

    // (a) Fuel economy: L/100 km <-> miles per gallon (US 235.215, UK 282.481).
    private static let uk = JsRegex(#"\b(uk|imperial|brit[âa]nic[oa]|ingl[eê]s)\b"#, flags: "i")
    private static let l100 = JsRegex(#"\#(num)\s*(?:l|litros?|liters?|litres?)\s*(?:/|a cada|por|per|every|each)\s*100\s*km"#, flags: "i")
    private static let asksMpg = JsRegex(#"\b(mpg|milhas? por gal[ãa]o|miles? per (?:us |uk |imperial )?gallon|mi\/gal)\b"#, flags: "i")
    private static let mpg = JsRegex(#"\#(num)\s*(?:mpg|milhas? por gal[ãa]o|miles? per (?:us |uk |imperial )?gallon)"#, flags: "i")
    private static let asksL100 = JsRegex(#"l\s*\/\s*100|litros? (a cada|por) 100|liters? per 100"#, flags: "i")

    private static func fuelEconomy(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        let isUk = uk.containsMatch(in: q)
        let k = isUk ? 282.481 : 235.215
        let gal = pt ? (isUk ? "galão imperial" : "galão americano") : (isUk ? "UK gallon" : "US gallon")
        if let m = l100.find(in: q), asksMpg.containsMatch(in: q) {
            let x = parseNumber(m.groupValue(1), pt: rd)
            if !(x > 0) { return nil }
            let v = k / x
            return pt
                ? "\(fmt(x, pt)) L/100 km = \(fmt(v, pt)) milhas por galão (\(gal)). Conta: mpg = \(fmt(k, pt, 3)) ÷ L/100 km."
                : "\(fmt(x, pt)) L/100 km = \(fmt(v, pt)) miles per gallon (\(gal)). Formula: mpg = \(fmt(k, pt, 3)) ÷ L/100 km."
        }
        if let m = mpg.find(in: q), asksL100.containsMatch(in: q) {
            let x = parseNumber(m.groupValue(1), pt: rd)
            if !(x > 0) { return nil }
            return pt
                ? "\(fmt(x, pt)) milhas por galão (\(gal)) = \(fmt(k / x, pt)) L/100 km. Conta: L/100 km = \(fmt(k, pt, 3)) ÷ mpg."
                : "\(fmt(x, pt)) miles per gallon (\(gal)) = \(fmt(k / x, pt)) L/100 km. Formula: L/100 km = \(fmt(k, pt, 3)) ÷ mpg."
        }
        return nil
    }

    // (b) Naismith's rule: 1 h per 5 km, plus 1 h per 600 m of ascent.
    private static let naismithRe = JsRegex("naismith", flags: "i")
    private static let km = JsRegex(#"\#(num)\s*km\b"#, flags: "i")
    private static let meters = JsRegex(#"\#(num)\s*m\b(?![a-z])"#, flags: "i")

    private static func naismith(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        if !naismithRe.containsMatch(in: q) { return nil }
        let kmMatch = km.find(in: q)
        let up = meters.find(in: JsString.replacingFirst(q, kmMatch?.value ?? "", with: ""))
        guard let kmMatch else { return nil }
        let d = parseNumber(kmMatch.groupValue(1), pt: rd)
        let a = up.map { parseNumber($0.groupValue(1), pt: rd) } ?? 0
        let h = d / 5 + a / 600
        let hh = h.rounded(.down)
        let mm = JsNumber.round((h - hh) * 60)
        let hhs = JsNumber.toString(hh)
        let mms = JsNumber.toString(mm)
        return pt
            ? "Pela regra de Naismith: \(fmt(d, pt)) km ÷ 5 km/h + \(fmt(a, pt, 0)) m ÷ 600 m/h = \(fmt(h, pt, 1)) h (cerca de \(hhs) h \(mms) min), sem contar paradas."
            : "By Naismith's rule: \(fmt(d, pt)) km ÷ 5 km/h + \(fmt(a, pt, 0)) m ÷ 600 m/h = \(fmt(h, pt, 1)) h (about \(hhs) h \(mms) min), not counting stops."
    }

    // (c) Currency with the rate the question gives, and an optional tip.
    private static let rate = JsRegex(
        #"\b1\s*(?:u\.?s\.?\s+)?(d[óo]lar(?:es)?(?: americanos?)?|us\$|usd|euros?|eur|€|libras?|gbp|reais|real|brl|r\$|dollars?(?: us)?)\s*(?:vale|valem|=|equals|is worth|is|custa)\s*\#(num)\s*([\p{L}$€£]+(?: [\p{L}]+)?)?"#,
        flags: "iu"
    )
    private static let amount = JsRegex(#"\#(num)\s*(?!%)(?!\s*%)([\p{L}$€£]+)?"#, flags: "iu")
    private static let percent = JsRegex(#"\#(num)\s*%"#)
    private static let tip = JsRegex(#"gorjeta|tip|servi[çc]o|gratuity"#, flags: "i")
    private static let esEnd = JsRegex(#"es$"#, flags: "i")
    private static let spaceDot = JsRegex(#"\s+\."#)
    private static let spaces2 = JsRegex(#"\s{2,}"#)

    private static func currency(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        guard let rateM = rate.find(in: q) else { return nil }
        let r = parseNumber(rateM.groupValue(2), pt: rd)
        let rest = JsString.replacingFirst(q, rateM.value, with: " ")
        let amountM = amount.find(in: percent.replace(in: rest, with: " "))
        guard let amountM, r > 0 else { return nil }
        let amountV = parseNumber(amountM.groupValue(1), pt: rd)
        let unitFrom = JsString.trim(amountM.group(2) ?? rateM.group(3) ?? "")
        let cur = rateM.groupValue(1)
        let unitTo = esEnd.replaceFirst(in: cur, with: "").lowercased().hasPrefix("d") ? (pt ? "dólares" : "US dollars") : cur
        let converted = amountV / r
        var text = "\(fmt(amountV, pt)) \(unitFrom) ÷ \(fmt(r, pt)) = \(fmt(converted, pt)) \(unitTo)."
        if let tipM = percent.find(in: q), tip.containsMatch(in: q) {
            let t = parseNumber(tipM.groupValue(1), pt: rd)
            let total = converted * (1 + t / 100)
            text += pt
                ? " Com \(fmt(t, pt))% de gorjeta: \(fmt(total, pt)) \(unitTo) (gorjeta de \(fmt(converted * (t / 100), pt)))."
                : " With a \(fmt(t, pt))% tip: \(fmt(total, pt)) \(unitTo) (tip \(fmt(converted * (t / 100), pt)))."
        }
        return spaces2.replace(in: spaceDot.replace(in: text, with: "."), with: " ")
    }

    // (d) Battery energy: Wh = mAh × V / 1000. With flight words, one neutral line instead of a verdict (adam, Nov 14; t9
    // 0143): the limits are set by airlines and IATA and they change (a power bank above 100 Wh is "Forbidden" in IATA's
    // 2026 guidance, and the 100-160 Wh approval goes from the DGR in 2027); an offline app can't know the rule of the day.
    private static let mah = JsRegex(#"\#(num)\s*mah\b"#, flags: "i")
    private static let volts = JsRegex(#"\#(num)\s*v\b"#, flags: "i")
    private static let flight = JsRegex(#"avi[ãa]o|voo|voar|bagagem|companhia a[ée]rea|plane|flight|fly|airline|carry[- ]on|luggage"#, flags: "i")

    public static let flightNoteEN = " Airlines set their battery limits in Wh, and the rules change: check your airline before you fly."
    public static let flightNotePT = " As companhias aéreas definem os limites de bateria em Wh, e as regras mudam: confira com a sua antes de voar."

    private static func battery(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        guard let mahM = mah.find(in: q), let vM = volts.find(in: q) else { return nil }
        let capacity = wholeNumber(mahM.groupValue(1)) ?? parseNumber(mahM.groupValue(1), pt: rd)
        let volt = parseNumber(vM.groupValue(1), pt: rd)
        let wh = (capacity * volt) / 1000
        var text = "\(fmt(capacity, pt, 0)) mAh × \(fmt(volt, pt)) V ÷ 1000 = \(fmt(wh, pt)) Wh."
        if flight.containsMatch(in: q) { text += pt ? flightNotePT : flightNoteEN }
        return text
    }

    private static let wordNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12,
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7,
        "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12,
    ]
    private static let countSrc =
        #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|um|uma|dois|duas|três|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze)"#

    private static func count(_ w: String, _ rd: Bool) -> Double {
        wordNumbers[w.lowercased()].map(Double.init) ?? parseNumber(w, pt: rd)
    }

    // (f) Water for a trip: people × days × litres per person per day; 1 L of water weighs about 1 kg.
    private static let waterRe = JsRegex(#"(?<![\p{L}])(water|[áa]gua)(?![\p{L}])"#, flags: "iu")
    private static let perDay = JsRegex(#"\#(num)\s*(?:l|litros?|liters?|litres?)\b[^.?!]{0,30}?(?:por dia|per day|a day|/dia|/day)"#, flags: "i")
    private static let people = JsRegex(#"\b(?:somos|we are|we're)\s+\#(countSrc)\b|\b\#(countSrc)\s+(?:of us|people|persons|pessoas|adultos|adults|hikers)\b"#, flags: "i")
    private static let days = JsRegex(#"\b\#(countSrc)[\s-]+(?:days?|dias?)\b"#, flags: "i")

    private static func water(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        if !waterRe.containsMatch(in: q) { return nil }
        guard let perDayM = perDay.find(in: q), let peopleM = people.find(in: q), let daysM = days.find(in: q) else { return nil }
        let l = parseNumber(perDayM.groupValue(1), pt: rd)
        let p = count(peopleM.group(1) ?? peopleM.group(2)!, rd)
        let d = count(daysM.groupValue(1), rd)
        if !(l > 0 && p > 0 && d > 0) { return nil }
        let total = l * p * d
        return pt
            ? "\(fmt(p, pt, 0)) pessoas × \(fmt(d, pt, 0)) dias × \(fmt(l, pt)) L = \(fmt(total, pt)) litros de água, que pesam cerca de \(fmt(total, pt)) kg (1 L de água ≈ 1 kg)."
            : "\(fmt(p, pt, 0)) people × \(fmt(d, pt, 0)) days × \(fmt(l, pt)) L = \(fmt(total, pt)) liters of water, weighing about \(fmt(total, pt)) kg (1 L of water ≈ 1 kg)."
    }

    // from context.ts; replace with the shared port when context.ts lands
    private static let temperatureRe = JsRegex(
        #"(?<!\d)(-?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?|-?\d+(?:[.,]\d+)?)\s*(?:°|º|degrees?|graus?)?\s*(c|celsius|centigrade|f|fahrenheit)\b[^?]*?\b(?:in|to|into|em|para)\s+(?:degrees?\s+|graus?\s+)?(celsius|centigrade|fahrenheit|c|f)\b"#,
        flags: "i"
    )

    /// "What is 30 °C in Fahrenheit?": the conversion with its formula, or nil.
    /// [rd]: the question's decimal mark is a comma ([readsComma]); "1,500 °C" is 1500 in English (validator B-6).
    private static func temperatureConversion(_ query: String, _ pt: Bool, _ rd: Bool) -> String? {
        guard let m = temperatureRe.find(in: query) else { return nil }
        let value = parseNumber(m.groupValue(1), pt: rd)
        let from = m.groupValue(2).first!.lowercased() == "f" ? "F" : "C"
        let to = m.groupValue(3).first!.lowercased() == "f" ? "F" : "C"
        if from == to || !value.isFinite { return nil }
        let result = from == "C" ? (value * 9) / 5 + 32 : ((value - 32) * 5) / 9
        func f(_ n: Double) -> String { JsNumber.locale(JsNumber.round(n * 10) / 10, pt: pt) }
        let formula = from == "C" ? "°F = °C × 9/5 + 32" : "°C = (°F − 32) × 5/9"
        return "\(f(value)) °\(from) = \(f(result)) °\(to) (\(formula))."
    }

    // (e) A temperature, plus the heat warning when the question asks if it's dangerous (or it clearly is).
    private static let celsiusRe = JsRegex(#"(-?[\d.,]+)\s*°C"#)
    private static let hasC = JsRegex("°C")
    private static let asksSafe = JsRegex(#"perig|segur|caminh|trilha|correr|exerc|danger|safe|hike|hiking|walk|run|exercise"#, flags: "i")

    private static func temperature(_ q: String, _ pt: Bool, _ rd: Bool) -> String? {
        guard let base = temperatureConversion(q, pt, rd) else { return nil }
        let piece = JsString.split(base, "=").map(JsString.trim).first { hasC.containsMatch(in: $0) } ?? ""
        let c = celsiusRe.find(in: piece)
        let celsius = c.map { parseNumber($0.groupValue(1), pt: rd) } ?? Double.nan
        let asks = asksSafe.containsMatch(in: q)
        if !celsius.isFinite || !(asks && celsius >= 32) { return base }
        let note: String
        if celsius >= 40 {
            note = pt
                ? " Sim, é perigoso: a 40 °C ou mais o esforço físico traz alto risco de exaustão pelo calor e insolação. Se precisar sair, evite as horas mais quentes, beba água com frequência e descanse na sombra."
                : " Yes, it is dangerous: at 40 °C or more, physical effort carries a high risk of heat exhaustion and heatstroke. If you must go, avoid the hottest hours, drink water often and rest in the shade."
        } else if pt {
            note = " Calor forte: acima de 32-35 °C o risco de exaustão pelo calor sobe com esforço físico. Evite as horas mais quentes, beba água e faça pausas na sombra."
        } else {
            note = " Strong heat: above 32-35 °C the risk of heat exhaustion rises with effort. Avoid the hottest hours, drink water and take breaks in the shade."
        }
        return base + note
    }

    /// The exact answer to an arithmetic question, or nil. Order: the most specific first. A plain unit conversion
    /// ("26 miles in km", UnitConversion) is the last try, after the temperature rule (adam, Nov 13).
    public static func calculate(_ query: String, pt: Bool) -> Calculation? {
        // A pasted table of digit groups made each pass quadratic (validator B-5: 16,000 characters, 5 s). No calculator
        // question is that long: the model takes it.
        if query.utf16.count > maxQuery { return nil }
        // The answer's language: the detector, or the rules' own Portuguese words. The numbers: the question's own mark first.
        let ptText = pt || ptWords.containsMatch(in: query)
        let rd = readsComma(query, pt: ptText)
        let tries: [(String, (String, Bool, Bool) -> String?)] = [
            ("battery", battery),
            ("fuel-economy", fuelEconomy),
            ("naismith", naismith),
            ("currency", currency),
            ("water", water),
            ("temperature", temperature),
            ("conversion", { q, p, _ in UnitConversion.convert(q, pt: p) }),
        ]
        for (kind, fn) in tries {
            if let text = fn(query, ptText, rd), !text.isEmpty { return Calculation(kind: kind, text: text) }
        }
        return nil
    }
}
