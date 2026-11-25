import Testing
@testable import BoarCore

/// Android AvatarStripTest: Boar Avatars merged into Display & theme, a few avatars and a last box that opens them all.
@Suite struct AvatarStripTests {
    let known = ["a", "b", "c", "d", "e", "f"]

    @Test func thePlainBoarTheOneWornThenTheLatestFourInAll() {
        let unlocked: [String: Int64] = ["a": 1, "b": 5, "c": 3, "d": 9, "e": 7]
        #expect(AvatarStrip.pick(unlocked: unlocked, known: known, equipped: nil) == [nil, "d", "e", "b"])
        #expect(AvatarStrip.pick(unlocked: unlocked, known: known, equipped: "a") == [nil, "a", "d", "e"])
        // Nothing unlocked: only BOAR (the last box still opens the page).
        #expect(AvatarStrip.pick(unlocked: [:], known: known, equipped: nil) == [nil])
        // An id without art, or a worn one no longer unlocked, isn't shown.
        #expect(AvatarStrip.pick(unlocked: ["zz": 9, "b": 1], known: known, equipped: "c") == [nil, "b"])
    }

    @Test func theLimitNeverDropsBelowTheBoar() {
        #expect(AvatarStrip.pick(unlocked: ["a": 1], known: known, equipped: nil, max: 0) == [nil])
        #expect(AvatarStrip.pick(unlocked: ["a": 1, "b": 2], known: known, equipped: nil, max: 2) == [nil, "b"])
    }
}
