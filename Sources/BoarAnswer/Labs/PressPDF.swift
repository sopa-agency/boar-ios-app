import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The paper's measures, in PDF points (A4: 595 × 842; android printer `PressPage.kt` `Paper`). The page in the app is
/// meant to be what the PDF prints.
public enum PressPaper {
    public static let w = 595.0
    public static let h = 842.0
    public static let m = 40.0
    public static let inner = w - 2 * m

    public static let title = 30.0
    public static let date = 11.5
    public static let heading = 21.0
    public static let question = 15.0
    public static let body = 16.0
    /// Line height over font size, on the screen; the PDF gets the same height through `pdfSpacing`.
    public static let line = 1.4
    public static let pdfSpacing = 1.2
    public static let refs = 12.0
    public static let note = 15.0
    public static let caption = 13.0
    public static let receiptTitle = 12.5
    /// The document's footer: small, light, centered (adam, Nov 13).
    public static let footer = 8.5
    public static let gap = 14.0
    /// The tallest a picture gets: about half a page.
    public static let pictureMaxH = 380.0
    /// A card's text: a little smaller than the answer's.
    public static let card = 13.0
    public static let cardTitle = 14.0

    public static let ink: UInt32 = 0x1D1D1F
    public static let muted: UInt32 = 0x55596A
    public static let meta: UInt32 = 0x7A7F90
    public static let dateInk: UInt32 = 0x6B7080
    public static let rule: UInt32 = 0xD5D8E2
    public static let receiptInk: UInt32 = 0x5D6273
    public static let noteBar: UInt32 = 0xD0D4E0
    public static let footInk: UInt32 = 0x9A9EAC
    /// A card's bars: the ink's grey, so a black-and-white print still reads.
    public static let bar: UInt32 = 0x6B7080
    public static let barTrack: UInt32 = 0xE8EAF0
}

/// One project as it prints (android printer `PressPage`): the date, the receipt and the words, the same for the paper,
/// the PDF and the Markdown. The app fills the words from its catalog and the options from Press settings.
public struct PressPage: Sendable {
    public var project: PressDoc.Project
    public var date: String
    public var version: String
    public var receipt: PressReceipt.Receipt
    public var labels: PressReceipt.Labels
    public var sourcesLabel: String
    /// What prints besides the blocks (Press settings, adam Nov 14).
    public var options: PressReceipt.Options
    /// The line under a card the model made ("made by the model · checked against the answer").
    public var cardByModel: String

    public init(project: PressDoc.Project, date: String, version: String, receipt: PressReceipt.Receipt? = nil,
                labels: PressReceipt.Labels = PressReceipt.Labels(), sourcesLabel: String = "Sources",
                options: PressReceipt.Options = PressReceipt.Options(), cardByModel: String = "") {
        self.project = project; self.date = date; self.version = version
        self.receipt = receipt ?? PressReceipt.build(project)
        self.labels = labels; self.sourcesLabel = sourcesLabel; self.options = options; self.cardByModel = cardByModel
    }

    public var rows: [PressReceipt.Row] { PressReceipt.rows(receipt, labels, date: date, version: version) }

    /// The Sources section at the end, one line per source with its pack; empty when off or there are none.
    public var sourceLines: [String] { PressReceipt.sourceLines(receipt, options, ownFile: labels.ownFile) }

    /// The footer: the models' line when on, and "Made offline with BOAR", always.
    public var footer: [String] { PressReceipt.footer(receipt, labels, date: date, options) }

    /// An answer's text as it prints: plain, its [k] marks as the document's numbers (none when sources are off).
    public func answerText(_ a: PressDoc.Answer) -> String {
        PressReceipt.plain(PressReceipt.renumber(a.text, options.sources ? receipt.local[a.id] ?? [:] : [:]))
    }

    public func refsLine(_ a: PressDoc.Answer) -> String? {
        options.sources ? PressReceipt.refsLine(receipt.refs[a.id], sourcesLabel) : nil
    }

    public func markdown(drawingLabel: String, photoLabel: String? = nil) -> String {
        PressReceipt.markdown(project, labels, date: date, version: version, sourcesLabel: sourcesLabel, drawingLabel: drawingLabel,
                              receipt: receipt, photoLabel: photoLabel ?? drawingLabel, options: options)
    }

