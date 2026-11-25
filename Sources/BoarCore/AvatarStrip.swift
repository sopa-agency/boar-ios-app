import Foundation

/// The avatars Settings → Display & theme shows (android `AvatarStrip`, adam 23 Nov: Boar Avatars merged into it, "limit
/// it to some avatars and on the last box we open the page"): the plain BOAR first, the one being worn, then the latest
/// unlocked, `max` in all. nil stands for the plain BOAR. Pure.
public enum AvatarStrip {
    public static let max = 4

    /// `unlocked`: id to when it was unlocked; `known`: the ids that have art; `equipped`: the one worn, nil for BOAR.
    public static func pick(unlocked: [String: Int64], known: some Collection<String>, equipped: String?, max: Int = AvatarStrip.max) -> [String?] {
        let known = Set(known)
        let have = unlocked.filter { known.contains($0.key) }
        let worn = equipped.flatMap { have[$0] != nil ? $0 : nil }
        // Newest first; a tie keeps a stable order by id (Kotlin's sort keeps the map's order, which has no meaning here).
        let latest = have.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key).filter { $0 != worn }
        var strip: [String?] = [nil]
        if let worn { strip.append(worn) }
        strip += latest.map { Optional($0) }
        return Array(strip.prefix(Swift.max(max, 1)))
    }
}
