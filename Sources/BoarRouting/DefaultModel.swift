import Foundation

/// Memory fit of a model on this device (src/inference/memoryFit.ts FitVerdict); the raw value is the TypeScript string.
public enum FitVerdict: String, Sendable, Equatable {
    /// Whole file + buffers fit in available RAM.
    case resident
    /// File larger than available RAM, but the per-token hot set fits: MoE streams experts from storage.
    case streaming
    /// Buffers fit but the per-token hot set does not: every token re-reads weights from storage. Very slow.
    case thrashing
    /// KV + compute buffers alone exceed available RAM: loading would OOM.
    case insufficient

    public var value: String { rawValue }
    public static func of(_ value: String) -> FitVerdict? { FitVerdict(rawValue: value) }
}

/// Which answer model a device gets when the user has not picked one (port of src/routing/defaultModel.ts). The
/// "default" tier (Qwen3-4B, dense: every token reads all 2.5 GB) only when it can stay resident: more than 4.5 GB of
/// RAM, fit "resident" or "streaming", not measured under 6 tok/s; otherwise the "compact" tier. Other installed models
/// only win when neither tier can: the largest measured at 6 tok/s or more. Pure.
public enum DefaultModel {
    public static let compactOnlyMaxRamBytes: Int64 = 4_831_838_208 // 4.5 GiB

    /// At <= compactOnlyMaxRamBytes nothing bigger than the compact model is used unless the user confirmed it (the
    /// 4B on 3.8 GB was OOM-killed). The compact 1.5B is ~1.0 GB; this leaves margin for its peers.
    public static let lowRamMaxModelBytes: Double = 1.6e9

    /// Lower cap for the automatic pick only: on a 4 GB iPhone 13 ~1.5 GB models load but decode at ~0.35 tok/s, so
    /// the app never picks them by itself (a user's choice keeps lowRamMaxModelBytes).
    public static let autoPickMaxModelBytes: Double = 1.1e9

    /// Measured median decode speed under which a model is too slow to be the automatic default.
    public static let defaultMinTokPerSec: Double = 6.0

    /// Catalog tier: "default" or "compact"; nil for any other model.
    public enum Tier: String, Sendable, Equatable {
        case `default`, compact
        public var value: String { rawValue }
        public static func of(_ value: String) -> Tier? { Tier(rawValue: value) }
    }

    /// Answer-tier and size only (tooBigForLowRam / tooBigForAutoPick / isCompactModel inputs).
    public protocol Sized {
        var answerTier: Tier? { get }
        var sizeBytes: Int64? { get }
    }

    public struct Candidate: Sized, Sendable, Equatable {
        public var id: String
        public var answerTier: Tier?
        /// Memory fit on this device; nil = unknown.
        public var fit: FitVerdict?
        /// File size; nil = unknown.
        public var sizeBytes: Int64?
        /// Median measured tok/s on this device, only with enough samples; nil = not measured.
        public var tokPerSec: Double?

        public init(id: String, answerTier: Tier? = nil, fit: FitVerdict? = nil, sizeBytes: Int64? = nil, tokPerSec: Double? = nil) {
            self.id = id
            self.answerTier = answerTier
            self.fit = fit
            self.sizeBytes = sizeBytes
            self.tokPerSec = tokPerSec
        }
    }

