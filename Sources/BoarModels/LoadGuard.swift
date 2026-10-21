import BoarCore
import Foundation

/// CR-2 (src/inference/loadMarker.ts) plus #73's mapped retry (port of `LoadGuard.kt`). A model load that gets the app
/// killed (low memory: on iOS a jetsam kill) leaves no error behind, so a marker is written right before the load and
/// cleared after it returns. A marker found on the next start means that load killed the app:
/// - it had repacked weights (llama.cpp copies them into app memory for its fast ARM kernels, which can only be swapped):
///   the next load of that model keeps the mapped file instead, once (`mappedNext`);
/// - otherwise it's a crash: the model isn't loaded again on its own (`isBlocked`) until the user picks it again
///   (`confirm`) or it loads fine; the chat says so once (`consume`).
public final class LoadGuard: @unchecked Sendable {
    public struct Meta: Codable, Sendable, Equatable {
        public var filename: String
        public var modelId: String?
        public var label: String?

        public init(filename: String, modelId: String? = nil, label: String? = nil) {
            self.filename = filename; self.modelId = modelId; self.label = label
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            filename = try c.decode(String.self, forKey: .filename)
            modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
            label = try c.decodeIfPresent(String.self, forKey: .label)
        }
    }

    public struct Marker: Codable, Sendable, Equatable {
        public var filename: String
        public var modelId: String?
        public var label: String?
        public var previous: Meta?
        public var at: Int64
        /// The load used repacked weights (the default); a mapped-file load that dies is a crash.
        public var repacked: Bool

        public init(filename: String, modelId: String? = nil, label: String? = nil, previous: Meta? = nil, at: Int64, repacked: Bool = false) {
            self.filename = filename; self.modelId = modelId; self.label = label; self.previous = previous; self.at = at; self.repacked = repacked
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            filename = try c.decode(String.self, forKey: .filename)
            modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            previous = try c.decodeIfPresent(Meta.self, forKey: .previous)
            at = try c.decode(Int64.self, forKey: .at)
            repacked = try c.decodeIfPresent(Bool.self, forKey: .repacked) ?? false
        }
    }

    /// What the chat shows once: "<crashed> closed the app … using <fallback>".
    public struct Crash: Codable, Sendable, Equatable {
        public var crashedModelId: String
        public var crashedLabel: String
        public var fallbackModelId: String
        public var fallbackLabel: String
        public var at: Int64

        public init(crashedModelId: String, crashedLabel: String, fallbackModelId: String, fallbackLabel: String, at: Int64) {
            self.crashedModelId = crashedModelId; self.crashedLabel = crashedLabel
            self.fallbackModelId = fallbackModelId; self.fallbackLabel = fallbackLabel; self.at = at
        }
    }

    /// Where the marker lives between a load's start and its end. I/O failures are swallowed by implementations.
    public protocol MarkerStore: Sendable {
        func read() -> String?
        func write(_ json: String)
        func clear()
    }

    /// Where the outcome is remembered (settings.json, the Expo app's keys plus `loadMappedIds`).
    public protocol Ledger: AnyObject, Sendable {
        var crashedIds: [String] { get set }
        var mappedIds: [String] { get set }
        var pendingCrash: Crash? { get set }
    }

    private let store: MarkerStore
    private let ledger: Ledger
    private let now: @Sendable () -> Int64
    private let lock = NSRecursiveLock()
    private var checked = false

    public init(store: MarkerStore, ledger: Ledger, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = store
        self.ledger = ledger
        self.now = now
    }

    /// Once per process, before any new marker: a marker left over means the last load killed the app.
    public func ensureChecked() {
        lock.lock(); defer { lock.unlock() }
        if checked { return }
        checked = true
        guard let raw = store.read() else { return }
        if let m = try? Self.decoder.decode(Marker.self, from: Data(raw.utf8)) {
            let id = m.modelId ?? m.filename
            if m.repacked {
                ledger.mappedIds = Self.distinct(ledger.mappedIds + [id])
            } else {
                ledger.crashedIds = Self.distinct(ledger.crashedIds + [id])
                ledger.mappedIds = ledger.mappedIds.filter { $0 != id }
                ledger.pendingCrash = Self.toCrash(m)
            }
        }
        store.clear()
    }

    /// True when the next load of `modelId` should keep the mapped file (its last repacked load was killed).
    public func mappedNext(_ modelId: String) -> Bool { ensureChecked(); return ledger.mappedIds.contains(modelId) }

