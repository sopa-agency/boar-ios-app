import Foundation

/// One-tap sets of `EngineTweaks`. Picking one sets every knob it names; changing any knob by hand afterwards makes it Custom.
/// The CPU build is the device's own choice and no preset touches it.
///
/// Boar's Path is Auto. The others lean one way from it: more threads is not more power on big.LITTLE-style chips, so
/// Run Boar Run keeps Auto's threads on the fast cores and spends the rest (bigger prompt batches, no time limit) instead.
public enum TweakPreset: String, Sendable, CaseIterable {
    /// Fastest answers: pinned to the fast cores, bigger prompt batches, weights locked in RAM, no time limit.
    case run
    /// Auto: what we measured best on real devices.
    case path
    /// Cooler and easier on the battery: 2 threads, a smaller context, no reasoning, a 5-minute limit.
    case forage
    /// For a hot device: 1 thread to generate, small prompt batches, a smaller context, no reasoning, a 5-minute limit.
    case cool

    public var emoji: String {
        switch self { case .run: "🐗"; case .path: "🌲"; case .forage: "🍄"; case .cool: "🧊" }
    }

    private var values: EngineTweaks {
        switch self {
        case .run: EngineTweaks(strictCpu: true, batch: 1024, microBatch: 512, loadMode: .mmapMlock, stageTimeoutSeconds: 0)
        case .path: EngineTweaks()
        case .forage: EngineTweaks(threads: 2, threadsBatch: 2, contextTokens: 2048, stageTimeoutSeconds: 300, thinking: false)
        case .cool: EngineTweaks(threads: 1, threadsBatch: 2, contextTokens: 2048, batch: 128, microBatch: 64, stageTimeoutSeconds: 300, thinking: false)
        }
    }

    /// This preset's tweaks, keeping `current`'s CPU build.
    public func applyTo(_ current: EngineTweaks) -> EngineTweaks {
        var t = values
        t.cpuBuild = current.cpuBuild
        return t
    }

    /// The string key stem: native.tweaks.preset.<key>.
    public var key: String { rawValue }

    /// The preset `tweaks` equal, or nil when they are Custom.
    public static func of(_ tweaks: EngineTweaks) -> TweakPreset? {
        allCases.first { $0.applyTo(tweaks) == tweaks }
    }
}
