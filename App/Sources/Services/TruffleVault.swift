import BoarCore
import Foundation
import Observation
import StoreKit
import os

/// Boar Avatars on this device (android app/appearance `TruffleVault.kt`; the code says vault and truffle): counts what
/// the vault's rules need (BoarCore `Vault`) as the app is used, stores it in the settings under `truffleVault`, and keeps
/// each newly unlocked avatar for a "New avatar unlocked" message. Everything is counted here and never leaves the device;
/// nothing runs in the background, only when the app opens and when something happens in it. The equipped avatar takes
/// the mascot's place while Boarverse is on (`equipped`).
@MainActor
@Observable
final class TruffleVault {
    /// Boarverse's switch (android SharedPreferences "vault" → `experimental.on`), off by default.
    nonisolated static let enabledKey = "vault.experimental.on"
    private static let log = BoarLog.logger("vault")

    private(set) var state: Vault.State
    /// Avatars unlocked while Boarverse is on, oldest first, each until its message has been shown (`shown`). The
    /// avatar every install starts with isn't news.
    private(set) var fresh: [String] = []
    /// The avatar chosen in Settings (android `icon`, stored as `iconId`); nil for BOAR's own.
    private(set) var icon: String?
    /// Boarverse: off, BOAR's own avatar and no messages. Avatars are still counted, so turning it on later finds them
    /// waiting. Only builds that show Labs can turn it on, like Android's EXPERIMENTAL_FEATURES.
    private(set) var enabled: Bool

    @ObservationIgnored private let settings: AppSettings
    /// The chat's ONLINE badge's monitor (AppModel's): offline answers and no-network days.
    @ObservationIgnored var connectivity: Connectivity?
    /// The App Store's word on this build, asked once per process.
    @ObservationIgnored private var askedStore = false

    /// Nonisolated: `BoarServices` opens off the main actor. It sets the observed values' storage directly (the
    /// Observation macro's `_state`, `_enabled`), as the properties themselves belong to the main actor.
    nonisolated init(settings: AppSettings) {
        self.settings = settings
        #if DEBUG
        // -uiVault <json>: the stored state for captures and UI tests (junk seeds an empty vault).
        if let seed = DebugLaunch.vault { settings.truffleVault = Vault.toJson(Vault.fromJson(seed)) }
        #endif
        let state = Vault.fromJson(settings.truffleVault)
        _state = state
        var on = AppPaths.defaults.bool(forKey: Self.enabledKey)
        #if DEBUG
        // -uiBoarverse YES: on for captures and UI tests, without storing it.
        if DebugLaunch.boarverse { on = true }
        #endif
        _enabled = LabsBuild.experimental && on
        var icon = settings.iconId
        #if DEBUG
        if let debug = DebugLaunch.icon { icon = debug }
        #endif
        // Only an unlocked avatar, as `equip` checks: a damaged state or -uiIcon of a locked one shows BOAR's own.
        _icon = icon.flatMap { state.unlocked[$0] != nil ? $0 : nil }
    }

    /// The avatar in the mascot's place: the equipped one while Boarverse is on, else nil (BOAR's own).
    var equipped: String? { enabled ? icon : nil }

    func setEnabled(_ on: Bool) {
        enabled = on && LabsBuild.experimental
        AppPaths.defaults.set(on, forKey: Self.enabledKey)
        if !enabled { fresh = [] }
    }

    /// Erase All Data (Android's "clear app data" empties the vault's preferences too): every count, unlocked avatar
    /// and the Boarverse switch. The state in memory goes with them, or the next `record` would write it all back.
    func erase() {
        state = Vault.State()
        fresh = []
        enabled = false
        askedStore = false
        settings.truffleVault = nil
        AppPaths.defaults.removeObject(forKey: Self.enabledKey)
        equip(nil)
    }

    /// Equips an unlocked avatar, or BOAR's own for nil (or an avatar that isn't unlocked). The mascot changes at once.
    func equip(_ id: String?) {
        let target = id.flatMap { unlocked($0) ? $0 : nil }
        settings.iconId = target
        icon = target
    }

    func unlocked(_ id: String) -> Bool { state.unlocked[id] != nil }

    /// The message about `id` was shown (or Boarverse went off): the next one, if any, comes up.
    func shown(_ id: String) {
        fresh.removeAll { $0 == id }
    }

    /// Changes the facts and unlocks what they now earn. Saved only when something changed.
    func record(_ change: (inout Vault.Facts) -> Void) {
        let before = state
        var facts = before.facts
        change(&facts)
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        let (after, unearthed) = Vault.apply(before, facts: facts, today: .today(), now: now)
        guard after != before else { return }
        state = after
        settings.truffleVault = Vault.toJson(after)
        if enabled { fresh += Vault.Counting.announced(unearthed) }
    }

    /// On launch, when the app comes back, and after leaving a screen that changes what's installed: the day, a day with
    /// no network at all (iOS has no airplane-mode API), the lock, and what the app's files say. Every iPhone and Mac
    /// counts as de-Googled (decided 2026-11-11), so `stealth` unlocks at the first open like `tactical`.
    func onOpen(pinOn: Bool, packs: Int, hfModels: Int) async {
        let noNetwork = await connectivity?.settledStatus() == .unsatisfied
        record {
            $0 = Vault.Counting.opened($0, today: .today(), noNetwork: noNetwork, pinOn: pinOn, packs: packs, hfModels: hfModels,
                                       sourceBuild: Self.debugBuild, degoogled: true)
        }
        checkStoreEnvironment()
    }

    /// After an answer that wrote something; `tokPerSec` only when the model generated it (not an instant Labs answer).
    func answered(sourced: Bool, deep: Bool, portuguese: Bool, tokPerSec: Double?, newChat: Bool) {
        // Offline as the chat's ONLINE badge sees it: no satisfied path.
        let offline = connectivity?.online != true
        let night = Vault.isNight(hour: Calendar.current.component(.hour, from: Date()))
        record {
            $0 = Vault.Counting.answered($0, sourced: sourced, deep: deep, portuguese: portuguese, tokPerSec: tokPerSec,
                                         newChat: newChat, offline: offline, night: night)
        }
    }

    /// A Daily Quiz question answered; `epochDay` is the quiz's day.
    func quizAnswered(right: Bool, epochDay: Int64) {
        record { $0 = Vault.Counting.quizAnswered($0, right: right, day: Vault.Day(epochDay: epochDay)) }
    }

    // MARK: source build

    /// A debug build was built from source by whoever runs it.
    private static var debugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Not from the App Store or TestFlight: the App Store says the build came from Xcode. Asked once, in the background;
    /// an error (offline, no receipt) counts nothing.
    private func checkStoreEnvironment() {
        guard !askedStore, !state.facts.sourceBuild else { return }
        askedStore = true
        #if os(macOS)
        // A Mac app with no receipt didn't come from the App Store or TestFlight, and asking may open the App Store's
        // sign-in. (The receipt's path, as `appStoreReceiptURL` is deprecated.)
        let receipt = Bundle.main.bundleURL.appending(path: "Contents/_MASReceipt/receipt")
        guard FileManager.default.fileExists(atPath: receipt.path(percentEncoded: false)) else { return }
        #endif
        Task { [weak self] in
            guard let result = try? await AppTransaction.shared else { return }
            let transaction = switch result {
            case .verified(let t), .unverified(let t, _): t
            }
            guard transaction.environment == .xcode else { return }
            Self.log.info("built from source (Xcode environment)")
            self?.record { $0.sourceBuild = true }
        }
    }
}
