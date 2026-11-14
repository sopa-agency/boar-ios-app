import BoarCore
import BoarLlama
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Settings → Engine Tweaks → Debug Log (android DebugLog.kt): how BOAR used the iPhone, to chase a slow answer, a crash
/// or a hot phone. Off until the user turns it on.
///
/// One line per record in files/debug/ (`DebugLogFile`: two files of 2 MB at most, the older one dropped): a sample of
/// memory, battery, heat and free space every 15 s (every minute in the background), plus launches, model loads, answer
/// speed, downloads, settings changes, memory warnings and Objective-C exceptions. Numbers and ids only, never what was
/// asked or answered. Nothing is sent: the user saves the file (Save Log) and shares it themselves.
///
/// iOS doesn't let an app read CPU speeds, the battery's temperature or current, or catch a Swift crash; a crash shows
/// as the log stopping, then an `app.start`.
enum DebugLog {
    static let file = DebugLogFile(dir: AppPaths.filesDir.appending(path: "debug"))

    private static let sampleSeconds = 15
    private static let backgroundSampleSeconds = 60
    private static let mb: Int64 = 1024 * 1024

    /// Settings that hold secrets or the user's own words (and the address of the user's Mac): the change is logged, the
    /// value isn't.
    private static let redacted: Set<String> = ["pinWrapped", "pinSalt", "customSystemPrompt", "shareDeviceId",
                                                "pendingFirstQuestion", "iosRemoteServerAddress"]
    /// Records the app updates by itself, not settings.
    private static let quiet: Set<String> = ["truffleVault", "debugLogEnabled"]

    private struct State: Sendable {
        var settings: AppSettings?
        var foreground = true
        var sampler: Task<Void, Never>?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static var enabled: Bool { state.withLock { $0.settings }?.debugLogEnabled == true }

