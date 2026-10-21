import BoarCore
import BoarRemote
import Foundation
import Security

/// Where the "Mac on your network" backend lives: the address in settings, the optional API key in the Keychain.
enum RemoteConfig {
    private static let addressKey = "iosRemoteServerAddress"
    private static let service = "team.sopa.boar.remote"

    static func address(_ settings: AppSettings) -> String {
        settings.jsonValue(forKey: addressKey)?.stringValue ?? ""
    }

    static func setAddress(_ text: String, _ settings: AppSettings) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.setJSONValue(t.isEmpty ? nil : .string(t), forKey: addressKey)
    }

    static func server(_ settings: AppSettings) -> RemoteServer? {
        RemoteServer.parse(address(settings), apiKey: apiKey)
    }

    // MARK: API key (Keychain, this device only)

    static var apiKey: String? {
        var out: CFTypeRef?
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecReturnData: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static func setApiKey(_ key: String) {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        SecItemDelete(base as CFDictionary)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        var add = base
        add[kSecValueData] = Data(k.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
