import BoarAnswer
import BoarModels
import Foundation
#if os(iOS)
import CoreMotion
import UIKit
#endif

/// What Nomad and Vitals read when they answer a question in the chat (android labs `PhoneReads.kt`, adam Nov 12). The tool
/// slot runs synchronously, so the chat reads the device first (`prepare`, before the tools run, off the slot) and the
/// tools answer from that reading: the compass waits up to 900 ms for Core Motion's first readings, as Android waits for
/// its rotation sensor.
enum PhoneReads {
    /// The device as the plugin answers name it ("This iPhone has no compass").
    static var device: PluginAnswers.Device { PluginAnswers.Device(en: Platform.deviceNoun, pt: Platform.deviceNoun) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var heading: (heading: Double?, tilt: Double?)?
    nonisolated(unsafe) private static var phone: PluginAnswers.PhoneNow?

    /// The last reading `prepare` took for this question; nil (no compass) when none was taken.
    static func lastHeading() -> (heading: Double?, tilt: Double?) { lock.withLock { heading } ?? (nil, nil) }
    static func lastPhone() -> PluginAnswers.PhoneNow? { lock.withLock { phone } }

    /// Reads what the switched-on plugins need for `query`: the heading for Nomad's question, the battery and memory for
    /// Vitals'. Nothing for any other question, so no sensor starts.
    @MainActor
    static func prepare(query: String, active: Set<String>) async {
        lock.withLock {
            heading = nil
            phone = nil
        }
        if active.contains("compass"), PluginAnswers.isDirectionQuestion(query) {
            let h = await readHeading()
            lock.withLock { heading = h }
        }
        if active.contains("pulse"), PluginAnswers.isPhoneQuestion(query) {
            let p = readPhone()
            lock.withLock { phone = p }
        }
    }

    /// The device's heading (degrees from magnetic north) and its tilt from flat (degrees); nils without a magnetometer
    /// (the Mac) or when no reading came in time.
    @MainActor
    static func readHeading(waitMs: Int = 900) async -> (heading: Double?, tilt: Double?) {
        #if os(iOS)
        guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical) else { return (nil, nil) }
        let motion = CMMotionManager()
        guard motion.isDeviceMotionAvailable else { return (nil, nil) }
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var heading: Double?
            var tilt: Double?
            var count = 0
        }
        let box = Box()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: queue) { m, _ in
            guard let m, m.heading >= 0 else { return }
            // Pitch and roll together: how far the screen is from facing up (android acos(cos·cos)).
            let tilt = acos(min(max(cos(m.attitude.pitch) * cos(m.attitude.roll), -1), 1)) * 180 / .pi
            box.lock.withLock {
                box.heading = m.heading.truncatingRemainder(dividingBy: 360)
                box.tilt = tilt
                box.count += 1
            }
        }
        defer { motion.stopDeviceMotionUpdates() }
        // Android waits for three readings, or the time.
        var waited = 0
        while waited < waitMs, box.lock.withLock({ box.count }) < 3 {
            try? await Task.sleep(for: .milliseconds(30))
            waited += 30
        }
        return box.lock.withLock { (box.heading, box.tilt) }
        #else
        return (nil, nil)
        #endif
    }

    /// Battery (level and charging), the system's heat level, memory and cores. iOS gives no battery temperature; the
    /// "free" memory is what BOAR can still use before iOS closes it (the Mac: none).
    @MainActor
    static func readPhone() -> PluginAnswers.PhoneNow {
        var pct: Int?
        var charging: Bool?
        #if os(iOS)
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        if d.batteryLevel >= 0 { pct = Int((d.batteryLevel * 100).rounded()) }
        if d.batteryState != .unknown { charging = d.batteryState == .charging || d.batteryState == .full }
        #endif
        let level = switch ProcessInfo.processInfo.thermalState {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        default: 3
        }
        return PluginAnswers.PhoneNow(
            batteryPct: pct, charging: charging, batteryTempC: nil,
            ramFreeMb: DeviceMemory.availableBytes.map { $0 / 1_048_576 }, ramTotalMb: DeviceMemory.totalBytes / 1_048_576,
            cores: ProcessInfo.processInfo.activeProcessorCount, heatLevel: level)
    }
}
