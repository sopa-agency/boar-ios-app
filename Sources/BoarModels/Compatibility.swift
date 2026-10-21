import Foundation

/// Rough RAM-fit estimate for a GGUF model on this device (port of `Compatibility.kt`, itself src/models/compatibility.ts),
/// shared by the catalog UI and the routing profiles. A heuristic, not a measurement: a quantized model's resident working
/// set tracks its file size plus context/KV overhead, approximated as 1.15x.
public enum Compatibility: String, Sendable, CaseIterable {
    case green, yellow, red, unknown

    /// The Kotlin enum's `value` string.
    public var value: String { rawValue }

    public static func compute(sizeBytes: Int64, deviceRamBytes: Int64) -> Compatibility {
        if deviceRamBytes <= 0 { return .unknown }
        let estimatedRamBytes = Double(sizeBytes) * 1.15
        if estimatedRamBytes <= Double(deviceRamBytes) * 0.65 { return .green }
        if estimatedRamBytes <= Double(deviceRamBytes) * 0.9 { return .yellow }
        return .red
    }
}
