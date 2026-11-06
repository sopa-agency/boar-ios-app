import Foundation

/// Ported from src/routing/travelDistance.ts in r4to's PR #85 (BOAR R&D, MIT), through android
/// `routing/TravelDistance.kt`.
///
/// Travel distance between two cities, computed offline. English only. Both places must resolve in the city table
/// (worldCities.v1.json: GeoNames cities15000, the 6,000 most populous cities, CC BY 4.0), passed in as its JSON;
/// otherwise nil and the question takes the normal path. The answer is always labelled an estimate: great-circle
/// distance from coordinates, times a stated route factor for walking, cycling or driving. It never claims a real road or
/// trail distance. The regexes are the TypeScript ones verbatim, through JsRegex.
public final class TravelDistance: Sendable {
    public struct City: Sendable, Equatable {
        /// The table row: two names of one row are the same city (Kotlin compares the instances).
        let row: Int
        public let name: String, country: String
        public let lat: Double, lon: Double, pop: Double
    }

    /// `mode`: "walk", "cycle", "drive" or nil.
    public struct Answer: Sendable, Equatable {
        public let text: String, from: String, to: String
        public let straightKm: Double
        public let mode: String?
        public let roundTrip: Bool
    }

    private let index: [String: City]

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any], let rows = root["cities"] as? [[Any]] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var index: [String: City] = [:]
        // Rows are sorted by population, so the first city under a name is the most populous one ("Paris" = Paris, France).
        for (i, r) in rows.enumerated() where r.count >= 6 {
            let name = r[0] as? String ?? ""
            let city = City(row: i, name: name, country: r[2] as? String ?? "", lat: (r[3] as? NSNumber)?.doubleValue ?? 0,
                            lon: (r[4] as? NSNumber)?.doubleValue ?? 0, pop: (r[5] as? NSNumber)?.doubleValue ?? 0)
            for k in [name, r[1] as? String ?? ""] where !k.isEmpty {
                let key = k.lowercased()
                if index[key] == nil { index[key] = city }
            }
        }
        self.index = index
    }

    /// A place phrase as the question writes it -> a city in the table, or nil. Accepts a trailing ", Country" or
    /// "in Country".
    public func lookupCity(_ phrase: String) -> City? {
        let s = Self.trail.replace(in: Self.lead.replace(in: JsString.trim(phrase), with: ""), with: "")
        let bare = JsString.trim(Self.countryTail.replace(in: s, with: ""))
        return index[s.lowercased()] ?? index[bare.lowercased()]
    }

    public func answer(_ query: String) -> Answer? {
        for (i, re) in Self.patterns.enumerated() {
            guard let m = re.find(in: query) else { continue }
            func g(_ n: Int) -> String? { m.group(n) }
            var verb: String?
            var by: String?
            let a: String, b: String
            var back: String?
            switch i {
            // As the TypeScript reads it: the second "by" after the round trip is not used.
            case 0: verb = g(1); by = g(2) ?? g(5); a = g(3) ?? ""; b = g(4) ?? ""; back = g(6)
            case 1: verb = g(1); a = g(2) ?? ""; b = g(3) ?? ""; back = g(4)
            case 2: b = g(1) ?? ""; a = g(2) ?? ""; by = g(3) // "how far is X from Y": from Y to X
            default: a = g(1) ?? ""; b = g(2) ?? ""; back = g(3)
            }
            guard let from = lookupCity(a), let to = lookupCity(b), from.row != to.row else { return nil }
            let km = Self.greatCircleKm(from.lat, from.lon, to.lat, to.lon)
            if km < 1 { return nil }
            let modeKey = (verb ?? (by == "foot" ? "walk" : by))?.lowercased()
            let mode = modeKey.flatMap { Self.verbMode[$0] }
            let roundTrip = !(back ?? "").isEmpty
            return Answer(text: Self.compose(from, to, km, mode, roundTrip, asksTime: i == 1), from: from.name, to: to.name,
                          straightKm: km, mode: mode, roundTrip: roundTrip)
        }
        return nil
    }

    /// Route factor (route length / straight line) and pace per mode; stated in the answer, never a measured route.
    private struct Pace {
        let factor: Double, perDayKm: Double, kmh: Double
        let verb: String
    }

    private static let modes = [
        "walk": Pace(factor: 1.3, perDayKm: 25, kmh: 5, verb: "walking"),
        "cycle": Pace(factor: 1.25, perDayKm: 80, kmh: 18, verb: "cycling"),
        "drive": Pace(factor: 1.25, perDayKm: 0, kmh: 80, verb: "driving"),
    ]

    /// In the Kotlin map's order: the regex alternation tries them in this order.
    private static let verbModes: [(String, String)] = [
        ("walk", "walk"), ("walking", "walk"), ("hike", "walk"), ("hiking", "walk"), ("trek", "walk"), ("run", "walk"), ("running", "walk"),
        ("cycle", "cycle"), ("cycling", "cycle"), ("bike", "cycle"), ("biking", "cycle"), ("ride", "cycle"), ("bicycle", "cycle"),
        ("drive", "drive"), ("driving", "drive"), ("car", "drive"),
    ]
    private static let verbMode = Dictionary(uniqueKeysWithValues: verbModes)

    private static let lead = JsRegex(#"^(?:the city of|downtown|central)\s+"#, flags: "i")
    private static let trail = JsRegex(#"[\s.?!,;:]+$"#, flags: "g")
    private static let countryTail = JsRegex(#"\s*(?:,|\bin\b)\s*[\p{L} .'-]+$"#, flags: "u")

    public static func greatCircleKm(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        func r(_ d: Double) -> Double { d * Double.pi / 180 }
        let dLat = r(bLat - aLat)
        let dLon = r(bLon - aLon)
        let s1 = sin(dLat / 2), s2 = sin(dLon / 2)
        let h = s1 * s1 + cos(r(aLat)) * cos(r(bLat)) * s2 * s2
        return 2 * 6371 * asin(h.squareRoot())
    }

    private static let place = #"([\p{L}][\p{L} .,'-]{0,40}?)"#
    private static let modeWords = verbModes.map(\.0).joined(separator: "|")
    private static let back = #"(\s+and\s+back|\s+and\s+return|\s+round[- ]trip|\s+return\s+trip|\s+there\s+and\s+back)?"#
    private static let by = #"(?:\s+(?:by|on)\s+(car|bike|bicycle|foot))?"#
    private static let patterns = [
        // "How far is it to walk from Paris to Rome and back?", "how many km to cycle from Lyon to Nice?"
        #"^\s*how\s+(?:far|many\s+(?:km|kilometers|kilometres|miles))\b(?:\s+(?:is\s+it|is|would\s+it\s+be|will\s+it\s+be))?(?:\s+to\s+(\#(modeWords)))?(?:\s+by\s+(car|bike|bicycle|foot))?\s+from\s+\#(place)\s+to\s+\#(place)\#(by)\#(back)\#(by)\s*\??\s*$"#,
        // "How long would it take to walk from Berlin to Prague?", "how many days to bike from Vienna to Budapest and back"
        #"^\s*how\s+(?:long|many\s+(?:days|hours|weeks))\b(?:\s+(?:does|would|will)\s+it\s+take(?:\s+me)?)?\s+to\s+(\#(modeWords))\s+from\s+\#(place)\s+to\s+\#(place)\#(back)\s*\??\s*$"#,
        // "How far is Rome from Paris?", "how far away is Kyoto from Tokyo by car"
        #"^\s*how\s+far(?:\s+away)?\s+is\s+\#(place)\s+from\s+\#(place)\#(by)\s*\??\s*$"#,
        // "What's the distance between Madrid and Barcelona?", "distance from Oslo to Bergen"
        #"^\s*(?:what(?:'s|\s+is)\s+the\s+)?distance\s+(?:between|from)\s+\#(place)\s+(?:and|to)\s+\#(place)\#(back)\s*\??\s*$"#,
    ].map { JsRegex($0, flags: "iu") }

    private static func fmt(_ n: Double) -> String { JsNumber.locale(JsNumber.round(n), pt: false) }
    private static func round10(_ n: Double) -> Double { JsNumber.round(n / 10) * 10 }
    private static func round100(_ n: Double) -> Double { JsNumber.round(n / 100) * 100 }

    /// Number.prototype.toFixed: the exact binary value, rounded half up, with exactly `digits` decimals (non-negative n).
    static func toFixed(_ n: Double, _ digits: Int) -> String {
        let d = JsNumber.exact(n).roundedHalfUp(toScale: digits)
        let s = d.plainString()
        let decimals = d.digits.isEmpty ? 0 : max(d.scale, 0)
        if decimals >= digits { return s }
        return s + (decimals == 0 ? "." : "") + String(repeating: "0", count: digits - decimals)
    }

    private static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func compose(_ from: City, _ to: City, _ km: Double, _ mode: String?, _ roundTrip: Bool, asksTime: Bool) -> String {
        let line = "\(from.name) and \(to.name) are about \(fmt(km)) km (\(fmt(km * 0.621)) miles) apart in a straight line."
        let caveat = "This is an estimate from the cities' coordinates, not a mapped route; the real route can differ."
        guard let mode, let p = modes[mode] else {
            let road = km * 1.25
            let total = roundTrip ? " Twice that for the round trip: about \(fmt(round10(2 * km))) km in a straight line." : ""
            return "\(line)\(total) Roads and trails are usually longer than the straight line, by about a quarter, so expect roughly "
                + "\(fmt(round10(road))) km\(roundTrip ? " each way (\(fmt(round100(2 * road))) km there and back)" : "") by land. \(caveat)"
        }
        let oneWay = km * p.factor
        let hours = oneWay / p.kmh
        let route = "\(line) \(cap(p.verb)) routes are usually about \(JsNumber.locale(JsNumber.round((p.factor - 1) * 100), pt: false))% longer than that, "
            + "so plan on roughly \(fmt(round10(oneWay))) km (\(fmt(round10(oneWay * 0.621))) miles) each way"
            + (roundTrip ? ", about \(fmt(round100(2 * oneWay))) km there and back." : ".")
        let time = mode == "drive"
            ? "about \(hours < 10 ? toFixed(hours, 1) : fmt(hours)) hours of driving each way at an average \(fmt(p.kmh)) km/h"
                + (roundTrip ? " (about \(fmt(2 * hours)) hours in total)" : "") + ", before stops"
            : "about \(fmt(oneWay / p.perDayKm)) days each way at a steady \(fmt(p.perDayKm)) km a day"
                + (roundTrip ? ", or around \(toFixed(2 * oneWay / p.perDayKm / 30, 1)) months for the round trip without rest days" : "")
                + " (about \(fmt(hours)) hours of \(p.verb) each way at \(fmt(p.kmh)) km/h)"
        let head = roundTrip ? "Roughly \(fmt(round100(2 * oneWay))) km there and back (an estimate)." : "Roughly \(fmt(round10(oneWay))) km (an estimate)."
        return asksTime ? "\(cap(time)) (an estimate). \(route) \(caveat)" : "\(head) \(route) That is \(time). \(caveat)"
    }
}
