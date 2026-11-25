import Foundation
import Testing

@testable import BoarAnswer

/// The end of every Press document: how it was made, and one numbered list of sources matching the answers' [n]
/// (android `PressReceiptTest`, `PressReceiptWordsTest`).
struct PressReceiptTests {
    typealias Block = PressDoc.Block

    private static func src(_ t: String, _ s: String? = "Wikipedia") -> PressDoc.Source { PressDoc.Source(t, s) }

    static let project = PressDoc.Project("p1", "Field notes", 0, [
        .heading(id: "h1", text: "Day 1: the coast"),
        .answer(PressDoc.Answer("a1", "Coast", "Why is the sea salty?", "Evaporation leaves salt [2], rivers bring it [1].", [src("Seawater"), src("Red Sea")], 1, "Qwen3-4B", 4.6)),
        .picture(PressDoc.Picture("pic", .drawing, "/d.png", recipe: PressDoc.Recipe(subject: "a crab", style: "engraving", size: "384", seed: 48213), width: 384, height: 512)),
        .answer(PressDoc.Answer("a2", "Coast", "What is a tide pool?", "Rock basins [1].", [src("Tide pool"), src("Seawater")], 2, "Qwen3-4B", 4.8, heading: "Tide pools")),
        .note(id: "n1", text: "Ask about the lighthouse."),
        .answer(PressDoc.Answer("a3", "Water", "What is evaporation?", "Water turns into vapour.", [src("Evaporation", nil)], 3, "Qwen3-1.7B", 9.1)),
        .answer(PressDoc.Answer("a4", "Calc", "2+2", "4", [], 4, nil, nil)),
    ])

    @Test func theAnswersRefsAreTheReceiptsListOneNumberPerSource() throws {
        let r = PressReceipt.build(Self.project)
        #expect(r.sources.map(\.title) == ["Seawater", "Red Sea", "Tide pool", "Evaporation"])
        #expect(r.refs["a1"] == [1, 2])
        // Seawater is cited again: the same number, not a new line.
        #expect(r.refs["a2"] == [3, 1])
        #expect(r.refs["a3"] == [4])
        #expect(r.refs["a4"] == [])
        // Every [n] under an answer is a line of the list, and every line is cited.
        #expect(Set(r.refs.values.flatMap { $0 }) == Set(1...r.sources.count))
        let rows = PressReceipt.rows(r, PressReceipt.Labels(), date: "13 November 2026", version: "2.0.0-rc3")
        let list = try #require(rows.filter(\.numbered).first)
        #expect(rows.filter(\.numbered).count == 1)
        #expect(list.lines == r.sources.map { PressReceipt.sourceText($0) })
        #expect(list.lines[0] == "Seawater — Wikipedia")
        #expect(list.lines[3] == "Evaporation")
        #expect(PressReceipt.refsLine(r.refs["a2"], "Sources") == "Sources [3] [1]")
        #expect(PressReceipt.refsLine(r.refs["a4"], "Sources") == nil)
    }

    @Test func anAnswersOwnMarksBecomeTheDocumentsNumbers() throws {
        let r = PressReceipt.build(Self.project)
        #expect(PressReceipt.renumber("Evaporation leaves salt [2], rivers bring it [1].", try #require(r.refs["a1"])) == "Evaporation leaves salt [2], rivers bring it [1].")
        #expect(PressReceipt.renumber("Rock basins [1].", try #require(r.refs["a2"])) == "Rock basins [3].")
        // A mark with no source behind it is taken out: it would read as another answer's source (validator G-5b).
        #expect(PressReceipt.renumber("See [7].", try #require(r.refs["a2"])) == "See.")
    }

    @Test func theReceiptIsAlwaysThereAndNamesModelsSpeedsAndDrawings() {
        // Even an empty document ends with how it was made.
        let empty = PressReceipt.rows(PressReceipt.build(PressDoc.Project("e", "Empty", 0)), PressReceipt.Labels(), date: "13 November 2026", version: "2.0.0-rc3")
        #expect(empty.map(\.label) == ["Made"])
        #expect(empty[0].lines == ["13 November 2026, offline, on this phone · BOAR 2.0.0-rc3"])

        let r = PressReceipt.build(Self.project)
        #expect(r.answers == 4)
        let rows = PressReceipt.rows(r, PressReceipt.Labels(), date: "13 November 2026", version: "2.0.0-rc3")
        #expect(rows.map(\.label) == ["Made", "Answers", "Drawings", "Sources"])
        #expect(rows[1].lines == ["4", "Qwen3-4B · 4.6–4.8 tok/s", "Qwen3-1.7B · 9.1 tok/s"])
        #expect(rows[2].lines == ["Designer · Engraving · portrait, medium quality · seed 48213"])
        // Photos (phase 2) count on their own line.
        var withPhoto = Self.project
        withPhoto.blocks.append(.picture(PressDoc.Picture("ph", .photo, "photos/1.jpg")))
        let photos = PressReceipt.rows(PressReceipt.build(withPhoto), PressReceipt.Labels(), date: "d", version: "v").filter { $0.label == "Photos" }
        #expect(photos.map(\.lines) == [["1 from this phone"]])
    }

