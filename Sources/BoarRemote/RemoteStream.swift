import BoarCore
import Foundation

/// The request bodies BOAR sends to llama-server and the streamed chunks it reads back, kept pure so tests can run them
/// without a server.
public enum RemoteStream {
    /// `POST /v1/chat/completions` (messages) or `POST /completion` (a finished prompt).
    public static func body(for request: GenerationRequest) -> (path: String, json: [String: Any]) {
        let s = request.sampling
        var o: [String: Any] = [
            "stream": true,
            "temperature": Double(s.temperature),
            "top_k": s.topK,
            "top_p": Double(s.topP),
            "min_p": Double(s.minP),
            "repeat_penalty": Double(s.repeatPenalty),
        ]
        if s.seed >= 0 { o["seed"] = s.seed }
        if !s.stops.isEmpty { o["stop"] = s.stops }
        switch request.input {
        case .messages(let messages):
            o["messages"] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            o["max_tokens"] = s.nPredict
            // The reasoning stays inline in <think> tags, as on the phone, so the answer view splits it the same way.
            o["reasoning_format"] = "none"
            o["chat_template_kwargs"] = ["enable_thinking": request.enableThinking]
            return ("v1/chat/completions", o)
        case .prompt(let prompt):
            o["prompt"] = prompt
            o["n_predict"] = s.nPredict
            return ("completion", o)
        }
    }

    /// One `data:` payload of the stream.
    public struct Chunk: Equatable, Sendable {
        public var text: String = ""
        /// "stop" or "length" on the last chunk.
        public var finishReason: String?
        public var timings: Timings?
    }

    /// llama-server's `timings` object (last chunk).
    public struct Timings: Equatable, Sendable {
        public var promptTokens: Int
        public var promptMs: Double
        public var predictedTokens: Int
        public var predictedMs: Double
        public var promptPerSecond: Double
        public var predictedPerSecond: Double
    }

    /// Reads one line of the event stream; nil for comments, keep-alives and `[DONE]`.
    public static func parse(line: String) -> Chunk? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var chunk = Chunk()
        if let choice = (o["choices"] as? [[String: Any]])?.first {
            // Chat completions.
            chunk.text = (choice["delta"] as? [String: Any])?["content"] as? String ?? ""
            chunk.finishReason = choice["finish_reason"] as? String
        } else {
            // /completion.
            chunk.text = o["content"] as? String ?? ""
            if o["stop"] as? Bool == true {
                chunk.finishReason = (o["stop_type"] as? String) == "limit" || o["truncated"] as? Bool == true ? "length" : "stop"
            }
        }
        if let t = o["timings"] as? [String: Any] {
            chunk.timings = Timings(
                promptTokens: t["prompt_n"] as? Int ?? 0, promptMs: t["prompt_ms"] as? Double ?? 0,
                predictedTokens: t["predicted_n"] as? Int ?? 0, predictedMs: t["predicted_ms"] as? Double ?? 0,
                promptPerSecond: t["prompt_per_second"] as? Double ?? 0, predictedPerSecond: t["predicted_per_second"] as? Double ?? 0)
        }
        return chunk
    }
}
