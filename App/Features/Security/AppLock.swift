import BoarAnswer
import BoarCore
import BoarModels
import Foundation
import LocalAuthentication
import Observation
import Security
import os

/// The app lock: Face ID, Touch ID or the device passcode opens BOAR (iOS counterpart of android `PinLock`).
///
/// Chats are sealed with a random 256-bit data key (AES-GCM, `AesTextCipher`, the Android format). The key lives only in
/// the Keychain, readable on this device while a passcode is set and only after the owner authenticates (`.userPresence`
/// access control), so a backup or a copied database can't be opened elsewhere. Until the lock is opened the chats
/// stay sealed and read as "🔒". There is no PIN to forget: the device passcode is the fallback.
@MainActor
@Observable
final class AppLock {
    /// Settings flag (not a Kotlin key; Android keeps `pinWrapped` instead).
    static let settingsKey = "iosAppLock"
    private static let log = BoarLog.logger("security")

    private(set) var enabled: Bool
    /// The lock screen covers the app.
    private(set) var locked: Bool
    private(set) var busy = false
    var error: String?
    /// The key is gone (the device passcode was removed): sealed chats can't be opened any more.
    private(set) var keyLost = false

    @ObservationIgnored private let services: BoarServices
    @ObservationIgnored private let keychain = ChatKeyStore()
    /// After a successful unlock: the sidebar reloads its titles, a pending Siri question runs.
    @ObservationIgnored var onUnlocked: (@MainActor () -> Void)?
    /// Before an erase: stops any answer and waits for it, so nothing writes a chat while they're deleted.
    @ObservationIgnored var stopAnswers: (@MainActor () async -> Void)?
    /// After an erase: the chat on screen starts over, the Knowledge list reloads.
    @ObservationIgnored var onErased: (@MainActor () -> Void)?
    /// The data key was read in this process (re-locking after the background keeps it in memory).
    @ObservationIgnored private var keyLoaded = false

    init(services: BoarServices) {
        self.services = services
        let on = services.settings.jsonValue(forKey: Self.settingsKey)?.boolValue ?? false
        enabled = on
        locked = on
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode", as this \(Platform.deviceNoun) unlocks.
    var methodName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch c.biometryType {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        default: String(localized: "Passcode")
        }
    }

    var methodSymbol: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch c.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock"
        }
    }

    /// A passcode is set (the Keychain item and the fallback need one).
    var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// The app went to the background: the lock screen covers it when it comes back.
    func lockOnBackground() {
        if enabled { locked = true }
    }

    func unlock() async {
        guard enabled else { locked = false; return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let context = try await authenticate(String(localized: "Unlock your saved chats"))
            if !keyLoaded {
                guard let key = try keychain.load(context: context) else {
                    keyLost = true
                    return
                }
                services.chats.cipher = AesTextCipher(key: key)
                keyLoaded = true
            }
            locked = false
            error = nil
            onUnlocked?()
        } catch {
            self.error = Self.message(error)
        }
    }

    /// The Settings toggle: a write turns the lock on or off (Face ID / passcode first); `enabled` follows when done.
    var enabledChoice: Bool {
        get { enabled }
        set { Task { if newValue { await enable() } else { await disable() } } }
    }

    /// Turns the lock on: a new data key in the Keychain, then every stored chat sealed with it (one transaction).
    func enable() async {
        guard !enabled, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await authenticate(String(localized: "Turn on the lock for your chats"))
            let key = PinKeys.newDataKey()
            // Saved before any chat is sealed with it, so a failure can't leave chats sealed with a lost key.
            try keychain.save(key)
            let cipher = AesTextCipher(key: key)
            do {
                try await services.background { try $0.chats.reseal(from: PlainCipher(), to: cipher) }
            } catch {
                keychain.delete()
                throw error
            }
            services.chats.cipher = cipher
            keyLoaded = true
            setFlag(true)
            error = nil
        } catch {
            self.error = Self.message(error)
        }
    }

    /// Turns the lock off: the chats go back to plain text and the key is deleted.
    func disable() async {
        guard enabled, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let context = try await authenticate(String(localized: "Turn off the lock for your chats"))
            guard let key = try keychain.load(context: context) else {
                keyLost = true
                return
            }
            let sealed = AesTextCipher(key: key)
            try await services.background { try $0.chats.reseal(from: sealed, to: PlainCipher()) }
            services.chats.cipher = PlainCipher()
            keychain.delete()
            keyLoaded = false
            setFlag(false)
            error = nil
        } catch {
            self.error = Self.message(error)
        }
    }

    /// The key is lost: the sealed chats can't be read, so they're erased with it and the lock turns off. Personal Files
    /// go too (android Forgot PIN, 2e0dafc0): only the chats are sealed, and the files would stay readable to whoever
    /// opened BOAR without the owner's passcode. Models and knowledge packs stay. A failed erase keeps the lock on.
    func eraseChatsAndReset() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await stopAnswers?()
        do {
            try await services.background { s in
                try s.knowledgeBase.eraseAllCollections()
                try s.chats.clearAll()
            }
        } catch {
            Self.log.error("erase failed: \(String(describing: error), privacy: .public)")
            self.error = String(localized: "Couldn't erase everything. The lock stays on: try again.")
            return
        }
        Labs.shared.eraseUserData()
        services.chats.cipher = PlainCipher()
        keychain.delete()
        keyLoaded = false
        keyLost = false
        error = nil
        setFlag(false)
        onErased?()
        onUnlocked?()
    }

    private func setFlag(_ on: Bool) {
        services.settings.setJSONValue(on ? .bool(true) : nil, forKey: Self.settingsKey)
        enabled = on
        locked = false
    }

    private func authenticate(_ reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
                if ok { c.resume() } else { c.resume(throwing: error ?? LAError(.authenticationFailed)) }
            }
        }
        return context
    }

    private static func message(_ error: Error) -> String? {
        if let la = error as? LAError {
            switch la.code {
            case .userCancel, .systemCancel, .appCancel: return nil
            case .passcodeNotSet: return String(localized: "Set a passcode for this \(Platform.deviceNoun) in Settings to use the lock.")
            case .biometryLockout: return String(localized: "Too many failed attempts. Unlock with your passcode.")
            default: break
            }
        }
        log.error("lock: \(String(describing: error), privacy: .public)")
        return error.localizedDescription
    }
}

/// The chats' data key in the Keychain: this device only, while a passcode is set, read after user presence.
struct ChatKeyStore: Sendable {
    static let service = "team.sopa.boar"
    static let account = "boar-chat-key-v1"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { String(localized: "Keychain error \(status)") }
    }

    private var base: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
    }

    func save(_ key: Data) throws {
        delete()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
            throw error?.takeRetainedValue() ?? Failure(status: errSecParam)
        }
        var query = base
        query[kSecValueData] = key
        query[kSecAttrAccessControl] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// The key, read with an already authenticated context (no second prompt); nil when it isn't there.
    func load(context: LAContext) throws -> Data? {
        var query = base
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = context
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return out as? Data
    }

    func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