    /// A heading on one line: its line breaks as spaces.
    public static func oneLine(_ s: String) -> String {
        s.kotlinTrim().replacingOccurrences(of: #"[ \t\n\x{0B}\f\r]*\n[ \t\n\x{0B}\f\r]*"#, with: " ", options: .regularExpression)
    }
}

/// A project as an A4 PDF (android printer `PdfCompiler.kt`), offline, with Core Text and Core Graphics so the same code
/// runs on the iPhone, the Mac and the test host: the title and date, the blocks in order (heading; answer: its heading,
/// the question in italics, the text, "Sources [n]", its card; note; paragraph; list; divider; picture with its caption
/// if it has one, a side picture with the next text beside it), then the Sources section and the footer. Text flows
/// across pages line by line; a heading that would end a page alone starts the next one, a picture that doesn't fit
/// starts a new page.
public enum PressPDF {
    /// Where a PDF page starts, for the paper on screen: the block it starts in (`unit`, a block id, `titleUnit`,
    /// `sourcesUnit` or `receiptUnit`) and how many points of that block came before it. 0: the block starts the page.
    public struct PageStart: Sendable, Equatable {
        public var unit: String
        public var intoPt: Double
        public init(_ unit: String, _ intoPt: Double) { self.unit = unit; self.intoPt = intoPt }
    }

    public static let titleUnit = "title"
    public static let receiptUnit = "receipt"
    public static let sourcesUnit = "sources"

    /// `fileOf` is a picture's file, or nil when it is gone (it is left out).
    public static func compile(_ page: PressPage, fileOf: (PressDoc.Picture) -> URL?) -> Data {
        let data = NSMutableData()
        guard let pager = Pager(data: data, dry: false) else { return Data() }
        layout(pager, page, fileOf)
        pager.close()
        return data as Data
    }

    /// The same layout as `compile`, no picture decoded (sizes only): where each page after the first starts.
    public static func pageStarts(_ page: PressPage, fileOf: (PressDoc.Picture) -> URL?) -> [PageStart] {
        guard let pager = Pager(data: NSMutableData(), dry: true) else { return [] }
        layout(pager, page, fileOf)
        pager.close()
        return pager.starts
    }

    private static func layout(_ p: Pager, _ page: PressPage, _ fileOf: (PressDoc.Picture) -> URL?) {
        p.begin(titleUnit)
        let name = page.project.name.kotlinTrim()
        p.text(name.isEmpty ? " " : name, serif(PressPaper.title, bold: true), after: 4)
        if page.options.date {
            p.text(page.date.uppercased(), sans(PressPaper.date, color: PressPaper.dateInk), after: PressPaper.gap + 4)
        } else {
            p.gap(PressPaper.gap)
        }
        func caption(_ b: PressDoc.Picture) -> (String, Font)? {
            let c = b.caption.kotlinTrim()
            return c.isEmpty ? nil : (c, serif(PressPaper.caption, italic: true, color: PressPaper.muted))
        }
        // The same plan as the paper on screen: a side picture with the next text block beside it (PressLayout).
        for item in PressLayout.plan(page.project.blocks) {
            switch item {
            case .single(let b):
                p.begin(b.id)
                if case .picture(let pic) = b {
                    if let f = fileOf(pic) {
                        // Empty captions don't print.
                        p.picture(f, caption: caption(pic))
                        p.gap(PressPaper.gap)
                    }
                } else {
                    block(p, page, b)
                }
            case .beside(let pic, let text, let left):
                let f = fileOf(pic)
                p.begin(pic.id)
                if let f { p.sidePicture(f, left: left, caption: caption(pic)) }
                if let text { p.begin(text.id); block(p, page, text) }
                // What follows (a heading above all) starts below the picture.
                p.endBeside()
                p.gap(text == nil ? PressPaper.gap : 0)
            }
        }
        sources(p, page)
        p.begin(receiptUnit)
        receipt(p, page)
        p.finish()
    }

