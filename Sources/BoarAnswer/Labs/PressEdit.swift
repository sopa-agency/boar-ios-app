import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// What Press's page has selected and open (android printer `PressScreen.kt`: `selected`, `editing`, `fresh`, `barNote`),
/// kept here so the rules are tested without the screen. A tap selects a block; the pencil opens it for typing on the
/// page; a block just added is selected and open with its text selected, so typing replaces it.
public struct PressEdit: Sendable, Equatable {
    /// The block with the action bar.
    public var selected: String?
    /// The block typed on the page (a text, or a picture's caption).
    public var editing: String?
    /// A block just added: its field takes the focus with its text selected.
    public var fresh: String?
    /// The last note the bar added: the next one goes after it (it isn't selected, `addedNote`).
    public var barNote: String?

    public init() {}

    /// Where a new block goes: after the selected one (or after the last note the bar added), else at the end.
    public func insertIndex(_ blocks: [PressDoc.Block]) -> Int {
        let anchor = selected ?? barNote
        guard let i = blocks.firstIndex(where: { $0.id == anchor }) else { return blocks.count }
        return i + 1
    }

    /// A block was added (android `addBlock`): selected and open for typing; a picture opens its caption, as the mock-up
    /// does. `opens: false` for a divider, which has nothing to type.
    public mutating func added(_ id: String, opens: Bool = true) {
        barNote = nil
        selected = id
        editing = opens ? id : nil
        fresh = opens ? id : nil
    }

    /// A note typed in the bar (t9 0110 item 4): placed as a block is, but neither selected nor opened, so no key replaces
    /// it; the next note goes after it.
    public mutating func addedNote(_ id: String) {
        added(id)
        selected = nil
        editing = nil
        fresh = nil
        barNote = id
    }

    /// A tap on a block: selects it; another block's typing ends.
    public mutating func select(_ id: String) {
        if selected != id { selected = id; editing = nil }
    }

    /// The pencil or the caption button: opens the selected block for typing, or closes it.
    public mutating func toggleEditing() {
        editing = editing == selected ? nil : selected
    }

    /// Close, a tap on the title, a removed block, Back: nothing selected or open.
    public mutating func close() {
        selected = nil
        editing = nil
    }

    /// A block's text that the pencil edits and that a rewrite works on: a heading's, note's, paragraph's or list's text,
    /// an answer's text (not its heading). Nil for a picture, a divider or an unknown block.
    public static func textOf(_ b: PressDoc.Block) -> String? {
        switch b {
        case .heading(_, let t), .note(_, let t), .paragraph(_, let t), .bullets(_, let t): t
        case .answer(let a): a.text
        default: nil
        }
    }

    /// What the add toolbar holds, in its order (adam, Nov 13): heading, paragraph, list, divider, photo, then a chat's
    /// answers. Android's Designer drawing sits between photo and chat; iOS has none yet (docs/labs-ios.md).
    public enum AddTool: String, Sendable, CaseIterable {
        case heading, paragraph, list, divider, photo, chat
    }
}

extension PressDoc.Place {
    /// The place button's next tap: left → center → right → left (android ActionBar).
    public var next: PressDoc.Place {
        switch self {
        case .left: .center
        case .center: .right
        case .right: .left
        }
    }
}

// MARK: - Text beside a picture

extension PressPDF {
    /// A piece of a text block for the flow beside a side picture (android printer `PressScreen.kt` `Piece`): its text,
    /// its style and the space above it, in points.
    public struct Piece: Sendable, Equatable {
        public enum Style: Sendable, Equatable { case heading, question, body, refs, note }
        public var text: String
        public var style: Style
        public var gap: Double
        public init(_ text: String, _ style: Style, _ gap: Double) { self.text = text; self.style = style; self.gap = gap }
    }

    /// A text block as pieces: an answer's heading, question, text and sources line; a note's, paragraph's or list's text.
    public static func pieces(_ b: PressDoc.Block, _ page: PressPage) -> [Piece] {
        switch b {
        case .answer(let a):
            var out = [Piece(PressPage.oneLine(a.shownHeading), .heading, 0)]
            if let q = a.shownQuestion { out.append(Piece(q.kotlinTrim(), .question, 3)) }
            out.append(Piece(page.answerText(a), .body, 3))
            if let refs = page.refsLine(a) { out.append(Piece(refs, .refs, 4)) }
            return out
        case .note(_, let t): return [Piece(t, .note, 0)]
        case .paragraph(_, let t): return [Piece(t.kotlinTrim(), .body, 0)]
        case .bullets(_, let t): return [Piece(PressDoc.bulleted(t), .body, 0)]
        default: return []
        }
    }

