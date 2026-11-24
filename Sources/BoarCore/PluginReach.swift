import Foundation

/// How an off plugin stays reachable, and the safety plugin that can't go with one tap (android `PluginReach`, validator
/// Q-B1). Pure, so the decisions are tested as behaviour, not as source strings.
public enum PluginReach {
    /// Plugins that deliver a safety card. Since the Plugins list is in every profile (adam, 23 Nov) their switch is too:
    /// turning one off asks first, in every profile, from the list or its page; no profile rule any more.
    public static let safety: Set<String> = ["cohazard"]

    /// Turning a safety plugin off asks first ("Turn off the carbon monoxide safety card?"), from its page or the list.
    public static func asksBeforeOff(_ id: String, turningOn: Bool) -> Bool { !turningOn && safety.contains(id) }

    /// Whether a switch may take effect: a safety plugin goes off only once the question was answered (`confirmed`).
    /// `Labs.setEnabled` applies it, so a switch that forgets to ask can't turn Cohazard off.
    public static func allowsSet(_ id: String, on: Bool, confirmed: Bool) -> Bool { !asksBeforeOff(id, turningOn: on) || confirmed }

    /// The plugins switched off from their pages after a switch: on leaves the set, off from a page joins it.
    public static func offFromPageAfter(_ set: Set<String>, id: String, on: Bool, fromPage: Bool) -> Set<String> {
        if on { return set.subtracting([id]) }
        return fromPage ? set.union([id]) : set
    }

    /// The header sheet's "Off" section, in `ids`' order: each off plugin the user switched off from its page, and any
    /// safety plugin that is off, so either is one tap from its page and its switch.
    public static func offListed(_ ids: [String], enabled: (String) -> Bool, offFromPage: Set<String>) -> [String] {
        ids.filter { !enabled($0) && (offFromPage.contains($0) || safety.contains($0)) }
    }

    /// The header's plugin icon: while any plugin is on, or one is listed as off.
    public static func headerIconShown(activeIds: [String], offListed: [String]) -> Bool { !activeIds.isEmpty || !offListed.isEmpty }
}
