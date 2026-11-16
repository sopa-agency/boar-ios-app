import Foundation

/// Why BOAR's last process ended, as far as iOS lets an app know, for LoadGuard (android `ExitReason.kt`, issue #89): a
/// model marker left by a process that was updated, reinstalled or swiped away isn't a load that ran out of memory.
/// Android reads the system's exit record; iOS keeps none per launch, so BOAR writes down what tells:
/// - the install it ran from: iOS gives every install and update a new bundle folder, so a different one means the app
///   was replaced (Android REASON_PACKAGE_UPDATED);
/// - when it went to the background: a process that ended there after the load began was swiped away or reclaimed by
///   iOS as a background app (Android REASON_USER_REQUESTED);
/// - when it stopped being active: the app switcher, where a swipe ends BOAR, leaves it inactive, not in the background.
///   Inactive is also a Face ID prompt or Control Center over BOAR, so this one excuses a leftover marker once: a second
///   one within `inactiveRepeatMs` counts, and a model too big for the phone can't close BOAR on every start.
/// A model too big for the phone gets BOAR killed while it is active, which still counts. Losing a kill that happened off
/// screen costs one more load at most, and that one runs on screen. A kill while active (jetsam, or a debugger's stop)
/// can't be told apart, as Android can't without a record.
public final class ExitRecord: @unchecked Sendable {
    static let installKey = "boar.exit.install"
    static let backgroundKey = "boar.exit.backgroundAt"
    static let inactiveKey = "boar.exit.inactiveAt"
    static let inactiveExcusedKey = "boar.exit.inactiveExcusedAt"
    /// An inactive exit excused less than this before the next marker doesn't excuse it.
    public static let inactiveRepeatMs: Int64 = 10 * 60 * 1000

    private let defaults: UserDefaults
    private let install: String
    private let now: @Sendable () -> Int64
    /// The last process's facts, read before this one writes its own.
    private let previousInstall: String?
    private let previousBackgroundAt: Int64?
    private let previousInactiveAt: Int64?

    /// `install`: where this install lives (`Bundle.main.bundlePath`). Reads the last process's record, then starts this one's.
    public init(defaults: UserDefaults, install: String,
                now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.defaults = defaults
        self.install = install
        self.now = now
        previousInstall = defaults.string(forKey: Self.installKey)
        previousBackgroundAt = Self.ms(defaults, Self.backgroundKey)
        previousInactiveAt = Self.ms(defaults, Self.inactiveKey)
        defaults.set(install, forKey: Self.installKey)
        defaults.removeObject(forKey: Self.backgroundKey)
        defaults.removeObject(forKey: Self.inactiveKey)
    }

    /// True only when the last process is known to have ended for a reason that isn't a load kill, for a marker written
    /// at `since` (ms); false when unsure. Called once per leftover marker (LoadGuard.ensureChecked).
    public func notALoadKill(since: Int64) -> Bool {
        if let previousInstall, previousInstall != install { return true }
        if let left = previousBackgroundAt, left >= since { return true }
        guard let inactive = previousInactiveAt, inactive >= since else { return false }
        if let excused = Self.ms(defaults, Self.inactiveExcusedKey), since - excused < Self.inactiveRepeatMs {
            defaults.removeObject(forKey: Self.inactiveExcusedKey)
            return false
        }
        defaults.set(NSNumber(value: since), forKey: Self.inactiveExcusedKey)
        return true
    }

    /// BOAR stopped being active (the app switcher, a system prompt, Control Center).
    public func resignedActive() { defaults.set(NSNumber(value: now()), forKey: Self.inactiveKey) }

    /// BOAR left the screen.
    public func enteredBackground() { defaults.set(NSNumber(value: now()), forKey: Self.backgroundKey) }

    /// BOAR is active again: a kill from now on counts.
    public func becameActive() {
        defaults.removeObject(forKey: Self.backgroundKey)
        defaults.removeObject(forKey: Self.inactiveKey)
    }

    private static func ms(_ d: UserDefaults, _ key: String) -> Int64? { (d.object(forKey: key) as? NSNumber)?.int64Value }
}
