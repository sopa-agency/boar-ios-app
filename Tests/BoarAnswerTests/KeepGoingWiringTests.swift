import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// Android's KeepGoingOverridesTest and KeepGoingWiringTest, which read the chat's Kotlin source: here the app's Swift
/// source (the app target has no unit-test host), as `PromptQueueWiringTests` does. What needs no source is a real test
/// (`overrides…` below). Differences: the overrides are one value (`KeepGoing.Overrides`) instead of four fields, and iOS
/// has no bypassed-plugin context (android `bypassed`, AskModelContext), so `drop()` clears only what exists here.
struct KeepGoingWiringTests {
    private func source(_ path: String) throws -> String { try Fixtures.text(Fixtures.root.appending(path: path)) }
    private func controller() throws -> String { try source("App/Sources/Model/ChatController.swift") }

    /// `text` after the first `marker`, up to the next `end` (Kotlin's substringAfter().substringBefore()).
    private func slice(_ text: String, after marker: String, before end: String) throws -> String {
        let from = try #require(text.range(of: marker), Comment(rawValue: "no \(marker)")).upperBound
        let rest = text[from...]
        return String(rest[..<(rest.range(of: end)?.lowerBound ?? rest.endIndex)])
    }

    // MARK: KeepGoingOverridesTest

    /// A step sets overrides for the next question only; each is taken once and nothing stays behind.
    @Test func overridesAreTakenOnceAndLeaveNothingBehind() {
        var once = KeepGoing.Overrides.of(.research)
        once.skipTools = true
        let taken = once.take()
        #expect(taken == KeepGoing.Overrides(step: .research, deep: true, skipTools: true))
        #expect(once == KeepGoing.Overrides())
    }

    /// closing the note or opening the catalog drops every override with the held question
    @Test func dropClearsEveryOverride() {
        var once = KeepGoing.Overrides(step: .deeper, style: "detailed", deep: true, skipTools: true)
        once.drop()
        #expect(once == KeepGoing.Overrides())
    }

    /// what each step sets, and what it leaves alone
    @Test func eachStepSetsItsOwnOverrides() {
        #expect(KeepGoing.Overrides.of(.deeper) == KeepGoing.Overrides(step: .deeper, style: "detailed"))
        #expect(KeepGoing.Overrides.of(.research) == KeepGoing.Overrides(step: .research, deep: true))
        #expect(KeepGoing.Overrides.of(.ask) == KeepGoing.Overrides(step: .ask, skipTools: true))
        // Continue is its own message with no step mark and no override.
        #expect(KeepGoing.Overrides.of(.continue).style == nil && KeepGoing.Overrides.of(.continue).deep == nil)
    }

    @Test func closingTheNotePrunedQuestionAndAFailedLoadDropEveryOverride() throws {
        let c = try controller()
        for f in ["dismissLoadNote", "pruneCancel"] {
            #expect(try slice(c, after: "func \(f)() {", before: "\n    }").contains("dropOnce()"), Comment(rawValue: f))
        }
        #expect(try slice(c, after: "private func dropOnce() {", before: "\n").contains("once.drop()"))
        // Loading the model instead sends the held question with its overrides: the load doesn't drop them, only the failed
        // load does (R-A5), and only from the note's buttons.
        let load = try slice(c, after: "private func load(held:", before: "\n    }\n")
        #expect(load.components(separatedBy: "dropOnce()").count - 1 == 1)
        #expect(load.contains("if loaded, let held { self.send(held, limit: nil, fromQueue: true) }"))
        #expect(load.contains("else if !loaded, fromNote { self.dropOnce(); self.dropQueueWithNote() }"))
    }

    @Test func theBubblesHideWhileANoteIsUpWhereATapWouldDoNothing() throws {
        let conversation = try source("App/Features/Chat/ChatConversation.swift")
        #expect(conversation.contains("!chat.isAnswering, chat.queued.isEmpty, !typing, !chat.noteUp, chat.pruneNote == nil"))
        // keepGoing refuses under a note, so hiding is the only honest choice there.
        #expect(try slice(controller(), after: "func keepGoing(", before: "\n    }").contains("guard job == nil, flow.isEmpty, !noteUp"))
    }

    // MARK: KeepGoingWiringTest

    /// a step is for that answer only: the settings are not written
    @Test func aStepIsForThatAnswerOnlyTheSettingsAreNotWritten() throws {
        let c = try controller()
        let fn = try slice(c, after: "func keepGoing(", before: "\n    }")
        #expect(fn.contains("once = .of(step)") && fn.contains("askModel(answerId)"))
        #expect(!fn.contains("settings.") && !fn.contains("setDeepResearch") && !fn.contains("personalityId ="))
        #expect(c.contains("let chosenStyle = carried.style ?? settings.personalityId") && c.contains("let deepOn = carried.deep ?? deepResearch"))
        // What the step carries is taken before anything can wait.
        let answer = try slice(c, after: "private func answer(", before: "await stopBackground()")
        #expect(answer.contains("let carried = once.take()"))
    }

