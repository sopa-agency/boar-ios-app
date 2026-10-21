import BoarCore
import BoarRAG
import Foundation

/// One generation: role messages for the model's chat template, or a plain prompt with stop words. `timeoutMs`: stop the
/// generation after this long and keep what it wrote (`EngineTweaks.stageTimeoutMs`), nil for none.
public struct GenRequest: Sendable, Equatable {
    public var messages: [PromptMessage]?
    public var prompt: String?
    public var nPredict: Int
    public var temperature: Float
    public var stops: [String]
    public var timeoutMs: Int64?

    public init(messages: [PromptMessage]?, prompt: String?, nPredict: Int, temperature: Float, stops: [String], timeoutMs: Int64? = nil) {
        self.messages = messages; self.prompt = prompt; self.nPredict = nPredict
        self.temperature = temperature; self.stops = stops; self.timeoutMs = timeoutMs
    }
}

public struct GenResult: Sendable, Equatable {
    public var text: String
    public var metrics: GenerationMetrics?
    public var timedOut: Bool
    public init(text: String, metrics: GenerationMetrics? = nil, timedOut: Bool = false) {
        self.text = text; self.metrics = metrics; self.timedOut = timedOut
    }
}

/// A loaded model as the plan executor uses it.
public protocol StepEngine: Sendable {
    var hasChatTemplate: Bool { get }
    func generate(_ request: GenRequest, onToken: (@Sendable (String) -> Void)?) async throws -> GenResult
}

/// One instruction-style generation: system + user in the model's chat template, or a plain prompt ending in "Answer:" for a
/// model without one (src/inference/format.ts taskRequest). Returns the text; `onToken` streams it.
public protocol StageGenerator: Sendable {
    /// Generates within `timeoutMs` (nil: no limit); on timeout it returns what was written and reports it through `GenResult.timedOut`.
    func generate(
        system: String, user: String, nPredict: Int, temperature: Float, timeoutMs: Int64?, onToken: (@Sendable (String) -> Void)?
    ) async throws -> GenResult
}

/// A `StageGenerator` from a closure (tests, previews, or an app-side model).
public struct ClosureStageGenerator: StageGenerator {
    public typealias Body = @Sendable (String, String, Int, Float, Int64?, (@Sendable (String) -> Void)?) async throws -> GenResult
    private let body: Body
    public init(_ body: @escaping Body) { self.body = body }
    public func generate(
        system: String, user: String, nPredict: Int, temperature: Float, timeoutMs: Int64?, onToken: (@Sendable (String) -> Void)?
    ) async throws -> GenResult {
        try await body(system, user, nPredict, temperature, timeoutMs, onToken)
    }
}

/// Which model is resident, and loading one by catalog id (nil when it isn't installed). The app implements this over its
/// session manager; calls are `async` so an actor can.
public protocol ModelHost: Sendable {
    func residentFilename() async -> String?
    func filenameOf(_ modelId: String) async -> String?
    func load(_ modelId: String) async throws -> (any StepEngine)?
}

/// A loaded model as the executor and Deep Research use it: role messages through the model's own chat template (or a
/// plain prompt with stop words), and a time limit that stops the native generation and keeps what it wrote.
public struct SessionEngine: StepEngine, StageGenerator {
    public let session: any TextModelSession
    public let enableThinking: Bool

    public init(_ session: any TextModelSession, enableThinking: Bool = false) {
        self.session = session; self.enableThinking = enableThinking
    }

    public var hasChatTemplate: Bool { session.capabilities.hasChatTemplate }

    public func generate(_ request: GenRequest, onToken: (@Sendable (String) -> Void)?) async throws -> GenResult {
        // The user's thinking tweak (off by default), as on the default path.
        let input: GenerationRequest.Input
        if let messages = request.messages {
            input = .messages(messages.map { ChatMessage(role: $0.role, content: $0.content) })
        } else {
            input = .prompt(request.prompt ?? "")
        }
        let sampling = Sampling(nPredict: request.nPredict, temperature: request.temperature, stops: request.stops)
        let out = try await session.generateText(
            GenerationRequest(input: input, sampling: sampling, enableThinking: enableThinking), timeoutMs: request.timeoutMs, onPiece: onToken
        )
        return GenResult(text: out.text, metrics: out.metrics, timedOut: out.timedOut)
    }

    /// taskRequest: system + user messages with a template, else "instruction\n\ninput\n\nAnswer:" (src/inference/format.ts).
    public func generate(
        system: String, user: String, nPredict: Int, temperature: Float, timeoutMs: Int64?, onToken: (@Sendable (String) -> Void)?
    ) async throws -> GenResult {
        if hasChatTemplate {
            return try await generate(
                GenRequest(
                    messages: [PromptMessage(role: "system", content: system), PromptMessage(role: "user", content: user)], prompt: nil,
                    nPredict: nPredict, temperature: temperature, stops: [], timeoutMs: timeoutMs
                ), onToken: onToken
            )
        }
        return try await generate(
            GenRequest(
                messages: nil, prompt: "\(system)\n\n\(user)\n\nAnswer:", nPredict: nPredict, temperature: temperature,
                stops: AnswerStopSequences.plain, timeoutMs: timeoutMs
            ), onToken: onToken
        )
    }
}