    /// A model whose load killed the app: not loaded again on its own.
    public func isBlocked(_ modelId: String) -> Bool { ensureChecked(); return ledger.crashedIds.contains(modelId) }

    public func begin(_ meta: Meta, previous: Meta?, repacked: Bool) {
        ensureChecked()
        let marker = Marker(filename: meta.filename, modelId: meta.modelId, label: meta.label, previous: previous, at: now(), repacked: repacked)
        if let data = try? Self.encoder.encode(marker), let s = String(data: data, encoding: .utf8) { store.write(s) }
    }

    /// After the load returned. A model that loaded is unblocked, and goes back to repacked weights on its next load.
    public func end(_ meta: Meta, loaded: Bool) {
        store.clear()
        guard let id = meta.modelId else { return }
        if loaded {
            if ledger.crashedIds.contains(id) { ledger.crashedIds = ledger.crashedIds.filter { $0 != id } }
            if ledger.mappedIds.contains(id) { ledger.mappedIds = ledger.mappedIds.filter { $0 != id } }
        }
    }

    /// The user picked the model again: let it load (CR-2's confirmation).
    public func confirm(_ modelId: String) {
        ensureChecked()
        if ledger.crashedIds.contains(modelId) { ledger.crashedIds = ledger.crashedIds.filter { $0 != modelId } }
    }

    /// The last crash, once.
    public func consume() -> Crash? {
        lock.lock(); defer { lock.unlock() }
        ensureChecked()
        guard let c = ledger.pendingCrash else { return nil }
        ledger.pendingCrash = nil
        return c
    }

    // MARK: stall detection

    /// Decode below this rate, for at least `stallMinMs`, is a stall (a 4B on a 6 GB phone normally writes 3.5–6 tok/s).
    public static let stallTokPerSec = 1.0
    public static let stallMinMs = 10_000.0

    /// memoryFit.ts isDecodeStall (#73): repacked weights pushed to swap make every token wait for them to be decompressed
    /// (0.1 tok/s on a Pixel 6a with the 4B, about 1 answer in 6 in long conversations).
    public static func isDecodeStall(generatedTokens: Int, decodeMs: Double) -> Bool {
        decodeMs >= stallMinMs && Double(generatedTokens) * 1000.0 / decodeMs < stallTokPerSec
    }

    // MARK: records

    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static func distinct(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { seen.insert($0).inserted }
    }

    public static func toCrash(_ m: Marker) -> Crash {
        Crash(
            crashedModelId: m.modelId ?? m.filename,
            crashedLabel: m.label ?? m.modelId ?? m.filename,
            fallbackModelId: m.previous?.modelId ?? m.previous?.filename ?? "",
            fallbackLabel: m.previous?.label ?? m.previous?.modelId ?? m.previous?.filename ?? "",
            at: m.at)
    }

    public static func crashFromJson(_ s: String) -> Crash? { try? decoder.decode(Crash.self, from: Data(s.utf8)) }

    public static func crashToJson(_ c: Crash) -> String {
        (try? encoder.encode(c)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// The marker in a file (Application Support in the app). Writes are atomic; every I/O failure is logged and swallowed, so
/// the guard never makes a load fail.
public struct FileMarkerStore: LoadGuard.MarkerStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }

    public func write(_ json: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url, options: .atomic)
        } catch {
            BoarLog.logger("models").error("load marker not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}

/// `LoadGuard.Ledger` over `AppSettings` (`loadCrashedIds`, `loadMappedIds`, `pendingLoadCrash`: the Expo app's keys).
public final class SettingsLoadLedger: LoadGuard.Ledger, @unchecked Sendable {
    private let settings: AppSettings

    public init(settings: AppSettings) { self.settings = settings }

    public var crashedIds: [String] {
        get { settings.loadCrashedIds }
        set { settings.loadCrashedIds = newValue }
    }

    public var mappedIds: [String] {
        get { settings.loadMappedIds }
        set { settings.loadMappedIds = newValue }
    }

    public var pendingCrash: LoadGuard.Crash? {
        get { settings.pendingLoadCrash.flatMap { LoadGuard.crashFromJson($0.jsonString) } }
        set { settings.pendingLoadCrash = newValue.flatMap { JSONValue(jsonString: LoadGuard.crashToJson($0)) } }
    }
}
