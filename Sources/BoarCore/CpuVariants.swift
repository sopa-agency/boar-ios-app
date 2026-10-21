import Foundation

/// The ggml CPU build choice. Android ships one build per instruction set; the iOS llama.cpp XCFramework is one build, so
/// `EngineTweaks.cpuBuild` stays "auto" there and no variant is loaded. The tables and rules are kept as they are (pure,
/// tested) so a saved setting round-trips and a future per-ISA build can use them.
public enum CpuVariants {
    public struct Variant: Sendable, Equatable {
        public var name: String
        public var label: String
        /// `/proc/cpuinfo`-style feature flags this build needs.
        public var needs: Set<String>
        public init(name: String, label: String, needs: Set<String>) { self.name = name; self.label = label; self.needs = needs }
    }

    /// Lowest to highest, as ggml declares them.
    public static let all: [Variant] = [
        Variant(name: "android_armv8.0_1", label: "armv8.0", needs: []),
        Variant(name: "android_armv8.2_1", label: "armv8.2 · dotprod", needs: ["asimddp"]),
        Variant(name: "android_armv8.2_2", label: "armv8.2 · dotprod, fp16", needs: ["asimddp", "asimdhp"]),
        Variant(name: "android_armv8.6_1", label: "armv8.6 · dotprod, fp16, i8mm", needs: ["asimddp", "asimdhp", "i8mm"]),
        Variant(name: "android_armv9.0_1", label: "armv9.0 · i8mm, SVE2", needs: ["asimddp", "asimdhp", "i8mm", "sve2"]),
        Variant(name: "android_armv9.2_1", label: "armv9.2 · i8mm, SVE, SME", needs: ["asimddp", "asimdhp", "i8mm", "sve", "sme"]),
        Variant(name: "android_armv9.2_2", label: "armv9.2 · i8mm, SVE2, SME", needs: ["asimddp", "asimdhp", "i8mm", "sve", "sve2", "sme"]),
    ]

    /// The user's setting: "auto" (default), "best" (ggml's own pick) or a variant name.
    public static let autoSetting = "auto"
    public static let bestSetting = "best"

    /// Feature flags from a `/proc/cpuinfo` text: the first "Features" line.
    public static func readFeatures(cpuinfo: String) -> Set<String> {
        for line in cpuinfo.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("Features") {
            guard let colon = line.firstIndex(of: ":") else { return [] }
            return Set(line[line.index(after: colon)...].split(whereSeparator: { $0.isWhitespace }).map(String.init))
        }
        return []
    }

    /// Feature flags of this device, under the Linux names the table above uses (Darwin `hw.optional.arm.*` sysctls).
    public static func readFeatures() -> Set<String> {
        let map: [(String, String)] = [
            ("hw.optional.arm.FEAT_DotProd", "asimddp"), ("hw.optional.arm.FEAT_FP16", "asimdhp"),
            ("hw.optional.arm.FEAT_I8MM", "i8mm"), ("hw.optional.arm.FEAT_SVE", "sve"),
            ("hw.optional.arm.FEAT_SVE2", "sve2"), ("hw.optional.arm.FEAT_SME", "sme"),
        ]
        return Set(map.compactMap { sysctlInt($0.0) == 1 ? $0.1 : nil })
    }

    /// The builds this CPU can run, lowest first: the only ones settings offer.
    public static func supported(_ features: Set<String>) -> [Variant] { all.filter { features.isSuperset(of: $0.needs) } }

    /// What Auto loads: a variant name, or nil for ggml's own pick.
    public static func auto(_ features: Set<String>) -> String? {
        features.contains("i8mm") && !features.contains("sme") && supported(features).contains(where: { $0.name == "android_armv8.6_1" })
            ? "android_armv8.6_1" : nil
    }

    /// The library to load for a setting; nil means ggml's own pick. A named variant the CPU can't run falls back to Auto.
    public static func resolve(_ setting: String?, _ features: Set<String>) -> String? {
        switch setting ?? autoSetting {
        case bestSetting: return nil
        case autoSetting: return auto(features)
        case let name: return supported(features).contains(where: { $0.name == name }) ? name : auto(features)
        }
    }
}
