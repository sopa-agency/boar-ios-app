import BoarCore
import Foundation
import MetricKit
import os

/// Performance signals without Instruments attached (docs/PERF.md):
/// - a main-thread watchdog: a background thread pings the main queue every 100 ms and logs any stall over 250 ms as a
///   `main.stall` mark (device log category `perf`, Points of Interest lane), with the memory at that moment;
/// - MetricKit: hang, crash and CPU/disk diagnostics plus daily metrics, written as JSON to
///   `Library/Application Support/BOAR/metrickit/` (pull them with `scripts/perf.sh metrickit`).
enum PerfMonitor {
    private static let started = OSAllocatedUnfairLock(initialState: false)

    static func start() {
        let first = started.withLock { s in
            defer { s = true }
            return !s
        }
        guard first else { return }
        MXMetricManager.shared.add(MetricKitSink.shared)
        let watchdog = Thread { MainThreadWatchdog.run() }
        watchdog.name = "team.sopa.boar.watchdog"
        watchdog.qualityOfService = .utility
        watchdog.start()
    }
}

/// Pings the main queue and measures how long the reply takes; long replies are the stalls a user feels as a frozen UI.
private enum MainThreadWatchdog {
    static let interval: TimeInterval = 0.1
    static let stallMs = 250.0

    static func run() {
        let replied = DispatchSemaphore(value: 0)
        while true {
            let sent = DispatchTime.now()
            DispatchQueue.main.async { replied.signal() }
            if replied.wait(timeout: sent + stallMs / 1000) == .timedOut {
                replied.wait()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1e6
                BoarPerf.event("main.stall", "\(Int(ms)) ms")
            }
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

/// Writes every MetricKit payload to disk as it arrives (diagnostics come on the next launch after a hang or crash).
private final class MetricKitSink: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitSink()
    private static let log = BoarLog.logger("perf")

    private var dir: URL {
        let d = AppPaths.filesDir.appending(path: "metrickit")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { write(p.jsonRepresentation(), prefix: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            write(p.jsonRepresentation(), prefix: "diagnostics")
            Self.log.notice("metrickit diagnostics: \(p.hangDiagnostics?.count ?? 0) hangs, \(p.crashDiagnostics?.count ?? 0) crashes, \(p.cpuExceptionDiagnostics?.count ?? 0) cpu")
        }
    }

    private func write(_ data: Data, prefix: String) {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: dir.appending(path: "\(prefix)-\(stamp).json"), options: .atomic)
    }
}