    /// A text block (or nothing for the others): beside a picture, the Pager narrows its lines.
    private static func block(_ p: Pager, _ page: PressPage, _ b: PressDoc.Block) {
        switch b {
        case .heading(_, let t):
            guard !PressDoc.isBlank(t) else { return }
            p.keepRoom(PressPaper.heading * 1.4 + PressPaper.body * 3)
            p.text(t.kotlinTrim(), serif(PressPaper.heading, bold: true), after: PressPaper.gap)
        case .answer(let a):
            p.keepRoom(PressPaper.heading * 1.4 + PressPaper.body * 3)
            p.text(PressPage.oneLine(a.shownHeading), serif(PressPaper.heading, bold: true), after: 3)
            if let q = a.shownQuestion { p.text(q.kotlinTrim(), serif(PressPaper.question, italic: true, color: PressPaper.muted), after: 3) }
            p.text(page.answerText(a), serif(PressPaper.body), after: 4, spacing: PressPaper.pdfSpacing)
            if let refs = page.refsLine(a) { p.text(refs, sans(PressPaper.refs, color: PressPaper.meta), after: 0) }
            // The card after the answer's own lines, as on the paper (beside a picture too, where it goes below it).
            if let card = a.card { self.card(p, page, card) }
            p.gap(PressPaper.gap)
        case .note(_, let t):
            guard !PressDoc.isBlank(t) else { return }
            p.text(t.kotlinTrim(), serif(PressPaper.note, italic: true, color: PressPaper.muted), after: PressPaper.gap,
                   spacing: PressPaper.pdfSpacing, indent: 12)
        case .paragraph(_, let t):
            guard !PressDoc.isBlank(t) else { return }
            p.text(t.kotlinTrim(), serif(PressPaper.body), after: PressPaper.gap, spacing: PressPaper.pdfSpacing)
        case .bullets(_, let t):
            guard !PressDoc.items(t).isEmpty else { return }
            p.text(PressDoc.bulleted(t), serif(PressPaper.body), after: PressPaper.gap, spacing: PressPaper.pdfSpacing)
        case .divider:
            p.gap(4); p.rule(); p.gap(PressPaper.gap - 10)
        case .picture, .unknown:
            break
        }
    }

    /// An answer's card under its text, drawn as on screen: bars, a table, the steps (✓ for a ticked one), the things
    /// compared side by side, the key facts. A pie or a line prints as its table. Full width: below a side picture.
    private static func card(_ p: Pager, _ page: PressPage, _ card: AnswerCard) {
        let text = sans(PressPaper.card)
        let muted = sans(PressPaper.card, color: PressPaper.muted)
        p.endBeside()
        p.keepRoom(PressPaper.cardTitle * 1.4 + PressPaper.card * 4)
        p.gap(4)
        p.rule()
        if !PressDoc.isBlank(card.title) { p.text(card.title.kotlinTrim(), sans(PressPaper.cardTitle, bold: true), after: 2) }
        if card.byModel && !PressDoc.isBlank(page.cardByModel) {
            p.text(page.cardByModel, sans(PressPaper.refs, color: PressPaper.meta), after: 4)
        } else {
            p.gap(2)
        }
        switch card.body {
        case .series(_, let points) where card.shape == .bars:
            p.bars(points.map { ($0.label, $0.written) }, points.map { abs($0.value) }, label: text, value: muted)
        case .series, .table:
            if let t = AnswerCard.asTable(card) {
                if t.header.contains(where: { !PressDoc.isBlank($0) }) {
                    p.cells(t.header.map { $0.uppercased() }, sans(PressPaper.refs, bold: true, color: PressPaper.meta), rule: false)
                }
                for row in t.rows { p.cells(row, text, rule: true) }
            }
        case .steps(let items):
            for (i, step) in items.enumerated() {
                p.cells([card.ticks.contains(i) ? "✓" : "\(i + 1)", step], text, rule: false, widths: [0.07, 0.93])
            }
        case .facts(let pairs):
            for f in pairs { p.cells([f.label, f.value], text, rule: true, widths: [0.38, 0.62], first: muted) }
        case .compare(let sides):
            p.cells(sides.map { s in s.name + "\n" + s.points.map { "•  " + $0 }.joined(separator: "\n") }, text, rule: false)
        }
        p.gap(4)
    }

