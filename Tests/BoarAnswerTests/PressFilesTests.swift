import Foundation
import Testing

@testable import BoarAnswer

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "press-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
private func canonical(_ u: URL) -> String { u.standardizedFileURL.resolvingSymlinksInPath().path }
private func write(_ bytes: [UInt8]) -> (URL) throws -> Void { { try Data(bytes).write(to: $0) } }
private func names(_ d: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).sorted() }

private struct Boom: Error {}

/// Press phase 2 (android `PressPicturesTest`, t9 0625 items 3 and 5): photos copied into the project, captions, and
/// left / center / right with the text beside. Its reads of the Android screen have no iOS counterpart.
struct PressPicturesTests {
    typealias Block = PressDoc.Block
    typealias Item = PressLayout.Item

    private func pic(_ id: String, _ place: PressDoc.Place = .center, kind: PressDoc.Kind = .drawing, caption: String = "") -> PressDoc.Picture {
        PressDoc.Picture(id, kind, "\(id).jpg", caption: caption, place: place, width: 400, height: 300)
    }
    private func answer(_ id: String) -> Block { .answer(PressDoc.Answer(id, "Chat", "Question \(id)", "Text \(id)")) }

    @Test func aPhotoIsCopiedIntoItsProjectsFolderAndGoesWithTheProject() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        var lib = PressDoc.emptyLibrary("p1", "Field notes", 0).newProject("p2", "Trip", 1)
        let f = try PressFiles.copyInto(press, "p2", "photo-1.jpg", write: write([1, 2, 3]))
        #expect(canonical(f.deletingLastPathComponent()) == canonical(press.appending(path: "p2")))
        #expect((try Data(contentsOf: f)).count == 3)
        // No half copy left behind.
        #expect(!exists(URL(fileURLWithPath: f.path + ".tmp")))
        lib = lib.insert(.picture(PressDoc.Picture("ph1", .photo, f.lastPathComponent, width: 4, height: 3)), at: 0)
        #expect(canonical(PressFiles.photoFile(press, "p2", try #require(lib.current.blocks[0].picture).file)) == canonical(f))
        // A name can't leave the folder.
        #expect(canonical(PressFiles.photoFile(press, "p2", "../../x.jpg")) == canonical(press.appending(path: "p2/x.jpg")))
        // A copy that fails leaves nothing.
        _ = try? PressFiles.copyInto(press, "p2", "broken.jpg") { _ in throw Boom() }
        #expect(!exists(press.appending(path: "p2/broken.jpg")) && !exists(press.appending(path: "p2/broken.jpg.tmp")))

        // Deleting the project deletes its folder and photo; the other project's folder stays.
        try PressFiles.copyInto(press, "p1", "keep.jpg", write: write([1]))
        lib = lib.deleteProject("p2")
        PressFiles.deleteProject(press, "p2")
        #expect(!exists(f))
        #expect(!exists(press.appending(path: "p2")))
        #expect(exists(press.appending(path: "p1/keep.jpg")))
        #expect(lib.projects.map(\.id) == ["p1"])

