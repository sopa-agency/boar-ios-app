import BoarModels
import SwiftUI

/// Shown once after a model closed the app while loading (not enough memory): what happened in plain words, which
/// model answers now, and the way to Models.
struct LoadCrashNotice: View {
    let chat: ChatController
    @Environment(AppModel.self) private var model

    var body: some View {
        if let crash = chat.loadCrash {
            NoticeCard(symbol: "memorychip", tint: .orange, title: "Not Enough Memory", message: message(crash)) {
                // Loads it keeping the file mapped instead of copying its weights into memory (LoadGuard.retryMapped).
                // Same as Android (ChatScreen.kt LoadNoteBanner): offered even when the load that closed the app was already
                // mapped, or when Advanced → Repacked weights is set (that tweak wins over the mapped retry). Kept for
                // parity; a fix starts on Android (PR #1 review).
                if chat.services.catalog.byId(crash.crashedModelId) != nil {
                    Button("Try Again with Less Memory") { chat.retryWithLessMemory(crash.crashedModelId) }
                        .buttonStyle(.boarProminent)
                }
                Button("Choose a Model", action: openModels)
                    .buttonStyle(.bordered)
                Button("OK", action: dismiss)
                    .buttonStyle(.bordered)
            }
        }
    }

    /// "Accurate needed more memory than this \(Platform.deviceNoun) had free, so BOAR closed while loading it. Answers now use Fast."
    private func message(_ crash: LoadGuard.Crash) -> String {
        let crashed = name(crash.crashedModelId, crash.crashedLabel)
        if crash.fallbackLabel.isEmpty {
            return String(localized: "\(crashed) needed more memory than this \(Platform.deviceNoun) had free, so BOAR closed while loading it. Pick a smaller model.")
        }
        let fallback = name(crash.fallbackModelId, crash.fallbackLabel)
        return String(localized: "\(crashed) needed more memory than this \(Platform.deviceNoun) had free, so BOAR closed while loading it. Answers now use \(fallback).")
    }

    /// The plain name the rest of the app uses ("Fast", "Accurate").
    private func name(_ id: String, _ label: String) -> String {
        chat.services.catalog.byId(id)?.friendlyName ?? shortModelLabel(label)
    }

    private func openModels() {
        chat.loadCrash = nil
        model.selection = .screen(.models)
    }

    private func dismiss() {
        chat.loadCrash = nil
    }
}
