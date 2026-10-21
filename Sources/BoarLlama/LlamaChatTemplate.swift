import BoarCore
import Foundation
import llama

/// The model's chat template, applied through `llama_chat_apply_template`.
///
/// The Android build links llama.cpp's `common` library and renders the GGUF's Jinja template (`common_chat_templates_apply`).
/// The release XCFramework exposes only `llama.h`, whose `llama_chat_apply_template` recognises the well-known template families
/// (ChatML/Qwen, Llama 3, Gemma, Phi, Mistral, DeepSeek, ...) by their Jinja source, without a Jinja engine. The thinking
/// switch that `common` derives from the Jinja is reproduced here for the Qwen3 family (`enable_thinking`, `<think>` tags).
/// A template the function does not know yields `nil` from `make`, and the session reports `hasChatTemplate == false`, so the
/// answer pipeline takes its hand-built plain-prompt path.
struct LlamaChatTemplate: Sendable, Equatable {
    /// The Jinja source (the GGUF's `tokenizer.chat_template`, or the override from `EngineParams.chatTemplate`).
    let source: String
    /// `enable_thinking` changes the prompt (a hybrid model that can switch reasoning on and off).
    let supportsThinking: Bool
    let thinkingStart: String
    let thinkingEnd: [String]
    /// The Jinja source opens a `<think>` block itself in the generation prompt.
    let opensThinkBlock: Bool
    let mentionsEnableThinking: Bool

    static let closedThinkBlock = "<think>\n\n</think>\n\n"
    static let openThinkBlock = "<think>\n"

    /// nil when `source` is empty or `llama_chat_apply_template` doesn't know it.
    static func make(source: String?) -> LlamaChatTemplate? {
        guard let source, !source.isEmpty else { return nil }
        let mentionsThink = source.contains("<think>")
        let mentionsEnable = source.contains("enable_thinking")
        // In the raw Jinja a newline inside a string literal is the two characters backslash + n.
        let opens = source.contains("<think>\\n'") || source.contains("<think>\\n\"")
        let t = LlamaChatTemplate(
            source: source,
            supportsThinking: mentionsThink && mentionsEnable,
            thinkingStart: mentionsThink ? "<think>" : "",
            thinkingEnd: mentionsThink ? ["</think>"] : [],
            opensThinkBlock: mentionsThink && opens,
            mentionsEnableThinking: mentionsEnable
        )
        // Probe with a tiny chat: unknown templates answer a negative size.
        guard (try? t.apply([ChatMessage(role: .system, content: "s"), ChatMessage(role: .user, content: "u")])) != nil else { return nil }
        return t
    }

    /// The rendered prompt (generation prompt included) with the thinking switch applied.
    func format(_ messages: [ChatMessage], enableThinking: Bool) throws -> FormattedPrompt {
        var prompt = try apply(messages)
        if mentionsEnableThinking {
            // Qwen3: disabled -> an empty think block; enabled -> the model opens it (Qwen3.5+ templates open it in the prompt).
            if !enableThinking { prompt += Self.closedThinkBlock } else if opensThinkBlock { prompt += Self.openThinkBlock }
        } else if opensThinkBlock {
            // Always-thinking variants (Qwen3-Thinking-2507): the template puts `<think>` in the prompt; it can't be switched off.
            prompt += Self.openThinkBlock
        }
        return FormattedPrompt(
            prompt: prompt, supportsThinking: supportsThinking, thinkingStart: thinkingStart, thinkingEnd: thinkingEnd, stops: []
        )
    }

    /// `llama_chat_apply_template` with add_ass = true. Throws `ModelSeamError.chatTemplate`.
    func apply(_ messages: [ChatMessage]) throws -> String {
        let roles = messages.map { strdup($0.role.rawValue) }
        let contents = messages.map { strdup($0.content) }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        let chat = zip(roles, contents).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }
        let total = messages.reduce(0) { $0 + $1.role.rawValue.utf8.count + $1.content.utf8.count }
        var capacity = max(256, 2 * total + 256)
        for _ in 0..<2 {
            var buf = [CChar](repeating: 0, count: capacity)
            let n = Int(llama_chat_apply_template(source, chat, chat.count, true, &buf, Int32(capacity)))
            if n < 0 { throw ModelSeamError.chatTemplate("unsupported chat template") }
            if n <= capacity { return String(decoding: buf[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self) }
            capacity = n + 1
        }
        throw ModelSeamError.chatTemplate("template output did not fit")
    }
}