    /// Once, with the app's settings: watches settings, memory warnings, heat and exceptions, and starts sampling if
    /// the log is on.
    static func start(settings: AppSettings) {
        let first = state.withLock { s -> Bool in
            guard s.settings == nil else { return false }
            s.settings = settings
            return true
        }
        guard first else { return }
        settings.onChange = { key, old, new in setting(key, old: old, new: new) }
        NSSetUncaughtExceptionHandler { e in
            // Synchronously: the process is ending.
            if DebugLog.enabled {
                DebugLog.file.appendNow(DebugLogFile.line("crash", [("error", "\(e.name.rawValue):\(String((e.reason ?? "").prefix(120)))"),
                                                                     ("at", e.callStackSymbols.prefix(6).joined(separator: "<"))]))
            }
        }
        let center = NotificationCenter.default
        // App-long observers: never removed, so their tokens aren't kept.
        _ = center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
            event("thermal.change", ("thermal", thermalName(ProcessInfo.processInfo.thermalState)))
        }
        _ = center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
            event("power.change", ("lowPower", ProcessInfo.processInfo.isLowPowerModeEnabled))
        }
        #if os(iOS)
        // UIApplication.didReceiveMemoryWarningNotification, by name: this runs off the main actor.
        _ = center.addObserver(forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"), object: nil, queue: nil) { _ in
            event("memory.warning", memoryFields())
        }
        #endif
        if enabled {
            event("app.start", device())
            startSampler()
        }
    }

    static func setEnabled(_ on: Bool) {
        guard let settings = state.withLock({ $0.settings }) else { return }
        if !on { event("log.off") }
        settings.debugLogEnabled = on
        if on { event("log.on", device()); startSampler() } else { stopSampler() }
    }

    static func foreground(_ on: Bool) {
        let changed = state.withLock { s -> Bool in
            defer { s.foreground = on }
            return s.foreground != on
        }
        if changed { event(on ? "app.foreground" : "app.background") }
    }

    static func modelLoad(id: String, ms: Int, ok: Bool, threads: Int, nCtx: Int, repack: Bool) {
        event("model.load", [("id", id), ("ok", ok), ("ms", ms), ("threads", threads), ("ctx", nCtx), ("repack", repack),
                             ("metal", LlamaSession.metalEnabled)] + memoryFields())
    }

    static func modelUnload(id: String?) {
        event("model.unload", [("id", id)] + memoryFields())
    }

    /// `nCtx`: the context window; how full it got shows a slowdown from a long chat.
    static func generation(id: String, _ m: GenerationMetrics, nCtx: Int) {
        let used = m.promptTokens + m.generatedTokens
        event("gen", ("id", id), ("ctxUsed", used), ("ctxMax", nCtx), ("ctxPct", nCtx > 0 ? used * 100 / nCtx : nil),
              ("prompt", m.promptTokens), ("decoded", m.promptTokensDecoded), ("tokens", m.generatedTokens),
              ("ttftMs", Int(m.ttftMs)), ("prefillTps", fixed(m.prefillTokPerSec)), ("decodeTps", fixed(m.decodeTokPerSec)),
              ("totalMs", Int(m.totalMs)), ("stop", m.stopReason.isEmpty ? nil : m.stopReason), ("error", m.error))
    }

    /// A model or pack download: when it started, how long it took, and why it failed.
    static func download<T>(id: String, sizeBytes: Int64, _ body: () async throws -> T) async throws -> T {
        let start = ContinuousClock.now
        func ms() -> Int { Int(start.duration(to: .now) / .milliseconds(1)) }
        event("download.start", ("id", id), ("mb", sizeBytes / mb))
        do {
            let value = try await body()
            event("download.done", ("id", id), ("ms", ms()))
            return value
        } catch {
            let why = error is CancellationError ? "cancelled" : String(String(describing: error).prefix(120))
            event("download.fail", ("id", id), ("ms", ms()), ("error", why))
            throw error
        }
    }

    /// For switches kept outside the settings store (Boar Labs, the vault).
    static func settingChanged(_ key: String, old: Any?, new: Any?) {
        let o = old.map { "\($0)" }, n = new.map { "\($0)" }
        if o != n { event("setting", ("key", key), ("old", o ?? "unset"), ("new", n ?? "unset")) }
    }

    /// Records an event with its fields (nil fields are left out).
    static func event(_ name: String, _ fields: (String, Any?)...) { event(name, fields) }

    static func event(_ name: String, _ fields: [(String, Any?)]) {
        guard enabled else { return }
        file.append(DebugLogFile.line(name, fields))
    }

    /// What Save Log writes: when, this device, the settings (secrets redacted), then the log.
    static func savedContents() -> Data {
        let now = DebugLogFile.line("saved", []).split(separator: " ").first.map(String.init) ?? ""
        var header = "# BOAR debug log, saved \(now)\n"
        header += "# " + device().compactMap { k, v in v.map { "\(k)=\($0)" } }.joined(separator: " ") + "\n"
        if let settings = state.withLock({ $0.settings }) {
            let values = settings.raw().filter { !quiet.contains($0.key) }.sorted { $0.key < $1.key }
                .map { k, v in "\(k)=\(redacted.contains(k) ? "\"redacted\"" : v.jsonString)" }
            header += "# settings " + values.joined(separator: " ") + "\n"
        }
        return file.contents(header: header)
    }

    static func clear() {
        file.clear()
        event("log.cleared")
    }

    // MARK: private

    /// A setting changed: key, old → new. An object (engineTweaks) is logged one changed field at a time.
    private static func setting(_ key: String, old: JSONValue?, new: JSONValue?) {
        guard enabled, !quiet.contains(key) else { return }
        if redacted.contains(key) { return event("setting", ("key", key), ("change", "redacted")) }
        let a = old?.objectValue, b = new?.objectValue
        if (a != nil || old == nil) && (b != nil || new == nil) && (a != nil || b != nil) {
            let a = a ?? [:], b = b ?? [:]
            for k in Set(a.keys).union(b.keys).sorted() where a[k] != b[k] {
                event("setting", ("key", "\(key).\(k)"), ("old", a[k]?.jsonString ?? "auto"), ("new", b[k]?.jsonString ?? "auto"))
            }
        } else {
            event("setting", ("key", key), ("old", old.map { String($0.jsonString.prefix(120)) } ?? "unset"),
                  ("new", new.map { String($0.jsonString.prefix(120)) } ?? "unset"))
        }
    }

    private static func startSampler() {
        state.withLock { s in
            guard s.sampler == nil else { return }
            s.sampler = Task.detached(priority: .utility) {
                #if os(iOS)
                await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }
                #endif
                while !Task.isCancelled && enabled {
                    event("sample", await sample())
                    let fg = state.withLock { $0.foreground }
                    try? await Task.sleep(for: .seconds(fg ? sampleSeconds : backgroundSampleSeconds))
                }
            }
        }
    }

    private static func stopSampler() {
        state.withLock { s in
            s.sampler?.cancel()
            s.sampler = nil
        }
    }

    private static func memoryFields() -> [(String, Any?)] {
        let m = BoarPerf.memory()
        return [("footprintMb", m.footprintMB), ("headroomMb", m.availableMB)]
    }

    /// Memory, battery, heat and free space, read in a few milliseconds.
    private static func sample() async -> [(String, Any?)] {
        var fields: [(String, Any?)] = [("fg", state.withLock { $0.foreground })]
        fields += memoryFields()
        fields.append(("ramTotalMb", Int64(ProcessInfo.processInfo.physicalMemory) / mb))
        #if os(iOS)
        let battery = await MainActor.run { () -> (Float, UIDevice.BatteryState) in
            (UIDevice.current.batteryLevel, UIDevice.current.batteryState)
        }
        fields.append(("battery", battery.0 >= 0 ? Int((battery.0 * 100).rounded()) : nil))
        fields.append(("charging", battery.1 == .charging || battery.1 == .full))
        #endif
        fields.append(("thermal", thermalName(ProcessInfo.processInfo.thermalState)))
        fields.append(("lowPower", ProcessInfo.processInfo.isLowPowerModeEnabled))
        fields.append(("freeMb", DeviceStorage.availableBytes().map { $0 / mb }))
        return fields
    }

    private static func device() -> [(String, Any?)] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return [("app", "\(version)(\(build))"), ("device", DeviceName.identifier), ("os", Self.osVersion),
                ("cores", ProcessInfo.processInfo.activeProcessorCount),
                ("ramMb", Int64(ProcessInfo.processInfo.physicalMemory) / mb), ("metal", LlamaSession.metalEnabled)]
    }

    /// "iOS_26.1" (Platform's names are main-actor only).
    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let name = "macOS"
        #else
        let name = "iOS"
        #endif
        return "\(name)_\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func fixed(_ v: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), v) }
}