    @Test func aDrawingWithoutARecipeStillCountsWithWhatIsKnown() {
        let p = PressDoc.Project("p", "P", 0, [.picture(PressDoc.Picture("x", .drawing, "/x.png"))])
        let r = PressReceipt.build(p, recipeOf: { _ in nil }, sizeOf: { _ in (640, 320) })
        #expect(r.drawings.map { PressReceipt.drawingText($0, PressReceipt.Labels()) } == ["Designer · wide, medium quality"])
        // The app's reader wins over the block's copy when it finds one.
        let r2 = PressReceipt.build(p, recipeOf: { _ in PressDoc.Recipe(style: "watercolor", seed: 7) }, sizeOf: { _ in (384, 384) })
        #expect(r2.drawings.map { PressReceipt.drawingText($0, PressReceipt.Labels()) } == ["Designer · Watercolor · square, low quality · seed 7"])
    }

    @Test func theMarkdownHasTheBlocksTheRefsAndTheSameReceipt() {
        let md = PressReceipt.markdown(Self.project, PressReceipt.Labels(), date: "13 November 2026", version: "2.0.0-rc3", sourcesLabel: "Sources", drawingLabel: "Drawing")
        #expect(md.hasPrefix("# Field notes\n\n_13 November 2026_"))
        #expect(md.contains("## Day 1: the coast"))
        #expect(md.contains("### Tide pools\n\n_What is a tide pool?_\n\nRock basins [3]."))
        // The heading is the question: no italic repeat.
        #expect(!md.contains("_Why is the sea salty?_"))
        #expect(md.contains("Sources [3] [1]"))
        #expect(md.contains("> Ask about the lighthouse."))
        // Nov 14: a Sources section (each with its pack, when the answer knew it), then the models' line and BOAR's.
        let end = "## Sources\n\n[1] Seawater — Wikipedia  \n[2] Red Sea — Wikipedia  \n[3] Tide pool — Wikipedia  \n[4] Evaporation\n\n"
            + "---\n\n_Qwen3-4B  ·  Qwen3-1.7B_  \n_Made offline with BOAR · 13 November 2026_"
        #expect(md.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(end), "\(md)")
        // No model line under the answers: models are in the footer only.
        #expect(md.components(separatedBy: "Qwen3-4B").count - 1 == 1)
    }

    @Test func shapes() {
        #expect(PressReceipt.Shape.of(384, 384) == .square)
        #expect(PressReceipt.Shape.of(384, 512) == .portrait)
        #expect(PressReceipt.Shape.of(640, 320) == .wide)
        #expect(PressReceipt.Shape.of(0, 10) == nil)
    }

    @Test func aDrawingsLineSaysItsShapeAndQualityNeverPixels() {
        let l = PressReceipt.Labels()
        let fast = PressReceipt.drawingText(PressReceipt.Drawing("photo", .square, 512, 512, 7), l)
        let slow = PressReceipt.drawingText(PressReceipt.Drawing("photo", .wide, 768, 320, nil), l)
        #expect(fast.contains("square, medium quality") && fast.range(of: #"[0-9]+[ \t]*[x×][ \t]*[0-9]+"#, options: .regularExpression) == nil, "\(fast)")
        #expect(slow.contains("wide, high quality"), "\(slow)")
    }
}

/// The footer (android `PressFooterTest`, `PressOwnFileNameTest`; their reads of the Android screen have no iOS
/// counterpart): two light lines under a short rule, the models and "Made offline with BOAR".
struct PressFooterTests {
    typealias Block = PressDoc.Block

    private static func answer(_ id: String, _ model: String, _ tps: Double, _ src: String...) -> Block {
        .answer(PressDoc.Answer(id, "Chat", "Q?", "A [1].", src.map { PressDoc.Source($0, "Wikipedia") }, 1, model, tps))
    }

