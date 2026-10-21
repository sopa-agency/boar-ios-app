import BoarCore
import BoarRouting
import Foundation

/// Sharing an evaluation run with the BOAR project (supabase/functions/submit-results): what gets sent and what the server's
/// answer means (port of src/eval/shareResults.pure.ts). Nothing leaves the phone until the user confirms.
public enum ShareResults {
    public struct Device: Sendable, Equatable {
        /// "ios" for this app (the Android port defaults to "android").
        public var platform: String
        public var osVersion: String?
        /// Android only.
        public var apiLevel: Int?
        public var brand: String?
        public var model: String?
        public var soc: String?
        public var socManufacturer: String?
        public var hardware: String?
        public var ramBytes: Int64?
        public var cpuCores: Int?
        public var cpuFeatures: [String]?
        public var coreMaxFreqKHz: [Int64]?

        public init(
            platform: String = "ios", osVersion: String? = nil, apiLevel: Int? = nil, brand: String? = nil, model: String? = nil,
            soc: String? = nil, socManufacturer: String? = nil, hardware: String? = nil, ramBytes: Int64? = nil, cpuCores: Int? = nil,
            cpuFeatures: [String]? = nil, coreMaxFreqKHz: [Int64]? = nil
        ) {
            self.platform = platform; self.osVersion = osVersion; self.apiLevel = apiLevel; self.brand = brand; self.model = model
            self.soc = soc; self.socManufacturer = socManufacturer; self.hardware = hardware; self.ramBytes = ramBytes
            self.cpuCores = cpuCores; self.cpuFeatures = cpuFeatures; self.coreMaxFreqKHz = coreMaxFreqKHz
        }
    }

    public static func submitResultsUrl(supabaseUrl: String?, publishableKey: String?) -> String? {
        guard let supabaseUrl, !supabaseUrl.isEmpty, let publishableKey, !publishableKey.isEmpty else { return nil }
        var base = Substring(supabaseUrl)
        while base.last == "/" { base.removeLast() }
        return base + "/functions/v1/submit-results"
    }

    /// What goes to submit-results: the run's description (in the TS key order) and every row.
    public struct Submission: Sendable, Equatable {
        public var run: [(key: String, value: JSONValue)]
        public var rows: [JSONValue]

        public static func == (a: Submission, b: Submission) -> Bool {
            a.rows == b.rows && a.run.count == b.run.count && zip(a.run, b.run).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        }

        public func runValue(_ key: String) -> JSONValue? { run.first { $0.key == key }?.value }

        /// The JSON text that is signed and sent: `run` in insertion order, rows with sorted keys (`JSONValue.jsonString`).
        public var jsonString: String {
            let runText = run.map { "\(JSONValue.string($0.key).jsonString):\($0.value.jsonString)" }.joined(separator: ",")
            return "{\"run\":{\(runText)},\"rows\":[\(rows.map(\.jsonString).joined(separator: ","))]}"
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return String?.none }
        return s
    }

    private static func positive(_ n: Int64?) -> Int64? {
        guard let n, n > 0 else { return Int64?.none }
        return n
    }

    /// buildSubmission: the run's description and every row; absent values are left out, as JSON.stringify drops undefined.
    /// `rows` must not be empty: the run's id and eval set version come from the first row.
    public static func buildSubmission(rows: [JSONValue], device d: Device, appVersion: String) -> Submission {
        var run: [(key: String, value: JSONValue)] = []
        func put(_ k: String, _ v: JSONValue?) { if let v { run.append((k, v)) } }
        let first = rows[0]
        put("runId", first["runId"])
        put("evalSetVersion", first["evalSetVersion"])
        put("appVersion", .string(appVersion))
        put("platform", .string(d.platform))
        put("osVersion", d.osVersion.map(JSONValue.string))
        put("apiLevel", d.apiLevel.map { .int(Int64($0)) })
        put("deviceBrand", d.brand.map(JSONValue.string))
        put("deviceModel", d.model.map(JSONValue.string))
        // (`JSONValue` is ExpressibleByNilLiteral: a `nil` inside a closure here would become `.null`, not "absent".)
        put("soc", nonEmpty(d.soc).map(JSONValue.string))
        put("socManufacturer", nonEmpty(d.socManufacturer).map(JSONValue.string))
        put("hardware", nonEmpty(d.hardware).map(JSONValue.string))
        put("ramBytes", positive(d.ramBytes).map(JSONValue.int))
        put("cpuCores", d.cpuCores.map { .int(Int64($0)) })
        // An empty flag list means unknown, not "no i8mm or dotprod".
        put("cpuFeatures", (d.cpuFeatures.flatMap { $0.isEmpty ? [String]?.none : $0 }).map { JSONValue.array($0.map(JSONValue.string)) })
        put("coreMaxFreqKHz", d.coreMaxFreqKHz.map { JSONValue.array($0.map(JSONValue.int)) })
        return Submission(run: run, rows: rows)
    }

