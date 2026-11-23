import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// Android's KeepGoingTest, one test per row of the t9 0235 table (adam: "send answers next"): what "Keep going" offers.
struct KeepGoingTests {
    let two = ["Tell me more about Salt", "What is Dead Sea?"]

    // Golden change (adam, 16 Nov): Succinct offers Continue, which sends "Continue" in the same style; no ladder under it.
    @Test func fromTheModelInSuccinctContinueThenUpToTwoFollowUps() {
        let n = KeepGoing.of(.init(style: "succinct", hasSources: true), followUps: two + ["A third"])
        #expect(n.step == .continue)
        #expect(n.followUps == two)
        #expect(!KeepGoing.showsLadder(.continue) && KeepGoing.showsLadder(.research))
        // An older chat's "Go deeper" bubble still reads as it was.
        #expect(KeepGoing.Step.of("deeper") == .deeper)
    }

    @Test func continueSendsAMetaFollowUpThatAsksForMoreEnAndPt() throws {
        let catalog = try #require(JSONValue(jsonString: try Fixtures.text(Fixtures.root.appending(path: "App/Resources/Localizable.xcstrings"))))
        let pt = try #require(catalog["strings"]?["Continue"]?["localizations"]?["pt"]?["stringUnit"]?["value"]?.str)
        for word in ["Continue", pt] {
            // A meta follow-up that asks for more: it keeps the search, so it adds rather than repeats (X6, Oct 16).
            #expect(DeepResearch.isMetaFollowUp(word) && !DeepResearch.isSummaryFollowUp(word), Comment(rawValue: word))
        }
        #expect(pt == "Continuar")
    }

    @Test func fromTheModelInDetailedResearchThis() {
        #expect(KeepGoing.of(.init(style: "detailed", hasSources: true), followUps: two).step == .research)
    }

    @Test func deepResearchTheLadderHasEndedFollowUpsOnly() {
        let n = KeepGoing.of(.init(style: "detailed", deepResearch: true, hasSources: true), followUps: two)
        #expect(n.step == nil)
        #expect(n.followUps == two)
    }

    @Test func aPluginsInstantAnswerAskBoarAndNothingElseTheCoAnswerNothing() {
        let n = KeepGoing.of(.init(instant: true, canBypass: true, hasSources: true), followUps: two)
        #expect(n.step == .ask)
        #expect(n.followUps.isEmpty)
        let co = KeepGoing.of(.init(instant: true, canBypass: false), followUps: two)
        #expect(co.step == nil)
        #expect(co.followUps.isEmpty)
    }

    @Test func cutAtTheLimitNoStepTheRepairIsInTheCard() {
        let n = KeepGoing.of(.init(style: "succinct", cut: true, hasSources: true), followUps: two)
        #expect(n.step == nil)
        #expect(n.followUps == two)
    }

    @Test func failedStoppedOrTimedOutNothing() {
        let n = KeepGoing.of(.init(broken: true, style: "succinct", hasSources: true), followUps: two)
        #expect(n.step == nil)
        #expect(n.followUps.isEmpty)
    }

    @Test func keptShortOnPurposePersonalFilesAndCustomNoStep() {
        #expect(KeepGoing.of(.init(style: "succinct", keptShort: true), followUps: []).step == nil)
        #expect(KeepGoing.of(.init(style: "personal"), followUps: []).step == nil)
        #expect(KeepGoing.of(.init(style: "custom"), followUps: []).step == nil)
    }

    @Test func noFollowUpWithoutSourcesThreeBubblesAtMost() {
        #expect(KeepGoing.of(.init(style: "succinct", hasSources: false), followUps: two).followUps.isEmpty)
        let n = KeepGoing.of(.init(style: "succinct", hasSources: true), followUps: ["a", "b", "c", "d"])
        #expect((n.step != nil ? 1 : 0) + n.followUps.count <= KeepGoing.max)
    }

    /// Follow-ups ship off in rc3 (adam reads the table first): the group builds none.
    @Test func followUpsAreOffAsInRc3() {
        #expect(!KeepGoing.followUpsOn)
    }

