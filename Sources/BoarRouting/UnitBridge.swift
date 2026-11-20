import Foundation

/// Miles and kilometres in one rate-and-time question (android `routing/UnitBridge.kt`, adam, Nov 12): "120 miles at 60 mph,
/// answer in km" or "200 km at 50 mph". The distance is converted to the rate's unit before the rate × time rule reads
/// it, and the answer says the conversion. Without a mix, nothing changes.
public enum UnitBridge {
    public static let kmPerMile = 1.609344

    public struct Prepared: Sendable, Equatable {
        public let query: String
        public let note: String?
        public init(query: String, note: String?) {
            self.query = query
            self.note = note
        }
    }

    private static let km = JavaRegex(#"(\d+(?:\.\d+)?)\s*(?:km|kms|kilomet(?:er|re)s?)\b"#, ignoreCase: true)
    private static let miles = JavaRegex(#"(\d+(?:\.\d+)?)\s*(?:mi|miles?)\b(?!\s*(?:per|an?)\s*hour)"#, ignoreCase: true)
    private static let mph = JavaRegex(#"\b(?:mph|miles?\s+(?:per|an?)\s+hour)\b"#, ignoreCase: true)
    private static let kmh = JavaRegex(#"\b(?:km/h|kmh|kph|kilomet(?:er|re)s?\s+(?:per|an?)\s+hour)\b"#, ignoreCase: true)
    private static let wantsKm = JavaRegex(#"\b(?:in|into|to)\s+(?:km|kilomet(?:er|re)s)\b|\banswer\s+in\s+km\b"#, ignoreCase: true)
    private static let wantsMiles = JavaRegex(#"\b(?:in|into|to)\s+miles\b"#, ignoreCase: true)
    private static let spaces2 = JavaRegex(#"\s{2,}"#)

    public static func prepare(_ query: String) -> Prepared {
        let isMph = mph.containsMatch(in: query)
        let isKmh = kmh.containsMatch(in: query)
        if isMph == isKmh { return Prepared(query: query, note: nil) }
        // The words asking for the other unit aren't a distance: "in km" left in the question would read as one.
        var q = wantsMiles.replace(in: wantsKm.replace(in: query, with: " "), with: " ")
        var notes: [String] = []
        func replaceRange(_ r: NSRange, _ with: String) { q = (q as NSString).replacingCharacters(in: r, with: with) }
        if isMph {
            if let m = km.find(in: q) {
                let k = JsNumber.parse(m.groupValue(1)); let mi = k / kmPerMile
                replaceRange(m.range, "\(exact(mi)) miles"); notes.append("\(fmt(k)) km = \(fmt(mi)) miles")
            }
            if notes.isEmpty && wantsKm.containsMatch(in: query), let m = miles.find(in: q) {
                let mi = JsNumber.parse(m.groupValue(1)); notes.append("\(fmt(mi)) miles = \(fmt(mi * kmPerMile)) km")
            }
        } else if let m = miles.find(in: q) {
            let mi = JsNumber.parse(m.groupValue(1)); let k = mi * kmPerMile
            replaceRange(m.range, "\(exact(k)) km"); notes.append("\(fmt(mi)) miles = \(fmt(k)) km")
        }
        return Prepared(query: kotlinTrim(spaces2.replace(in: q, with: " ")), note: notes.first)
    }

    /// Kotlin `String.trim()`: `Char.isWhitespace` at both ends.
    static func kotlinTrim(_ s: String) -> String {
        let u = Array(s.utf16)
        func ws(_ c: UInt16) -> Bool {
            guard let sc = Unicode.Scalar(c) else { return false }
            return sc.properties.isWhitespace || (0x1C...0x1F).contains(c)
        }
        var a = 0
        var b = u.count
        while a < b, ws(u[a]) { a += 1 }
        while b > a, ws(u[b - 1]) { b -= 1 }
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    /// For the sum itself: full precision, so 0.02 miles isn't "0 km" (CodeRabbit); [fmt] is only for the note.
    private static func exact(_ x: Double) -> String {
        // A number too big for a Double (a 400-digit one) stays as it was printed before, never a throw (validator N-4).
        if !x.isFinite { return JavaNumber.nonFinite(x) }
        if abs(x - x.rounded(.toNearestOrEven)) < 1e-9 && abs(x) < 9e15 { return String(Int64(x.rounded(.toNearestOrEven))) }
        return JavaNumber.roundedPlain(x, significant: 15)
    }

    /// The note: one decimal, or up to three significant digits under 1 ("0.02 miles = 0.032 km", not "0 miles = 0 km").
    private static func fmt(_ x: Double) -> String {
        if !x.isFinite { return JavaNumber.nonFinite(x) }
        if x != 0.0 && abs(x) < 1 { return JavaNumber.roundedPlain(x, significant: 2) }
        if abs(x - x.rounded(.toNearestOrEven)) < 0.05 && abs(x) < 9e15 { return String(Int64(x.rounded(.toNearestOrEven))) }
        return JavaNumber.fixed(x, decimals: 1)
    }
}
