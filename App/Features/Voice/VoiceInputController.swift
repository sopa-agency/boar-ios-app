import BoarAppleAI
import BoarCore
import Foundation
import Observation

/// Dictation in the composer (android `VoiceInput`): SpeechAnalyzer's on-device English transcriber, so the audio
/// stays on the iPhone. The live text replaces what was dictated so far after whatever was typed before the mic.
@MainActor
@Observable
final class VoiceInputController {
    enum State: Equatable {
        case idle
        case preparing
        /// The English speech model is downloading (once, from Apple), 0…1.
        case installing(Double)
        case listening
        case finishing
    }

    private(set) var state: State = .idle
    var error: String?

    /// A `VoiceTranscriber` once dictation starts (iOS 26 and later only).
    @ObservationIgnored private var transcriber: AnyObject?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// A dictation ended with words heard (Boar Avatars counts voice input, android VoiceInput.onResults).
    @ObservationIgnored var onRecognized: (@MainActor () -> Void)?
    private static let log = BoarLog.logger("voice")

    /// This iPhone has the on-device transcriber (iOS 26 SpeechTranscriber).
    static var supported: Bool { Dictation.isAvailable }

    var active: Bool { state != .idle }

    /// Starts listening; `onText` gets the composer's whole new text (the text before the mic plus the transcript).
    func start(prefix: String, onText: @escaping @MainActor (String) -> Void) {
        guard state == .idle else { return }
        error = nil
        state = .preparing
        let base = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            error = Self.message(VoiceTranscriberError.speechUnavailable)
            state = .idle
            return
        }
        let voice = (transcriber as? VoiceTranscriber) ?? VoiceTranscriber()
        transcriber = voice
        task = Task {
            // Words were heard, whether the dictation was stopped or cut short by sending.
            var heard = false
            do {
                switch await VoiceTranscriber.assetState() {
                case .unsupported:
                    throw VoiceTranscriberError.speechUnavailable
                case .downloadable, .downloading:
                    state = .installing(0)
                    try await VoiceTranscriber.installAssets { p in Task { @MainActor in if case .installing = self.state { self.state = .installing(p) } } }
                case .installed:
                    break
                }
                if Task.isCancelled { state = .idle; return }
                let updates = try await voice.startMicrophone()
                state = .listening
                for try await update in updates {
                    let spoken = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !spoken.isEmpty { heard = true }
                    onText(base.isEmpty ? spoken : spoken.isEmpty ? base : "\(base) \(spoken)")
                }
            } catch is CancellationError {
            } catch {
                self.error = Self.message(error)
                Self.log.error("dictation: \(String(describing: error), privacy: .public)")
            }
            if heard { onRecognized?() }
            state = .idle
        }
    }

    /// Ends the dictation; the last words are finalized into the text.
    func stop() {
        guard state == .listening || state == .preparing else {
            if case .installing = state { cancel() }
            return
        }
        state = .finishing
        guard #available(iOS 26.0, macOS 26.0, *), let voice = transcriber as? VoiceTranscriber else { state = .idle; return }
        Task { await voice.stop() }
    }

    /// Stops at once (the message is being sent, or the app left the foreground).
    func cancel() {
        guard active else { return }
        task?.cancel()
        if #available(iOS 26.0, macOS 26.0, *), let voice = transcriber as? VoiceTranscriber {
            Task { await voice.cancel() }
        }
        state = .idle
    }

    private static func message(_ error: Error) -> String {
        switch error as? VoiceTranscriberError {
        case .microphonePermissionDenied?: String(localized: "BOAR needs the microphone for dictation. Allow it in Settings → Privacy & Security → Microphone.")
        case .speechUnavailable?, .unsupportedLocale?: String(localized: "On-device dictation isn't available on this \(Platform.deviceNoun).")
        case .assetsUnavailable?: String(localized: "The English speech model couldn't be downloaded. Try again when online.")
        default: error.localizedDescription
        }
    }
}
