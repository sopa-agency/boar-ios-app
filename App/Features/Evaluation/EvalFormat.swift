import Foundation

/// How the Benchmark screen prints its numbers.
enum EvalFormat {
    /// "7/10"; "—" when nothing was counted.
    static func fraction(_ part: Int, _ whole: Int) -> String {
        whole > 0 ? "\(part)/\(whole)" : "—"
    }

    /// "9.8 tok/s".
    static func tokensPerSecond(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        return "\(rate.formatted(.number.precision(.fractionLength(1)))) tok/s"
    }

    static func bytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        return bytes.formatted(.byteCount(style: .memory))
    }

    /// "honesty-refusal" → "Honesty refusal".
    static func category(_ id: String) -> String {
        let words = id.replacing("-", with: " ").replacing("_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