        // Clear all / Forgot PIN: everything.
        PressFiles.eraseAll(press)
        #expect(!exists(press))
    }

    @Test func filesNoProjectUsesAnyMoreAreFoundTheUsedOnesKept() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        let lib = PressDoc.emptyLibrary("p1", "A", 0).insert(.picture(PressDoc.Picture("ph", .photo, "used.jpg")), at: 0)
        try PressFiles.copyInto(press, "p1", "used.jpg", write: write([1]))
        try PressFiles.copyInto(press, "p1", "removed.jpg", write: write([1]))
        try PressFiles.copyInto(press, "gone", "a.jpg", write: write([1]))
        let base = canonical(press) + "/"
        let orphans = Set(PressFiles.orphans(press, lib).map { canonical($0).replacingOccurrences(of: base, with: "") })
        #expect(orphans == ["p1/removed.jpg", "gone"])
    }

    @Test func aPhotoIsDownscaledToASaneSizeInItsShape() {
        #expect(PressFiles.scaled(4000, 3000) == (1600, 1200))
        #expect(PressFiles.scaled(2250, 4000) == (900, 1600))
        #expect(PressFiles.scaled(800, 600) == (800, 600))
        #expect(PressFiles.sampleSize(4000, 3000) == 2)
        #expect(PressFiles.sampleSize(3000, 2000) == 1)
        #expect(PressFiles.sampleSize(8000, 6000) == 4)
    }

    @Test func captionsAndPlacesSurviveASaveAndALoad() throws {
        var lib = PressDoc.emptyLibrary("p1", "A", 0).insert(.picture(pic("d1")), at: 0).insert(.picture(pic("ph", kind: .photo)), at: 1)
        lib = lib.editText("d1", .caption, "Morning on the cliffs").place("d1", .right).place("ph", .left)
        let back = try PressDoc.parse(PressDoc.toJson(lib))
        let d1 = try #require(back.current.blocks[0].picture)
        #expect(d1.caption == "Morning on the cliffs")
        #expect(d1.place == .right)
        #expect(back.current.blocks[1].picture?.place == .left)
        #expect(back.current.blocks[1].picture?.kind == .photo)
        // place() leaves text blocks alone.
        #expect(lib.place("nope", .left) == lib)
    }

    @Test func anEmptyCaptionDoesntPrintInTheMarkdown() {
        let p = PressDoc.Project("p", "P", 0, [.picture(pic("a", caption: "  ")), .picture(pic("b", caption: "A crab"))])
        let md = PressReceipt.markdown(p, PressReceipt.Labels(), date: "d", version: "v", sourcesLabel: "Sources", drawingLabel: "Drawing")
        #expect(md.contains("_Drawing_\n"), "\(md)")
        #expect(md.contains("_Drawing: A crab_"), "\(md)")
    }

    @Test func theReceiptCountsThePhotos() {
        let p = PressDoc.Project("p", "P", 0, [.picture(pic("a", kind: .photo)), .picture(pic("b", kind: .photo)), .picture(pic("c"))])
        let r = PressReceipt.build(p)
        #expect(r.photos == 2)
        #expect(r.drawings.count == 1)
        #expect(PressReceipt.rows(r, PressReceipt.Labels(), date: "d", version: "v").filter { $0.label == "Photos" }.map(\.lines) == [["2 from this phone"]])
    }

    @Test func theNextTextBlockFlowsBesideASidePictureAHeadingNeverDoes() {
        let h = Block.heading(id: "h", text: "Day 2")
        let n = Block.note(id: "n", text: "note"), n2 = Block.note(id: "n2", text: "note")
        let plan = PressLayout.plan([
            .picture(pic("c")), answer("a1"),                         // centered: nothing beside
            .picture(pic("r", .right)), answer("a2"), n,              // a2 beside, the note below
            .picture(pic("l", .left)), h, answer("a3"),               // a heading after: it starts below, and nothing flows
            .picture(pic("l2", .left)), n2,                           // a note flows too
            .picture(pic("r2", .right)), .picture(pic("c2")),         // a picture after: nothing flows
            .picture(pic("end", .right)),                             // the last block
        ])
        #expect(plan == [
            .single(.picture(pic("c"))), .single(answer("a1")),
            .beside(pic("r", .right), text: answer("a2"), left: false), .single(n),
            .beside(pic("l", .left), text: nil, left: true), .single(h), .single(answer("a3")),
            .beside(pic("l2", .left), text: n2, left: true),
            .beside(pic("r2", .right), text: nil, left: false), .single(.picture(pic("c2"))),
            .beside(pic("end", .right), text: nil, left: false),
        ])
        // Every block is placed once, in order.
        let ids = plan.flatMap { item -> [String] in
            switch item {
            case .single(let b): [b.id]
            case .beside(let p, let t, _): [p.id] + (t.map { [$0.id] } ?? [])
            }
        }
        #expect(ids == ["c", "a1", "r", "a2", "n", "l", "h", "a3", "l2", "n2", "r2", "c2", "end"])
        #expect(!plan.contains { if case .beside(_, .heading?, _) = $0 { true } else { false } })
    }

    @Test func widthsAndTheLinesBeside() {
        #expect(abs(PressLayout.sideWidth(515) - 515 * 0.45) < 0.001)
        #expect(abs(PressLayout.besideWidth(515) - (515 - 515 * 0.45 - 14)) < 0.001)
        // Lines whose top is above the picture's bottom go beside; the rest continue at the full width.
        #expect(PressLayout.linesBeside([0, 20, 40, 60, 80], 55) == 3)
        #expect(PressLayout.linesBeside([60, 80], 55) == 0)
        #expect(PressLayout.linesBeside([0, 20], 500) == 2)
    }
}

