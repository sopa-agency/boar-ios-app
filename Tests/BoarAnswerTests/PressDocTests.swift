import Foundation
import Testing

@testable import BoarAnswer

/// Press projects (android `PressDocTest`, adam's mock-up, Nov 13): the basket becomes "Field notes", several projects,
/// a deleted chat leaves every one.
struct PressDocTests {
    typealias Block = PressDoc.Block

    static let basket = """
    [
        {"id":"m1","chatTitle":"Coast","question":"Why is the sea salty?","text":"Rivers bring **salt** [1].","addedAt":10,"model":"Qwen3-4B","tokPerSec":4.6,
         "image":null,"imageOff":false,"sources":[{"title":"Seawater","source":"Wikipedia"},{"title":"Red Sea","source":null}]},
        {"id":"m2","chatTitle":"Coast","question":"Tide pools","text":"Rock basins.","addedAt":11,"model":null,"tokPerSec":null,
         "image":"/data/labs/images/a.png","imageOff":false,"sources":[]},
        {"id":"m3","chatTitle":"Coast","question":"Crabs?","text":"Yes.","addedAt":12,"model":"Qwen3-4B","tokPerSec":4.8,
         "image":null,"imageOff":true,"sources":[]}
    ]
    """

    static func answer(_ id: String, _ src: String..., at: Int64 = 100) -> PressDoc.Answer {
        PressDoc.Answer(id, "Chat", "Question \(id)", "Text \(id)", src.map { PressDoc.Source($0, "Wikipedia") }, at, "Qwen3-4B", 5.0)
    }

    private func ids(_ p: PressDoc.Project) -> [String] { p.blocks.map(\.id) }

    @Test func theBasketBecomesFieldNotesInOrderNothingLost() throws {
        let lib = try PressDoc.fromBasket(Self.basket, projectId: "p1", name: "Field notes", now: 1000,
                                          illustrations: ["m1": "/own/m1.png", "m3": "/own/m3.png"])
        #expect(lib.projects.count == 1)
        let p = lib.current
        #expect(p.name == "Field notes")
        #expect(lib.open == "p1")
        // m1, its own illustration; m2, the drawing picked for it; m3 had its drawing switched off.
        #expect(ids(p) == ["m1", "pic-m1", "m2", "pic-m2", "m3"])
        let a = try #require(p.blocks[0].answer)
        #expect(a.question == "Why is the sea salty?")
        #expect(a.text == "Rivers bring **salt** [1].")
        #expect(a.sources == [PressDoc.Source("Seawater", "Wikipedia"), PressDoc.Source("Red Sea", nil)])
        #expect(a.model == "Qwen3-4B")
        #expect(a.tokPerSec == 4.6)
        #expect(a.chatTitle == "Coast")
        #expect(a.addedAt == 10)
        #expect(p.blocks[2].answer?.model == nil)
        #expect(p.blocks[1].picture?.file == "/own/m1.png")
        #expect(p.blocks[1].picture?.answerId == "m1")
        #expect(p.blocks[3].picture?.file == "/data/labs/images/a.png")
        // Migrated answers aren't announced as new.
        #expect(p.unseen == 0)
    }

