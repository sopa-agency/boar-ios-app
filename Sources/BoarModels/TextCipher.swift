import BoarCore
import CommonCrypto
import CryptoKit
import Foundation
import Security

/// How chat text is stored: as is, or sealed with the PIN's data key (port of `TextCipher.kt`).
public protocol TextCipher: Sendable {
    func seal(_ plain: String) -> String
    func open(_ stored: String) -> String
}

/// No PIN: stored as written. Opening still reads text sealed earlier as-is (it can't, so it shows a placeholder).
public struct PlainCipher: TextCipher {
    public init() {}
    public func seal(_ plain: String) -> String { plain }
    public func open(_ stored: String) -> String { AesTextCipher.isSealed(stored) ? AesTextCipher.locked : stored }
}

/// AES-256-GCM with a random 12-byte nonce per value, stored as "enc1:<base64(nonce|ciphertext|tag)>", byte for byte the
/// layout the Android app writes (CryptoKit's `SealedBox.combined`). Text written before the PIN was set (no prefix) opens
/// as is, so turning the PIN on can re-seal rows one at a time.
public struct AesTextCipher: TextCipher {
    public static let prefix = "enc1:"
    /// What a sealed value shows when it can't be opened (wrong key, or no PIN entered).
    public static let locked = "🔒"

    private let key: SymmetricKey

    /// `key` is the 32-byte data key (`PinKeys.newDataKey()`).
    public init(key: Data) { self.key = SymmetricKey(data: key) }

    public static func isSealed(_ s: String?) -> Bool { s?.hasPrefix(prefix) ?? false }

    public func seal(_ plain: String) -> String {
        do {
            let box = try AES.GCM.seal(Data(plain.utf8), using: key, nonce: AES.GCM.Nonce())
            return Self.prefix + box.combined!.base64EncodedString()
        } catch {
            // Sealing a string with a valid key cannot fail; never fall back to writing the text in the clear.
            BoarLog.logger("security").fault("seal failed: \(error.localizedDescription, privacy: .public)")
            return Self.locked
        }
    }

    public func open(_ stored: String) -> String {
        guard Self.isSealed(stored) else { return stored }
        guard let combined = Data(base64Encoded: String(stored.dropFirst(Self.prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key),
              let text = String(data: plain, encoding: .utf8) else { return Self.locked }
        return text
    }
}

/// The PIN's keys. A random data key encrypts the chats; it is stored sealed with a key derived from the PIN
/// (PBKDF2-HMAC-SHA256), so the PIN never needs to be stored and changing it only re-seals the data key. The app adds a
/// second seal with a device-bound Keychain key (`DeviceKeySeal`), so a copy of the files can't be brute-forced off the phone.
public enum PinKeys {
    /// Mirrored by `AppSettings.defaultPinIterations`.
    public static let iterations = 210_000

    public static func newDataKey() -> Data { randomBytes(32) }
    public static func newSalt() -> Data { randomBytes(16) }

    private static func randomBytes(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }

    /// PBKDF2WithHmacSHA256, 256-bit output, password as UTF-8 (PINs are digits).
    public static func derive(pin: String, salt: Data, iterations: Int = PinKeys.iterations) -> Data {
        let password = Array(pin.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) }, password.count,
                    s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                    &out, out.count)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed (\(status))")
        return Data(out)
    }

    /// nonce(12) | ciphertext | tag(16).
    public static func wrap(_ dataKey: Data, kek: Data) -> Data {
        // A random nonce and a 32-byte key cannot fail to seal.
        try! AES.GCM.seal(dataKey, using: SymmetricKey(data: kek), nonce: AES.GCM.Nonce()).combined!
    }

    /// The data key, or nil when `kek` is wrong (a wrong PIN).
    public static func unwrap(_ wrapped: Data, kek: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: wrapped), let plain = try? AES.GCM.open(box, using: SymmetricKey(data: kek)) else { return nil }
        return plain
    }

    /// 4 to 8 digits.
    public static func valid(_ pin: String) -> Bool {
        let scalars = pin.unicodeScalars
        return (4...8).contains(scalars.count) && scalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    /// Seconds to wait before the next try after `failures` wrong PINs: none for the first 4, then 30 s doubling, at most 1 h.
    public static func backoffSeconds(_ failures: Int) -> Int64 {
        failures < 5 ? 0 : min(3600, Int64(30) << Int64(min(failures - 5, 7)))
    }
}

// MARK: - Device-bound key (the Keychain replaces the Android Keystore key)

/// Where the app keeps a small secret that must stay on this device: the Keychain in the app, memory in tests.
public protocol SecretStore: Sendable {
    func load(account: String) throws -> Data?
    func save(_ secret: Data, account: String) throws
    func delete(account: String) throws
}

public struct SecretStoreError: Error, CustomStringConvertible, Sendable {
    public let status: Int32
    public var description: String { "Keychain error \(status)" }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}

    public func load(account: String) throws -> Data? { lock.withLock { items[account] } }
    public func save(_ secret: Data, account: String) throws { lock.withLock { items[account] = secret } }
    public func delete(account: String) throws { lock.withLock { items[account] = nil } }
}

/// Generic-password Keychain items, readable only while the device is unlocked and never synced or backed up to another
/// device (`WhenUnlockedThisDeviceOnly`).
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "team.sopa.boar") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load(account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError(status: status) }
        return item as? Data
    }

    public func save(_ secret: Data, account: String) throws {
        var q = query(account)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError(status: update) }
        q[kSecValueData as String] = secret
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = SecItemAdd(q as CFDictionary, nil)
        guard add == errSecSuccess else { throw SecretStoreError(status: add) }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError(status: status) }
    }
}

/// The second seal of the PIN's data key (Android: `PinLock.keystoreSeal/keystoreOpen`): a random 256-bit key created on
/// first use and kept in a `SecretStore`, so the wrapped key stored in settings is useless off this device.
public struct DeviceKeySeal: Sendable {
    private let store: SecretStore
    private let account: String

    /// `account` is the Keychain item's name (the Android alias `boar-pin-v1`); tests use their own.
    public init(store: SecretStore, account: String = "boar-pin-v1") {
        self.store = store
        self.account = account
    }

    private func deviceKey() throws -> Data {
        if let k = try store.load(account: account) { return k }
        let k = PinKeys.newDataKey()
        try store.save(k, account: account)
        return k
    }

    public func seal(_ bytes: Data) throws -> Data { PinKeys.wrap(bytes, kek: try deviceKey()) }

    /// nil when the device key is gone or this wasn't sealed with it.
    public func open(_ sealed: Data) throws -> Data? { PinKeys.unwrap(sealed, kek: try deviceKey()) }

    /// Forgets the device key (turning the PIN off).
    public func destroy() throws { try store.delete(account: account) }
}
