import Dispatch
import Foundation
import Synchronization
import Testing

@testable import BoarAnswer

/// Android rc3's prompt queue (BOAR-48): PromptQueueTest, the queue and merge cases of RegateDeltaTest (M-1, M-2, Q-9) and
/// FinalGateTest (Q-1b, Q-8, Q-9), and CoMergeOrdersTest. The cases are the same ones; the Kotlin names are in the
/// comments. RegateDeltaTest's compass and unit-bridge cases and FinalGateTest's Designer, settings and emoji cases are
/// not this feature (see `PromptQueueWiringTests` for the cases that read the chat's source).
struct PromptQueueTests {
    // PromptQueueTest

    @Test func questionsRunInTheOrderTheyWereSent() {
        let q = PromptQueue()
        q.add("one"); q.add("two"); q.add("three")
        #expect(Array(sequence(state: (), next: { _ in q.next()?.text })) == ["one", "two", "three"])
        #expect(q.next() == nil)
    }

    @Test func atMostFiveWaitABlankOneNever() {
        let q = PromptQueue()
        for i in 0..<5 { #expect(q.add("q\(i)")) }
        #expect(!q.add("sixth"))
        #expect(!PromptQueue().add("   "))
        #expect(q.size == 5)
    }

    @Test func oneCanBeRemovedAndClearQueueEmptiesIt() {
        let q = PromptQueue()
        q.add("a"); q.add("b"); q.add("c")
        #expect(q.remove(q.waiting[1].id))
        #expect(q.waiting.map(\.text) == ["a", "c"])
        q.clear()
        #expect(q.isEmpty)
    }

    @Test func aRemovedSlotFreesRoomForAnother() {
        let q = PromptQueue(limit: 2)
        q.add("a"); q.add("b")
        #expect(!q.add("c"))
        _ = q.next()
        #expect(q.add("c"))
        #expect(q.waiting.map(\.text) == ["b", "c"])
    }

    @Test func aQuestionTakenOffGoesBackToTheFrontNotTheEnd() throws {
        let q = PromptQueue()
        q.add("a"); q.add("b"); q.add("c")
        let first = try #require(q.next())
        q.pushFront(first)
        #expect(q.waiting.map(\.text) == ["a", "b", "c"])
    }

    @Test func mergeTurnsTheWaitingQuestionsIntoOneNumberedInTheirLanguage() throws {
        let q = PromptQueue()
        q.add("Why is the sky blue?"); q.add("How far is the sun?"); q.add("What is a nebula?")
        #expect(q.merge())
        let one = try #require(q.waiting.first).text
        #expect(q.waiting.count == 1)
        #expect(one.hasPrefix("Answer these questions together") && one.contains("1. Why is the sky blue?") && one.contains("3. What is a nebula?"), "\(one)")
        #expect(!q.merge())
        #expect(PromptMerge.of(["Por que o céu é azul?", "Qual a distância até o sol?"]).hasPrefix("Responda a estas perguntas juntas"))
    }

    // RegateDeltaTest

    private let co = "Can I run my portable generator in the attached garage if I keep the door open?"
    private let coPt = "Posso usar o gerador na garagem fechada?"
    private func isSafety(_ s: String) -> Bool { LabTools.coHazard(s) != nil }

    /// a safety question is never merged, in English or mixed with Portuguese (M-1, M-2)
    @Test func aSafetyQuestionIsNeverMerged() {
        #expect(LabTools.coHazard(co) != nil)
        for others in [["What is the capital of Peru?", "Quantos habitantes tem Portugal?"], ["Qual a capital do Brasil?", "Who was Napoleon?"]] {
            let q = PromptQueue()
            q.add(co); others.forEach { q.add($0) }
            #expect(q.merge(keepApart: isSafety))
            let left = q.waiting.map(\.text)
            #expect(left[0] == co)  // its own turn, first, unchanged: the card answers it
            #expect(left.count == 2)
            #expect(PromptMerge.isMerged(left[1]) && LabTools.coHazard(left[1]) == nil)
        }
        // A safety question and one other: nothing to merge.
        let q = PromptQueue(); q.add(co); q.add("Who was Napoleon?")
        #expect(!q.merge(keepApart: isSafety))
        #expect(q.waiting.count == 2)
        if LabTools.coHazard(coPt) != nil {
            let p = PromptQueue(); p.add("a?"); p.add(coPt); p.add("b?")
            #expect(p.merge(keepApart: isSafety))
            #expect(p.waiting[0].text == coPt)
        }
    }

    /// a Portuguese pair gets the Portuguese head (Q-9 tie)
    @Test func aPortuguesePairGetsThePortugueseHead() {
        #expect(PromptMerge.of(["Quantos habitantes tem Portugal?", "Qual a capital do Brasil?"]).hasPrefix("Responda a estas perguntas"))
        #expect(PromptMerge.of(["What is the capital of Peru?", "Who was Napoleon?"]).hasPrefix("Answer these questions"))
    }

    // CoMergeOrdersTest

    private let harmlessEn = ["What is the capital of Peru?", "Who was Napoleon?"]
    private let harmlessPt = ["Qual a capital do Brasil?", "Quantos habitantes tem Portugal?"]

    private func mergeOf(_ qs: [String]) -> [String] {
        let q = PromptQueue()
        qs.forEach { q.add($0) }
        q.merge(keepApart: isSafety)
        return q.waiting.map(\.text)
    }

    /// the validator's mixed cases and every order keep the CO question as its own turn (M-1, M-2)
    @Test func everyOrderKeepsTheCoQuestionAsItsOwnTurn() {
        let cases: [[String]] = [
            [co, harmlessPt[0]], [harmlessPt[0], co, harmlessPt[1]], [co, harmlessEn[0], harmlessPt[0]],
            [co] + harmlessEn, harmlessEn + [co], [harmlessEn[0], co, harmlessEn[1]],
            [co] + harmlessPt, harmlessPt + [co], [harmlessPt[0], co, harmlessPt[1]],
        ]
        for c in cases {
            let left = mergeOf(c)
            #expect(left.first == co, "\(c)")
            #expect(left.dropFirst().allSatisfy { !(LabTools.coHazard($0) != nil && $0 == co) }, "\(c)")
            let others = c.filter { $0 != co }
            #expect(left.count == (others.count >= 2 ? 2 : c.count), "\(c)")
        }
    }

    /// a merged text that still matches is told to state the card first
    @Test func aMergedTextThatStillMatchesIsToldToStateTheCardFirst() {
        let ctx = PromptMerge.safetyContext("Carbon monoxide can kill.")
        #expect(ctx.hasPrefix("SAFETY WARNING. Start your answer with this warning, word for word") && ctx.hasSuffix("Carbon monoxide can kill."))
    }

    // FinalGateTest

    /// the queue takes a clear from another thread (Q-1b). Kotlin counted exceptions; here a torn list would crash or break
    /// the limit, so the sizes seen are checked too.
    @Test func theQueueTakesAClearFromAnotherThread() {
        let q = PromptQueue(limit: 1000)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            for _ in 0..<20_000 { q.clear() }
            done.signal()
        }
        thread.start()
        var outOfRange = 0
        for _ in 0..<20_000 {
            q.add("a")
            _ = q.next()
            if !(0...1000).contains(q.waiting.count) { outOfRange += 1 }
        }
        done.wait()
        #expect(outOfRange == 0)
        #expect(q.size >= 0)
    }

