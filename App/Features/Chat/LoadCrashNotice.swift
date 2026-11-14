import BoarModels
import SwiftUI

/// Shown once after a model closed the app while loading (not enough memory): what happened in plain words, which
/// model answers now, and the way to Models. Also the note for a model that may not fit this device's memory, which the
/// chat doesn't load until the user chooses (android ChatScreen.kt LoadNoteBanner, StartLoad).
struct LoadCrashNotice: View {
    let chat: ChatController
    @Environment(AppModel.self) private var model

    var body: some View {
        if let risky = chat.riskyLoad {
            NoticeCard(symbol: "memorychip", tint: .orange, title: "May Not Fit", message: message(risky)) {
                Button(risky.onlyModel ? "Choose a Model" : "Pick Another Model", action: openModels)
                    .buttonStyle(.boarProminent)
                Button("Load Anyway") { chat.loadAnyway(risky.modelId) }
                    .buttonStyle(.bordered)
                Button("OK", action: dismiss)
                    .buttonStyle(.bordered)
            }
        } else if let crash = chat.loadCrash {
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

    /// "Accurate may not fit in this \(Platform.deviceNoun)'s memory." With no other model installed, names a smaller one.
    private func message(_ risky: RiskyLoad) -> String {
        let model = name(risky.modelId, risky.modelId)
        guard risky.onlyModel else { return String(localized: "\(model) may not fit in this \(Platform.deviceNoun)'s memory.") }
        let small = chat.services.catalog.byId(Self.smallModelId)?.friendlyName ?? "Qwen2.5 1.5B"
        return String(localized: "\(model) may not fit in this \(Platform.deviceNoun)'s memory. A smaller model, such as \(small) (about 1 GB), fits better.")
    }

    /// The model Android's note names as the one that fits (Qwen2.5 1.5B, "Fast").
    private static let smallModelId = "qwen2.5-1.5b-instruct-q4km"

    /// The plain name the rest of the app uses ("Fast", "Accurate").
    private func name(_ id: String, _ label: String) -> String {
        chat.services.catalog.byId(id)?.friendlyName ?? shortModelLabel(label)
    }

    /// Leaves the note: a question held for its model is dropped.
    private func openModels() {
        chat.dismissLoadNote()
        model.selection = .screen(.models)
    }

    private func dismiss() {
        chat.dismissLoadNote()
    }
}