/// The validator's Press gate, files half (android `PressGateGTest` G-1, G-6, G-9 and `ZzPressGTest`).
struct PressFilesGateTests {
    typealias Block = PressDoc.Block
    private func lib(_ b: Block...) -> PressDoc.Library { PressDoc.Library("p1", [PressDoc.Project("p1", "Doc", 0, b, seenAt: 9)]) }

    @Test func g1ARemovedPhotosCopyGoesAfterTheUndoIfNothingUsesItAgain() {
        let l = lib(.picture(PressDoc.Picture("k", .photo, "keep.jpg")))
        #expect(PressFiles.unused(l, "p1", "gone.jpg"))
        #expect(!PressFiles.unused(l, "p1", "keep.jpg"))
        // Another project's photo of that name is not this one.
        #expect(PressFiles.unused(l, "p2", "keep.jpg"))
    }

    @Test func g9AnEmptyIdOrADotNameNeverNamesThePressFolderDeleteProjectOfOneLeavesTheRest() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        try Data("{}".utf8).write(to: press.appending(path: "projects.json"))
        try PressFiles.copyInto(press, "p1", "a.jpg", write: write([1]))
        for bad in ["", "  ", ".", ".."] { #expect(canonical(PressFiles.projectDir(press, bad).deletingLastPathComponent()) == canonical(press), "\(bad)") }
        for bad in ["", ".", "..", "a/.."] {
            #expect(canonical(PressFiles.photoFile(press, "p1", bad).deletingLastPathComponent()) == canonical(PressFiles.projectDir(press, "p1")), "\(bad)")
        }
        PressFiles.deleteProject(press, "")
        #expect(exists(press.appending(path: "projects.json")) && exists(PressFiles.projectDir(press, "p1").appending(path: "a.jpg")))
    }

