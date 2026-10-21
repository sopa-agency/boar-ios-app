import Foundation

/// Launch arguments of the UI audit tooling (`scripts/ui-capture.sh`). Everything here exists only in DEBUG builds; the
/// Release stubs are constants, so the call sites in the app need no `#if`.
///
///     -uiDemo            seed an in-memory-style demo state (no model needed); wipes BOAR's files in the app container
///     -uiScreen <name>   open that screen directly (see `DebugRouter`)
///     -uiScroll <pts|end> scroll the main list that far once the screen is up
enum DebugLaunch {
    #if DEBUG
    /// `-uiScreen <name>`: the argument domain of UserDefaults carries it.
    static let screen: String? = UserDefaults.standard.string(forKey: "uiScreen")
    /// `-uiDemo`.
    static let demo: Bool = ProcessInfo.processInfo.arguments.contains("-uiDemo")
    /// `-uiRemote <address>`: answers come from llama-server at that address ("Mac on Your Network").
    static let remote: String? = UserDefaults.standard.string(forKey: "uiRemote")
    /// `-uiImport <file>`: imports that file into a "Test Import" collection on launch (Mac test of the import path
    /// without the system's file panel, which runs in another process).
    static let importFile: String? = UserDefaults.standard.string(forKey: "uiImport")
    /// `-uiScroll <points>` or `-uiScroll end`.
    static let scroll: String? = UserDefaults.standard.string(forKey: "uiScroll")
    /// iPhone 13 memory: the demo shows the owner's phone numbers, not the Mac's.
    static let ramBytes: Int64? = demo ? 4 * 1_073_741_824 : nil

    static func isScreen(_ name: String) -> Bool { screen == name }
    /// The lock screen stays as it is drawn: no Face ID / passcode prompt, no error text under it.
    static var holdsLockScreen: Bool { screen == "lock" }
    #else
    static let demo = false
    static let ramBytes: Int64? = nil
    static func isScreen(_ name: String) -> Bool { false }
    static var holdsLockScreen: Bool { false }
    #endif
}