    let p = PressDoc.Project("p", "Coast", 1, [answer("a", "Qwen3 4B", 9.5, "Salt", "Sea"), answer("b", "LFM2.5 8B", 12.0, "Sea", "Tide")])
    var r: PressReceipt.Receipt { PressReceipt.build(p) }

    @Test func theSourcesAreTheirOwnSectionEachWithItsPack() {
        #expect(PressReceipt.sourceLines(r, PressReceipt.Options()) == ["[1] Salt — Wikipedia", "[2] Sea — Wikipedia", "[3] Tide — Wikipedia"])
        #expect(PressReceipt.sourceLines(r, PressReceipt.Options(sources: false)).isEmpty)
    }

    @Test func theUsersOwnFileNamesNeverPrintAPacksSourceAndLinkDo() {
        let mine = Block.answer(PressDoc.Answer("m", "Chat", "Q?", "A [1] [2] [3].", [
            PressDoc.Source("Imposto 2025", "imposto-2025.pdf"),
            PressDoc.Source("Nosebleed", "Wikipedia — https://en.wikipedia.org/wiki/Nosebleed (CC BY-SA 4.0)"),
            PressDoc.Source("Notes", "  "),
        ], 1, "Qwen3 4B", 9.5))
        let lines = PressReceipt.sourceLines(PressReceipt.build(PressDoc.Project("q", "Mine", 1, [mine])), PressReceipt.Options())
        // Golden change (validator R-A1): a user's file prints a neutral line, not its title (the file name, often).
        #expect(lines == ["[1] Your own file", "[2] Nosebleed — Wikipedia — https://en.wikipedia.org/wiki/Nosebleed (CC BY-SA 4.0)", "[3] Notes"])
        // The shapes a file name can take never pass.
        for f in ["notes.txt", "Relatório final.docx", "a — b.pdf", "IMG_2041", "Wikipedia notes.pdf"] { #expect(!PressReceipt.shareable(f), "\(f)") }
        for s in ["Wikipedia", "Wikivoyage — https://en.wikivoyage.org/wiki/Lisbon"] { #expect(PressReceipt.shareable(s), "\(s)") }
    }

    @Test func theFooterIsTheModelsOnOneLineAndMadeWithBOAROnTheNextAlways() {
        let l = PressReceipt.Labels()
        #expect(PressReceipt.footer(r, l, date: "13 Nov", PressReceipt.Options()) == ["Qwen3 4B  ·  LFM2.5 8B", "Made offline with BOAR · 13 Nov"])
        #expect(PressReceipt.footer(r, l, date: "13 Nov", PressReceipt.Options(speed: true)) == ["Qwen3 4B (9.5 tok/s)  ·  LFM2.5 8B (12.0 tok/s)", "Made offline with BOAR · 13 Nov"])
        #expect(PressReceipt.footer(r, l, date: "13 Nov", PressReceipt.Options(models: false, speed: true)) == ["Made offline with BOAR · 13 Nov"])
        let none = PressDoc.Project("p", "Coast", 1, [.paragraph(id: "t", text: "Mine.")])
        #expect(PressReceipt.footer(PressReceipt.build(none), l, date: "13 Nov", PressReceipt.Options()) == ["Made offline with BOAR · 13 Nov"])
    }

    @Test func inTheMarkdownTheDateAndTheSourcesFollowTheSwitchesAndWithSourcesOffNoMarkIsLeft() {
        func md(_ o: PressReceipt.Options) -> String {
            PressReceipt.markdown(p, PressReceipt.Labels(), date: "13 November 2026", version: "v", sourcesLabel: "Sources", drawingLabel: "Drawing", receipt: r, options: o)
        }
        let on = md(PressReceipt.Options())
        #expect(on.contains("_13 November 2026_") && on.contains("## Sources\n\n[1] Salt — Wikipedia  \n[2] Sea — Wikipedia") && on.contains("A [1]."), "\(on)")
        let off = md(PressReceipt.Options(date: false, sources: false))
        #expect(!off.contains("_13 November 2026_") && !off.contains("## Sources") && !off.contains("[1]") && off.contains("_Made offline with BOAR · 13 November 2026_"), "\(off)")
    }

    @Test func theSourcesSectionTheReceiptAndTheMarkdownNeverPrintAUsersFileTitle() {
        let mine = Block.answer(PressDoc.Answer("m", "Chat", "Q?", "A [1] [2].", [
            PressDoc.Source("imposto-2025", "imposto-2025.pdf"),
            PressDoc.Source("Tax", "Wikipedia — https://en.wikipedia.org/wiki/Tax"),
        ], 1, "Qwen3 4B", 9.5))
        let p = PressDoc.Project("q", "Mine", 1, [mine])
        let r = PressReceipt.build(p)
        #expect(PressReceipt.sourceLines(r, PressReceipt.Options(), ownFile: "Arquivo seu") == ["[1] Arquivo seu", "[2] Tax — Wikipedia — https://en.wikipedia.org/wiki/Tax"])
        let md = PressReceipt.markdown(p, PressReceipt.Labels(), date: "today", version: "x", sourcesLabel: "Sources", drawingLabel: "Drawing", receipt: r, photoLabel: "Photo")
        #expect(!md.contains("imposto-2025"), "\(md)")
    }
}

/// Validator Q-B3 (t9 0115): a user's own file name doesn't reach a shared PDF or .md through the chat's words
/// (android `PressScrubTest`; its read of the Android screen is the app's export, which scrubs first here too).
struct PressScrubTests {
    typealias Block = PressDoc.Block

    let own = PressDoc.Source("imposto-2025", "imposto-2025.pdf")
    let pack = PressDoc.Source("Income tax", "Wikipedia — https://en.wikipedia.org/wiki/Income_tax")
    func project(_ b: Block...) -> PressDoc.Project { PressDoc.Project("p", "Taxes", 0, b) }

    @Test func theQuestionTheChatTitleTheAnswersTextAndTheCardsTitleSayYourOwnFile() throws {
        let card = AnswerCard(.facts, "imposto-2025", .facts([CardFact("Refund", "120"), CardFact("File", "imposto-2025.pdf")]), byModel: true)
        let a = Block.answer(PressDoc.Answer("a1", "imposto-2025", "what does imposto-2025.pdf say about tax?",
                                             "Imposto-2025.PDF lists a refund [1]. Income tax is progressive [2].", [own, pack], card: card))
        let out = try #require(PressReceipt.scrubOwnFiles(project(a), ownFile: "Your own file").answers.first)
        #expect(out.question == "what does Your own file say about tax?")
        #expect(out.chatTitle == "Your own file")
        #expect(out.text == "Your own file lists a refund [1]. Income tax is progressive [2].")
        #expect(out.card?.title == "Your own file")
        // Its body too (CodeRabbit on all73).
        #expect(out.card?.body == .facts([CardFact("Refund", "120"), CardFact("File", "Your own file")]))
        // Through the Markdown export too: the name appears nowhere.
        let md = PressReceipt.markdown(PressReceipt.scrubOwnFiles(project(a), ownFile: "Your own file"), PressReceipt.Labels(), date: "16 Nov 2026", version: "x",
                                       sourcesLabel: "Sources", drawingLabel: "Drawing")
        #expect(!md.lowercased().contains("imposto"), "\(md)")
    }

    @Test func whatTheUserTypedInPressStaysAndAPacksNamesStay() throws {
        let a = Block.answer(PressDoc.Answer("a1", "Taxes", "How does income tax work?", "Income tax is progressive [1].", [pack, own]))
        let typed = Block.note(id: "n1", text: "Check imposto-2025 again")
        let out = PressReceipt.scrubOwnFiles(project(a, typed), ownFile: "Your own file")
        #expect(out.blocks[1] == typed)
        #expect(out.answers.first?.text == "Income tax is progressive [1].")
        // No own file: the project is unchanged.
        let p = project(.answer(PressDoc.Answer("a2", "T", "Q", "Text", [pack])))
        #expect(PressReceipt.scrubOwnFiles(p, ownFile: "Your own file") == p)
    }
}

/// The validator's Press gate (android `PressGateGTest` G-5 and G-2, and the engine half of `ZzPressGTest`): a used
/// rewrite keeps only the sources it still cites; stray marks never borrow another answer's number.
struct PressGateTests {
    typealias Block = PressDoc.Block

    private static func ans(_ id: String, _ text: String, _ src: String...) -> Block {
        .answer(PressDoc.Answer(id, "chat", "Q \(id)?", text, src.map { PressDoc.Source($0, nil) }, 1, "m", 5.0))
    }
    private static func lib(_ b: Block...) -> PressDoc.Library { PressDoc.Library("p1", [PressDoc.Project("p1", "Doc", 0, b, seenAt: 9)]) }
    private static func md(_ p: PressDoc.Project) -> String {
        PressReceipt.markdown(p, PressReceipt.Labels(), date: "2026-11-13", version: "2.0.0", sourcesLabel: "Sources", drawingLabel: "Drawing",
                              receipt: PressReceipt.build(p), photoLabel: "Photo")
    }

    @Test func g5AUsedRewriteKeepsTheSourcesItStillCitesRenumberedAndTheFlagSurvivesASave() throws {
        let l = Self.lib(Self.ans("a1", "Paris [1]. Lyon [2].", "Paris", "Lyon")).editText("a1", .text, "Lyon is calm [2].")
        let a = try #require(l.current.blocks[0].answer)
        #expect(a.edited)
        let r = PressReceipt.build(l.current)
        #expect(r.sources.map(\.title) == ["Lyon"])
        #expect(PressReceipt.renumber(a.text, try #require(r.local["a1"])) == "Lyon is calm [1].")
        #expect(r.refs["a1"] == [1])
        #expect(try PressDoc.parse(PressDoc.toJson(l)) == l)
        // The chat's answer as it came keeps every source, cited or not.
        #expect(PressReceipt.build(Self.lib(Self.ans("a2", "No marks.", "X", "Y")).current).sources.count == 2)
        // Changing only the heading is not a changed text.
        #expect(Self.lib(Self.ans("a3", "t [1]", "S")).editText("a3", .heading, "New").current.blocks[0].answer?.edited == false)
    }

    @Test func g5bAMarkWithNoSourceOfItsOwnIsTakenOutMarkdownLineBreaksStay() {
        #expect(PressReceipt.renumber("Fact [4]. Next.", [1: 1]) == "Fact. Next.")
        #expect(PressReceipt.renumber("A [1] b.  \n  - nested", [1: 3]) == "A [3] b.  \n  - nested")
    }

    @Test func g2EveryShapeKeptMarksWrittenPlainly() {
        #expect(PressRewrite.dropNewMarks("old [1]", "A fact [1, 5].") == "A fact [1].")
        #expect(PressRewrite.dropNewMarks("old [1]", "A fact [1-5].") == "A fact [1].")
        #expect(PressRewrite.dropNewMarks("old [1]", "Year [2024] stays.") == "Year [2024] stays.")
        #expect(PressRewrite.marks("x [1–3]") == [1, 2, 3])
    }

    @Test func dropNewMarksBasics() {
        #expect(PressRewrite.dropNewMarks("old [1]", "A fact [5]. B [7].") == "A fact. B.")
        #expect(PressRewrite.dropNewMarks("old [1]", "A [1].") == "A [1].")
        #expect(PressRewrite.dropNewMarks("no marks here", "note [1]") == "note")
    }

    @Test func defectG2OtherMarkShapesSlipThroughDropNewMarks() {
        let leaks = ["A fact [1, 5].", "A fact [ 5 ].", "A fact [5][6].", "A fact [S5].", "A fact [^5].", "A fact 【5】.", "A fact [1-5]."]
            .filter { PressRewrite.dropNewMarks("old [1]", $0).contains("5") }
        #expect(leaks.isEmpty, "new source number survived in: \(leaks)")
    }

    @Test func g1ReceiptStillListsSourcesAfterTheTextWasRewrittenWithoutMarks() {
        let before = Self.lib(Self.ans("a1", "Paris is big [1]. Lyon too [2].", "Paris article", "Lyon article"))
        let t = Self.md(before.editText("a1", .text, "Cities are nice places.").current)
        // An answer whose text cites nothing any more prints no Sources line and lists none of its sources.
        #expect(!t.contains("Sources [1] [2]"))
        #expect(!t.contains("Paris article"))
    }

    @Test func g1bAStrayLocalMarkCollidesWithTheDocumentsNumbering() {
        // Answer 1 has 1 source; answer 2 has 2. A stray [2] in answer 1 would print as document source 2 = S-B1.
        let t = Self.md(Self.lib(Self.ans("a1", "Rewritten, cites [2].", "S-A"), Self.ans("a2", "B [1][2].", "S-B1", "S-B2")).current)
        #expect(!t.contains("cites [2]"), "\(t)")
    }

    @Test func markdownExportHasNoPrivatePathsOrFiles() {
        let l = Self.lib(Self.ans("a1", "t [1]", "S"),
                         .picture(PressDoc.Picture("d", .drawing, "/data/user/0/team.sopa.aoair/files/labs/images/secret.png", caption: "cap",
                                                   recipe: PressDoc.Recipe(subject: "a cat", style: "ink", size: "512x512", seed: 42))),
                         .picture(PressDoc.Picture("p", .photo, "photo-1234.jpg", caption: "")))
        let t = Self.md(l.current)
        for bad in ["/data/", "secret.png", "photo-1234", "files/labs", "team.sopa", "a cat", "512"] { #expect(!t.contains(bad), "export leaks <\(bad)>:\n\(t)") }
    }

    @Test func migrationBasketToProjectKeepsEverythingAndRunsOnce() throws {
        let basket = """
        [{"id":"a1","chatTitle":"T","question":"Q1","text":"Hello [1]","sources":[{"title":"S1","source":"u"}],"addedAt":5,"model":"M","tokPerSec":4.5,"image":"/x/d.png"},
            {"id":"a2","chatTitle":"T","question":"Q2","text":"Two","sources":[],"addedAt":6}]
        """
        guard case .migrated(let l) = PressDoc.load(projects: nil, basket: basket, newId: "p9", name: "Field notes", now: 100) else { Issue.record("not migrated"); return }
        #expect(l.current.blocks.map(\.id) == ["a1", "pic-a1", "a2"])
        #expect(l.current.unseen == 0)
        guard case .read(let again) = PressDoc.load(projects: PressDoc.toJson(l), basket: basket, newId: "p10", name: "x", now: 200) else { Issue.record("not read"); return }
        #expect(again.current.id == "p9")
        #expect(again == l)
    }

    @Test func unreadableProjectsFileIsNeverReplacedByBasketOrFresh() {
        for bad in ["", "{", "[]", "null", #"{"projects":[]}"#, #"{"projects":"x"}"#, #"{"projects":[{"name":"no id"}]}"#, "\u{0}\u{0}"] {
            guard case .unreadable = PressDoc.load(projects: bad, basket: "[]", newId: "n", name: "n", now: 1) else { Issue.record("bad=<\(bad)>"); continue }
        }
        guard case .fresh(_, let flagged) = PressDoc.load(projects: nil, basket: "{broken", newId: "n", name: "n", now: 1) else { Issue.record("not fresh"); return }
        #expect(flagged)
    }

    @Test func unknownBlockSurvivesARoundTrip() throws {
        let j = #"{"version":1,"open":"p1","projects":[{"id":"p1","name":"D","createdAt":1,"blocks":[{"type":"hologram","id":"z","x":1},{"type":"note","id":"n","text":"t"}]}]}"#
        let out = PressDoc.toJson(try PressDoc.parse(j))
        #expect(out.contains("hologram") && out.contains("\"x\""), "\(out)")
    }

    @Test func g3AnOldBasketUnreadableTheFirstTimeIsMergedLaterAsOneMoreProject() throws {
        let basket = #"[{"id":"a1","chatTitle":"T","question":"Q1","text":"Hello","sources":[],"addedAt":5}]"#
        guard case .fresh(let start, _) = PressDoc.load(projects: nil, basket: "{broken", newId: "p1", name: "Field notes", now: 1) else { Issue.record("not fresh"); return }
        let merged = try PressDoc.mergeBasket(start, basket, newId: "p2", name: "Field notes", now: 2)
        #expect(merged.projects.map(\.id) == ["p1", "p2"])
        #expect(merged.projects[1].blocks.map(\.id) == ["a1"])
        #expect(try PressDoc.mergeBasket(start, "[]", newId: "p3", name: "x", now: 3) == start)
        #expect(throws: (any Error).self) { try PressDoc.mergeBasket(start, "{still broken", newId: "p3", name: "x", now: 3) }
    }

    @Test func chatDeleteTakesAnswersAndTheirDrawingsFromEveryProjectOnly() {
        let a = Self.ans("a1", "t", "S"), b = Self.ans("a2", "u")
        let l = PressDoc.Library("p1", [
            PressDoc.Project("p1", "A", 0, [a, .picture(PressDoc.Picture("pic-a1", .drawing, "/d.png", answerId: "a1")), .note(id: "n", text: "mine"), b,
                                            .picture(PressDoc.Picture("ph", .photo, "x.jpg"))]),
            PressDoc.Project("p2", "B", 0, [a, .heading(id: "h", text: "H")]),
        ])
        #expect(l.countOf(["a1"]) == 2)
        let r = l.eraseAnswers(["a1"])
        #expect(r.projects[0].blocks.map(\.id) == ["n", "a2", "ph"])
        #expect(r.projects[1].blocks.map(\.id) == ["h"])
        #expect(l.eraseAnswers([String]()) == l)
    }
}