    /// The Sources section at the end of the document (adam, Nov 14): a small heading, then each source by its [n] with
    /// its pack. Its heading never ends a page alone.
    private static func sources(_ p: Pager, _ page: PressPage) {
        let lines = page.sourceLines
        guard !lines.isEmpty else { return }
        p.begin(sourcesUnit)
        p.keepRoom(PressPaper.gap + PressPaper.receiptTitle * 1.6 + PressPaper.refs * 2.6)
        p.gap(PressPaper.gap)
        p.text(page.sourcesLabel, sans(PressPaper.receiptTitle, bold: true), after: 6)
        let line = sans(PressPaper.refs, color: PressPaper.receiptInk)
        for l in lines { p.text(l, line, after: 3, spacing: 1.25) }
    }

    /// The footer, always at the end (adam, Nov 13): a short centered hairline, then at most two small light lines (the
    /// models; "Made offline with BOAR" and the date). Kept together on one page (t9 1721); on a nearly full last page
    /// the space above it shrinks instead of moving the footer alone to a new page (2c09f532).
    private static func receipt(_ p: Pager, _ page: PressPage) {
        let lines = page.footer
        let font = sans(PressPaper.footer, color: PressPaper.footInk)
        var total = 8.0
        for line in lines { total += Laid(line, font, spacing: 1.3).height(width: PressPaper.inner) + 2 }
        let above = p.room() >= total + 18 ? 18.0 : 6.0
        p.keepRoom(min(total + above, PressPaper.h - 2 * PressPaper.m))
        p.gap(above)
        p.shortRule()
        for line in lines { p.text(line, font, after: 2, spacing: 1.3, center: true) }
    }

    // MARK: type

    struct Font {
        let ct: CTFont
        let color: UInt32
        var size: Double { Double(CTFontGetSize(ct)) }
    }

    /// Android's Typeface.SERIF; Core Text falls back per character for scripts Georgia lacks (Arabic, Chinese, emoji).
    static func serif(_ size: Double, bold: Bool = false, italic: Bool = false, color: UInt32 = PressPaper.ink) -> Font {
        let name = switch (bold, italic) {
        case (true, true): "Georgia-BoldItalic"
        case (true, false): "Georgia-Bold"
        case (false, true): "Georgia-Italic"
        case (false, false): "Georgia"
        }
        return Font(ct: CTFontCreateWithName(name as CFString, size, nil), color: color)
    }

    /// Android's Typeface.SANS_SERIF: the system's.
    static func sans(_ size: Double, bold: Bool = false, color: UInt32 = PressPaper.ink) -> Font {
        let f = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return Font(ct: f, color: color)
    }

    static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Text laid out in lines of a width (Android's StaticLayout): each line `(ascent + descent) × spacing` tall.
    final class Laid {
        struct Line {
            let line: CTLine
            let start: Int
            let top: Double
            let bottom: Double
            let ascent: Double
            let width: Double
        }

        let attributed: NSAttributedString
        let length: Int
        private let typesetter: CTTypesetter
        private let spacing: Double
        private let fontAscent: Double
        private let fontDescent: Double

        init(_ s: String, _ font: Font, spacing: Double) {
            attributed = NSAttributedString(string: s, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font.ct,
                kCTForegroundColorAttributeName as NSAttributedString.Key: PressPDF.cgColor(font.color),
            ])
            length = attributed.length
            typesetter = CTTypesetterCreateWithAttributedString(attributed)
            self.spacing = spacing
            fontAscent = Double(CTFontGetAscent(font.ct))
            fontDescent = Double(CTFontGetDescent(font.ct))
        }

        /// The lines from `start` on, at `width`; tops and bottoms from the first one's top.
        func lines(from start: Int, width: Double) -> [Line] {
            var out: [Line] = []
            var i = start
            var top = 0.0
            while i < length {
                var n = CTTypesetterSuggestLineBreak(typesetter, i, max(width, 1))
                if n <= 0 { n = 1 }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: i, length: n))
                var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
                let w = CTLineGetTypographicBounds(line, &a, &d, &l) - CTLineGetTrailingWhitespaceWidth(line)
                let ascent = max(Double(a), fontAscent)
                let h = (ascent + max(Double(d), fontDescent)) * spacing
                out.append(Line(line: line, start: i, top: top, bottom: top + h, ascent: ascent, width: max(w, 0)))
                top += h
                i += n
            }
            return out
        }

