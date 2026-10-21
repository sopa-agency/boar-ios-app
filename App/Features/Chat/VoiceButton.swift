import SwiftUI

/// The mic: starts on-device dictation into the field, stops it; live partial text appears as it's heard.
struct VoiceButton: View {
    @Bindable var voice: VoiceInputController
    @Binding var text: String

    var body: some View {
        Button(action: toggle) {
            switch voice.state {
            case .idle: Label("Dictate", systemImage: "mic")
            case .preparing, .finishing: ProgressView()
            case .installing(let p): ProgressView(value: p).progressViewStyle(.circular)
            case .listening:
                Label("Stop Dictation", systemImage: "mic.fill")
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityLabel(voice.active ? Text("Stop Dictation") : Text("Dictate"))
        .accessibilityHint(voice.active ? Text("Keeps the words heard so far") : Text("Speak your question; it's transcribed on this \(Platform.deviceNoun)"))
        .alert("Dictation", item: $voice.error) { _ in
        } message: { error in
            Text(error)
        }
    }

    private func toggle() {
        if voice.active { voice.stop() } else { voice.start(prefix: text) { text = $0 } }
    }
}
