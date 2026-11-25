import Foundation

/// Which plugins start on (android `LabDefaults`, v2.0.0, adam's list of Nov 10 replacing rc2's "every lab starts off").
/// A plugin the user never switched keeps following this list; a switch the user flipped is kept as it is.
public enum LabDefaults {
    /// adam's default-on list, without the ALPHA labs still waiting for tests and a phone pass (`pendingAlpha`). Android's
    /// ids: `image` is Designer, `canvas` is Cards (not on iOS yet). Polyglot left the list on Nov 11 and is deprecated.
    public static let on: Set<String> = ["pulse", "image", "printer", "calc", "distance", "facts", "cohazard", "canvas"]

    /// On adam's list but ALPHA: they start off until each has tests and a device pass, or is raised to BETA, or adam
    /// writes an exception. Moving one into `on` is the whole change.
    public static let pendingAlpha: Set<String> = ["compass", "lunar", "guard"]

    /// Deprecated plugins (adam, 23 Nov: Polyglot): the code stays, but they are out of the Plugins list and off for
    /// everyone, a switch flipped before included: hidden but on, nobody could switch them off.
    public static let deprecated: Set<String> = ["polyglot"]

    /// iOS only: on Android's list but off here at first. Designer draws with Apple's Image Playground on iOS, which needs
    /// Apple Intelligence and iOS 18.4, so it starts off and the page says why. It still follows the user's own switch.
    public static let startsOffHere: Set<String> = ["image"]

    /// The plugins that start on in this app: Android's list less `startsOffHere`.
    public static var startsOn: Set<String> { on.subtracting(startsOffHere) }

    /// The plugins an update switched on: default-on plugins the user never switched (no stored choice), in `ids`' order.
    /// The one-time update note names them, so nobody finds a plugin on without being told.
    public static func turnedOnByUpdate(ids: [String], stored: (String) -> Bool?) -> [String] {
        ids.filter { startsOn.contains($0) && stored($0) == nil }
    }

    /// The user switched a plugin on themselves (a stored true), counted only while Plugins is on: a switch left on behind
    /// a master switch that's off shows nowhere, so it must not make the install Pro.
    public static func userChoseOn(labsOn: Bool, stored: [Bool?]) -> Bool { labsOn && stored.contains(true) }

    /// The switch a plugin shows: the user's own choice when there is one, else the default.
    public static func switchOf(_ id: String, stored: Bool?) -> Bool { stored ?? startsOn.contains(id) }

    /// Plugins' own places in Settings (the master switch, its storage limit) are Pro's. A plugin that is on keeps working
    /// in every profile: its rows under answers and its header icon are not gated.
    public static func managementShown(_ profile: UserProfile) -> Bool { profile == .pro }
}
