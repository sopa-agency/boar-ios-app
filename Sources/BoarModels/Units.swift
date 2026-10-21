import Foundation

/// File and storage sizes in decimal units, as Android shows them (port of `Units.kt`): "18.6 MB", "986 MB", "2.5 GB";
/// "18,6 MB" in Portuguese. RAM is not formatted here.
public enum Units {
    private static let kb = 1000.0
    private static let mb = 1000 * kb
    private static let gb = 1000 * mb

    /// HALF_UP matches Intl.NumberFormat (the TS app) and the Kotlin port; half-even would round 18.65 down.
    private static func number(_ value: Double, locale: Locale, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.roundingMode = .halfUp
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func scaled(_ bytes: Double, unit: Double, locale: Locale) -> String {
        let v = bytes / unit
        return number(v, locale: locale, digits: v >= 99.95 ? 0 : 1)
    }

    public static func formatBytes(_ bytes: Int64, locale: Locale = Locale(identifier: "en")) -> String {
        let b = Double(max(bytes, 0))
        if b >= 999.5 * mb { return "\(scaled(b, unit: gb, locale: locale)) GB" }
        if b >= 999.5 * kb { return "\(scaled(b, unit: mb, locale: locale)) MB" }
        // Kotlin roundToLong: ties toward positive infinity.
        let kilo = b > 0 ? max(1.0, (b / kb + 0.5).rounded(.down)) : 0.0
        return "\(number(kilo, locale: locale, digits: 0)) kB"
    }
}
