import Foundation
import Testing

/// Lunar, Nomad and Vitals answer in the chat, and a plugin that's off but would have answered is named under the answer
/// (android rc3 7286cf91, bd041e73), read from the Swift source (the app target has no unit-test host).
struct PluginAnswersWiringTests {
    private let store = try! AppSource.text("App/Features/Labs/Labs.swift")
    private let chat = try! AppSource.text("App/Sources/Model/ChatController.swift")
    private let answer = try! AppSource.text("App/Features/Chat/AnswerView.swift")

    @Test func eachPluginAnswersItsQuestionWithItsToolCode() throws {
        for (file, check, code) in [("LunarLab", "isMoonQuestion", "lunar-phase"), ("CompassLab", "isDirectionQuestion", "compass-heading"),
                                    ("VitalsLab", "isPhoneQuestion", "vitals-phone")] {
            let src = try AppSource.text("App/Features/Labs/Plugins/\(file).swift")
            #expect(src.contains("func recognizes(_ query: String) -> Bool { PluginAnswers.\(check)(query) }"), "\(file)")
            #expect(src.contains("var answerTool: (any AnswerTool)? { Tool() }") && src.contains("\"\(code)\""), "\(file)")
        }
        // The answer speaks as the plugin.
        for (prefix, id) in [("lunar-", "lunar"), ("compass-", "compass"), ("vitals-", "pulse")] {
            #expect(store.contains("code.hasPrefix(\"\(prefix)\"): \"\(id)\""), "\(prefix)")
        }
    }

    @Test func theDeviceIsReadBeforeTheToolsRun() throws {
        let prepare = try #require(chat.range(of: "await PhoneReads.prepare(query: q"))
        let tools = try #require(chat.range(of: "Labs.shared.activeTools, query: q"))
        #expect(prepare.lowerBound < tools.lowerBound)
    }

    @Test func anOffPluginIsNamedUnderAModelAnswerOnly() throws {
        let off = try AppSource.slice(store, after: "func offPlugin(_ query: String)", before: "\n    }\n")
        #expect(off.contains("guard labsOn") && off.contains("!enabled($0.id) && $0.recognizes(query)"))
        #expect(chat.contains("messages[i].offPlugin = instant == nil && !stopped ? Labs.shared.offPlugin(q) : nil"))
        #expect(answer.contains("if !streaming, let id = message.offPlugin") && answer.contains("is off. Turn it on in Plugins ›"))
    }
}
