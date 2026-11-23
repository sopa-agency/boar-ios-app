import Foundation
import Testing

@testable import BoarAnswer

/// Android's MessageQueueWiringTest (and FinalGateTest's Q-5 and Q-6 cases), which read the chat's Kotlin source: here they
/// read the app's Swift source the same way, since the app target has no unit-test host. The behaviours that don't need
/// the source are real tests in `PromptQueueFlowTests`. Differences: no answer notification (iOS has none; leaving the
/// screen stops the answer and the queue), and the stop-and-wait lives in `BoarServices.answers`.
struct PromptQueueWiringTests {
    private func source(_ path: String) throws -> String { try Fixtures.text(Fixtures.root.appending(path: path)) }
    private func controller() throws -> String { try source("App/Sources/Model/ChatController.swift") }
    private func composer() throws -> String { try source("App/Features/Chat/Composer.swift") }

    /// `text` after the first `marker`, up to the next `end` (Kotlin's substringAfter().substringBefore()).
    private func slice(_ text: String, after marker: String, before end: String) throws -> String {
        let from = try #require(text.range(of: marker), Comment(rawValue: "no \(marker)")).upperBound
        let rest = text[from...]
        return String(rest[..<(rest.range(of: end)?.lowerBound ?? rest.endIndex)])
    }

    /// a question sent while answering waits, at most five
    @Test func aQuestionSentWhileAnsweringWaits() throws {
        let c = try controller()
        #expect(c.contains("switch flow.admit(q, running: job != nil, fromQueue: fromQueue, behindNote: heldQuestion != nil && noteUp, noteUp: noteUp) {"))
        #expect(c.contains("case .full(let startNow):\n            toast = String(localized: \"Up to 5 questions can wait. Send this one when one of them has run.\")"))
        #expect(c.contains("PromptQueueFlow(store: .defaults("))
        // The chat's own send no longer refuses while answering.
        let view = try source("App/Features/Chat/ChatView.swift")
        let viewSend = try slice(view, after: "private func send(_ text: String) {", before: "\n    }")
        #expect(!viewSend.contains("chat.isAnswering"))
    }

    /// the next one starts however the answer ended, stopped or failed included; Stop doesn't touch the queue
    @Test func theNextOneStartsHoweverTheAnswerEnded() throws {
        let c = try controller()
        #expect(c.contains("await self.answer(q, limit: limit)\n            // However the answer ended (done, stopped, failed), the next waiting question starts.\n            self.job = nil\n            self.runNext()"))
        #expect(c.contains("await self.answer(question.text, savedQuestionId: question.id)\n            self.job = nil\n            self.runNext()"))
        // A note that holds the question isn't an answer's end: nothing starts behind it.
        let held = try slice(c, after: "self.heldQuestion = q", before: "return")
        #expect(!held.contains("runNext"))
        let next = try slice(c, after: "private func runNext() {", before: "\n    }")
        #expect(next.contains("flow.takeNext(running: job != nil)") && next.contains("send(next, limit: nil, fromQueue: true)"))
        let stop = try slice(c, after: "    func stop() {", before: "\n    }")
        #expect(!stop.contains("flow"))
    }

    /// deleting the open chat, or the PIN's erase, drops its queue
    @Test func deletingTheOpenChatOrTheErasePutsTheQueueAway() throws {
        let c = try controller()
        #expect(try slice(c, after: "func deleteSession(_ id: String) async {", before: "\n    }").contains("if sessionId == id {\n            flow.clear()\n            newChat()"))
        #expect(c.contains("if !exists {\n                flow.clear()\n                newChat()"))
        let app = try source("App/Sources/Model/AppModel.swift")
        #expect(app.contains("lock.stopAnswers = { _ = await services.answers.stopAndWait() }"))
        #expect(app.contains("services.answers.register { [weak chat] in await chat?.stopAllAndWait() ?? true }"))
    }

    /// a closed app says what it dropped
    @Test func aClosedAppSaysWhatItDropped() throws {
        let c = try controller()
        #expect(c.contains("if let n = flow.droppedAtStart() { toast = String(localized: \"BOAR was closed: \\(n) waiting questions were dropped.\") }"))
    }

    /// one button that stops or queues, resting after a send; the strip has remove, merge and Clear queue
    @Test func oneButtonThatStopsOrQueuesRestingAfterASend() throws {
        let bar = try composer()
        #expect(bar.contains("private var stops: Bool { answering && !hasText }"))
        #expect(bar.contains("Button(action: stops ? onStop : send) {"))
        #expect(bar.contains(".disabled((!answering && !hasText) || resting)"))
        #expect(bar.contains("static let sendRest = Duration.milliseconds(500)"))
        #expect(bar.contains(".opacity(resting ? 0.45 : 1)"))
        // Every send rests, on an idle chat too, the return key included (Q-6).
        #expect(bar.contains("onSend()\n        resting = true"))
        #expect(bar.contains("if hasText && !resting { send() }"))
        // The mic stays off while answering, as on Android.
        #expect(bar.contains("guard let voice, !answering else { return false }"))
        let view = try source("App/Features/Chat/ChatView.swift")
        #expect(view.contains("if !chat.queued.isEmpty { QueueStrip(chat: chat) }"))
    }

