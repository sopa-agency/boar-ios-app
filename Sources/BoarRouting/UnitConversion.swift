import Foundation

/// A plain unit conversion, answered exactly (android `routing/UnitConversion.kt`, adam, Nov 13: "send converter"). On the F3
/// "26 miles in km" went to the 1.7B model: 35.8 s for a long text that said 41.8 km and then flagged its own numbers as
/// not in the sources. Calculators runs this last, after the temperature rule; the receipt says "calculator-conversion".
///
/// Length (mile, km, m, cm, foot, inch, yard), mass (kg, lb, g, oz) and volume (US gallon, L), exact factors, any two
/// units of one family, EN and PT. Two shapes, both with the question's own number: "26 miles in km" (also "to", "into",
/// "em", "para") and "how many km is 26 miles" / "quantos km são 26 milhas".
///
/// Left alone, so the rules that work today keep their questions: a rate (mph, km/h, "per hour", "por hora", "/h": those
/// are UnitBridge + Arithmetic), a fuel economy ("/100" or mpg: the fuel rule), a UK or imperial gallon (the fuel rule
/// tells them apart, this one only knows the US gallon), two names for the same unit, and a unit with no number before
/// it. The health lexicon is CalcShortcut's (NumGuard). Pure: text in, answer out.
public enum UnitConversion {
    private struct Unit {
        let family: String
        /// The size in the family's base: metres, grams or litres.
        let base: Double
        /// Miles, feet, pounds: the factor is said from this side ("1 lb = 0.45359237 kg").
        let imperial: Bool
        let en: (String, String)
        let pt: (String, String)
        /// The names a question uses, as a regex alternation.
        let names: String
    }