    @Test func migratedOnceAndAnUnreadableFileIsNeverWrittenOver() throws {
        // No projects file: the basket is migrated.
        guard case .migrated = PressDoc.load(projects: nil, basket: Self.basket, newId: "p1", name: "Field notes", now: 1) else { Issue.record("not migrated"); return }
        // A projects file exists: the basket is not read again, whatever it holds.
        let saved = PressDoc.toJson(PressDoc.emptyLibrary("p9", "Mine", 5))
        guard case .read(let lib) = PressDoc.load(projects: saved, basket: Self.basket, newId: "p1", name: "Field notes", now: 1) else { Issue.record("not read"); return }
        #expect(lib.current.name == "Mine")
        #expect(lib.current.blocks.isEmpty)
        // A projects file that can't be read: unreadable, so the app writes nothing over it.
        guard case .unreadable = PressDoc.load(projects: "{not json", basket: Self.basket, newId: "p1", name: "Field notes", now: 1) else { Issue.record("read a broken file"); return }
        guard case .unreadable = PressDoc.load(projects: #"{"projects":[]}"#, basket: nil, newId: "p1", name: "Field notes", now: 1) else { Issue.record("read an empty file"); return }
        // A basket that can't be read: a fresh project, and the app is told to keep the basket file.
        guard case .fresh(_, let unreadable) = PressDoc.load(projects: nil, basket: "[{\"broken\":", newId: "p1", name: "Field notes", now: 1) else { Issue.record("not fresh"); return }
        #expect(unreadable)
        // Nothing at all: a first empty project.
        guard case .fresh(let none, let flagged) = PressDoc.load(projects: nil, basket: nil, newId: "p1", name: "Notas de campo", now: 1) else { Issue.record("not fresh"); return }
        #expect(!flagged)
        #expect(none.current.name == "Notas de campo")
    }

    @Test func roundTripThroughJSONANewerBlockKeptAsItIs() throws {
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 1)
        lib = lib.addAnswer(Self.answer("a1", "Lisbon"), after: [.picture(PressDoc.Picture("pic-a1", .drawing, "/d.png", answerId: "a1",
            recipe: PressDoc.Recipe(subject: "a boar", style: "engraving", size: "384", seed: 48213), width: 384, height: 512))])
        lib = lib.insert(.heading(id: "h1", text: "Day 1"), at: 0).insert(.note(id: "n1", text: "Ask about the lighthouse."), at: 99)
        lib = lib.editText("a1", .heading, "Lisbon")
        let text = PressDoc.toJson(lib)
        #expect(try PressDoc.parse(text) == lib)
        // A block type from a later version survives a load and a save.
        let newer = text.replacingOccurrences(of: "\"blocks\":[", with: "\"blocks\":[{\"type\":\"table\",\"id\":\"t1\",\"rows\":[[1,2]]},")
        let kept = try PressDoc.parse(newer)
        guard case .unknown = kept.current.blocks.first else { Issue.record("not kept"); return }
        #expect(PressDoc.toJson(kept).contains("\"rows\":[[1,2]]"))
    }

