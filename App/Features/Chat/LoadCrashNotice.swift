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
                Button("Choose a Model", action: openModels)
                    .buttonStyle(.borderedProminent)
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
