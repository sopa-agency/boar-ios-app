import Testing
@testable import BoarCore

/// android `engine/settings/AnswerLimit.kt` (Android has no test for it).
struct AnswerLimitTests {
    /// personalities.json's lengths.
    let options = [256, 512, 1024, 2048]

    @Test func reachedCountsATokenOrTwoShort() {
        #expect(AnswerLimit.reached(generated: 1024, limit: 1024))
        #expect(AnswerLimit.reached(generated: 1022, limit: 1024))
        #expect(!AnswerLimit.reached(generated: 1021, limit: 1024))
        #expect(AnswerLimit.reached(generated: 1030, limit: 1024))
    }

    @Test func noLimitIsNeverReached() {
        #expect(!AnswerLimit.reached(generated: 5000, limit: 0))
        #expect(!AnswerLimit.reached(generated: 0, limit: -1))
    }

    @Test func nextIsTheNextLengthUp() {
        #expect(AnswerLimit.next(after: 512, options: options, openedContext: nil) == 1024)
        #expect(AnswerLimit.next(after: 300, options: [2048, 256, 1024, 512], openedContext: nil) == 512)
        #expect(AnswerLimit.next(after: 2048, options: options, openedContext: nil) == nil)
    }

    @Test func nextLeavesRoomForThePrompt() {
        // 4096 - 1500 = 2596: 2048 still fits.
        #expect(AnswerLimit.next(after: 1024, options: options, openedContext: 4096) == 2048)
        // 3000 - 1500 = 1500: 2048 doesn't.
        #expect(AnswerLimit.next(after: 1024, options: options, openedContext: 3000) == nil)
        #expect(AnswerLimit.next(after: 512, options: options, openedContext: 2524) == 1024)
        #expect(AnswerLimit.next(after: 512, options: options, openedContext: 2523) == nil)
    }
}