    @Test func defectG9DegenerateNamesResolveOutsideTheProjectFolder() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        #expect(canonical(PressFiles.projectDir(press, "")) != canonical(press))
        #expect(canonical(PressFiles.photoFile(press, "p1", "..")) != canonical(press))
        #expect(canonical(PressFiles.photoFile(press, "p1", "..")) != canonical(PressFiles.projectDir(press, "p1")))
    }

    @Test func g6MirroredOrientationsAreMirroredBack() {
        let got = (1...8).map { PressFiles.upright($0) }
        let want: [(Int, Bool)] = [(0, false), (0, true), (180, false), (180, true), (90, true), (90, false), (270, true), (270, false)]
        #expect(got.map(\.degrees) == want.map(\.0))
        #expect(got.map(\.mirror) == want.map(\.1))
    }

    @Test func copyIntoIsAllOrNothing() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        #expect(throws: Boom.self) { try PressFiles.copyInto(press, "p1", "a.jpg") { try Data([1, 2]).write(to: $0); throw Boom() } }
        let d = PressFiles.projectDir(press, "p1")
        #expect(names(d).isEmpty, "no half copy, no tmp: \(names(d))")
        let f = try PressFiles.copyInto(press, "p1", "a.jpg", write: write([1, 2, 3]))
        #expect(names(d) == ["a.jpg"])
        #expect((try Data(contentsOf: f)).count == 3)
        // Written again: replaced, still one file.
        try PressFiles.copyInto(press, "p1", "a.jpg", write: write([9]))
        #expect(names(d) == ["a.jpg"])
        #expect((try Data(contentsOf: f)) == Data([9]))
    }

    /// Java's `Random(7)` stream isn't reproduced; any fixed seed checks the same properties.
    @Test func scaledAndSampleSizeFuzz() {
        var g = SplitMix(seed: 7)
        for _ in 0..<20000 {
            let w = 1 + Int(g.next() % 12000), h = 1 + Int(g.next() % 12000)
            let (sw, sh) = PressFiles.scaled(w, h)
            #expect(max(sw, sh) <= 1600 && sw >= 1 && sh >= 1, "A w=\(w) h=\(h) -> \(sw) x \(sh)")
            if max(w, h) <= 1600 { #expect(sw == w && sh == h) }
            let s = PressFiles.sampleSize(w, h)
            #expect(s >= 1 && s & (s - 1) == 0, "B s=\(s)")
            if max(w, h) >= 1600 { #expect(max(w, h) / s >= 1600 || s == 1, "C w=\(w) h=\(h) s=\(s)") }
            if max(w, h) > 1600 && min(sw, sh) >= 20 {
                let err = abs(Double(sw) / Double(sh) - Double(w) / Double(h)) / (Double(w) / Double(h))
                #expect(err < 0.01 + 2.0 / Double(min(sw, sh)), "D w=\(w) h=\(h) -> \(sw) x \(sh)")
            }
        }
    }

    @Test func photoNameCannotLeaveItsFolder() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        for n in ["../../x.jpg", "/etc/passwd", "a/b/c.jpg", "..\\x.jpg"] {
            #expect(canonical(PressFiles.photoFile(press, "p1", n).deletingLastPathComponent()) == canonical(PressFiles.projectDir(press, "p1")), "\(n)")
        }
        #expect(PressFiles.projectDir(press, "../x").lastPathComponent == "___x")
    }

    @Test func orphansAreOnlyWhatNoBlockUsesAndRemovalOfAPhotoBlockMakesItsFileOne() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        let keep = try PressFiles.copyInto(press, "p1", "keep.jpg", write: write([1]))
        let gone = try PressFiles.copyInto(press, "p1", "gone.jpg", write: write([1]))
        try Data("x".utf8).write(to: PressFiles.projectDir(press, "p1").appending(path: "half.jpg.tmp"))
        let stray = press.appending(path: "stray", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: stray.appending(path: "f.jpg"))
        let photo = { (f: URL) in Block.picture(PressDoc.Picture("pic-" + f.lastPathComponent, .photo, f.lastPathComponent)) }
        let l0 = lib(photo(keep), photo(gone))
        #expect(Set(PressFiles.orphans(press, l0).map(\.lastPathComponent)) == ["half.jpg.tmp", "stray"])
        let l1 = lib(photo(keep))
        #expect(PressFiles.orphans(press, l1).contains { $0.lastPathComponent == "gone.jpg" }, "removed photo's file becomes an orphan")
        #expect(!PressFiles.orphans(press, l1).contains { $0.lastPathComponent == "keep.jpg" })
        // A drawing block (Designer's file) never claims or loses a project-folder file.
        let l2 = lib(.picture(PressDoc.Picture("d", .drawing, "/designer/keep.jpg")))
        #expect(PressFiles.orphans(press, l2).contains { $0.lastPathComponent == "keep.jpg" })
    }

    @Test func deleteProjectAndEraseAll() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        try PressFiles.copyInto(press, "p1", "a.jpg", write: write([1]))
        try PressFiles.copyInto(press, "p2", "b.jpg", write: write([1]))
        try Data("{}".utf8).write(to: press.appending(path: "projects.json"))
        PressFiles.deleteProject(press, "p1")
        #expect(!exists(PressFiles.projectDir(press, "p1")))
        #expect(exists(PressFiles.projectDir(press, "p2")))
        PressFiles.eraseAll(press)
        #expect(!exists(press))
    }

    /// android `ClearHistoryPressTest` (validator R-A3): a drawing copied into its project's folder, when the chats were
    /// cleared with Press kept, isn't cleaned up as an orphan.
    @Test func withPressKeptADrawingCopiedIntoItsProjectsFolderIsNotAnOrphan() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pd = PressFiles.projectDir(dir, "p1")
        try FileManager.default.createDirectory(at: pd, withIntermediateDirectories: true)
        let copied = pd.appending(path: "drawing-a.png")
        try Data("x".utf8).write(to: copied)
        try Data("x".utf8).write(to: pd.appending(path: "old.png"))
        let lib = PressDoc.Library("p1", [PressDoc.Project("p1", "P", 1, [.picture(PressDoc.Picture("pic", .drawing, copied.path))])])
        #expect(PressFiles.orphans(dir, lib).map(\.lastPathComponent) == ["old.png"])
    }
}

