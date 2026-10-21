@preconcurrency import AVFoundation
import BoarCore
import CoreMedia
import Foundation
import Speech

/// What the composer shows while the user speaks. Both cases carry the WHOLE transcript so far, so the UI just replaces its text.
public enum VoiceTranscriptUpdate: Sendable, Equatable {
    /// Finalized text plus the current volatile guess (may still change).
    case partial(String)
    /// Text the recognizer will not revise any more (emitted whenever a segment finalizes, and once at the end).
    case final(String)

    public var text: String {
        switch self {
        case .partial(let s), .final(let s): s
        }
    }
}

/// Folds SpeechTranscriber results (volatile guesses replaced by finals) into one running transcript. Pure.
public struct TranscriptAccumulator: Sendable, Equatable {
    public private(set) var finalized = ""
    public private(set) var volatile = ""

    public init() {}

    /// The whole text: finalized + volatile, joined by one space where needed.
    public var fullText: String { Self.join(finalized, volatile) }

    public mutating func apply(text: String, isFinal: Bool) -> VoiceTranscriptUpdate {
        if isFinal {
            finalized = Self.join(finalized, text)
            volatile = ""
            return .final(finalized)
        }
        volatile = text
        return .partial(fullText)
    }

    static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines), b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}

public enum VoiceTranscriberError: Error, Equatable {
    case speechUnavailable
    case unsupportedLocale(String)
    case assetsUnavailable
    case microphonePermissionDenied
    case noCompatibleAudioFormat
    case alreadyRunning
}

/// On-device English dictation with SpeechAnalyzer + SpeechTranscriber (iOS 26). Audio never leaves the device.
///
/// ```swift
/// let voice = VoiceTranscriber()
/// if await VoiceTranscriber.assetState() != .installed { try await VoiceTranscriber.installAssets() }
/// for try await update in try await voice.startMicrophone() { composer.text = update.text }
/// // the send button: await voice.stop()  → the stream ends after a last `.final`
/// ```
/// Whether the English speech model is on the device.
public enum VoiceAssetState: Sendable, Equatable {
    case installed
    /// Supported; the model must be downloaded first (`installAssets`).
    case downloadable
    case downloading
    case unsupported
}

/// Dictation entry points that are safe to call on any OS version: before iOS 26 / macOS 26 (no SpeechAnalyzer) dictation
/// is unsupported.
public enum Dictation {
    public static var isAvailable: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        return VoiceTranscriber.isAvailable
    }

    public static func assetState() async -> VoiceAssetState {
        guard #available(iOS 26.0, macOS 26.0, *) else { return .unsupported }
        return await VoiceTranscriber.assetState()
    }

    public static func installAssets(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw VoiceTranscriberError.speechUnavailable }
        try await VoiceTranscriber.installAssets(progress: progress)
    }
}

@available(iOS 26.0, macOS 26.0, *)
public actor VoiceTranscriber {
    public typealias AssetState = VoiceAssetState

    public static let locale = Locale(identifier: "en-US")
    private static let log = BoarLog.logger("Voice")

    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    public init() {}

    public static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    static func resolvedLocale() async throws -> Locale {
        guard SpeechTranscriber.isAvailable else { throw VoiceTranscriberError.speechUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) else {
            throw VoiceTranscriberError.unsupportedLocale(Self.locale.identifier)
        }
        return locale
    }

    /// Whether the English speech model is on the device.
    public static func assetState() async -> AssetState {
        guard let locale = try? await resolvedLocale() else { return .unsupported }
        switch await AssetInventory.status(forModules: [makeTranscriber(locale)]) {
        case .installed: return .installed
        case .downloading: return .downloading
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Downloads and installs the English speech model if missing (system download, on-device afterwards). `progress` gets 0…1.
    public static func installAssets(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let locale = try await resolvedLocale()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber(locale)]) else { return }
        let watcher: Task<Void, Never>? = progress.map { report in
            Task {
                while !Task.isCancelled {
                    report(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        defer { watcher?.cancel() }
        try await request.downloadAndInstall()
        progress?(1)
    }

    // MARK: Transcription

    /// Transcribes audio the caller provides (already in a format from `SpeechAnalyzer.bestAvailableAudioFormat`).
    public func transcribe<S: AsyncSequence & Sendable>(_ inputs: S) async throws -> AsyncThrowingStream<VoiceTranscriptUpdate, Error>
    where S.Element == AnalyzerInput {
        let (transcriber, analyzer) = try await prepare(format: nil)
        let stream = results(of: transcriber)
        try await analyzer.start(inputSequence: inputs)
        return stream
    }

    /// Transcribes an audio file to the end.
    public func transcribe(fileURL: URL) async throws -> AsyncThrowingStream<VoiceTranscriptUpdate, Error> {
        let (transcriber, analyzer) = try await prepare(format: nil)
        let stream = results(of: transcriber)
        let file = try AVAudioFile(forReading: fileURL)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return stream
    }

    /// Live dictation from the microphone. Asks for record permission; call `stop()` to finish.
    public func startMicrophone() async throws -> AsyncThrowingStream<VoiceTranscriptUpdate, Error> {
        guard engine == nil else { throw VoiceTranscriberError.alreadyRunning }
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceTranscriberError.microphonePermissionDenied }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let locale = try await Self.resolvedLocale()
        let probe = Self.makeTranscriber(locale)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe]) else {
            throw VoiceTranscriberError.noCompatibleAudioFormat
        }
        let (transcriber, analyzer) = try await prepare(format: analyzerFormat, transcriber: probe)
        let stream = results(of: transcriber)

        let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let converter = BufferConverter(from: micFormat, to: analyzerFormat) else {
            throw VoiceTranscriberError.noCompatibleAudioFormat
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        try await analyzer.start(inputSequence: inputs)
        return stream
    }

    /// Ends the input, lets the recognizer finalize, then the update stream finishes after its last `.final`.
    public func stop() async {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch {
                Self.log.error("finalize failed: \(String(describing: error), privacy: .public)")
                await analyzer.cancelAndFinishNow()
            }
        }
        analyzer = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Stops at once, dropping audio not yet transcribed.
    public func cancel() async {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        resultsTask?.cancel()
    }

    private func prepare(format: AVAudioFormat?, transcriber given: SpeechTranscriber? = nil) async throws -> (SpeechTranscriber, SpeechAnalyzer) {
        guard analyzer == nil else { throw VoiceTranscriberError.alreadyRunning }
        let transcriber: SpeechTranscriber
        if let given { transcriber = given } else { transcriber = Self.makeTranscriber(try await Self.resolvedLocale()) }
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            throw VoiceTranscriberError.assetsUnavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        self.analyzer = analyzer
        return (transcriber, analyzer)
    }

    private func results(of transcriber: SpeechTranscriber) -> AsyncThrowingStream<VoiceTranscriptUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: VoiceTranscriptUpdate.self, throwing: Error.self)
        let task = Task {
            var acc = TranscriptAccumulator()
            do {
                for try await result in transcriber.results {
                    continuation.yield(acc.apply(text: String(result.text.characters), isFinal: result.isFinal))
                }
                if !acc.volatile.isEmpty { continuation.yield(acc.apply(text: acc.volatile, isFinal: true)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        resultsTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

/// Microphone buffers → the analyzer's format (runs on the audio thread; AVAudioConverter is used from that thread only).
@available(iOS 26.0, macOS 26.0, *)
final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init?(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.target = target
        if source == target {
            converter = nil
        } else {
            guard let c = AVAudioConverter(from: source, to: target) else { return nil }
            converter = c
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed { inputStatus.pointee = .noDataNow; return nil }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }
}
