import BoarCore
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device OCR for document import: an image or a PDF → plain text in reading order.
///
/// Uses Vision's document recognition (`RecognizeDocumentsRequest`, iOS 26), which returns the page as a structure (title,
/// paragraphs, lists, tables) already in reading order. When it finds no structure, the line-level `RecognizeTextRequest` result
/// is arranged with `ReadingOrder` (rows top to bottom, left to right). English only (BOAR's scope).
public struct DocumentTextRecognizer: Sendable {
    public var languages: [Locale.Language]
    public var usesLanguageCorrection: Bool
    /// PDF pages are rendered at this scale (points → pixels) before recognition.
    public var pdfRenderScale: CGFloat
    /// At most this many PDF pages are read.
    public var maxPDFPages: Int

    public init(languages: [Locale.Language] = [Locale.Language(identifier: "en-US")], usesLanguageCorrection: Bool = true,
                pdfRenderScale: CGFloat = 2, maxPDFPages: Int = 200) {
        self.languages = languages; self.usesLanguageCorrection = usesLanguageCorrection
        self.pdfRenderScale = pdfRenderScale; self.maxPDFPages = maxPDFPages
    }

    public enum RecognitionError: Error, Equatable {
        case unreadableFile(String)
    }

    /// Text of one image.
    public func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation? = nil) async throws -> String {
        // iOS 26 reads paragraphs; before it (and when that finds nothing), lines in reading order.
        if #available(iOS 26.0, macOS 26.0, *) {
            let text = Self.text(of: try await documentRequest().perform(on: image, orientation: orientation))
            if !text.isEmpty { return text }
        }
        return ReadingOrder.arrange(try await lineRequest().perform(on: image, orientation: orientation).map(TextLineBox.init))
    }

    /// Text of an image file or a PDF (pages separated by a blank line).
    public func recognize(fileURL url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = CGPDFDocument(url as CFURL) else { throw RecognitionError.unreadableFile(url.lastPathComponent) }
            var pages: [String] = []
            for index in 1...max(1, min(pdf.numberOfPages, maxPDFPages)) where pdf.numberOfPages > 0 {
                guard let page = pdf.page(at: index), let image = Self.render(page, scale: pdfRenderScale) else { continue }
                let text = try await recognize(image)
                if !text.isEmpty { pages.append(text) }
            }
            return pages.joined(separator: "\n\n")
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            let text = Self.text(of: try await documentRequest().perform(on: url, orientation: nil))
            if !text.isEmpty { return text }
        }
        return ReadingOrder.arrange(try await lineRequest().perform(on: url, orientation: nil).map(TextLineBox.init))
    }

    // MARK: Internals

    @available(iOS 26.0, macOS 26.0, *)
    private func documentRequest() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = languages
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.useLanguageCorrection = usesLanguageCorrection
        return request
    }

    private func lineRequest() -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = usesLanguageCorrection
        return request
    }

    /// Paragraphs in Vision's reading order (the title first when Vision found one separately).
    @available(iOS 26.0, macOS 26.0, *)
    static func text(of observations: [DocumentObservation]) -> String {
        observations.map { observation -> String in
            let doc = observation.document
            var blocks = doc.paragraphs.map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let title = doc.title?.transcript.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, blocks.first != title {
                blocks.insert(title, at: 0)
            }
            if blocks.isEmpty { return doc.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            return blocks.joined(separator: "\n\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func render(_ page: CGPDFPage, scale: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}

/// One recognized line with its normalized box (Vision coordinates: origin bottom-left, 0…1).
public struct TextLineBox: Sendable, Equatable {
    public var text: String
    public var minX: Double, minY: Double, maxX: Double, maxY: Double

    public init(text: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.text = text; self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    init(_ o: RecognizedTextObservation) {
        let xs = [o.topLeft.x, o.topRight.x, o.bottomLeft.x, o.bottomRight.x].map(Double.init)
        let ys = [o.topLeft.y, o.topRight.y, o.bottomLeft.y, o.bottomRight.y].map(Double.init)
        self.init(text: o.topCandidates(1).first?.string ?? "", minX: xs.min()!, minY: ys.min()!, maxX: xs.max()!, maxY: ys.max()!)
    }

    var height: Double { maxY - minY }
}

/// Line boxes → text in reading order: rows from the top down (lines whose vertical extents overlap by at least half the
/// smaller height share a row), each row left to right joined by a space; a vertical gap larger than 1.5× the median line
/// height starts a new paragraph (blank line).
public enum ReadingOrder {
    public static func arrange(_ lines: [TextLineBox]) -> String {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return "" }
        let sorted = lines.sorted { $0.maxY != $1.maxY ? $0.maxY > $1.maxY : $0.minX < $1.minX }
        var rows: [[TextLineBox]] = []
        for line in sorted {
            if let last = rows.last, let anchor = last.first, overlaps(anchor, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let heights = lines.map(\.height).sorted()
        let median = heights[heights.count / 2]
        var out = ""
        var previousBottom: Double?
        for row in rows {
            let ordered = row.sorted { $0.minX < $1.minX }
            let top = ordered.map(\.maxY).max()!
            if let previousBottom {
                out += (previousBottom - top) > 1.5 * median ? "\n\n" : "\n"
            }
            out += ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            previousBottom = ordered.map(\.minY).min()!
        }
        return out
    }

    static func overlaps(_ a: TextLineBox, _ b: TextLineBox) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let smaller = min(a.height, b.height)
        return smaller > 0 ? overlap >= 0.5 * smaller : overlap >= 0
    }
}