    /// each waiting row is the hourglass and its number, clear and merge are icons
    @Test func eachWaitingRowIsTheHourglassAndItsNumber() throws {
        let strip = try source("App/Features/Chat/QueueStrip.swift")
        #expect(strip.contains("Text(verbatim: \"⏳ \\(index + 1)\")"))
        #expect(strip.contains("if chat.queued.count >= 2 {") && strip.contains("Text(verbatim: \"⇉\")"))
        #expect(strip.contains("Button(action: chat.clearQueue)") && strip.contains("chat.removeQueued(prompt.id)") && strip.contains("Text(verbatim: \"✕\")"))
        #expect(try controller().contains("func mergeQueue() { flow.merge { LabTools.coHazard($0) != nil } }"))
    }

    /// strings in English and Portuguese
    @Test func stringsInEnglishAndPortuguese() throws {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Localizable.xcstrings"))) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let keys = [
            "Up to 5 questions can wait. Send this one when one of them has run.": "Até 5 perguntas podem esperar. Envie esta quando uma delas tiver rodado.",
            "BOAR was closed: %lld waiting questions were dropped.": "O BOAR foi fechado: %lld perguntas na fila foram descartadas.",
            "%lld waiting questions were dropped: they need that model too.": "%lld perguntas na fila foram descartadas: elas também precisam desse modelo.",
            "Clear queue": "Limpar fila",
            "They run one at a time, after this answer.": "Elas rodam uma de cada vez, depois desta resposta.",
            "Merge into one question": "Juntar numa só pergunta",
            "BOAR is still answering. Stop the answer, then pick %@ again.": "O BOAR ainda está respondendo. Pare a resposta e escolha %@ de novo.",
        ]
        for (en, pt) in keys {
            let entry = try #require(strings[en], Comment(rawValue: en))
            let value = (((entry["localizations"] as? [String: Any])?["pt"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value == pt, Comment(rawValue: en))
        }
    }

    /// Close BOAR, a model switch or delete, and leaving the screen clear the queue (Q-1)
    @Test func stopAllClearsTheQueue() throws {
        let c = try controller()
        #expect(try slice(c, after: "func stopAll() {", before: "\n    }").contains("flow.clear()"))
        #expect(try slice(c, after: "func stopForBackground() {", before: "\n    }").contains("stopAll()"))
        #expect(try slice(c, after: "func stopAllAndWait(", before: "\n    }").contains("stopAll()"))
    }

    /// deleting the active model, saving tweaks and starting an evaluation stop the answer first (Q-5)
    @Test func removingTheModelSavingTweaksAndEvaluatingStopTheAnswerFirst() throws {
        let models = try source("App/Features/Models/ModelsController.swift")
        let remove = try slice(models, after: "func remove(_ a: CatalogAsset) {", before: "\n    func ")
        let stop = try #require(remove.range(of: "services.answers.stopAndWait()")).lowerBound
        let unload = try #require(remove.range(of: "services.host.unload()")).lowerBound
        #expect(stop < unload)
        let use = try slice(models, after: "func use(_ a: CatalogAsset) {", before: "\n    /// Apple's")
        let useStop = try #require(use.range(of: "services.answers.stopAndWait()")).lowerBound
        let useUnload = try #require(use.range(of: "services.host.unload()")).lowerBound
        #expect(useStop < useUnload)
        let tweaks = try source("App/Features/Settings/EngineTweaksScreen.swift")
        #expect(tweaks.contains("if await answers.stopAndWait() { await host.unload() }"))
        let eval = try source("App/Features/Evaluation/EvaluationController.swift")
        #expect(eval.contains("guard await services.answers.stopAndWait() else { throw EvalError.answerStillWritten }\n                // One model in memory at a time: the chat's is reloaded on its next message.\n                await services.host.unload()"))
    }

    /// a queue behind the load note starts when the model loads, or goes with the note (Q-3); retry, redo and Ask BOAR do
    /// nothing while answering or while questions wait
    @Test func aQueueBehindTheLoadNote() throws {
        let c = try controller()
        #expect(c.contains("if loaded, let held { self.send(held, limit: nil, fromQueue: true) }"))
        #expect(c.contains("else if loaded { self.runNext() }"))
        #expect(c.contains("else { self.skipToolsOnce = false; self.dropQueueWithNote() }"))
        #expect(try slice(c, after: "func dismissLoadNote() {", before: "\n    }").contains("dropQueueWithNote()"))
        #expect(c.contains("guard job == nil, flow.isEmpty, !noteUp, let q"))
        #expect(try slice(c, after: "func redo(_ answerId: String, limit: Int) {", before: "\n    }").contains("guard job == nil"))
        #expect(try slice(c, after: "func retry(_ answerId: String) {", before: "\n        let question").contains("guard job == nil"))
    }

    /// a merged question goes to the model (Q-8)
    @Test func aMergedQuestionGoesToTheModel() throws {
        #expect(try controller().contains(".flatMap { PromptMerge.forModel($0, question: q) }"))
    }
}
