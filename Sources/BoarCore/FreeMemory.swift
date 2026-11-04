import Foundation

/// Settings → "Free memory when I leave BOAR" (port of FreeMemory.kt): a while after BOAR leaves the screen, the model
/// (1-5 GB) is unloaded, so the system doesn't end BOAR to get its memory back. The next answer loads it again. The
/// rules are here, apart from the app, so they're tested.
public enum FreeMemory {
    /// Auto's delay, in seconds: none. A suspended app can't run a timer, and iOS ends a background app that holds this
    /// much memory, so the model goes at once. An answer still being written finishes first.
    public static let autoSeconds = 0
    /// Advanced → "Free memory after": 5 min, 30 min (Auto is nil and immediate; a saved 0 works the same).
    public static let choicesMinutes = [5, 30]
    /// How often a release that found an answer running looks again.
    public static let busyPollMs = 500

    /// The delay for the user's choice in minutes: Auto (nil) is `autoSeconds`; a negative value counts as Immediately.
    public static func delayMs(_ minutes: Int?) -> Int {
        guard let minutes else { return autoSeconds * 1_000 }
        return max(minutes, 0) * 60_000
    }

    public enum Decision: Sendable, Equatable { case unload, wait, skip }

    /// When the delay is over: nothing to do if the setting is off, BOAR is back on screen or no model is loaded; an
    /// answer, a chat title or summary, or a load still running is waited for; otherwise the model goes.
    public static func decide(enabled: Bool, inForeground: Bool, loaded: Bool, busy: Bool) -> Decision {
        if !enabled || inForeground { return .skip }
        // Busy first: a model still loading isn't "loaded" yet, and skipping would leave it in memory once it is.
        if busy { return .wait }
        return loaded ? .unload : .skip
    }
}
