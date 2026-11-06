import Foundation

/// Ported from r4to's src/routing/numguard.ts (PR #85, BOAR R&D, MIT), through android `routing/NumGuard.kt`.
///
/// NUMGUARD: an English, single-topic numeric question that is a pure unit conversion, a clock calculation or an exact
/// calculator match may be answered by a deterministic calculator; anything that names a body, person/age, drug, dose,
/// symptom, injury, danger, alcohol or ingestion word, a body-range temperature, or that is not English, in this message
/// or (for the lexicon) in any earlier user turn, is not. The regexes are the TypeScript ones verbatim, through JsRegex.
///
/// Not ported (as on Android): conditionCards.ts isCardEmergency.
public enum NumGuard {
    // A short explicit list on top of Arithmetic's health and danger: people, care settings and symptoms they don't name.
    private static let personCare = JsRegex(
        #"\b(?:pregnan\w*|child(?:ren)?|kids?|son|daughter|sick|ill|illness|hospital|doctor|nurse|vomit\w*|diarrh\w*|rash|cough\w*|headaches?|ache\w*|dizz\w*|nause\w*|thermometer|body temperature|my temperature|weigh(?:t|s)? loss|bmi|alcohol|drunk|safe(?:ly)?|hurt\w*|wound\w*|burn\w*|cpr|(?:my|his|her|their|your|our) (?:temp|temperature)|\d+[\s-]*(?:year|month|week|day)s?[\s-]*old|paracetamol|acetaminophen|ibuprofen|aspirin|tylenol|advil|benadryl|antibiotic\w*|amoxicillin|units? of|urin\w*|pee\w*|poop\w*|stool|toxic\w*|bleach|ingest\w*|swallow\w*|drank|drink\w*|beers?|wine|vodka|bac|sober|bp|blood pressure|saturation|unconscious|wake up|survive|surviv\w*|without (?:food|water)|fell|fall(?:s|en)?|hit (?:his|her|my|their)? ?head|faint\w*|\w+'s (?:core )?temp\w*|core temp\w*|boy|girl|husband|wife|partner|mom|mum|mother|dad|father|grand\w*|friend|patient|newborn|stranded|chest|passed out|water broke)\b"#,
        flags: "i"
    )
    // A body temperature (30-45 °C, 86-113 °F) is a person's, whatever the wording.
    private static let bodyTemp = JsRegex(
        #"\b(?:3\d|4[0-5])(?:[.,]\d+)?\s?(?:°\s?|degrees? )?c(?:elsius)?\b|\b(?:8[6-9]|9\d|10\d|11[0-3])(?:[.,]\d+)?\s?(?:°\s?|degrees? )?f(?:ahrenheit)?\b"#,
        flags: "i"
    )
    // Accented Latin letters (not × ÷): not an English message.
    private static let nonEn = JsRegex("[À-ÖØ-öø-ɏ]")

