import Foundation

/// JavaScript number semantics the routing modules print or parse.
public enum JsNumber {
    /// An exact decimal: `digits` (most significant first, no leading zeros, empty = zero) × 10^-scale.
    struct Decimal10: Equatable {
        var digits: [UInt8]
        var scale: Int

        var isZero: Bool { digits.isEmpty }

        /// Drops trailing zero digits (BigDecimal.stripTrailingZeros).
        func stripped() -> Decimal10 {
            var d = digits
            var s = scale
            while let l = d.last, l == 0 { d.removeLast(); s -= 1 }
            if d.isEmpty { return Decimal10(digits: [], scale: 0) }
            return Decimal10(digits: d, scale: s)
        }

        /// BigDecimal.round(MathContext(p, HALF_EVEN)).
        func rounded(significant p: Int) -> Decimal10 {
            if digits.count <= p { return self }
            var kept = Array(digits[0..<p])
            let first = digits[p]
            let restNonZero = digits[(p + 1)...].contains { $0 != 0 }
            let up = first > 5 || (first == 5 && (restNonZero || (kept.last! % 2 == 1)))
            if up { Decimal10.increment(&kept) }
            return Decimal10(digits: kept, scale: scale - (digits.count - p))
        }

        /// BigDecimal.setScale(n, HALF_UP) when the scale is larger than n (only the first dropped digit counts).
        func roundedHalfUp(toScale n: Int) -> Decimal10 {
            if scale <= n { return self }
            let drop = scale - n
            var padded = digits
            if padded.count < drop { padded = [UInt8](repeating: 0, count: drop - padded.count) + padded }
            let keepCount = padded.count - drop
            var kept = Array(padded[0..<keepCount])
            if padded[keepCount] >= 5 { Decimal10.increment(&kept) }
            while let f = kept.first, f == 0 { kept.removeFirst() }
            return Decimal10(digits: kept, scale: n)
        }

        static func increment(_ d: inout [UInt8]) {
            var i = d.count - 1
            while i >= 0 {
                if d[i] == 9 { d[i] = 0; i -= 1 } else { d[i] += 1; return }
            }
            d.insert(1, at: 0)
        }

        var asDouble: Double {
            if digits.isEmpty { return 0 }
            return Double(String(digits.map { Character(UnicodeScalar($0 + 48)) }) + "e" + String(-scale)) ?? .nan
        }

        /// BigDecimal.toPlainString() for a stripped value.
        func plainString() -> String {
            if digits.isEmpty { return "0" }
            let ds = String(digits.map { Character(UnicodeScalar($0 + 48)) })
            if scale <= 0 { return ds + String(repeating: "0", count: -scale) }
            if digits.count > scale {
                let cut = ds.index(ds.startIndex, offsetBy: digits.count - scale)
                return ds[..<cut] + "." + ds[cut...]
            }
            return "0." + String(repeating: "0", count: scale - digits.count) + ds
        }
    }

    /// The exact decimal expansion of a finite positive double (BigDecimal(d)).
    static func exact(_ d: Double) -> Decimal10 {
        let bits = d.significandBitPattern
        var m: UInt64
        var e: Int
        if d.exponentBitPattern == 0 {
            m = bits
            e = -1074
        } else {
            m = bits | (UInt64(1) << 52)
            e = Int(d.exponentBitPattern) - 1075
        }
        while m & 1 == 0, e < 0 { m >>= 1; e += 1 }
        // little-endian base 1e9 limbs
        var limbs: [UInt64] = []
        var t = m
        while t > 0 { limbs.append(t % 1_000_000_000); t /= 1_000_000_000 }
        func mul(_ f: UInt64) {
            var carry: UInt64 = 0
            for i in 0..<limbs.count {
                let v = limbs[i] * f + carry
                limbs[i] = v % 1_000_000_000
                carry = v / 1_000_000_000
            }
            while carry > 0 { limbs.append(carry % 1_000_000_000); carry /= 1_000_000_000 }
        }
        var scale = 0
        if e >= 0 {
            var left = e
            while left >= 29 { mul(1 << 29); left -= 29 }
            if left > 0 { mul(UInt64(1) << UInt64(left)) }
        } else {
            var left = -e
            scale = left
            while left >= 12 { mul(244_140_625); left -= 12 } // 5^12
            while left > 0 { mul(5); left -= 1 }
        }
        var digits: [UInt8] = []
        for (idx, limb) in limbs.reversed().enumerated() {
            var s = String(limb)
            if idx > 0 { s = String(repeating: "0", count: 9 - s.count) + s }
            digits.append(contentsOf: s.utf8.map { $0 - 48 })
        }
        return Decimal10(digits: digits, scale: scale)
    }

    /// The shortest decimal that reads back as [d] (finite, non-negative), as ECMAScript and ICU pick it.
    static func shortest(_ d: Double) -> Decimal10 {
        if d == 0 { return Decimal10(digits: [], scale: 0) }
        let ex = exact(d)
        for p in 1...17 {
            let r = ex.rounded(significant: p)
            if r.asDouble == d { return r.stripped() }
        }
        return ex.stripped()
    }

