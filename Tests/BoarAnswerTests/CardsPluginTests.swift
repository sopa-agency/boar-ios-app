import BoarAnswer
import BoarCore
import BoarRAG
import Foundation
import Testing

/// android `CardsPluginTest` and `VisualPrivacyTest` (v2.0.0), which read the plugin's Kotlin source: here `CardsLab.swift`
/// and the chat files it reaches into. Differences: the row is in the answer's More menu (iOS has no 🧩 sheet); the model's
/// card runs as the chat's own job (`runForLab`) instead of a lab hold; Press doesn't take the card along yet (BOAR-55);
/// no widget or pre-Cards files ever existed on iOS, so nothing to check is gone or migrated.
struct CardsPluginTests {
    private func lab() throws -> String { try AppSource.text("App/Features/Labs/Plugins/CardsLab.swift") }

    @Test func cardsIsRegisteredAsCanvasAndStartsOn() throws {
        let src = try lab()
        #expect(src.contains("let id = \"canvas\"") && src.contains("let order = 25") && src.contains("let status = LabStatus.beta"))
        #expect(try AppSource.text("App/Features/Labs/Labs.swift").contains("            CardsLab(),\n"))
        #expect(LabDefaults.on.contains("canvas") && LabDefaults.switchOf("canvas", stored: nil))
    }

    @Test func oneRowInTheMoreMenuWhichSaysWhatTheRulesFoundBeforeTheTap() throws {
        let actions = try AppSource.slice(lab(), after: "func answerActions(_ a: AnswerRef) -> [LabAnswerAction] {", before: "    func answerExtra(")
        #expect(actions.components(separatedBy: "LabAnswerAction(").count - 1 == 4)
        #expect(actions.contains("detail: CardsModel.foundLine(cards)") && actions.contains("detail: String(localized: \"Ask BOAR to make one · slower\")"))
        // The model only from the "Nothing to draw here" row, and only when nothing holds the model.
        #expect(try lab().components(separatedBy: "model.start(").count - 1 == 1)
        #expect(actions.contains("enabled: !model.busy && !a.chatBusy) {\n            model.start(a, fallbackTitle: fallback)"))
        // The rules run off the main actor as the answer shows (validator R-E4).
        #expect(try lab().contains("await Task.detached(priority: .utility) {\n                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : CardRules.find(question, text)"))
        // The menu shows the row's second line, and a disabled row can't be chosen.
        let footer = try AppSource.text("App/Features/Chat/AnswerFooter.swift")
        #expect(footer.contains("if let detail = action.detail { Text(verbatim: detail) }") && footer.contains(".disabled(!action.enabled)"))
    }

    @Test func theCardHasItsTitleWhereItCameFromTheBodyOneSwitchAndRemoveAndNoOtherButton() throws {
        let view = try AppSource.slice(lab(), after: "struct CardView: View {", before: "/// One shape in the switch")
        #expect(view.contains("made by the model · checked against the answer") && view.contains("from this answer"))
        #expect(view.contains("if choices.count > 1 {"))
        #expect(view.components(separatedBy: "Button(").count - 1 == 1)
        // Theme tokens only.
        #expect(try !lab().contains("Color(red:") && !lab().contains("Color(hex"))
        // Under the answer's text, in the same bubble, before the footer.
        let answer = try AppSource.text("App/Features/Chat/AnswerView.swift")
        #expect(try #require(answer.range(of: "Labs.shared.answerExtras(")).lowerBound < #require(answer.range(of: "AnswerFooter(message: message")).lowerBound)
    }

    @Test func theCardAndItsTicksAreSavedWithTheAnswerInItsMeta() throws {
        let src = try lab()
        #expect(src.contains("AnswerCard.withCard($0, card)") && src.contains("AnswerCard.withTicks($0, ticks)"))
        #expect(src.contains("try s.chats.setMessageMeta(messageId: id, meta: meta)") && src.contains("AnswerCard.fromMeta(meta)"))
        // One write after another, so two quick ticks can't undo each other.
        #expect(src.contains("await previous?.value"))
    }