    private static let num = #"\d[\d,]*(?:\.\d+)?"#
    // A number followed by a unit, a currency or a percent.
    private static let unit = JsRegex(
        #"(?:[$€£¥]\s?\#(num)|\#(num)\s?(?:%|°\s?[cf]?\b|degrees?\b|(?:k?m|cm|mm|km\/h|kph|mph|mi|miles?|ft|feet|foot|inch(?:es)?|yards?|metres?|meters?|kilomet(?:re|er)s?|kg|g|lbs?|pounds?|ounces?|oz|tons?|tonnes?|l|litres?|liters?|gallons?|gal|pints?|cups?|bar|psi|kpa|hpa|mah|wh|kwh|w|watts?|v|volts?|amps?|hz|ghz|mhz|gb|mb|kb|tb|tokens?|bytes?|bits?|sec(?:ond)?s?|min(?:ute)?s?|h|hrs?|hours?|days?|weeks?|dollars?|euros?|usd|eur|gbp|cents?|btc|eth|sats?|gwei|coins?|million|billion|thousand)\b))"#,
        flags: "i"
    )
    private static let clock = JsRegex(#"\b\d{1,2}(?::\d{2}\s?(?:am|pm)?|\s?(?:am|pm))\b"#, flags: "i")
    // A conversion target ("in psi", "to Celsius", "convert") or a clock question: the shape of a misfire, not of a situation.
    private static let convert = JsRegex(
        #"\b(?:convert(?:s|ed|ing)?|(?:in|to|into) (?:fahrenheit|celsius|kelvin|psi|bar|kpa|hpa|mph|km\/h|kph|feet|ft|inches|cm|mm|metres|meters|miles|kilomet(?:re|er)s|yards|pounds|lbs|kg|kilograms|grams|ounces|oz|litres|liters|gallons|pints|cups|ml|watt-hours|wh|kwh|euros?|dollars?|usd|eur|gbp))\b"#,
        flags: "i"
    )
    private static let howManyUnit = JsRegex(
        #"\bhow many (?:kilomet(?:re|er)s|km|miles|feet|ft|metres|meters|inches|cm|yards|pounds|lbs|kg|kilograms|grams|ounces|oz|litres|liters|gallons|pints|cups|psi|watt-hours|wh|kwh) (?:is|are|in|make)\b"#,
        flags: "i"
    )
    private static let when = JsRegex(#"\b(?:what time|when (?:does|do|will|did)|arrive|arrives)\b"#, flags: "i")
    private static let identifier = JsRegex(#"\b[A-Za-z]+-\d+\b"#, flags: "g")
    private static let year = JsRegex(#"\b(?:1[5-9]\d\d|20\d\d)s?\b"#, flags: "g")
    private static let digit = JsRegex(#"\d"#)

    /// True when the question names a health, injury, danger or person-care word: the health path's call stands.
    public static func healthLexicon(_ query: String) -> Bool {
        Arithmetic.health.containsMatch(in: query) || Arithmetic.danger.containsMatch(in: query) || personCare.containsMatch(in: query)
            || QueryContext.isHealthQuestion(query)
    }

    /// A body-range temperature (30-45 °C, 86-113 °F): a person's.
    public static func bodyTemperature(_ query: String) -> Bool { bodyTemp.containsMatch(in: query) }

    /// A number with a unit plus a conversion target ("in psi", "to Celsius", "how many feet is"), or a clock time plus a
    /// clock question.
    public static func numericIntent(_ query: String) -> Bool {
        // Identifiers ("EIP-4444", "DS-160") and years or decades ("in 1900", "the 1600s", "mid-2012") are not quantities.
        let q = year.replace(in: identifier.replace(in: query, with: " "), with: " ")
        if !digit.containsMatch(in: q) { return false }
        return (unit.containsMatch(in: q) && (convert.containsMatch(in: q) || howManyUnit.containsMatch(in: q)))
            || (clock.containsMatch(in: q) && when.containsMatch(in: q))
    }

    /// The guard: English (not PT/ES, no accented letters), no body-range temperature, no health lexicon in this or any
    /// earlier user turn, AND (a calculator match OR numeric intent).
    public static func numericGuard(_ query: String, pt: Bool, userTurns: [String] = []) -> Bool {
        if pt || QueryContext.isSpanishQuestion(query) || nonEn.containsMatch(in: query) || bodyTemperature(query) { return false }
        if ([query] + userTurns).contains(where: healthLexicon) { return false }
        return Calculators.calculate(query, pt: pt) != nil || numericIntent(query)
    }
}

/// The calculator shortcuts of r4to's src/routing/answer.ts (PR #85, BOAR R&D, MIT), through android
/// `routing/CalcShortcut.kt`, in its order: the exact calculators (Calculators: battery, fuel economy, Naismith,
/// currency, water, temperature; EN and PT), then the word problems (Arithmetic; EN only). NumGuard's health lexicon
/// over this turn and the earlier user turns keeps them off health.
public enum CalcShortcut {
    /// `code`: the receipt code answer.ts gives ("calculator-battery", "temperature-conversion", "calculator-rate-time").
    public struct Hit: Sendable, Equatable {
        public let code: String
        public let text: String
    }

    public static func answer(_ query: String, userTurns: [String] = []) -> Hit? {
        if ([query] + userTurns).contains(where: NumGuard.healthLexicon) { return nil }
        let pt = QueryContext.isPortugueseQuestion(query)
        if let c = Calculators.calculate(query, pt: pt) {
            return Hit(code: c.kind == "temperature" ? "temperature-conversion" : "calculator-\(c.kind)", text: c.text)
        }
        if pt || QueryContext.isSpanishQuestion(query) { return nil }
        return Arithmetic.answer(query).map { Hit(code: "calculator-\($0.kind)", text: $0.text) }
    }
}
