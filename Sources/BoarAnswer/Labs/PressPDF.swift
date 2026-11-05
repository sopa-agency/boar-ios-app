import CoreGraphics
import CoreText
import Foundation

/// Boar Press's A4 PDF (android printer `PdfCompiler.kt`): the title and date, a rule, then each item (its question as the
/// heading, the answer, its model line and sources in small type), with Core Text and Core Graphics so the same code runs
/// on the iPhone, the Mac and the test host. Text flows across pages; the page number is centred at the foot.
/// iOS has no drawings yet (no Image Gen), so `Meta.images`, `drawings` and `drawingFirst` have nothing to place.
public enum PressPDF {
    static let width: CGFloat = 595 // A4 in points
    static let height: CGFloat = 842
    static let margin: CGFloat = 56

    public static func compile(title: String, items: [Basket.Item], footer: String, meta: Press.Meta, date: String) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let pager = Pager(ctx: ctx)
        pager.text(title, font: serif(24, bold: true), color: 0x111111, after: 4)
        pager.text((meta.date ? date + " · " : "") + footer, font: serif(9), color: 0x777777, after: 18)
        pager.rule()
        for item in items {
            pager.text(Press.plain(Press.heading(item)), font: serif(14, bold: true), color: 0x1B4D3E, after: 6)
            pager.text(Press.plain(item.text), font: serif(11), color: 0x222222, after: 8, spacing: 1.35)
            if meta.model, let line = Press.modelLine(item) { pager.text(line, font: serif(8.5), color: 0x1B4D3E, after: 4) }
            if meta.sources, !item.sources.isEmpty {
                pager.text(Press.sourceLines(item), font: serif(8.5), color: 0x666666, after: 18)
            } else {
                pager.gap(12)
            }
        }
        pager.finish()
        ctx.closePDF()
        return data as Data
    }

    /// Android's Typeface.SERIF; Core Text falls back per character for scripts Georgia lacks (Arabic, Chinese, emoji).
    static func serif(_ size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateWithName((bold ? "Georgia-Bold" : "Georgia") as CFString, size, nil)
    }

    static func color(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Pages and the pen's height on the current one (`y` from the top, as Android's canvas counts).
    final class Pager {
        let ctx: CGContext
        private(set) var pages = 0
        private var open = false
        private var y = margin

        init(ctx: CGContext) { self.ctx = ctx }

        private var inner: CGFloat { width - 2 * margin }

        private func ensurePage() { if !open { newPage() } }

        private func newPage() {
            if open { finishPage() }
            ctx.beginPDFPage(nil)
            open = true
            pages += 1
            y = margin
        }

        private func finishPage() {
            let number = NSAttributedString(string: "\(pages)", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
                kCTForegroundColorAttributeName as NSAttributedString.Key: color(0x999999),
            ])
            let line = CTLineCreateWithAttributedString(number)
            ctx.textPosition = CGPoint(x: width / 2, y: margin / 2)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
            open = false
        }

        /// `s` from the pen down, onto as many pages as it needs; a blank `s` prints nothing and adds no space.
        func text(_ s: String, font: CTFont, color rgb: UInt32, after: CGFloat, spacing: CGFloat = 1.2) {
            guard !s.allSatisfy(\.isWhitespace) else { return }
            var multiple = spacing
            let style = withUnsafeBytes(of: &multiple) { raw -> CTParagraphStyle in
                var setting = CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: raw.baseAddress!)
                return CTParagraphStyleCreate(&setting, 1)
            }
            let attributed = NSAttributedString(string: s, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color(rgb),
                kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            var start = 0
            var fresh = false
            while start < attributed.length {
                ensurePage()
                let room = height - margin - y
                // Core Text counts up from the bottom: the frame's top is the pen.
                let rect = CGRect(x: margin, y: margin, width: inner, height: max(room, 0))
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), CGPath(rect: rect, transform: nil), nil)
                let shown = CTFrameGetVisibleStringRange(frame)
                let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
                if shown.length == 0 || lines.isEmpty {
                    // Not even one line fits: a new page. A fresh page that can't hold a line would loop: stop there.
                    if fresh { return }
                    newPage()
                    fresh = true
                    continue
                }
                fresh = false
                CTFrameDraw(frame, ctx)
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)
                var descent: CGFloat = 0
                CTLineGetTypographicBounds(lines[lines.count - 1], nil, &descent, nil)
                // The last line's bottom, from the frame's top.
                y += rect.height - (origins[lines.count - 1].y - descent)
                start = shown.location + shown.length
                if start < attributed.length { newPage() }
            }
            y += after
        }

        func rule() {
            ensurePage()
            ctx.setStrokeColor(color(0xCCCCCC))
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: margin, y: height - y))
            ctx.addLine(to: CGPoint(x: width - margin, y: height - y))
            ctx.strokePath()
            y += 18
        }

        func gap(_ h: CGFloat) { y += h }

        func finish() { if open { finishPage() } }
    }
}