    /// Why the picked model was picked: "default-tier", "compact-low-ram", "compact-does-not-fit",
    /// "compact-default-too-slow", "largest-fast", "smallest-fallback".
    public struct Choice: Sendable, Equatable {
        public var id: String
        public var reason: String
        public init(id: String, reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    /// [reason]: a pick reason, or why it was not picked: "low-ram", "wont-fit", "too-slow", "unmeasured", "outranked".
    public struct Ranked: Sendable, Equatable {
        public var id: String
        public var picked: Bool
        public var reason: String
        public init(id: String, picked: Bool, reason: String) {
            self.id = id
            self.picked = picked
            self.reason = reason
        }
    }

    /// [ranked]: every candidate once, the pick first, then the rest in order of preference.
    public struct Ranking: Sendable, Equatable {
        public var pick: Choice?
        public var ranked: [Ranked]
        public init(pick: Choice?, ranked: [Ranked]) {
            self.pick = pick
            self.ranked = ranked
        }
    }

    private static func lowRam(_ totalRamBytes: Int64) -> Bool { totalRamBytes > 0 && totalRamBytes <= compactOnlyMaxRamBytes }

    private static func aboveLowRamCap(_ m: some Sized, _ totalRamBytes: Int64, _ cap: Double) -> Bool {
        if !lowRam(totalRamBytes) || m.answerTier == .compact { return false }
        return m.answerTier == .default || (m.sizeBytes.map(Double.init) ?? .infinity) > cap
    }

    /// True when a model may not be used on this device, even as the saved pick, until the user confirms it.
    public static func tooBigForLowRam(_ m: some Sized, _ totalRamBytes: Int64) -> Bool {
        aboveLowRamCap(m, totalRamBytes, lowRamMaxModelBytes)
    }

    /// True when the app may not pick a model by itself on this device (the user can still choose it).
    public static func tooBigForAutoPick(_ m: some Sized, _ totalRamBytes: Int64) -> Bool {
        aboveLowRamCap(m, totalRamBytes, autoPickMaxModelBytes)
    }

    /// The compact tier, or an untiered model no bigger than it: too small to answer from memory unasked.
    public static func isCompactModel(_ m: some Sized) -> Bool {
        if let t = m.answerTier { return t == .compact }
        return (m.sizeBytes.map(Double.init) ?? .infinity) <= lowRamMaxModelBytes
    }

    private static func fits(_ c: Candidate) -> Bool { c.fit != .thrashing && c.fit != .insufficient }
    private static func tooSlow(_ c: Candidate) -> Bool { c.tokPerSec.map { $0 < defaultMinTokPerSec } ?? false }
    private static func size(_ c: Candidate) -> Double { c.sizeBytes.map(Double.init) ?? .infinity }

    /// A JavaScript sort comparator's number as an Int: NaN (Infinity - Infinity) means equal.
    private static func sign(_ d: Double) -> Int { d > 0 ? 1 : (d < 0 ? -1 : 0) }

    /// A stable sort (Kotlin `sortedWith` is stable; Swift's `sort` does not promise it) of indices.
    private static func stableSorted(_ items: [Candidate], by cmp: (Candidate, Candidate) -> Int) -> [Candidate] {
        items.enumerated().sorted { a, b in
            let c = cmp(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }

    private static func largestFirst(_ a: Candidate, _ b: Candidate) -> Int { sign(size(b) - size(a)) }

    /// The automatic answer model among the installed ones, and why each other one was not chosen. In order: the
    /// default tier when the phone has more than 4.5 GB, it fits and isn't measured under 6 tok/s; else the compact tier
    /// when it fits and isn't too slow; else the largest model that fits and was measured at 6 tok/s or more; else the
    /// smallest, fitting ones first. An unmeasured speed never disqualifies a tier model.
    public static func rankAnswerModels(_ candidates: [Candidate], totalRamBytes: Int64) -> Ranking {
        if candidates.isEmpty { return Ranking(pick: nil, ranked: []) }
        let lowRam = lowRam(totalRamBytes)
        let defIndex = candidates.firstIndex { $0.answerTier == .default }
        let compactIndex = candidates.firstIndex { $0.answerTier == .compact }
        let def = defIndex.map { candidates[$0] }
        let compact = compactIndex.map { candidates[$0] }
        let others = candidates.filter { $0.answerTier == nil }

        func notPicked(_ c: Candidate) -> String {
            if tooBigForAutoPick(c, totalRamBytes) { return "low-ram" }
            if !fits(c) { return "wont-fit" }
            if tooSlow(c) { return "too-slow" }
            if c.answerTier == nil && c.tokPerSec == nil { return "unmeasured" }
            return "outranked"
        }

        let pick: Choice?
        if let def, !lowRam, fits(def), !tooSlow(def) {
            pick = Choice(id: def.id, reason: "default-tier")
        } else if let compact, fits(compact), !tooSlow(compact) {
            let reason: String
            if def == nil || lowRam { reason = "compact-low-ram" }
            else if tooSlow(def!) && fits(def!) { reason = "compact-default-too-slow" }
            else { reason = "compact-does-not-fit" }
            pick = Choice(id: compact.id, reason: reason)
        } else {
            let allowed = { (c: Candidate) in !tooBigForAutoPick(c, totalRamBytes) }
            let fast = stableSorted(
                others.filter { allowed($0) && fits($0) && $0.tokPerSec != nil && !tooSlow($0) }, by: largestFirst
            ).first
            if let fast {
                pick = Choice(id: fast.id, reason: "largest-fast")
            } else {
                // On a low-RAM phone, nothing above the compact size: no pick rather than an OOM kill.
                let smallest = stableSorted(candidates.filter(allowed)) { a, b in
                    let f = (fits(b) ? 1 : 0) - (fits(a) ? 1 : 0)
                    return f != 0 ? f : sign(size(a) - size(b))
                }.first
                pick = smallest.map { Choice(id: $0.id, reason: "smallest-fallback") }
            }
        }

        // Preference order for the rest: default, compact, then the others largest first. Candidates are told apart by
        // position, not by id (Kotlin compares by identity).
        var order: [Int] = [defIndex, compactIndex].compactMap { $0 }
        let othersSorted = candidates.enumerated().filter { $0.element.answerTier == nil }.sorted { a, b in
            let c = largestFirst(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.offset)
        order += othersSorted
        for i in candidates.indices where !order.contains(i) { order.append(i) }
        _ = others
        var ranked: [Ranked] = []
        if let pick { ranked.append(Ranked(id: pick.id, picked: true, reason: pick.reason)) }
        for i in order where candidates[i].id != pick?.id {
            ranked.append(Ranked(id: candidates[i].id, picked: false, reason: notPicked(candidates[i])))
        }
        return Ranking(pick: pick, ranked: ranked)
    }

    /// The automatic answer model (see rankAnswerModels); nil when nothing is installed.
    public static func pickDefaultAnswerModel(_ candidates: [Candidate], totalRamBytes: Int64) -> Choice? {
        rankAnswerModels(candidates, totalRamBytes: totalRamBytes).pick
    }
}
