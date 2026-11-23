import Synchronization

/// When the chat header shows the connection as a word ("ONLINE" / "OFFLINE") before it folds back to the dot (android
/// `chat/ConnectionPill.kt`, adam Nov 11): once when BOAR opens, and again on a real change, read after the connection has
/// held for `settleMs` so a flapping signal doesn't flash it. Kept for the process, so coming back to the chat or
/// redrawing it doesn't repeat it.
public enum ConnectionPill {
    public static let showMs = 2_000
    /// After a tap on the dot: long enough to read it and tap the word for the details (adam, Nov 13).
    public static let tapShowMs = 4_000
    public static let settleMs = 1_500

    private static let last = Mutex<Bool?>(nil)

    /// The state the word last showed this process; nil: not shown yet (android `lastShown`).
    public static var lastShown: Bool? {
        get { last.withLock { $0 } }
        set { last.withLock { $0 = newValue } }
    }

    /// Whether the settled state `online` is news: the first one this process, or different from the last shown.
    public static func shouldShow(online: Bool, last: Bool?) -> Bool { last == nil || last != online }

    public static func shouldShow(online: Bool) -> Bool { shouldShow(online: online, last: lastShown) }
}
