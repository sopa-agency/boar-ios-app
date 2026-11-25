import Foundation

/// Where Press's pictures sit (android engine `labs/PressLayout.kt`; adam's mock-up, Nov 13): a picture placed center
/// takes the column's width; left or right takes `side` of it, and the text of the NEXT text block (an answer, a note, a
/// paragraph or a list) flows beside it, then continues at the full width below. A heading never starts beside a
/// picture: after a side picture it starts below it, and so does any block after the one that flowed. The paper on
/// screen and the PDF both follow `plan`, with the same widths and the same line rule (`linesBeside`).
public enum PressLayout {
    /// Keeps a moved block in view (adam, Nov 14; t9 0143). `blockTop` is the block's top from the viewport's top, all in
    /// points. Nil when the block is fully visible; else how far to scroll (negative: up): `room` above it, or its bottom
    /// `room` above the viewport's bottom when it went down, and a block taller than the viewport lines up its top.
    public static func scrollToShow(viewHeight: Double, blockTop: Double, blockHeight: Double, room: Double) -> Double? {
        if blockTop >= 0 && blockTop + blockHeight <= viewHeight { return nil }
        let delta = blockTop < 0 || blockHeight + 2 * room > viewHeight ? blockTop - room : blockTop + blockHeight + room - viewHeight
        return abs(delta) >= 1 ? delta : nil
    }

    /// A side picture's share of the column, and the gap between it and the text.
    public static let side = 0.45
    public static let gutter = 14.0

    public enum Item: Sendable, Equatable {
        /// A block on its own, at the full width (a centered picture, or any block not beside one).
        case single(PressDoc.Block)
        /// A side picture, and the text block that flows beside it (nil: nothing flows; what follows starts below).
        case beside(PressDoc.Picture, text: PressDoc.Block?, left: Bool)
    }

    /// Text that may flow beside a picture; a heading (and another picture, or a divider) never does.
    public static func flows(_ b: PressDoc.Block?) -> Bool {
        switch b {
        case .answer?, .note?, .paragraph?, .bullets?: true
        default: false
        }
    }

    public static func plan(_ blocks: [PressDoc.Block]) -> [Item] {
        var out: [Item] = []
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            if case .picture(let p) = b, p.place != .center {
                let next = i + 1 < blocks.count && flows(blocks[i + 1]) ? blocks[i + 1] : nil
                out.append(.beside(p, text: next, left: p.place == .left))
                i += next != nil ? 2 : 1
            } else {
                out.append(.single(b))
                i += 1
            }
        }
        return out
    }

    /// A side picture's box width in a column of `inner` points.
    public static func sideWidth(_ inner: Double) -> Double { inner * side }

    /// The text's width beside a side picture.
    public static func besideWidth(_ inner: Double) -> Double { inner - sideWidth(inner) - gutter }

    /// How many lines go beside a picture `height` tall: those whose top is above the picture's bottom (`lineTops` from
    /// the top of the text beside it, in order). The rest continue at the full width.
    public static func linesBeside(_ lineTops: [Double], _ height: Double) -> Int {
        lineTops.prefix { $0 < height }.count
    }
}

/// Press's pictures keep their shape (android engine `labs/PictureFit.kt`; adam, Nov 11).
public enum PictureFit {
    /// The longer side fills `box`, the shorter one follows.
    public static func fit(_ width: Int, _ height: Int, _ box: Double) -> (Double, Double) {
        if width <= 0 || height <= 0 { return (box, box) }
        return width >= height ? (box, box * Double(height) / Double(width)) : (box * Double(width) / Double(height), box)
    }

    /// The paper's pictures (Nov 13): as wide as the column, in their own shape, no taller than `maxHeight` (a tall one
    /// is narrower then). A broken size gets a square.
    public static func within(_ width: Int, _ height: Int, _ maxWidth: Double, _ maxHeight: Double) -> (Double, Double) {
        if width <= 0 || height <= 0 { let s = min(maxWidth, maxHeight); return (s, s) }
        let scale = min(maxWidth / Double(width), maxHeight / Double(height))
        return (Double(width) * scale, Double(height) * scale)
    }
}