/// android `PressMoveInViewTest` (t9 0143) and `PictureFitTest`.
struct PressLayoutTests {
    let view = 1000.0, room = 40.0

    @Test func fullyVisibleNoScroll() {
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: 0, blockHeight: 200, room: room) == nil)
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: 800, blockHeight: 200, room: room) == nil)
    }

    @Test func movedAboveTheTopScrollUpToItWithRoomAbove() {
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: -300, blockHeight: 200, room: room) == -340)
        // Partly hidden at the top counts too.
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: -20, blockHeight: 200, room: room) == -60)
    }

    @Test func movedBelowTheBottomScrollDownSoItsBottomShowsWithRoomUnderIt() {
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: 900, blockHeight: 200, room: room) == 140)
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: 2200, blockHeight: 200, room: room) == 1440)
    }

    @Test func aBlockTallerThanTheScreenLinesUpItsTopAndStaysPutOnceItIsThere() {
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: 500, blockHeight: 1500, room: room) == 460)
        #expect(PressLayout.scrollToShow(viewHeight: view, blockTop: room, blockHeight: 1500, room: room) == nil)
    }

    @Test func squarePortraitAndBannerKeepTheirShapeInTheBox() {
        #expect(PictureFit.fit(384, 384, 300) == (300, 300))
        #expect(PictureFit.fit(384, 512, 300) == (225, 300))
        #expect(PictureFit.fit(640, 320, 200) == (200, 100))
    }

    @Test func aBrokenSizeFallsBackToTheSquareBox() {
        #expect(PictureFit.fit(0, 512, 200) == (200, 200))
    }

    @Test func onThePaperAPictureTakesTheColumnsWidthInItsShapeNoTallerThanTheCap() {
        #expect(PictureFit.within(640, 480, 515, 400) == (515, 386.25))
        // A tall one is held to the cap, and narrower.
        #expect(PictureFit.within(384, 512, 515, 400) == (300, 400))
        #expect(PictureFit.within(640, 320, 515, 400) == (515, 257.5))
        #expect(PictureFit.within(0, 0, 515, 400) == (400, 400))
    }

    @Test func designerSizes() {
        #expect(DesignerCanvas.Size(384, 384).shape == .square)
        #expect(DesignerCanvas.Size(512, 512).quality == .medium)
        #expect(DesignerCanvas.Size(768, 320).quality == .high)
    }
}

/// A fixed-seed generator for the fuzz (SplitMix64).
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
