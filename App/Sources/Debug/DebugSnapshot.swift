#if DEBUG && os(macOS)
import AppKit

/// `-uiSnapshot <seconds>` (Mac, DEBUG): after that many seconds, writes the app window's number to `ui-window.txt` in
/// the container's tmp folder, so `screencapture -l <number>` can capture just this window (even behind others, without
/// bringing it to the front); quits 6 s later.
@MainActor
enum DebugSnapshot {
    /// From the App's init: notes how many windows exist a few seconds in (`ui-windows.txt`).
    static func probeWindows() {
        guard UserDefaults.standard.string(forKey: "uiSnapshot") != nil else { return }
        Task {
            // `-uiAppearance light|dark`: the capture's look, whatever the Mac is set to.
            switch UserDefaults.standard.string(forKey: "uiAppearance") {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: break
            }
            try? await Task.sleep(for: .seconds(1))
            // Launched in the background, SwiftUI waits for activation before it opens the first window: open it the way
            // File → New Window does, without bringing the app to the front.
            if NSApp.windows.filter({ $0.frame.width > 200 }).isEmpty, let item = newWindowItem(NSApp.mainMenu) ?? mainWindowItem() {
                _ = item.target.map { NSApp.sendAction(item.action!, to: $0, from: item) } ?? NSApp.sendAction(item.action!, to: nil, from: item)
            }
            try? await Task.sleep(for: .seconds(3))
            let menu = (NSApp.mainMenu?.items ?? []).map { m in "\(m.title): " + (m.submenu?.items.map(\.title).joined(separator: "|") ?? "") }.joined(separator: "\n")
            let all = NSApp.windows.map { "\($0.className) visible=\($0.isVisible) w=\(Int($0.frame.width))" }.joined(separator: "\n")
            let url = URL(filePath: NSTemporaryDirectory()).appending(path: "ui-windows.txt")
            try? "active=\(NSApp.isActive) count=\(NSApp.windows.count)\n\(all)\n\(menu)".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// The single-window Mac app has no New Window item: its Window menu lists the main window ("BOAR") instead.
    private static func mainWindowItem() -> NSMenuItem? {
        let items = NSApp.windowsMenu?.items ?? NSApp.mainMenu?.items.last(where: { $0.submenu?.title == "Window" })?.submenu?.items ?? []
        return items.first { $0.title == "BOAR" && $0.action != nil }
    }

    private static func newWindowItem(_ menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.title.hasPrefix("New") && item.title.contains("Window"), item.action != nil { return item }
            if let found = newWindowItem(item.submenu) { return found }
        }
        return nil
    }

    static func scheduleIfRequested() {
        guard let seconds = UserDefaults.standard.string(forKey: "uiSnapshot").flatMap(Double.init) else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 200 }) {
                // Captures share the real app's saved window frame: give them the default size (or `-uiSize 1000x600`).
                let size = (UserDefaults.standard.string(forKey: "uiSize") ?? "1240x800").split(separator: "x").compactMap { Double($0) }
                window.setContentSize(NSSize(width: size.first ?? 1240, height: size.last ?? 800))
                try? await Task.sleep(for: .milliseconds(800))
                let url = URL(filePath: NSTemporaryDirectory()).appending(path: "ui-window.txt")
                try? "\(window.windowNumber)".write(to: url, atomically: true, encoding: .utf8)
            }
            try? await Task.sleep(for: .seconds(6))
            NSApp.terminate(nil)
        }
    }
}
#endif