    @Test func severalProjectsEachItsOwnDocument() {
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 1).addAnswer(Self.answer("a1"))
        lib = lib.newProject("p2", "Trip to Lisbon", 2)
        #expect(lib.open == "p2")
        #expect(lib.projects.map(\.id) == ["p2", "p1"])
        #expect(lib.current.blocks.isEmpty)
        // 📎 goes to the open project, at the end, once.
        lib = lib.addAnswer(Self.answer("a2")).addAnswer(Self.answer("a3")).addAnswer(Self.answer("a2"))
        #expect(ids(lib.current) == ["a2", "a3"])
        #expect(lib.projects.first { $0.id == "p1" }.map(ids) == ["a1"])
        // The same answer can be in two projects.
        lib = lib.switchTo("p1").addAnswer(Self.answer("a2"))
        #expect(ids(lib.current) == ["a1", "a2"])
        lib = lib.rename("p1", "  Coast  ").rename("p1", "   ")
        #expect(lib.current.name == "Coast")
        // Delete: the open one goes, another opens. The last one goes too, a blank one in its place (adam, Nov 14).
        lib = lib.deleteProject("p1")
        #expect(lib.projects.map(\.id) == ["p2"])
        #expect(lib.open == "p2")
        #expect(lib.deleteProject("p2") == lib)
        let blank = PressDoc.Project("p9", "Untitled", 5, seenAt: 5)
        let after = lib.deleteProject("p2", blank: blank)
        #expect(after.projects.map(\.id) == ["p9"]); #expect(after.open == "p9")
        #expect(after.current.blocks.isEmpty && after.current.name == "Untitled")
        #expect(lib.deleteProject("nope", blank: blank) == lib)
    }

    @Test func blocksMoveAreRemovedAndComeBackWithUndoAndAreEditedInPlace() {
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 1).addAnswer(Self.answer("a1")).addAnswer(Self.answer("a2"))
            .insert(.note(id: "n1", text: "note"), at: 1)
        #expect(ids(lib.current) == ["a1", "n1", "a2"])
        lib = lib.move("a2", by: -1).move("a1", by: -1)
        #expect(ids(lib.current) == ["a1", "a2", "n1"])
        let removed = lib.current.blocks[1]
        lib = lib.remove("a2")
        #expect(ids(lib.current) == ["a1", "n1"])
        lib = lib.insert(removed, at: 1)
        #expect(ids(lib.current) == ["a1", "a2", "n1"])
        lib = lib.editText("n1", .text, "changed").editText("a1", .text, "new text")
        #expect(lib.current.blocks[2].text == "changed")
        #expect(lib.current.blocks[0].answer?.text == "new text")
        // A heading typed back to the question is no heading of its own: the question stands, no italic line.
        lib = lib.editText("a1", .heading, "Short")
        #expect(lib.current.blocks[0].answer?.shownHeading == "Short")
        #expect(lib.current.blocks[0].answer?.shownQuestion == "Question a1")
        lib = lib.editText("a1", .heading, "Question a1")
        #expect(lib.current.blocks[0].answer?.heading == "")
        #expect(lib.current.blocks[0].answer?.shownQuestion == nil)
    }

    @Test func aDeletedChatsAnswersLeaveEveryProjectWithTheirDrawings() {
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 1)
            .addAnswer(Self.answer("a1"), after: [.picture(PressDoc.Picture("pic-a1", .drawing, "/d.png", answerId: "a1"))]).addAnswer(Self.answer("b1"))
            .insert(.picture(PressDoc.Picture("pic-x", .drawing, "/x.png")), at: 0)
        lib = lib.newProject("p2", "Two", 2).addAnswer(Self.answer("a1")).addAnswer(Self.answer("a2")).insert(.note(id: "n", text: "kept"), at: 0)
        #expect(lib.countOf(["a1", "a2"]) == 3)
        lib = lib.eraseAnswers(["a1", "a2"])
        #expect(lib.projects.first { $0.id == "p1" }.map(ids) == ["pic-x", "b1"])
        #expect(lib.projects.first { $0.id == "p2" }.map(ids) == ["n"])
        #expect(lib.countOf(["a1", "a2"]) == 0)
        #expect(!lib.has("a1"))
    }

    @Test func newAnswersSinceTheLastLookMakeTheBanner() {
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 50)
        lib = lib.addAnswer(Self.answer("a1", at: 60)).addAnswer(Self.answer("a2", at: 70))
        #expect(lib.current.unseen == 2)
        lib = lib.markSeen(80)
        #expect(lib.current.unseen == 0)
        // Taking an answer out takes its drawing with it.
        lib = lib.addAnswer(Self.answer("a3", at: 90), after: [.picture(PressDoc.Picture("pic-a3", .drawing, "/d.png", answerId: "a3"))])
        #expect(lib.current.unseen == 1)
        lib = lib.removeAnswer("a3")
        #expect(ids(lib.current) == ["a1", "a2"])
    }

    /// dfb41659: Undo after a project switch goes back where it was; markSeen of a project changes nothing without news.
    @Test func undoAndSeenMarksAreScopedToTheirProject() {
        var lib = PressDoc.emptyLibrary("p1", "A", 1).addAnswer(Self.answer("a1", at: 5)).addAnswer(Self.answer("a2", at: 6))
        let removed = lib.current.blocks[0]
        lib = lib.remove("a1").newProject("p2", "B", 2)
        lib = lib.insert(removed, at: 0, projectId: "p1")
        #expect(lib.projects.first { $0.id == "p1" }.map(ids) == ["a1", "a2"])
        #expect(lib.current.blocks.isEmpty)
        // p1 still has its two unseen answers: marked from p2's page, they're seen; again, nothing changes.
        let seen = lib.markSeen(9, projectId: "p1")
        #expect(seen.projects.first { $0.id == "p1" }?.unseen == 0)
        #expect(seen.markSeen(10, projectId: "p1") == seen)
        #expect(seen.current == lib.current)
    }
}