    private static let units: [Unit] = [
        Unit(family: "length", base: 1609.344, imperial: true, en: ("mile", "miles"), pt: ("milha", "milhas"), names: "mi|miles?|milhas?"),
        Unit(family: "length", base: 1000.0, imperial: false, en: ("km", "km"), pt: ("km", "km"), names: #"km|kms|kilomet(?:er|re)s?|quil[ôo]metros?"#),
        // "m" is a metre only as a whole word (after a number, or after "in"/"em"): never the start of "my" or "min".
        Unit(family: "length", base: 1.0, imperial: false, en: ("m", "m"), pt: ("m", "m"), names: "m|met(?:er|re)s?|metros?"),
        Unit(family: "length", base: 0.01, imperial: false, en: ("cm", "cm"), pt: ("cm", "cm"), names: #"cm|centimet(?:er|re)s?|cent[íi]metros?"#),
        Unit(family: "length", base: 0.3048, imperial: true, en: ("foot", "feet"), pt: ("pé", "pés"), names: #"ft|feet|foot|pés?|pes"#),
        // "in" alone is an inch only in the source slot and only when a "to"/"in"/"em" follows ("5 in to cm"): see sourceTail.
        Unit(family: "length", base: 0.0254, imperial: true, en: ("inch", "inches"), pt: ("polegada", "polegadas"), names: "inch(?:es)?|polegadas?"),
        Unit(family: "length", base: 0.9144, imperial: true, en: ("yard", "yards"), pt: ("jarda", "jardas"), names: "yds?|yards?|jardas?"),
        Unit(family: "mass", base: 1000.0, imperial: false, en: ("kg", "kg"), pt: ("kg", "kg"), names: "kgs?|kilos?|kilogram(?:me)?s?|quilos?|quilogramas?"),
        Unit(family: "mass", base: 453.59237, imperial: true, en: ("lb", "lb"), pt: ("lb", "lb"), names: "lbs?|pounds?|libras?"),
        Unit(family: "mass", base: 1.0, imperial: false, en: ("g", "g"), pt: ("g", "g"), names: "g|gram(?:me)?s?|gramas?"),
        Unit(family: "mass", base: 28.349523125, imperial: true, en: ("oz", "oz"), pt: ("oz", "oz"), names: #"oz|ounces?|on[çc]as?"#),
        Unit(family: "volume", base: 3.785411784, imperial: true, en: ("US gallon", "US gallons"), pt: ("galão americano", "galões americanos"),
             names: #"(?:us\s+)?gallons?|gal|gal[ãa]o(?:\s+americano)?|gal[õo]es(?:\s+americanos)?"#),
        Unit(family: "volume", base: 1.0, imperial: false, en: ("L", "L"), pt: ("L", "L"), names: "l|lit(?:er|re)s?|litros?"),
    ]

    private static let unitRes: [JavaRegex] = units.map { JavaRegex("(?:\($0.names))", ignoreCase: true) }
    private static let allNames = units.map(\.names).joined(separator: "|")

    // As Calculators.num: "1.5", PT "1,5", "1,200.5", PT "2.450"; starts only where a run of digits starts.
    private static let num = #"(?<![\d\p{L}])(\d{1,3}(?:[.\s]\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)"#
    private static let end = #"(?![\p{L}/])"#
    private static let to = "(?:in|into|to|em|para|in terms of)"

    /// The number and the unit it's in: "in" counts as inches only when a "to"/"in"/"em" follows ("5 in to cm").
    private static let sourceTail = #"\s*((?:\#(allNames))\#(end)|in(?=\s+(?:to|into|in|em|para)\s))"#

    /// "26 miles in km", "convert 26 miles into kilometres", "26 milhas para quilômetros".
    private static let forward = JavaRegex(#"\#(num)\#(sourceTail)\s+\#(to)\s+(?:(?:the|o|a|os|as)\s+)?((?:\#(allNames)))\#(end)"#, ignoreCase: true)

    /// A quantity right before the converted number: "5 feet " in "5 feet 10 in to cm", "1 lb and " in "1 lb and 8 oz".
    private static let partBefore = JavaRegex(#"\d\s*((?:\#(allNames)))\#(end)\s*(?:,|and|e|&|plus|mais|y)?\s*$"#, ignoreCase: true)

    /// A bare number and a range word right before the converted number: "5 and ", "5-", "5 to ", "5 a ", "5 ou ".
    private static let rangeBefore = JavaRegex(#"\d(?:[.,]\d+)?\s*(?:and|to|or|-|–|—|a|e|até|ou)\s*[-−]?$"#, ignoreCase: true)

    /// A quantity right after the converted one: " 10 inches" in "how many cm is 5 feet 10 inches".
    private static let partAfter = JavaRegex(#"^\s*(?:,|and|e|&|plus|mais|y)?\s*\d+(?:[.,]\d+)?\s*((?:\#(allNames)))\#(end)"#, ignoreCase: true)
    /// A bare number right after the converted quantity ("5 feet 10", the inches unsaid): a compound too (R-B3).
    private static let bareAfter = JavaRegex(#"^\s*(?:and|e|plus|mais)?\s*\d+(?:[.,]\d+)?\s*(?:\?|$|\s+(?:in|to|into|em|para)\b)"#, ignoreCase: true)

    /// "how many km is 26 miles", "how many cm in 6 feet", "quantos km são 26 milhas", "quantas libras tem 80 kg".
    private static let asked = JavaRegex(
        #"(?<![\p{L}])(?:how\s+many|quant[oa]s)\s+((?:\#(allNames)))\#(end)\s+(?:is|are|in|make|equals?|são|sao|é|e|tem|têm|dá|da|dão|em|há\s+em|cabem\s+em)\s+(?:there\s+in\s+)?\#(num)\#(sourceTail)"#,
        ignoreCase: true
    )

    /// A rate or a fuel economy: UnitBridge + Arithmetic, or the fuel rule.
    private static let rate = JavaRegex(
        #"\b(?:mph|kph|kmh|mpg)\b|km\s*/\s*h|/\s*100|/\s*(?:h|hr|hour|s|sec|min)\b|\b(?:per|an?|each|every)\s+(?:hour|minute|second|hr)\b|\bpor\s+(?:hora|minuto|segundo)\b|\b(?:miles?|kilomet(?:er|re)s?)\s+per\b"#,
        ignoreCase: true
    )
    private static let ukGallon = JavaRegex(#"\b(?:uk|imperial|brit[âa]nic[oa]|ingl[eê]s)\b"#, ignoreCase: true)

    /// PT words in the conversion itself: "26 milhas em km" has no PT_QUESTION word and only one PT_ONLY one.
    private static let ptWords = JavaRegex(
        #"(?<![\p{L}])(?:em|para|quantos|quantas|quanto|são|milhas?|quil[ôo]metros?|metros?|cent[íi]metros?|pés?|polegadas?|jardas?|quilos?|quilogramas?|libras?|gramas?|on[çc]as?|gal[ãa]o|gal[õo]es|litros?)(?![\p{L}])"#,
        ignoreCase: true
    )

    private static func unitIndex(_ raw: String) -> Int? {
        let name = UnitBridge.kotlinTrim(raw)
        if name.lowercased() == "in" && name.utf16.count == 2 { return 5 }
        return unitRes.firstIndex { $0.matches(name) }
    }

    /// Kotlin `Char.isLetterOrDigit` on one UTF-16 unit.
    private static func isLetterOrDigit(_ u: UInt16) -> Bool {
        guard let s = Unicode.Scalar(u) else { return false }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: return true
        default: return false
        }
    }

    /// "26 miles = 41.84 km (1 mile = 1.609344 km)." for a plain conversion, or nil.
    public static func convert(_ query: String, pt: Bool) -> String? {
        let ns = query as NSString
        if ns.length > Calculators.maxQuery { return nil }
        if rate.containsMatch(in: query) { return nil }
        let fwd = forward.find(in: query)
        let ask = fwd == nil ? asked.find(in: query) : nil
        let rawNum: String, from: String, dest: String, matched: String
        let numAt: Int, unitEnd: Int
        if let f = fwd {
            rawNum = f.groupValue(1); from = f.groupValue(2); dest = f.groupValue(3); matched = f.value
            numAt = f.ranges[1].location
            unitEnd = f.ranges[2].location + f.ranges[2].length
        } else if let a = ask {
            rawNum = a.groupValue(2); from = a.groupValue(3); dest = a.groupValue(1); matched = a.value
            numAt = a.ranges[2].location
            unitEnd = a.ranges[3].location + a.ranges[3].length
        } else {
            return nil
        }
        guard let srcI = unitIndex(from) else { return nil }
        let src = units[srcI]
        // "5 feet 10 in to cm", "1 lb 8 oz to kg": the number is the last part of a compound quantity. Converting it alone
        // looks exact and is wrong (validator B-2): the model takes the question.
        let before = ns.substring(to: numAt)
        let after = ns.substring(from: unitEnd)
        if let m = partBefore.find(in: before), let i = unitIndex(m.groupValue(1)), units[i].family == src.family { return nil }
        if let m = partAfter.find(in: after), let i = unitIndex(m.groupValue(1)), units[i].family == src.family { return nil }
        if src.family == "length" && bareAfter.containsMatch(in: after) { return nil }
        // "between 5 and 10 miles in km", "5-10 miles", "de 5 a 10 milhas": a range, not its last number (validator B-3).
        if rangeBefore.containsMatch(in: before) { return nil }
        guard let dstI = unitIndex(dest) else { return nil }
        let dst = units[dstI]
        if srcI == dstI || src.family != dst.family { return nil }
        if src.family == "volume" && ukGallon.containsMatch(in: query) { return nil }
        let ptHere = pt || ptWords.containsMatch(in: matched)
        // A minus right against the number is its sign ("-5 km", "−5 kg": a change, a difference), not a dash: it was
        // dropped and the answer turned positive (validator B-4). "5-10" never gets here (rangeBefore).
        let prev: UInt16 = numAt > 0 ? ns.character(at: numAt - 1) : 0
        let negative = numAt > 0 && (prev == 0x2D || prev == 0x2212) && (numAt == 1 || !isLetterOrDigit(ns.character(at: numAt - 2)))
        var x = Calculators.parseNumber(rawNum, pt: Calculators.readsComma(query, pt: ptHere))
        if negative { x = -x }
        if !x.isFinite { return nil }
        let y = x * src.base / dst.base
        if !y.isFinite { return nil }

        // The factor, said from the imperial side ("1 lb = 0.45359237 kg"), or from the bigger unit ("1 km = 1,000 m").
        let refI: Int
        if src.imperial != dst.imperial {
            refI = src.imperial ? srcI : dstI
        } else {
            refI = src.base >= dst.base ? srcI : dstI
        }
        let ref = units[refI]
        let otherI = refI == srcI ? dstI : srcI
        let other = units[otherI]
        let factor = ref.base / other.base
        let xs = JsNumber.locale(x, pt: ptHere, maxFractionDigits: 6)
        let ys = value(y, ptHere)
        let fs = JsNumber.locale(factor, pt: ptHere, maxFractionDigits: 9)
        return "\(xs) \(name(src, xs, ptHere)) = \(ys) \(name(dst, ys, ptHere)) (1 \(name(ref, "1", ptHere)) = \(fs) \(name(other, fs, ptHere)))."
    }

    /// Two decimals at most; under 1, three significant digits, so 0.02 miles isn't "0 km".
    private static func value(_ y: Double, _ pt: Bool) -> String {
        if y != 0.0 && abs(y) < 1 {
            return JsNumber.locale(JavaNumber.roundedDouble(y, significant: 3), pt: pt, maxFractionDigits: 12)
        }
        return JsNumber.locale(y, pt: pt, maxFractionDigits: 2)
    }

    /// Singular for "1" (EN) or under 2 (PT, "1,5 milha"); the printed number decides, so "1.00" rounds count.
    private static func name(_ u: Unit, _ printed: String, _ pt: Bool) -> String {
        let n = Calculators.parseNumber(printed, pt: pt)
        if pt { return n < 2 ? u.pt.0 : u.pt.1 }
        return n == 1.0 ? u.en.0 : u.en.1
    }
}