    /// a merged question goes to the model, a safety card is read by it (Q-8)
    @Test func aMergedQuestionGoesToTheModelASafetyCardIsReadByIt() {
        let m = PromptMerge.of(["my heater smells, is it carbon monoxide?", "capital of Peru"])
        #expect(PromptMerge.isMerged(m))
        #expect(!PromptMerge.isMerged("capital of Peru"))
        // The chat's send: an instant answer to a merged text is dropped, or kept as context when it is a safety card.
        #expect(PromptMerge.forModel(.instant(tool: "calculator-battery", text: "42"), question: m) == nil)
        #expect(PromptMerge.forModel(.instant(tool: "safety-fact-co-hazard", text: "Never run it indoors."), question: m)
            == .context(tool: "safety-fact-co-hazard", text: PromptMerge.safetyContext("Never run it indoors.")))
        // Asked alone, the answers stay as they are; a context is never touched.
        let instant = ToolResult.instant(tool: "safety-fact-co-hazard", text: "Never run it indoors.")
        #expect(PromptMerge.forModel(instant, question: "capital of Peru") == instant)
        let context = ToolResult.context(tool: "guard", text: "x")
        #expect(PromptMerge.forModel(context, question: m) == context)
    }

    /// merging twice keeps one list, Spanish gets a Spanish head (Q-9)
    @Test func mergingTwiceKeepsOneListSpanishGetsASpanishHead() {
        let once = PromptMerge.of(["a?", "b?"])
        let twice = PromptMerge.of([once, "c?", "d?"])
        #expect(PromptMerge.parts(twice) == ["a?", "b?", "c?", "d?"])
        #expect(twice.ranges(of: "Answer these questions").count == 1)
        #expect(PromptMerge.of(["¿Cuál es la capital de Perú?", "¿Dónde está Lima?"]).hasPrefix("Responde a estas preguntas"))
    }
}

/// The chat's queue decisions (PromptQueueFlow), the behaviours MessageQueueWiringTest reads from Android's ChatViewModel
/// source, here as running code.
@MainActor
struct PromptQueueFlowTests {
    private final class Count: Sendable {
        let n = Mutex(0)
    }

    private func flow(_ count: Count = Count()) -> PromptQueueFlow {
        PromptQueueFlow(store: QueueCountStore(read: { count.n.withLock { $0 } }, write: { v in count.n.withLock { $0 = v } }))
    }