    public enum Result: String, Sendable, Equatable, CaseIterable {
        case shared, sharedPending = "shared-pending", alreadyShared = "already-shared", rateLimited = "rate-limited"
        case cooldown, networkLimited = "network-limited", rejected, offline, busy
        case serverError = "server-error", keyFailed = "key-failed", failed

        public var key: String { rawValue }
        public var succeeded: Bool { self == .shared || self == .sharedPending || self == .alreadyShared }
        public var canRetry: Bool { self == .offline || self == .busy || self == .serverError || self == .failed }
    }

    public struct Outcome: Sendable, Equatable {
        public var result: Result
        public var retryAt: String?
        public var status: Int?
        public var detail: String?
        public init(result: Result, retryAt: String? = nil, status: Int? = nil, detail: String? = nil) {
            self.result = result; self.retryAt = retryAt; self.status = status; self.detail = detail
        }
    }

    private static let offsetDateTime = Rx(
        "^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\\.[0-9]{1,9})?)?(?:[Zz]|[+-]([0-9]{2})(?::([0-9]{2})(?::([0-9]{2}))?)?)\\z"
    )

    /// Whether `OffsetDateTime.parse` accepts the text (ISO_OFFSET_DATE_TIME).
    static func isOffsetDateTime(_ s: String) -> Bool {
        guard let m = offsetDateTime.firstMatch(in: s) else { return false }
        func n(_ i: Int) -> Int? { m.group(i, in: s).flatMap(Int.init) }
        guard let y = n(1), let mo = n(2), let d = n(3), let h = n(4), let mi = n(5) else { return false }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...12).contains(mo), (1...days[mo - 1]).contains(d), h < 24, mi < 60 else { return false }
        if let sec = n(6), sec > 59 { return false }
        if let oh = n(7), oh > 18 { return false }
        if let om = n(8), om > 59 { return false }
        if let os = n(9), os > 59 { return false }
        return true
    }

    /// What submit-results answered, as something the screen can say.
    public static func outcome(status: Int, body: JSONValue?) -> Outcome {
        let error = body?["error"]?.stringValue
        switch status {
        case 201:
            return Outcome(result: body?["pendingReview"]?.boolValue == true ? .sharedPending : .shared, status: status)
        case 409:
            return Outcome(result: .alreadyShared, status: status)
        case 429:
            if error == "network_limited" { return Outcome(result: .networkLimited, status: status, detail: error) }
            let at = body?["retryAt"]?.stringValue.flatMap { isOffsetDateTime($0) ? $0 : nil }
            return Outcome(result: error == "cooldown" ? .cooldown : .rateLimited, retryAt: at, status: status, detail: error)
        case 400...499:
            return Outcome(result: .rejected, status: status, detail: error)
        case 503:
            return Outcome(result: .busy, status: status, detail: error)
        case 500...:
            return Outcome(result: .serverError, status: status, detail: error)
        default:
            return Outcome(result: .failed, status: status, detail: error)
        }
    }

    /// The string the device's key signs: the server's one-time challenge, then the exact payload.
    public static func signedMessage(challenge: String, payload: String) -> String { "\(challenge).\(payload)" }


    /// Splits a features line on whitespace (Kotlin `\s+`: ASCII whitespace), dropping empties.
    public static func parseCpuFeatures(_ line: String?) -> [String] {
        (line ?? "").split(whereSeparator: { " \t\n\u{0B}\u{0C}\r".contains($0) }).map(String.init)
    }

    public static func describeChipset(_ d: Device) -> String? {
        if let soc = d.soc, !soc.isEmpty {
            return [nonEmpty(d.socManufacturer), soc].compactMap { $0 }.joined(separator: " ")
        }
        return nonEmpty(d.hardware)
    }

    /// BigDecimal(kHz / 1e6).setScale(2, HALF_UP).stripTrailingZeros().toPlainString(): the double's exact value, rounded.
    private static func ghz(_ kHz: Int64) -> String {
        let d = Double(kHz) / 1e6
        var n = Int64((d * 100).rounded())
        // Settle the half-way cases on the double's exact value (fma is exact before its one rounding).
        if fma(d, 100, -(Double(n) - 0.5)) < 0 { n -= 1 } else if fma(d, 100, -(Double(n) + 0.5)) >= 0 { n += 1 }
        let whole = n / 100, frac = n % 100
        if frac == 0 { return String(whole) }
        return frac % 10 == 0 ? "\(whole).\(frac / 10)" : "\(whole).\(frac < 10 ? "0" : "")\(frac)"
    }

    /// "1 × 3.35 GHz + 3 × 3.2 GHz + 4 × 2.2 GHz": cores grouped by top frequency, fastest first.
    public static func describeCores(_ freqs: [Int64]?) -> String? {
        let known = (freqs ?? []).filter { $0 > 0 }
        if known.isEmpty { return nil }
        let counts = Dictionary(known.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.key > $1.key }.map { "\($0.value) × \(ghz($0.key)) GHz" }.joined(separator: " + ")
    }
}
