import Foundation
import os

/// Where `AppSettings` keeps its keys. Values are JSON nodes so unknown keys round-trip untouched.
/// Implementations are thread-safe; writes are durable when the call returns.
public protocol KeyValueStore: Sendable {
    func value(forKey key: String) -> JSONValue?
    /// nil or `.null` removes the key.
    func setValue(_ value: JSONValue?, forKey key: String)
    func removeValues(forKeys keys: [String])
    /// Every key as stored.
    func allValues() -> [String: JSONValue]
}

/// A store in memory (tests, previews).
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: JSONValue]

    public init(_ initial: [String: JSONValue] = [:]) { values = initial }

    public func value(forKey key: String) -> JSONValue? { lock.withLock { values[key] } }
    public func setValue(_ value: JSONValue?, forKey key: String) {
        lock.withLock { if let value, !value.isNull { values[key] = value } else { values[key] = nil } }
    }
    public func removeValues(forKeys keys: [String]) { lock.withLock { keys.forEach { values[$0] = nil } } }
    public func allValues() -> [String: JSONValue] { lock.withLock { values } }
}

/// The app's store: each key is JSON text in `UserDefaults` under `prefix + key`, so numbers, booleans and nested objects keep their types.
public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "boar.settings.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func value(forKey key: String) -> JSONValue? {
        defaults.string(forKey: prefix + key).flatMap { JSONValue(jsonString: $0) }
    }
    public func setValue(_ value: JSONValue?, forKey key: String) {
        if let value, !value.isNull { defaults.set(value.jsonString, forKey: prefix + key) } else { defaults.removeObject(forKey: prefix + key) }
    }
    public func removeValues(forKeys keys: [String]) { keys.forEach { defaults.removeObject(forKey: prefix + $0) } }
    public func allValues() -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(prefix) {
            if let s = v as? String, let j = JSONValue(jsonString: s) { out[String(k.dropFirst(prefix.count))] = j }
        }
        return out
    }
}

/// A store in one JSON object file (the Android app's `settings.json`, which the Expo app also wrote). Read once at init (a
/// missing or broken file means empty), written in full on every change through a temporary file, so a crash never leaves half a file.
public final class JSONFileKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var values: [String: JSONValue]
    private static let log = BoarLog.logger("settings")

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let obj = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue {
            values = obj
        } else {
            values = [:]
        }
    }

    public func value(forKey key: String) -> JSONValue? { lock.withLock { values[key] } }
    public func setValue(_ value: JSONValue?, forKey key: String) {
        lock.withLock {
            if let value, !value.isNull { values[key] = value } else { values[key] = nil }
            persist()
        }
    }
    public func removeValues(forKeys keys: [String]) { lock.withLock { keys.forEach { values[$0] = nil }; persist() } }
    public func allValues() -> [String: JSONValue] { lock.withLock { values } }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONValue.object(values).jsonString.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            Self.log.error("settings write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
