import Foundation

/// The device line of an exported trace ("iPhone14,5 iOS 26.6"; the simulator reports the \(Platform.deviceNoun) it simulates).
@MainActor
enum EvalHost {
    static var description: String {
        let id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        return "\(id) \(Platform.systemName) \(Platform.systemVersion)"
    }

    private static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
