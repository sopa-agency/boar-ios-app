import Foundation
import Testing

@testable import BoarAnswer

/// android InstantTypingTest (rc3 bd041e73).
struct InstantTypingTests {
    @Test func typedAtAbout80CharactersASecondTheWholeTextWithinSixSeconds() {
        let text = "About 2 hours: 120 miles ÷ 60 miles per hour = 2 hours. Computed from the numbers in your question."
        let p = InstantTyping.pieces(text)
        #expect(p.joined() == text)
        let seconds = Double(p.count * InstantTyping.stepMs) / 1000
        #expect((1.0...1.5).contains(seconds), "\(seconds)")
        #expect(InstantTyping.pieces(String(repeating: "x", count: 5000)).count * InstantTyping.stepMs <= InstantTyping.maxMs)
    }

    @Test func aPieceNeverEndsInsideAnEmoji() {
        let text = String(repeating: "🌑🌒🌓", count: 40)
        let p = InstantTyping.pieces(text)
        #expect(p.joined() == text)
        #expect(p.allSatisfy { $0.unicodeScalars.allSatisfy { $0.value != 0xFFFD } && !$0.isEmpty })
        #expect(InstantTyping.pieces("").isEmpty)
    }

    @Test func theSafetyAnswerAnimationsOffAndAScreenReaderShowItAtOnce() {
        #expect(!InstantTyping.typed(tool: "safety-fact-co-hazard", animationsOff: false, screenReader: false))
        #expect(!InstantTyping.typed(tool: "calculator-rate-time", animationsOff: true, screenReader: false))
        #expect(!InstantTyping.typed(tool: "calculator-rate-time", animationsOff: false, screenReader: true))
        #expect(InstantTyping.typed(tool: "lunar-phase", animationsOff: false, screenReader: false))
    }

    /// android: the chat types it, a tap skips, the receipt keeps the real time and says instant (the app has no test host, so
    /// this reads its source).
    @Test func theChatTypesItATapSkipsTheReceiptKeepsTheRealTimeAndSaysInstant() throws {
        let ctl = try AppSource.text("App/Sources/Model/ChatController.swift")
        #expect(ctl.contains("for piece in InstantTyping.pieces(instant)"))
        #expect(ctl.contains("skipTyping || stopFlag.value"))
        // Stop shows the rest at once, as a tap does: the answer is already whole, the typing only presents it (android
        // `if (skipTyping || stopRequested) onPiece(rest(...))`), so it's never saved cut short.
        let typing = try AppSource.slice(ctl, after: "for piece in InstantTyping.pieces(instant)", before: "throw InstantAnswer()")
        #expect(!typing.contains("!stopFlag.value"))
        #expect(typing.contains("if shownLen < instant.count { onPiece(String(instant.dropFirst(shownLen))) }"))
        #expect(ctl.contains("instantAt"))
        let details = try AppSource.text("App/Features/Chat/ReceiptDetails.swift")
        #expect(details.contains("receipt.instant"))
        #expect(try AppSource.portuguese("instant") == "instantâneo")
        let answer = try AppSource.text("App/Features/Chat/AnswerView.swift")
        #expect(answer.contains("chat.skipInstantTyping()"))
    }
}