    @Test func theModelsCardKeepsItsGroundingCheckAndItsLeftOutLine() throws {
        let src = try lab()
        #expect(src.contains("Visual.parse($0, answer: grounding, userText: job.question)"))
        #expect(src.contains("AnswerCard.ofVisual(visual, leftOut: leftOut, fallbackTitle: job.fallbackTitle, answer: job.text)"))
        #expect(src.contains("⚠ Left out, not in the answer, the earlier answers or the sources:"))
        // Removed (✕) or erased while it was made: nothing is kept.
        #expect(src.contains("guard statuses[job.id] == .making else { return }"))
    }

    @Test func theModelsCardHoldsTheChatsModelAndTheChecklistReadsAsCheckboxes() throws {
        let src = try lab()
        #expect(src.contains("guard chat.runForLab({ [weak self] stopped in await self?.make(job, stopped: stopped) }) else {\n            statuses[id] = .failed(.busy, detail: nil, raw: nil)"))
        let chat = try AppSource.text("App/Sources/Model/ChatController.swift")
        let run = try AppSource.slice(chat, after: "func runForLab(", before: "\n    }\n")
        // The chat's job: questions wait in the queue, and the next one starts however it ended.
        #expect(run.contains("guard !modelBusy else { return false }") && run.contains("job = Task {") && run.contains("self.job = nil\n            self.runNext()"))
        // Stop reaches it: the composer's Stop, Chat ▸ Stop Answering and New Chat see it as an answer in progress; ✕ on
        // the wait line stops it; a Stop before the model starts keeps the model from starting.
        #expect(run.contains("labWorking = true") && run.contains("self.labWorking = false"))
        #expect(chat.contains("var holdsModel: Bool { isAnswering || labWorking }"))
        #expect(try AppSource.text("App/Features/Chat/ChatView.swift").contains("answering: chat.holdsModel"))
        #expect(try AppSource.text("App/Sources/Platform/BoarCommands.swift").contains("model.chat?.holdsModel"))
        #expect(src.contains("if let session, !stopped() {"))
        #expect(src.contains("Button(\"Stop\", systemImage: \"xmark\") { model.cancel(a.id) }"))
        #expect(src.contains(".accessibilityAddTraits(.isToggle)") && src.contains(".frame(minHeight: 44)"))
    }

    @Test func noHealthSeedPhraseOrToolAnswerGetsACard() throws {
        let allowed = try AppSource.slice(lab(), after: "static func allowed(_ a: AnswerRef) -> Bool {", before: "\n    }\n")
        #expect(allowed.contains("a.tool == nil && a.styleNote == nil") && allowed.contains("QueryContext.isHealthQuestion(a.question)")
            && allowed.contains("QueryContext.isSeedPhraseQuestion(a.question)"))
    }

    // MARK: android VisualPrivacyTest

    @Test func deletingAChatErasesTheCardsWithItsAnswersMeta() throws {
        let db = try SqliteDatabase.inMemory()
        _ = try KnowledgeBase(db: db)
        let store = try ChatStore(db: db)
        let s = try store.createSession(title: "t")
        try store.addMessage(sessionId: s.id, role: "user", text: "q", id: "u1")
        try store.addMessage(sessionId: s.id, role: "assistant", text: "a", id: "a1")
        let card = AnswerCard(.checklist, "T", .steps(["one", "two"]))
        let meta = try #require(AnswerCard.withTicks(AnswerCard.withCard(nil, card), [1]))
        try store.setMessageMeta(messageId: "a1", meta: meta)
        #expect(AnswerCard.fromMeta(try store.messageMeta(messageId: "a1")) != nil)
        try store.deleteSession(sessionId: s.id)
        #expect(try store.messageMeta(messageId: "a1") == nil)
    }

    @Test func noEarlierAnswerTextIsKeptOnlyTheCardAndTheEraseReachesIt() throws {
        let src = try lab()
        // The earlier answers are read from the chat when the card is made, never stored.
        #expect(!src.contains("FileManager") && !src.contains("UserDefaults"))
        #expect(src.contains("func eraseUserData(_ scope: UserDataScope) { CardsModel.shared.eraseAll() }"))
    }
}