    /// String(n).
    public static func toString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n == .infinity { return "Infinity" }
        if n == -.infinity { return "-Infinity" }
        if n == 0 { return "0" }
        if n < 0 { return "-" + toString(-n) }
        let bd = shortest(n)
        let digits = String(bd.digits.map { Character(UnicodeScalar($0 + 48)) })
        let k = digits.count
        let e = k - bd.scale // value = 0.digits x 10^e
        if e >= k && e <= 21 { return digits + String(repeating: "0", count: e - k) }
        if e >= 1 && e <= 21 {
            let cut = digits.index(digits.startIndex, offsetBy: e)
            return digits[..<cut] + "." + digits[cut...]
        }
        if e >= -5 && e <= 0 { return "0." + String(repeating: "0", count: -e) + digits }
        let x = e - 1
        let exp = "e" + (x < 0 ? "-" : "+") + String(abs(x))
        if k == 1 { return digits + exp }
        return String(digits.first!) + "." + digits.dropFirst() + exp
    }

    private static func isDigit(_ u: UInt8, base: Int) -> Bool {
        switch base {
        case 16: return (u >= 48 && u <= 57) || (u >= 65 && u <= 70) || (u >= 97 && u <= 102)
        case 8: return u >= 48 && u <= 55
        case 2: return u == 48 || u == 49
        default: return u >= 48 && u <= 57
        }
    }

    /// Number(string) for decimal, hex/octal/binary and Infinity literals; anything else is NaN.
    public static func parse(_ raw: String) -> Double {
        let s = JsString.trim(raw)
        if s.isEmpty { return 0 }
        let u = Array(s.utf8)
        if u.count > 2, u[0] == 48, let b = [UInt8(120): 16, 88: 16, 111: 8, 79: 8, 98: 2, 66: 2][u[1]] {
            let body = u[2...]
            if body.allSatisfy({ isDigit($0, base: b) }) { return radixValue(Array(body), base: b) }
        }
        if s == "Infinity" || s == "+Infinity" { return .infinity }
        if s == "-Infinity" { return -.infinity }
        // [+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?
        var i = 0
        if i < u.count, u[i] == 43 || u[i] == 45 { i += 1 }
        let intStart = i
        while i < u.count, isDigit(u[i], base: 10) { i += 1 }
        let intDigits = i - intStart
        var fracDigits = 0
        if i < u.count, u[i] == 46 {
            i += 1
            let fs = i
            while i < u.count, isDigit(u[i], base: 10) { i += 1 }
            fracDigits = i - fs
        }
        if intDigits == 0 && fracDigits == 0 { return .nan }
        if i < u.count, u[i] == 101 || u[i] == 69 {
            i += 1
            if i < u.count, u[i] == 43 || u[i] == 45 { i += 1 }
            let es = i
            while i < u.count, isDigit(u[i], base: 10) { i += 1 }
            if i == es { return .nan }
        }
        if i != u.count { return .nan }
        return Double(s) ?? .nan
    }

    /// The correctly rounded value of an integer written in base 2, 8 or 16 (any length).
    private static func radixValue(_ digits: [UInt8], base: Int) -> Double {
        func v(_ u: UInt8) -> Int { u <= 57 ? Int(u) - 48 : (u >= 97 ? Int(u) - 87 : Int(u) - 55) }
        var hex = ""
        switch base {
        case 16:
            hex = String(decoding: digits, as: UTF8.self)
        default:
            let bitsPer = base == 8 ? 3 : 1
            var bits: [UInt8] = []
            for d in digits {
                let x = v(d)
                for sh in stride(from: bitsPer - 1, through: 0, by: -1) { bits.append(UInt8((x >> sh) & 1)) }
            }
            while bits.count % 4 != 0 { bits.insert(0, at: 0) }
            var h: [Character] = []
            for k in stride(from: 0, to: bits.count, by: 4) {
                let n = Int(bits[k]) << 3 | Int(bits[k + 1]) << 2 | Int(bits[k + 2]) << 1 | Int(bits[k + 3])
                h.append(Character(String(n, radix: 16)))
            }
            hex = String(h)
        }
        return Double("0x" + hex + "p0") ?? .infinity
    }

    /// Math.round: the nearest integer, ties toward +Infinity, -0 kept for [-0.5, 0).
    public static func round(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return x }
        let f = x.rounded(.down)
        let r = x - f >= 0.5 ? f + 1 : f
        return (r == 0 && (x < 0 || 1.0 / x < 0)) ? -0.0 : r
    }

    /// n.toLocaleString(pt ? "pt-BR" : "en-US", { maximumFractionDigits }), as ICU prints it (half-expand rounding).
    public static func locale(_ n: Double, pt: Bool, maxFractionDigits: Int = 3) -> String {
        if n.isNaN { return "NaN" }
        let neg = n < 0 || (n == 0 && 1.0 / n < 0)
        if n.isInfinite { return (neg ? "-" : "") + "\u{221E}" }
        let plain = shortest(abs(n)).roundedHalfUp(toScale: maxFractionDigits).stripped().plainString()
        let parts = plain.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        let frac = parts.count > 1 ? String(parts[1]) : ""
        let group: Character = pt ? "." : ","
        var grouped = ""
        let count = intPart.count
        for (i, ch) in intPart.enumerated() {
            if i > 0 && (count - i) % 3 == 0 { grouped.append(group) }
            grouped.append(ch)
        }
        let body = frac.isEmpty ? grouped : "\(grouped)\(pt ? "," : ".")\(frac)"
        return (neg ? "-" : "") + body
    }
}
