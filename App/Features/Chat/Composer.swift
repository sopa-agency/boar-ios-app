import SwiftUI

/// The input bar, one glass pill like Messages: the answer style on the left, the question field, and one trailing
/// button that is the mic (empty field, voice input on), send (there is text) or stop (while answering with nothing
/// typed). Typing while BOAR answers turns the button back into Send: the question waits its turn (the queue).
struct Composer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    /// The current answer style's symbol; Deep Research shows its own.
    let toneSymbol: AppIcon
    let toneLabel: String
    let deepResearch: Bool
    let answering: Bool
    let stopping: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onTones: () -> Void
    /// On-device dictation; nil when voice input is off in Settings or this iPhone has no transcriber.
    var voice: VoiceInputController? = nil
    /// The Mac shows the answer styles as a pop-up menu on the style button instead of a sheet.
    var chat: ChatController? = nil

    /// After a send the round button rests this long before it can stop the answer (android `SEND_REST_MS`).
    static let sendRest = Duration.milliseconds(500)
    @State private var resting = false

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// One round button that follows what the user does: while BOAR answers it is Stop, and Send (to the queue) while
    /// something is typed. After a send it ignores taps for half a second, dimmed, so a second tap meant for Send can't
    /// land on the Stop it turns back into.
    private var stops: Bool { answering && !hasText }

    /// The mic takes the trailing slot while dictating, or when there is nothing to send yet.
    private var showsMic: Bool {
        guard let voice, !answering else { return false }
        return voice.active || !hasText
    }

    var body: some View {
        HStack(alignment: .bottom) {
            styleButton
                .frame(minHeight: 36)
                .accessibilityValue(deepResearch ? Text("\(toneLabel), Deep Research on") : Text(toneLabel))
                .accessibilityHint("Choose how BOAR answers")

            TextField(deepResearch ? "Ask with Deep Research" : "Ask BOAR", text: $text, axis: .vertical)
                #if os(macOS)
                // The glass pill is the field: no second bezel inside it.
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                #endif
                .lineLimit(1...5)
                .focused(focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .frame(minHeight: 36)

            trailing
        }
        .font(.boar("ui.body"))
        .padding(.leading)
        .padding(4)
        .glassOrMaterial(in: .rect(cornerRadius: 22), interactive: true)
        .padding(.horizontal)
        #if os(macOS)
        // No home indicator on a Mac: the bar keeps a margin above the window's bottom edge.
        .padding(.bottom, 12)
        #endif
    }

    @ViewBuilder private var styleButton: some View {
        #if os(macOS)
        if let chat {
            ToneMenu(chat: chat, symbol: deepResearch ? Symbols.deepResearch : toneSymbol)
                .help("Answer Style: \(toneLabel)\(deepResearch ? String(localized: ", Deep Research") : "")")
        }
        #else
        Button("Answer Style", icon: deepResearch ? Symbols.deepResearch : toneSymbol, action: onTones)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        #endif
    }

    @ViewBuilder private var trailing: some View {
        if showsMic, let voice {
            VoiceButton(voice: voice, text: $text)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: 36, minHeight: 36)
        } else {
            Button(action: stops ? onStop : send) {
                Label(stops ? "Stop Answering" : "Send", icon: stops ? Symbols.stop : Symbols.send)
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .contentTransition(.symbolEffect(.replace))
            }
            .opacity(resting ? 0.45 : 1)
            .prominentGlassButtonStyle()
            .buttonBorderShape(.circle)
            #if os(macOS)
            .controlSize(.large)
            #endif
            .disabled((!answering && !hasText) || resting)
            #if os(macOS)
            .help(stops ? "Stop Answering (⌘.)" : "Send (Return)")
            #endif
            .accessibilityLabel(stops ? (stopping ? Text("Stopping") : Text("Stop Answering")) : Text("Send"))
        }
    }

    private func submit() {
        if hasText && !resting { send() }
    }

    /// Every send rests, on an idle chat too (validator Q-6).
    private func send() {
        voice?.cancel()
        onSend()
        resting = true
        Task {
            try? await Task.sleep(for: Self.sendRest)
            resting = false
        }
    }
}
