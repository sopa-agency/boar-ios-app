import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import BoarAnswer

/// Press's page (BOAR-55 part 6.2): what the screen selects and opens, where a new block goes, the place button, the text
/// beside a side picture and the photo copy. Android checks some of these by reading `PressScreen.kt`'s source
/// (`PressBarNoteTest`, the add toolbar's order, the move that stays in view); here they're rules in `PressEdit`, tested
/// by behaviour.
struct PressEditTests {
    typealias Block = PressDoc.Block

    private let blocks: [Block] = [.heading(id: "h1", text: "A"), .paragraph(id: "t1", text: "B"), .divider(id: "d1")]

    // android PressBarNoteTest (t9 0110 item 4)
    @Test func aNoteFromTheBarIsPlacedButNeitherSelectedNorOpenedAndTheNextOneFollowsIt() {
        var e = PressEdit()
        #expect(e.insertIndex(blocks) == 3)
        var doc = blocks
        doc.insert(.note(id: "n1", text: "first"), at: e.insertIndex(doc))
        e.addedNote("n1")
        #expect(e.selected == nil && e.editing == nil && e.fresh == nil)
        #expect(e.barNote == "n1")
        // The next note goes right after it, not to the end.
        e.select("h1")
        e.close()
        #expect(e.insertIndex(doc) == 4)
        doc.insert(.note(id: "n0", text: "x"), at: 1)
        #expect(e.insertIndex(doc) == 5)
    }

    @Test func aNewBlockGoesAfterTheSelectedOneAndOpensWithItsTextSelected() {
        var e = PressEdit()
        e.select("t1")
        #expect(e.insertIndex(blocks) == 2)
        e.barNote = "h1"
        // The selection wins over the bar's last note.
        #expect(e.insertIndex(blocks) == 2)
        e.added("h2")
        #expect(e.selected == "h2" && e.editing == "h2" && e.fresh == "h2" && e.barNote == nil)
        // A divider has nothing to type.
        e.added("d2", opens: false)
        #expect(e.selected == "d2" && e.editing == nil && e.fresh == nil)
        // An unknown anchor: the end.
        e.selected = "gone"
        #expect(e.insertIndex(blocks) == 3)
    }

    @Test func selectingAnotherBlockEndsTypingAndThePencilToggles() {
        var e = PressEdit()
        e.select("t1")
        e.toggleEditing()
        #expect(e.editing == "t1")
        e.select("t1")
        #expect(e.editing == "t1")
        e.select("h1")
        #expect(e.selected == "h1" && e.editing == nil)
        e.toggleEditing()
        e.toggleEditing()
        #expect(e.editing == nil)
        e.close()
        #expect(e.selected == nil && e.editing == nil)
    }

    // android PressMoreBlocksTest: the add toolbar is heading, paragraph, list, divider, photo (adam's order), then chats.
    @Test func theAddToolbarIsHeadingParagraphListDividerPhotoThenChats() {
        #expect(PressEdit.AddTool.allCases == [.heading, .paragraph, .list, .divider, .photo, .chat])
    }

    @Test func thePlaceButtonGoesLeftCenterRight() {
        #expect(PressDoc.Place.left.next == .center)
        #expect(PressDoc.Place.center.next == .right)
        #expect(PressDoc.Place.right.next == .left)
    }

    @Test func thePencilWorksOnTextsNotOnPicturesOrDividers() {
        #expect(PressEdit.textOf(.heading(id: "h", text: "H")) == "H")
        #expect(PressEdit.textOf(.bullets(id: "l", text: "a\nb")) == "a\nb")
        #expect(PressEdit.textOf(.answer(PressDoc.Answer("a", "Chat", "Q?", "The text"))) == "The text")
        #expect(PressEdit.textOf(.divider(id: "d")) == nil)
        #expect(PressEdit.textOf(.picture(PressDoc.Picture("p", .photo, "p.jpg"))) == nil)
    }

    // MARK: text beside a picture

    private func page(_ b: [Block]) -> PressPage { PressPage(project: PressDoc.Project("p", "Coast", 1, b), date: "25 November 2026", version: "1") }

    @Test func shortTextGoesBesideWholeLongTextContinuesBelow() {
        let short = Block.paragraph(id: "t", text: "Salt dries in the sun.")
        let s = PressPDF.splitBeside(PressPDF.pieces(short, page([short])), room: 200)
        #expect(s.beside.map(\.text) == ["Salt dries in the sun."] && s.below.isEmpty)

        let words = (1...200).map { "word\($0)" }.joined(separator: " ")
        let long = Block.paragraph(id: "t", text: words)
        let l = PressPDF.splitBeside(PressPDF.pieces(long, page([long])), room: 120)
        #expect(l.beside.count == 1 && l.below.count == 1)
        // Cut at a line's end: nothing lost, nothing doubled.
        #expect(l.beside[0].text + " " + l.below[0].text == words)
        #expect(l.below[0].gap == 0)
        // As many lines as start above the room, at the beside width (the PDF's own rule).
        let laid = PressPDF.Laid(words, PressPDF.font(.body).0, spacing: PressPaper.pdfSpacing)
        let lines = laid.lines(from: 0, width: PressLayout.besideWidth(PressPaper.inner).rounded(.towardZero))
        let n = PressLayout.linesBeside(lines.map(\.top), 120)
        #expect(n > 0 && n < lines.count)
        #expect(l.beside[0].text == (words as NSString).substring(to: lines[n].start).kotlinTrimEnd())
    }

