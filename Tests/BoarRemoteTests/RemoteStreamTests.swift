import BoarCore
import Foundation
import Testing
@testable import BoarRemote

@Suite struct RemoteStreamTests {
    @Test func parsesAddresses() {
        #expect(RemoteServer.parse("mac-mini.local")?.baseURL.absoluteString == "http://mac-mini.local:8080")
        #expect(RemoteServer.parse(" 192.168.0.20:8191 ")?.displayName == "192.168.0.20:8191")
        #expect(RemoteServer.parse("http://host:9000/v1/")?.baseURL.absoluteString == "http://host:9000")
        #expect(RemoteServer.parse("") == nil)
        #expect(RemoteServer.parse("ftp://host") == nil)
    }

    @Test func chatBodyCarriesSamplingAndThinking() throws {
        let req = GenerationRequest(messages: [ChatMessage(role: .system, content: "s"), ChatMessage(role: .user, content: "q")],
                                    sampling: Sampling(nPredict: 300, temperature: 0.2, stops: ["\nUser:"]), enableThinking: true)
        let (path, o) = RemoteStream.body(for: req)
        #expect(path == "v1/chat/completions")
        #expect(o["max_tokens"] as? Int == 300)
        #expect((o["messages"] as? [[String: String]])?.last?["content"] == "q")
        #expect((o["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"] == true)
        #expect(o["stop"] as? [String] == ["\nUser:"])
        #expect(o["seed"] == nil)
    }

    @Test func promptBodyUsesCompletion() {
        let (path, o) = RemoteStream.body(for: GenerationRequest(prompt: "Q: hi\nA:", sampling: Sampling(nPredict: 50)))
        #expect(path == "completion")
        #expect(o["n_predict"] as? Int == 50)
    }

    @Test func parsesChatChunks() {
        let piece = RemoteStream.parse(line: #"data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"#)
        #expect(piece?.text == "Hel")
        #expect(piece?.finishReason == nil)
        let last = RemoteStream.parse(line: #"data: {"choices":[{"delta":{},"finish_reason":"length"}],"timings":{"prompt_n":120,"prompt_ms":300.5,"predicted_n":40,"predicted_ms":2000,"prompt_per_second":399.3,"predicted_per_second":20}}"#)
        #expect(last?.finishReason == "length")
        #expect(last?.timings?.predictedTokens == 40)
        #expect(RemoteStream.parse(line: "data: [DONE]") == nil)
        #expect(RemoteStream.parse(line: ": keep-alive") == nil)
    }

    @Test func parsesCompletionChunks() {
        #expect(RemoteStream.parse(line: #"data: {"content":" world","stop":false}"#)?.text == " world")
        #expect(RemoteStream.parse(line: #"data: {"content":"","stop":true,"stop_type":"eos"}"#)?.finishReason == "stop")
    }

    @Test func metricsMapStopReasons() {
        let now = ContinuousClock.now
        #expect(RemoteSession.metrics(start: now, firstPiece: now, pieces: 3, finish: "stop", timings: nil).stopReason == "stop")
        #expect(RemoteSession.metrics(start: now, firstPiece: nil, pieces: 0, finish: "cancelled", timings: nil).stopReason == "cancelled")
        #expect(RemoteSession.metrics(start: now, firstPiece: now, pieces: 3, finish: "length", timings: nil).generatedTokens == 3)
    }
}