    /// Continue is its own message, with no step mark
    @Test func continueIsItsOwnMessageNotAStepMark() throws {
        let fn = try slice(controller(), after: "func keepGoing(", before: "\n    }")
        #expect(fn.contains("if step == .continue {\n            send(String(localized: \"Continue\"))\n            return"))
        // It is sent before any override is set: nothing is carried to it.
        #expect(try #require(fn.range(of: "send(String(localized: \"Continue\"))")).lowerBound < #require(fn.range(of: "once = .of(step)")).lowerBound)
    }

    /// the user message keeps the real question as its text, the step in its meta
    @Test func theUserMessageKeepsTheRealQuestionAsItsTextTheStepInItsMeta() throws {
        let c = try controller()
        #expect(c.contains("try s.chats.addMessage(sessionId: sid, role: \"user\", text: q, id: userId)\n                if let step = carried.step { try s.chats.setMessageMeta(messageId: userId, meta: KeepGoing.stepMeta(step)) }"))
        #expect(c.contains("ChatItem(id: userId, role: \"user\", text: q, step: carried.step)"))
        #expect(c.contains("if r.role == \"user\" { item.step = KeepGoing.step(fromMeta: r.meta) }"))
    }

    /// the bubble shows the verb, hold and VoiceOver still have the question
    @Test func theBubbleShowsTheVerbAskAgainAndVoiceOverStillHaveTheQuestion() throws {
        let b = try source("App/Features/Chat/UserBubble.swift")
        for s in ["String(localized: \"Go deeper\")", "String(localized: \"Research this\")", "String(localized: \"Ask BOAR: \\(text)\")", "case .continue, nil: text"] {
            #expect(b.contains(s), Comment(rawValue: s))
        }
        #expect(b.contains("Button(\"Ask Again\", icon: Symbols.retry, action: reuse)") && b.contains("Platform.copy(text)"))
        // Two `Text`s, not a ternary of literals (which can be typed `String` and skip the catalog).
        #expect(b.contains("shownText == text ? Text(\"You: \\(text)\") : Text(\"You: \\(shownText). \\(text)\")"))
    }

    /// iOS only (Android asks again as a new message, with no step): Try Again on the latest answer answers the saved
    /// question again, so what its step set comes back for it, or a "Research this" would run without Deep Research
    /// while the bubble still says "Research this".
    @Test func tryAgainAnswersTheSavedQuestionWithItsStepAgain() throws {
        let retry = try slice(try controller(), after: "func retry(_ answerId: String) {", before: "\n        job = Task {")
        #expect(retry.contains("once = question.step.map(KeepGoing.Overrides.of) ?? KeepGoing.Overrides()"))
    }

    /// under the latest answer only, not while answering or queued, gone with text in the field
    @Test func underTheLatestAnswerOnlyNotWhileAnsweringOrQueuedGoneWithTextInTheField() throws {
        let conversation = try source("App/Features/Chat/ChatConversation.swift")
        #expect(conversation.contains("if let last = chat.messages.last, !last.isUser, !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,"))
        let view = try source("App/Features/Chat/ChatView.swift")
        #expect(view.contains("typing: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"))
        // No "Ask BOAR instead" pill any more: it is the Ask BOAR step.
        #expect(!(try source("App/Features/Chat/AnswerView.swift")).contains("Text(\"Ask BOAR instead\")"))
        // Try Again and Allow more stay in the card.
        #expect(try source("App/Features/Chat/AnswerView.swift").contains("Allow \\(String(next)) and redo"))
    }

    @Test func theStringsAreInTheCatalogInEnglishAndPortuguese() throws {
        let catalog = try #require(JSONValue(jsonString: try source("App/Resources/Localizable.xcstrings")))
        let pt: [String: String] = [
            "Keep going": "Seguir adiante", "Keep going: what to ask next": "Seguir adiante: o que perguntar depois",
            "Go deeper": "Ir mais fundo", "Continue": "Continuar", "Research this": "Pesquisar isto", "keepgoing.ask": "Perguntar ao BOAR",
            "Ask BOAR: %@": "Perguntar ao BOAR: %@", "Quick": "Rápida", "Detailed": "Detalhada", "Research": "Pesquisa", "BOAR": "BOAR",
            "Continue: BOAR goes on from its last answer.": "Continuar: o BOAR segue a partir da última resposta.",
            "Go deeper: ask the same question again, in Detailed.": "Ir mais fundo: a mesma pergunta de novo, em Detalhada.",
            "Research this: ask the same question again, with Deep Research.": "Pesquisar isto: a mesma pergunta de novo, com a Pesquisa Profunda.",
            "Ask BOAR: the model answers this question instead of %@.": "Perguntar ao BOAR: o modelo responde esta pergunta no lugar de %@.",
            "Ask: %@": "Perguntar: %@", "You: %@. %@": "Você: %1$@. %2$@",
        ]
        for (key, value) in pt {
            #expect(catalog["strings"]?[key]?["localizations"]?["pt"]?["stringUnit"]?["value"]?.str == value, Comment(rawValue: key))
        }
        // Golden change (t9 0125 language review): PT "Seguir adiante", since "Continuar" is the Continue step under it.
        #expect(catalog["strings"]?["Keep going"]?["localizations"]?["pt"]?["stringUnit"]?["value"]?.str == "Seguir adiante")
    }
}