    /// a question sent while answering waits, at most five
    @Test func aQuestionSentWhileAnsweringWaitsAtMostFive() {
        let f = flow()
        for i in 0..<5 { #expect(f.admit("q\(i)", running: true, fromQueue: false, behindNote: false, noteUp: false) == .queued(startNow: false)) }
        #expect(f.admit("sixth", running: true, fromQueue: false, behindNote: false, noteUp: false) == .full(startNow: false))
        #expect(f.waiting.count == 5)
        // Nothing runs and nothing waits: it runs now, and is not queued.
        let idle = flow()
        #expect(idle.admit("go", running: false, fromQueue: false, behindNote: false, noteUp: false) == .start)
        #expect(idle.isEmpty)
    }

    /// the next one starts however the answer ended; a question sent once the queue has started waits its turn (Q-2)
    @Test func theNextWaitingQuestionRunsFirstAndNothingJumpsIt() {
        let f = flow()
        _ = f.admit("one", running: true, fromQueue: false, behindNote: false, noteUp: false)
        _ = f.admit("two", running: true, fromQueue: false, behindNote: false, noteUp: false)
        // The answer ended: nothing runs, but two wait. A typed question joins the end, it doesn't start.
        #expect(f.admit("three", running: false, fromQueue: false, behindNote: false, noteUp: false) == .queued(startNow: true))
        #expect(f.takeNext(running: false) == "one")
        // The queue starting its own question doesn't queue it again.
        #expect(f.admit("one", running: false, fromQueue: true, behindNote: false, noteUp: false) == .start)
        #expect(f.waiting.map(\.text) == ["two", "three"])
    }

    /// something started meanwhile: the question goes back to the front, not the end
    @Test func aQuestionTakenWhileSomethingRunsGoesBackToTheFront() {
        let f = flow()
        for q in ["a", "b", "c"] { _ = f.admit(q, running: true, fromQueue: false, behindNote: false, noteUp: false) }
        #expect(f.takeNext(running: true) == nil)
        #expect(f.waiting.map(\.text) == ["a", "b", "c"])
        #expect(f.takeNext(running: false) == "a")
        #expect(f.takeNext(running: false) == "b")
        #expect(f.takeNext(running: false) == "c")
        #expect(f.takeNext(running: false) == nil)
    }

    /// a queue behind the load note starts when the model loads, or goes with the note (Q-3, Q-4)
    @Test func aQuestionBehindTheLoadNoteWaitsAndStartsOrGoesWithIt() {
        let f = flow()
        // A held question waits for the note: this one waits behind it, and nothing starts while the note is up.
        #expect(f.admit("second", running: false, fromQueue: false, behindNote: true, noteUp: true) == .queued(startNow: false))
        #expect(f.admit("third", running: false, fromQueue: false, behindNote: true, noteUp: true) == .queued(startNow: false))
        // The note was answered and nothing runs: the oldest waiting one starts now.
        #expect(f.admit("fourth", running: false, fromQueue: false, behindNote: false, noteUp: false) == .queued(startNow: true))
        // The note closed, or the model didn't load: they go, said once with their number.
        #expect(f.dropWithNote() == 3)
        #expect(f.dropWithNote() == nil)
        #expect(f.isEmpty)
    }

    /// Stop-all, a deleted open chat and the PIN's erase clear it; Clear queue and ✕ too
    @Test func clearRemoveAndMerge() throws {
        let f = flow()
        for q in ["a?", "b?", "c?"] { _ = f.admit(q, running: true, fromQueue: false, behindNote: false, noteUp: false) }
        f.remove(f.waiting[1].id)
        #expect(f.waiting.map(\.text) == ["a?", "c?"])
        f.merge { _ in false }
        let one = try #require(f.waiting.first)
        #expect(f.waiting.count == 1 && PromptMerge.isMerged(one.text))
        f.clear()
        #expect(f.isEmpty)
    }

    /// the queue on screen, and its size kept so a closed app can say what it dropped
    @Test func aClosedAppSaysWhatItDropped() {
        let count = Count()
        let before = flow(count)
        #expect(before.droppedAtStart() == nil)
        _ = before.admit("a", running: true, fromQueue: false, behindNote: false, noteUp: false)
        _ = before.admit("b", running: true, fromQueue: false, behindNote: false, noteUp: false)
        #expect(count.n.withLock { $0 } == 2)
        // The app is closed here; the next start finds the count, says it once, and starts from nothing.
        let after = flow(count)
        #expect(after.droppedAtStart() == 2)
        #expect(after.droppedAtStart() == nil)
        // A queue that ran out (or was cleared) leaves nothing to report.
        _ = after.admit("c", running: true, fromQueue: false, behindNote: false, noteUp: false)
        after.clear()
        #expect(flow(count).droppedAtStart() == nil)
    }

    @Test func theChatIsToldWhenTheQueueChanges() {
        let f = flow()
        var seen: [Int] = []
        f.onChange = { seen.append(f.waiting.count) }
        _ = f.admit("a", running: true, fromQueue: false, behindNote: false, noteUp: false)
        _ = f.admit("b", running: true, fromQueue: false, behindNote: false, noteUp: false)
        _ = f.takeNext(running: false)
        f.clear()
        #expect(seen == [1, 2, 1, 0])
    }
}
