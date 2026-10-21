import BoarAppleAI
import SwiftUI

/// Voice: dictation in the chat, and the one-time English speech model download when iOS needs it.
struct SettingsVoiceSection: View {
    let bridge: SettingsBridge
    @State private var state: VoiceAssetState?
    @State private var installing: Double?
    @State private var error: String?

    var body: some View {
        Section {
            Toggle(isOn: bridge.binding({ $0.voiceInputEnabled && state != .unsupported }, { $0.voiceInputEnabled = $1 })) {
                SettingsLabel("Dictation", symbol: "mic.fill", color: .red)
            }
                .disabled(state == .unsupported)
            if state == .downloadable || state == .downloading {
                HStack {
                    VStack(alignment: .leading) {
                        Text("English Speech Model")
                        Text(installing == nil && state == .downloadable ? "Needed once for dictation" : "Downloading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let installing {
                        ProgressView(value: installing)
                            .progressViewStyle(.circular)
                            .accessibilityLabel("Downloading the speech model")
                    } else if state == .downloadable {
                        Button("Download", systemImage: Symbols.download, action: install)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .font(.title2)
                    } else {
                        ProgressView()
                    }
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            VStack(alignment: .leading) {
                if state == .unsupported {
                    Text("Dictation isn't available on this \(Platform.deviceNoun).")
                } else {
                    Text("Speech is recognized on your \(Platform.deviceNoun). The audio never leaves it.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .task { state = await Dictation.assetState() }
    }

    private func install() {
        installing = 0
        error = nil
        Task {
            do {
                try await Dictation.installAssets { p in Task { @MainActor in installing = p } }
            } catch {
                self.error = error.localizedDescription
            }
            installing = nil
            state = await Dictation.assetState()
        }
    }
}
