import BoarCore
import Foundation
import Testing
@testable import BoarRemote

/// Against a real llama-server: `BOAR_REMOTE_URL=http://127.0.0.1:8199 swift test --filter RemoteSmokeTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BOAR_REMOTE_URL"] != nil))
struct RemoteSmokeTests {
    private var server: RemoteServer { RemoteServer.parse(ProcessInfo.processInfo.environment["BOAR_REMOTE_URL"] ?? "")! }

    @Test func probesAndAnswers() async throws {
        let session = try await RemoteSession.connect(server)
        #expect(!session.info.name.isEmpty)
        var text = ""
        var done: GenerationMetrics?
        let req = GenerationRequest(messages: [ChatMessage(role: .user, content: "Reply with the single word: hello")],
                                    sampling: Sampling(nPredict: 16, temperature: 0, seed: 1))
        for try await e in session.generate(req) {
            switch e {
            case .piece(let p): text += p
            case .done(let m): done = m
            }
        }
        #expect(text.lowercased().contains("hello"))
        #expect(done?.generatedTokens ?? 0 > 0)
        #expect(done?.stopReason == "stop" || done?.stopReason == "length")
        await session.close()
    }

    @Test func cancelKeepsTextAndEndsWithDone() async throws {
        let session = try await RemoteSession.connect(server)
        let req = GenerationRequest(messages: [ChatMessage(role: .user, content: "Count from 1 to 200, one number per line.")],
                                    sampling: Sampling(nPredict: 600, temperature: 0))
        var pieces = 0
        var done: GenerationMetrics?
        for try await e in session.generate(req) {
            switch e {
            case .piece:
                pieces += 1
                if pieces == 10 { session.cancel() }
            case .done(let m): done = m
            }
        }
        #expect(pieces >= 10)
        #expect(done?.stopReason == "cancelled")
        await session.close()
    }
}