    /// A step's meta round trip (android stepMeta and stepFromMeta); a user message with no step, or another meta, has none.
    @Test func aStepIsKeptInTheMetaAndReadBack() {
        for step in KeepGoing.Step.allCases { #expect(KeepGoing.step(fromMeta: KeepGoing.stepMeta(step)) == step) }
        #expect(KeepGoing.stepMeta(.research) == "{\"step\":\"research\"}")
        #expect(KeepGoing.step(fromMeta: nil) == nil)
        #expect(KeepGoing.step(fromMeta: "{\"sources\":[]}") == nil)
        #expect(KeepGoing.step(fromMeta: "not json") == nil)
        #expect(KeepGoing.step(fromMeta: "{\"step\":\"bogus\"}") == nil)
    }
}

struct FollowUpsTests {
    @Test func anotherSourcesTitleFirstThenANamedThingFromACitedPassageNeverTheQuestionsTopic() {
        let sources = [
            FollowUps.Source(title: "Seawater", body: "Seawater is water from a sea. Its salinity comes from the Dead Sea basins and rivers.", cited: true),
            FollowUps.Source(title: "Salinity (water)", body: "Salinity is the saltiness of a body of water.", cited: true),
            FollowUps.Source(title: "Seawater", body: "duplicate", cited: false),
        ]
        #expect(FollowUps.pick("Why is seawater salty?", sources, pt: false) == ["Tell me more about Salinity", "What is Dead Sea?"])
    }

    @Test func portugueseTwoAtMostNoDuplicates() {
        let sources = [FollowUps.Source(title: "Marie Curie", body: "Marie Curie trabalhou com Pierre Curie em Paris.", cited: true),
                       FollowUps.Source(title: "Polônio", body: "O polônio foi descoberto em 1898.", cited: true)]
        let got = FollowUps.pick("Quem foi Marie Curie?", sources, pt: true)
        #expect(got.first == "Fale mais sobre Polônio")
        #expect(got.count <= 2 && Set(got).count == got.count && got.allSatisfy { !$0.contains("Marie Curie") })
    }

    @Test func titlesLoseATrailingParenthesisAndAPackSection() {
        #expect(FollowUps.cleanTitle("Mercury (planet)") == "Mercury")
        #expect(FollowUps.cleanTitle("Salt — Uses") == "Salt")
    }

    @Test func noSourcesNoFollowUps() {
        #expect(FollowUps.pick("Why is the sky blue?", [], pt: false).isEmpty)
    }

    /// Swift's side of the rule: a file's name is never offered, nor an uncited or user-file source.
    @Test func filesAndUncitedSourcesAreNeverOffered() {
        let sources = [
            FollowUps.Source(title: "eBook_investimentos (part 16/17)", body: "Warren Buffett wrote.", cited: true),
            FollowUps.Source(title: "Cutlet", body: "Schnitzel.", cited: false),
            FollowUps.Source(title: "My notes", body: "Alice Walker met Bob.", cited: true, fromPack: false),
        ]
        #expect(FollowUps.pick("How do I bake bread?", sources, pt: false).isEmpty)
    }
}

/// all75 on the F3: Keep going's "Continue" searched the word "continue" and cited "training should continue" from a book.
struct ContinueSearchTests {
    let history = ConversationHistory(turns: [
        ConversationTurn(role: "user", text: "How does photosynthesis work?"),
        ConversationTurn(role: "assistant", text: "Photosynthesis converts light energy into chemical energy."),
    ])

    @Test func continueAndItsKinSearchThePreviousQuestion() async throws {
        for q in ["Continue", "Continuar", "go on", "tell me more", "prossiga"] {
            #expect(FollowUp.plan(q, history).direct == "How does photosynthesis work?", Comment(rawValue: q))
        }
        // A summary isn't one: it is written from the last answer (aboutConversation), not searched.
        #expect(FollowUp.plan("a short summary please", history).direct == nil)
        // What actually gets searched.
        let searched = Log<String>()
        _ = try await FollowUp.search("Continue", history: history) { (text: String) -> [String] in searched.add(text); return ["x"] }
        #expect(searched.all == ["How does photosynthesis work?"])
    }
}