        func height(width: Double) -> Double { lines(from: 0, width: width).last?.bottom ?? 0 }
    }

    /// Pages and the pen's height on the current one (`y` from the top, as Android's canvas counts). `dry`: lay out only
    /// (pageStarts): pictures are measured from their size, nothing is decoded.
    final class Pager {
        let ctx: CGContext
        let dry: Bool
        /// Where each page after the first starts (PageStart).
        private(set) var starts: [PageStart] = []
        private var unit = titleUnit
        private var unitTop = PressPaper.m
        private var unitDone = 0.0
        private var n = 0
        private var open = false
        private var y = PressPaper.m
        private let bottom = PressPaper.h - PressPaper.m

        /// A side picture's region: the text beside it is narrower until `bottom`; `left` puts the picture on the left.
        private struct Beside { let left: Bool; let bottom: Double }
        private var float: Beside?

        init?(data: NSMutableData, dry: Bool) {
            var box = CGRect(x: 0, y: 0, width: PressPaper.w, height: PressPaper.h)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
            self.ctx = ctx
            self.dry = dry
        }

        /// The block being laid out now; a page that starts inside it is recorded with how far into it.
        func begin(_ id: String) { unit = id; unitTop = y; unitDone = 0 }

        /// A picture's pixel size: decoded for the PDF, read from the file's header in a dry run.
        private func imageOrSize(_ url: URL) -> (CGImage?, Int, Int)? {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            if dry {
                guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                      let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0 else { return nil }
                return (nil, w, h)
            }
            guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return (img, img.width, img.height)
        }

        private func ensurePage() { if !open { newPage() } }

        private func newPage() {
            if open {
                let into = unitDone + max(y - unitTop, 0)
                starts.append(PageStart(unit, into))
                unitDone = into
                finishPage()
            }
            ctx.beginPDFPage(nil)
            open = true
            n += 1
            y = PressPaper.m
            unitTop = PressPaper.m
            float = nil
        }

        private func finishPage() {
            let number = NSAttributedString(string: "\(n)", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
                kCTForegroundColorAttributeName as NSAttributedString.Key: cgColor(PressPaper.footInk),
            ])
            let line = CTLineCreateWithAttributedString(number)
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: PressPaper.w / 2 - w / 2, y: PressPaper.m / 2)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
            open = false
        }

        /// What is left on this page, in points.
        func room() -> Double { bottom - y }

        /// Starts a new page unless `h` points still fit on this one (a heading never ends a page alone); not beside a
        /// picture.
        func keepRoom(_ h: Double) {
            ensurePage()
            if float == nil && y > PressPaper.m && bottom - y < h { newPage() }
        }

        private func draw(_ l: Laid.Line, x: Double, top: Double, width: Double, center: Bool) {
            ctx.textMatrix = .identity
            let dx = center ? max((width - l.width) / 2, 0) : 0
            ctx.textPosition = CGPoint(x: x + dx, y: PressPaper.h - (top + l.top + l.ascent))
            CTLineDraw(l.line, ctx)
        }

        /// Text that flows across pages line by line; `indent` with a bar on its left (a note). Beside a side picture the
        /// lines whose top is above the picture's bottom are narrower (PressLayout.linesBeside), the rest get the full
        /// width back.
        func text(_ s: String, _ font: Font, after: Double, spacing: Double = 1.15, indent: Double = 0, center: Bool = false) {
            if PressDoc.isBlank(s) { y += after; return }
            let laid = Laid(s, font, spacing: spacing)
            var start = 0
            var fresh = false
            while start < laid.length {
                ensurePage()
                let f = float.flatMap { y < $0.bottom ? $0 : nil }
                let column = f != nil ? PressLayout.besideWidth(PressPaper.inner) : PressPaper.inner
                let x0 = f?.left == true ? PressPaper.m + PressLayout.sideWidth(PressPaper.inner) + PressLayout.gutter : PressPaper.m
                let width = (column - indent).rounded(.towardZero)
                let lines = laid.lines(from: start, width: width)
                guard !lines.isEmpty else { break }
                let room = bottom - y
                var last = 0
                while last < lines.count && lines[last].bottom <= room { last += 1 }
                if let f { last = min(last, PressLayout.linesBeside(lines.map(\.top), f.bottom - y)) }
                if last == 0 {
                    // Nothing more beside the picture: below it at the full width; or nothing fits this page: the next one.
                    if let f, y + lines[0].bottom <= bottom {
                        y = f.bottom; float = nil
                    } else if fresh {
                        // A line taller than a whole page: drawn anyway, so the loop ends.
                        last = 1
                    } else {
                        newPage(); fresh = true
                        continue
                    }
                }
                if last == 0 { continue }
                fresh = false
                let h = lines[last - 1].bottom
                if indent > 0 {
                    ctx.setStrokeColor(cgColor(PressPaper.noteBar))
                    ctx.setLineWidth(2)
                    ctx.move(to: CGPoint(x: x0 + 1, y: PressPaper.h - (y + 2)))
                    ctx.addLine(to: CGPoint(x: x0 + 1, y: PressPaper.h - (y + h - 2)))
                    ctx.strokePath()
                }
                for l in lines[0..<last] { draw(l, x: x0 + indent, top: y, width: width, center: center) }
                y += h
                if last == lines.count { break }
                start = lines[last].start
                // Stopped by the picture's bottom: the rest at the full width; by the page's end: the next page.
                if let f, lines[last].bottom <= room { y = max(y, f.bottom); float = nil } else { newPage() }
            }
            y += after
        }

        /// Ends the text beside a picture: what follows starts below it, at the full width.
        func endBeside() {
            if let f = float { y = max(y, f.bottom) }
            float = nil
        }

        private func drawImage(_ img: CGImage?, x: Double, top: Double, w: Double, h: Double) {
            guard let img else { return }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: x, y: PressPaper.h - (top + h), width: w, height: h))
        }

        /// A picture on the left or right, PressLayout.sideWidth of the column, its caption under it in the same width;
        /// the text that follows goes beside it (`text`).
        func sidePicture(_ url: URL, left: Bool, caption: (String, Font)?) {
            endBeside()
            guard let size = imageOrSize(url) else { return }
            let (img, pw, ph) = size
            let box = PressLayout.sideWidth(PressPaper.inner)
            let (w, h) = PictureFit.within(pw, ph, box, PressPaper.pictureMaxH)
            let cap = caption.map { Laid($0.0, $0.1, spacing: 1.1) }
            let capLines = cap?.lines(from: 0, width: box.rounded(.towardZero)) ?? []
            let total = h + (cap != nil ? (capLines.last?.bottom ?? 0) + 4 : 0)
            ensurePage()
            if bottom - y < total { newPage() }
            let x = left ? PressPaper.m : PressPaper.w - PressPaper.m - box
            // The picture to the outer edge of its box; a narrow (tall) one leaves no gap by the text.
            let px = left ? x : x + box - w
            drawImage(img, x: px, top: y, w: w, h: h)
            for l in capLines { draw(l, x: x, top: y + h + 4, width: box, center: false) }
            float = Beside(left: left, bottom: y + total + 8)
        }

        /// A picture centered at the column's width in its own shape, no taller than half a page; its caption under it.
        func picture(_ url: URL, caption: (String, Font)?) {
            endBeside()
            guard let size = imageOrSize(url) else { return }
            let (img, pw, ph) = size
            let (w, h) = PictureFit.within(pw, ph, PressPaper.inner, PressPaper.pictureMaxH)
            ensurePage()
            if bottom - y < h + (caption != nil ? 24 : 0) { newPage() }
            drawImage(img, x: (PressPaper.w - w) / 2, top: y, w: w, h: h)
            y += h + 4
            if let caption { text(caption.0, caption.1, after: 0, center: true) }
        }

        private func line(_ x1: Double, _ x2: Double, at yy: Double, color: UInt32, width: Double) {
            ctx.setStrokeColor(cgColor(color))
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: x1, y: PressPaper.h - yy))
            ctx.addLine(to: CGPoint(x: x2, y: PressPaper.h - yy))
            ctx.strokePath()
        }

        /// A short hairline in the middle of the page, above the footer.
        func shortRule() {
            ensurePage()
            line(PressPaper.w / 2 - 24, PressPaper.w / 2 + 24, at: y, color: PressPaper.rule, width: 0.6)
            y += 8
        }

        func rule() {
            ensurePage()
            line(PressPaper.m, PressPaper.w - PressPaper.m, at: y, color: PressPaper.rule, width: 0.8)
            y += 10
        }

        func gap(_ h: Double) { y += h }

        /// One row of cells across the column (`widths` as parts of it, equal by default), each wrapped in its own width;
        /// the row starts a new page when it doesn't fit; `rule`: a hairline above it.
        func cells(_ cells: [String], _ font: Font, rule: Bool, widths: [Double]? = nil, first: Font? = nil) {
            guard !cells.isEmpty else { return }
            let parts = widths ?? Array(repeating: 1.0 / Double(cells.count), count: cells.count)
            let gutter = 8.0
            let laid = cells.enumerated().map { i, s -> (Double, [Laid.Line]) in
                let w = max((PressPaper.inner * parts[i] - gutter).rounded(.towardZero), 20)
                let l = Laid(s.isEmpty ? " " : s, i == 0 && first != nil ? first! : font, spacing: 1.15)
                return (w, l.lines(from: 0, width: w))
            }
            let h = (laid.map { $0.1.last?.bottom ?? 0 }.max() ?? 0) + (rule ? 6 : 3)
            ensurePage()
            if bottom - y < h { newPage() }
            if rule {
                line(PressPaper.m, PressPaper.w - PressPaper.m, at: y, color: PressPaper.rule, width: 0.6)
                y += 3
            }
            var x = PressPaper.m
            for (i, (w, lines)) in laid.enumerated() {
                for l in lines { draw(l, x: x, top: y, width: w, center: false) }
                x += PressPaper.inner * parts[i]
            }
            y += h - (rule ? 3 : 0)
        }

        /// Bars: each label and its value as the answer writes it, a bar under them, the longest the column's width.
        func bars(_ items: [(String, String)], _ values: [Double], label: Font, value: Font) {
            let maxValue = values.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
            let lineH = label.size * 1.3
            let barH = 7.0
            for (i, (l, v)) in items.enumerated() {
                let h = lineH + barH + 6
                ensurePage()
                if bottom - y < h { newPage() }
                let valueLine = CTLineCreateWithAttributedString(Laid(v, value, spacing: 1).attributed)
                let vw = CTLineGetTypographicBounds(valueLine, nil, nil, nil)
                let labelLine = CTLineCreateWithAttributedString(Laid(l, label, spacing: 1).attributed)
                let ellipsis = CTLineCreateWithAttributedString(Laid("…", label, spacing: 1).attributed)
                let shown = CTLineCreateTruncatedLine(labelLine, max(PressPaper.inner - vw - 12, 1), .end, ellipsis) ?? labelLine
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: PressPaper.m, y: PressPaper.h - (y + label.size))
                CTLineDraw(shown, ctx)
                ctx.textPosition = CGPoint(x: PressPaper.w - PressPaper.m - vw, y: PressPaper.h - (y + label.size))
                CTLineDraw(valueLine, ctx)
                let top = y + lineH
                let track = CGRect(x: PressPaper.m, y: PressPaper.h - (top + barH), width: PressPaper.inner, height: barH)
                ctx.setFillColor(cgColor(PressPaper.barTrack))
                ctx.addPath(CGPath(roundedRect: track, cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.fillPath()
                let w = min(max(PressPaper.inner * (values[i] / maxValue), 4), PressPaper.inner)
                ctx.setFillColor(cgColor(PressPaper.bar))
                ctx.addPath(CGPath(roundedRect: CGRect(x: PressPaper.m, y: track.minY, width: w, height: barH), cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.fillPath()
                y += h
            }
        }

        func finish() {
            ensurePage()
            if open { finishPage() }
        }

        func close() { ctx.closePDF() }
    }
}
