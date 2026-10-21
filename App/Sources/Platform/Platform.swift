import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The few system calls that differ between iPhone/iPad and Mac, so the screens stay free of `#if os`.
@MainActor
enum Platform {
    /// "iOS" or "macOS", for labels and exported results.
    static var systemName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// "26.1".
    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// "iPhone" or "Mac", for copy such as "Free on this iPhone" (the iPad build reads "iPhone" too, as before).
    nonisolated static let deviceNoun: String = {
        #if os(macOS)
        String(localized: "Mac")
        #else
        String(localized: "iPhone")
        #endif
    }()

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    #if os(macOS)
    private static var awake: NSObjectProtocol?
    #endif

    /// Keeps the screen on (iPhone) or the Mac awake while a long job runs: downloads, indexing, the benchmark.
    static func keepAwake(_ on: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #else
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                          reason: "BOAR is downloading or measuring")
        } else if !on, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
        #endif
    }
}