    @Test func anAnswersPiecesFillTheRoomInOrderAndTheRestGoBelow() {
        let a = Block.answer(PressDoc.Answer("a", "Chat", "Why is the sea salty?", String(repeating: "Rivers carry salt to the sea. ", count: 30),
                                           heading: "Salt"))
        let pieces = PressPDF.pieces(a, page([a]))
        #expect(pieces.map(\.style) == [.heading, .question, .body])
        #expect(pieces.map(\.gap) == [0, 3, 3])
        let s = PressPDF.splitBeside(pieces, room: 90)
        #expect(s.beside.first?.style == .heading)
        #expect(s.below.last?.style == .body)
        // No room at all: everything below.
        let none = PressPDF.splitBeside(pieces, room: 0)
        #expect(none.beside.isEmpty && none.below.count == 3)
        // Blank pieces are dropped.
        let blank = Block.note(id: "n", text: "  ")
        #expect(PressPDF.splitBeside(PressPDF.pieces(blank, page([blank])), room: 100) == ([], []))
    }

    // MARK: photos (android PressPicturesTest's copy, G-6 on real pixels)

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "press-edit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A PNG `w` × `h`, its left half red and its right half blue, with that EXIF orientation.
    private func png(_ w: Int, _ h: Int, orientation: Int) throws -> Data {
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
        let img = try #require(ctx.makeImage())
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    /// The colour at (x, y) from the top left: "r", "b" or "?".
    private func color(_ url: URL, _ x: Int, _ y: Int) throws -> String {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // The pixel (x, y) from the top lands on the 1 × 1 context.
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return px[0] > 180 && px[2] < 80 ? "r" : px[2] > 180 && px[0] < 80 ? "b" : "?"
    }

    @Test func aPhotoIsCopiedUprightAsAJPEGInItsProjectsFolder() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        // As taken: no turn.
        let plain = try PressFiles.copyPhoto(png(40, 20, orientation: 1), pressDir: press, projectId: "p1", blockId: "pic-1", name: "photo-1.jpg")
        #expect(plain.id == "pic-1" && plain.kind == .photo && plain.file == "photo-1.jpg")
        #expect(plain.width == 40 && plain.height == 20)
        let f1 = PressFiles.photoFile(press, "p1", plain.file)
        #expect(try color(f1, 5, 10) == "r" && color(f1, 35, 10) == "b")
        // 6: turned 90° clockwise, the left (red) half on top.
        let six = try PressFiles.copyPhoto(png(40, 20, orientation: 6), pressDir: press, projectId: "p1", blockId: "pic-2", name: "photo-2.jpg")
        #expect(six.width == 20 && six.height == 40)
        let f2 = PressFiles.photoFile(press, "p1", six.file)
        #expect(try color(f2, 10, 5) == "r" && color(f2, 10, 35) == "b")
        // 2: mirrored left-right (G-6).
        let two = try PressFiles.copyPhoto(png(40, 20, orientation: 2), pressDir: press, projectId: "p1", blockId: "pic-3", name: "photo-3.jpg")
        let f3 = PressFiles.photoFile(press, "p1", two.file)
        #expect(try color(f3, 5, 10) == "b" && color(f3, 35, 10) == "r")
        // 8: turned 270° clockwise, the left half at the bottom.
        let eight = try PressFiles.copyPhoto(png(40, 20, orientation: 8), pressDir: press, projectId: "p1", blockId: "pic-4", name: "photo-4.jpg")
        let f4 = PressFiles.photoFile(press, "p1", eight.file)
        #expect(try color(f4, 10, 5) == "b" && color(f4, 10, 35) == "r")
        // A JPEG, and no half copy left.
        let head = try Data(contentsOf: f1).prefix(2)
        #expect(head == Data([0xFF, 0xD8]))
        #expect(!FileManager.default.fileExists(atPath: f1.path + ".tmp"))
    }

    @Test func aBigPhotoIsDownscaledInItsShapeAndJunkIsNotAPicture() throws {
        let press = try tempDir()
        defer { try? FileManager.default.removeItem(at: press) }
        let big = try PressFiles.copyPhoto(png(4000, 1000, orientation: 1), pressDir: press, projectId: "p1", blockId: "b", name: "big.jpg")
        #expect(big.width == 1600 && big.height == 400)
        #expect(throws: PressFiles.PhotoError.self) {
            try PressFiles.copyPhoto(Data("not a photo".utf8), pressDir: press, projectId: "p1", blockId: "j", name: "junk.jpg")
        }
        #expect(!FileManager.default.fileExists(atPath: press.appending(path: "p1/junk.jpg").path))
    }
}