    /// The type the PDF uses for a piece, and its line spacing.
    static func font(_ s: Piece.Style) -> (Font, Double) {
        switch s {
        case .heading: (serif(PressPaper.heading, bold: true), 1.15)
        case .question: (serif(PressPaper.question, italic: true, color: PressPaper.muted), 1.15)
        case .body: (serif(PressPaper.body), PressPaper.pdfSpacing)
        case .refs: (sans(PressPaper.refs, color: PressPaper.meta), 1.15)
        case .note: (serif(PressPaper.note, italic: true, color: PressPaper.muted), PressPaper.pdfSpacing)
        }
    }

    /// Splits a text block's pieces between beside a side picture and below it (android `BesideView`): the lines whose top
    /// is above `room` (the picture's height and 8 points, from the top of the text) go beside it, at the beside width
    /// (less a note's indent), the rest continue below at the full width. Measured with the PDF's own lines, in points,
    /// so the paper breaks where the PDF does.
    public static func splitBeside(_ pieces: [Piece], room: Double, indent: Double = 0) -> (beside: [Piece], below: [Piece]) {
        let width = (PressLayout.besideWidth(PressPaper.inner) - indent).rounded(.towardZero)
        var beside: [Piece] = []
        var below: [Piece] = []
        var y = 0.0
        for p in pieces {
            if PressDoc.isBlank(p.text) { continue }
            if y >= room { below.append(p); continue }
            let (font, spacing) = font(p.style)
            let laid = Laid(p.text, font, spacing: spacing)
            let lines = laid.lines(from: 0, width: width)
            let n = PressLayout.linesBeside(lines.map { y + p.gap + $0.top }, room)
            if n >= lines.count {
                beside.append(p)
                y += p.gap + (lines.last?.bottom ?? 0)
            } else if n == 0 {
                below.append(p)
                y = room
            } else {
                let ns = p.text as NSString
                let cut = lines[n].start
                var head = p, tail = p
                head.text = String(ns.substring(to: cut)).kotlinTrimEnd()
                tail.text = String(ns.substring(from: cut)).kotlinTrimStart()
                tail.gap = 0
                beside.append(head)
                below.append(tail)
                y = room
            }
        }
        return (beside, below)
    }
}

// MARK: - Photos

extension PressFiles {
    public enum PhotoError: Error { case notAPicture, notSaved }

    /// A photo picked on the device (PhotosPicker), COPIED into its project's folder (android printer `PressPictures.
    /// copyPhoto`): turned upright, mirrored ones too (G-6), its long side at most `photoMax`, as a JPEG at 85. The
    /// original stays in the library; the copy goes with its project. Returns the picture block. Off the main actor.
    public static func copyPhoto(_ data: Data, pressDir: URL, projectId: String, blockId: String, name: String) throws -> PressDoc.Picture {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let ph = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, pw > 0, ph > 0 else { throw PhotoError.notAPicture }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let (w, h) = scaled(pw, ph)
        // Decoded at the copy's size (as Android's inSampleSize, then a scale), pixels as stored: turned upright below.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let raw = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw PhotoError.notAPicture }
        let img = try uprighted(raw, orientation)
        let file = try copyInto(pressDir, projectId, name) { url in
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw PhotoError.notSaved }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            if !CGImageDestinationFinalize(dest) { throw PhotoError.notSaved }
        }
        return PressDoc.Picture(blockId, .photo, file.lastPathComponent, width: img.width, height: img.height)
    }

    /// The image stood upright by its EXIF orientation (`upright`): rotated clockwise, then mirrored left-right.
    static func uprighted(_ img: CGImage, _ orientation: Int) throws -> CGImage {
        let (degrees, mirror) = upright(orientation)
        if degrees == 0 && !mirror { return img }
        let turned = degrees == 90 || degrees == 270
        let w = turned ? img.height : img.width
        let h = turned ? img.width : img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PhotoError.notSaved }
        ctx.interpolationQuality = .high
        // Applied to the image last to first: rotate (clockwise on the page: negative in Core Graphics' y-up space), then
        // mirror, then centre in the new box.
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        if mirror { ctx.scaleBy(x: -1, y: 1) }
        ctx.rotate(by: -CGFloat(degrees) * .pi / 180)
        ctx.draw(img, in: CGRect(x: -CGFloat(img.width) / 2, y: -CGFloat(img.height) / 2, width: CGFloat(img.width), height: CGFloat(img.height)))
        guard let out = ctx.makeImage() else { throw PhotoError.notSaved }
        return out
    }
}