/// adam, Nov 13: the add toolbar gets a paragraph (body text, not a note), a list and a divider (android
/// `PressMoreBlocksTest`; its source checks of the Android screen have no iOS counterpart).
struct PressMoreBlocksTests {
    let blocks: [PressDoc.Block] = [
        .paragraph(id: "t1", text: "Plain body text."),
        .bullets(id: "l1", text: "- salt\n• water\n\n  sun  "),
        .divider(id: "d1"),
        .note(id: "n1", text: "An aside."),
    ]

    @Test func theNewBlocksAreSavedAndReadBack() throws {
        let lib = PressDoc.Library("p", [PressDoc.Project("p", "Coast", 1, blocks)])
        #expect(try PressDoc.parse(PressDoc.toJson(lib)).current.blocks == blocks)
    }

    @Test func aListsItemsDropTheMarksTheUserTypedAndTheBlankLines() {
        #expect(PressDoc.items("- salt\n• water\n\n  sun  ") == ["salt", "water", "sun"])
        #expect(PressDoc.bulleted("- salt\n• water\n\n  sun  ") == "•  salt\n•  water\n•  sun")
    }

    @Test func paragraphAndListAreEditedAndFlowBesideAPictureADividerDoesNeither() {
        var lib = PressDoc.Library("p", [PressDoc.Project("p", "Coast", 1, blocks)])
        lib = lib.editText("t1", .text, "New text.").editText("l1", .text, "a\nb")
        #expect(lib.current.blocks[0].text == "New text.")
        #expect(lib.current.blocks[1].text == "a\nb")
        #expect(PressLayout.flows(blocks[0]) && PressLayout.flows(blocks[1]) && !PressLayout.flows(blocks[2]))
    }

    @Test func inTheMarkdownAParagraphIsPlainTextAListHasDashesADividerABreakANoteStaysAQuote() {
        let md = PressReceipt.markdown(PressDoc.Project("p", "Coast", 1, blocks), PressReceipt.Labels(), date: "13 November 2026", version: "2.0.0-rc3",
                                       sourcesLabel: "Sources", drawingLabel: "Drawing")
        #expect(md.contains("Plain body text.\n\n- salt\n- water\n- sun\n\n* * *\n\n> An aside."), "\(md)")
    }
}

/// android `PressManyProjectsTest`: the menu's short list and the search.
struct PressManyProjectsTests {
    private func lib(_ n: Int) -> PressDoc.Library {
        var l = PressDoc.Library("p0", [PressDoc.Project("p0", "Field notes", 1)])
        for i in 1..<n { l = l.newProject("p\(i)", i == 7 ? "Viagem a São Paulo" : "Project \(i)", 10 * Int64(i)) }
        return l.switchTo("p3")
    }

    @Test func theMenuListsTheOpenProjectAndTheThreeMostRecentHoweverManyThereAre() {
        let l = lib(12)
        #expect(l.shortList().map(\.id) == ["p3", "p11", "p10", "p9"])
        #expect(l.search("").count == 12)
        #expect(l.search("").first?.id == "p3")
        #expect(lib(2).shortList().count == 2)
    }

    @Test func searchFindsByNameCaseAndAccentsAside() {
        let l = lib(12)
        #expect(l.search("sao paulo").map(\.id) == ["p7"])
        #expect(l.search("project 1").map(\.id) == ["p11", "p10", "p1"])
        #expect(l.search("zzz").isEmpty)
    }
}

