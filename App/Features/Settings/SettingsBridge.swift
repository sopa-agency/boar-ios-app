import BoarCore
import Observation
import SwiftUI

/// Bindings onto `AppSettings` (which reads through to UserDefaults and isn't observable): a write bumps `version`, and
/// every binding reads it, so the form redraws with the stored value.
@MainActor
@Observable
final class SettingsBridge {
    /// Bumped on every write (the Mac Settings window refreshes the chat from it).
    private(set) var version = 0
    @ObservationIgnored let settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    func binding<T>(_ get: @escaping (AppSettings) -> T, _ set: @escaping (AppSettings, T) -> Void) -> Binding<T> {
        Binding(
            get: { _ = self.version; return get(self.settings) },
            set: { set(self.settings, $0); self.version += 1 }
        )
    }

    /// A value read outside a binding (a footer, an Auto label) that should follow writes.
    func read<T>(_ get: (AppSettings) -> T) -> T {
        _ = version
        return get(settings)
    }

    /// After a write that went around the bindings (reset, presets).
    func touch() { version += 1 }
}