/// Cards in Press (android `PressCardTest`, t9 0207 item 4): the answer's Add to Press takes its card along; old
/// projects still read.
struct PressCardTests {
    let steps = AnswerCard(.checklist, "Purify water", .steps(["Collect it.", "Boil it.", "Let it cool."]), ticks: [1])

    private func lib(_ card: AnswerCard?) -> PressDoc.Library {
        PressDoc.emptyLibrary("p1", "Field notes", 1).addAnswer(
            PressDoc.Answer("m1", "Chat", "How do you purify water?", "Collect, boil, cool [1].", [PressDoc.Source("Water purification", "Wikipedia")], 5, card: card))
    }

    @Test func anAnswersCardAndItsTicksAreKeptInTheProject() throws {
        let back = try PressDoc.parse(PressDoc.toJson(lib(steps)))
        #expect(back.current.answers.first?.card == steps)
        // Golden change (validator R-E3): an edit of the text drops the card, which showed the old text's figures.
        #expect(back.editText("m1", .text, "Boil it.").current.answers.first?.card == nil)
        // Its heading edited, the card stays.
        #expect(back.editText("m1", .heading, "Water").current.answers.first?.card == steps)
    }

    @Test func aProjectsFileFromBeforeCardsStillReadsWithNoCard() throws {
        let old = """
        {"version":1,"open":"p1","projects":[{"id":"p1","name":"Field notes","createdAt":1,"seenAt":1,"blocks":[
            {"type":"answer","id":"m1","chatTitle":"Chat","question":"Q","heading":"","text":"T","addedAt":5,"model":null,"tokPerSec":null,"edited":false,"sources":[]}]}]}
        """
        let a = try #require(try PressDoc.parse(old).current.answers.first)
        #expect(a.text == "T")
        #expect(a.card == nil)
        // Written again with no card, it has no "card" key.
        #expect(!PressDoc.toJson(try PressDoc.parse(old)).contains("\"card\""))
        // A card a newer BOAR wrote in a form this one doesn't know is left out, the answer kept.
        let newer = old.replacingOccurrences(of: "\"sources\":[]}", with: "\"sources\":[],\"card\":{\"shape\":\"HOLOGRAM\"}}")
        #expect(try PressDoc.parse(newer).current.answers.first?.card == nil)
    }

    @Test func theMarkdownHasTheCardAfterTheAnswersLinesAsANumberedListForSteps() throws {
        let md = PressReceipt.markdown(lib(steps).current, PressReceipt.Labels(), date: "14 Nov 2026", version: "2.0.0", sourcesLabel: "Sources", drawingLabel: "Drawing")
        let text = try #require(md.range(of: "Collect, boil, cool [1].")).lowerBound
        let refs = try #require(md.range(of: "Sources [1]")).lowerBound
        let card = try #require(md.range(of: "**Purify water**\n\n1. Collect it.\n2. Boil it.\n3. Let it cool.")).lowerBound
        #expect(text < refs && refs < card)
        #expect(!PressReceipt.markdown(lib(nil).current, PressReceipt.Labels(), date: "d", version: "v", sourcesLabel: "Sources", drawingLabel: "Drawing").contains("1. Collect"))
    }

    @Test func aChartGoesToTheMarkdownAsATable() {
        let chart = AnswerCard(.pie, "Air", .series(unit: "%", points: [CardRules.Point("Nitrogen", "78 %", 78), CardRules.Point("Oxygen", "21 %", 21)]))
        let md = PressReceipt.markdown(lib(chart).current, PressReceipt.Labels(), date: "d", version: "v", sourcesLabel: "Sources", drawingLabel: "Drawing")
        #expect(md.contains("| Nitrogen | 78 % |\n| Oxygen | 21 % |"), "\(md)")
    }
}
