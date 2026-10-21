import BoarCore
import CoreGraphics
import CoreSpotlight
import CoreText
import Foundation
import Testing
@testable import BoarAppleAI

@Suite struct TranscriptAccumulatorTests {
    @Test func volatileThenFinal() {
        var acc = TranscriptAccumulator()
        #expect(acc.apply(text: "hello", isFinal: false) == .partial("hello"))
        #expect(acc.apply(text: "hello wor", isFinal: false) == .partial("hello wor"))
        #expect(acc.apply(text: "Hello world.", isFinal: true) == .final("Hello world."))
        #expect(acc.apply(text: " how are", isFinal: false) == .partial("Hello world. how are"))
        #expect(acc.apply(text: " How are you?", isFinal: true) == .final("Hello world. How are you?"))
        #expect(acc.volatile.isEmpty)
        #expect(acc.fullText == "Hello world. How are you?")
    }

    @Test func emptyPieces() {
        var acc = TranscriptAccumulator()
        #expect(acc.apply(text: "", isFinal: false) == .partial(""))
        #expect(acc.apply(text: "  ", isFinal: true) == .final(""))
        #expect(VoiceTranscriptUpdate.partial("x").text == "x")
    }
}

@Suite struct ReadingOrderTests {
    func box(_ t: String, _ x: Double, _ y: Double, w: Double = 0.2, h: Double = 0.03) -> TextLineBox {
        TextLineBox(text: t, minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    @Test func topToBottomLeftToRight() {
        let lines = [box("world", 0.4, 0.80), box("second", 0.1, 0.75), box("Hello", 0.1, 0.80)]
        #expect(ReadingOrder.arrange(lines) == "Hello world\nsecond")
    }

    @Test func largeGapStartsParagraph() {
        let lines = [box("Title", 0.1, 0.9), box("Body one", 0.1, 0.7), box("Body two", 0.1, 0.665)]
        #expect(ReadingOrder.arrange(lines) == "Title\n\nBody one\nBody two")
    }

    @Test func emptyInput() {
        #expect(ReadingOrder.arrange([]) == "")
        #expect(ReadingOrder.arrange([box("  ", 0, 0)]) == "")
    }
}

@Suite struct DocumentTextRecognizerTests {
    /// Black text on white, drawn with Core Text.
    func image(lines: [String]) -> CGImage? {
        let width = 1200, height = 400
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, text) in lines.enumerated() {
            let attr = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            ctx.textPosition = CGPoint(x: 60, y: CGFloat(height - 110 - i * 110))
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        return ctx.makeImage()
    }

    @Test func recognizesRenderedText() async throws {
        let img = try #require(image(lines: ["Offline research assistant", "Boars are wild pigs"]))
        let text = try await DocumentTextRecognizer().recognize(img)
        #expect(text.lowercased().contains("offline research assistant"))
        #expect(text.lowercased().contains("wild pigs"))
        let first = text.lowercased().range(of: "offline")?.lowerBound
        let second = text.lowercased().range(of: "wild")?.lowerBound
        if let first, let second { #expect(first < second) }
    }

    @Test func blankImageGivesEmptyText() async throws {
        let img = try #require(image(lines: []))
        #expect(try await DocumentTextRecognizer().recognize(img).isEmpty)
    }

    @Test func unreadablePDF() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boar-not-a-\(UUID().uuidString).pdf")
        try? Data("nope".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: DocumentTextRecognizer.RecognitionError.self) {
            try await DocumentTextRecognizer().recognize(fileURL: url)
        }
    }
}

@Suite struct SessionSpotlightIndexerTests {
    @Test func identifiersRoundTrip() {
        let id = SessionSpotlightIndexer.searchableItemIdentifier(sessionID: "abc-1")
        #expect(id == "team.sopa.boar.chat-sessions/abc-1")
        #expect(SessionSpotlightIndexer.sessionID(fromSearchableItemIdentifier: id) == "abc-1")
        #expect(SessionSpotlightIndexer.sessionID(fromSearchableItemIdentifier: "other/abc") == nil)
        #expect(SessionSpotlightIndexer.sessionID(fromSearchableItemIdentifier: "team.sopa.boar.chat-sessions/") == nil)
    }

    @Test func itemAttributes() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let session = SpotlightSession(id: "s1", title: "Boar diet", snippet: "What do boars eat?",
                                       text: String(repeating: "a", count: 20_000), updatedAt: date, keywords: ["boar"])
        let item = SessionSpotlightIndexer.item(for: session)
        #expect(item.uniqueIdentifier == "team.sopa.boar.chat-sessions/s1")
        #expect(item.domainIdentifier == SessionSpotlightIndexer.domainIdentifier)
        #expect(item.attributeSet.title == "Boar diet")
        #expect(item.attributeSet.contentDescription == "What do boars eat?")
        #expect(item.attributeSet.textContent?.count == SessionSpotlightIndexer.maxTextLength)
        #expect(item.attributeSet.keywords == ["boar"])
        #expect(item.attributeSet.contentModificationDate == date)
        #expect(item.expirationDate == date.addingTimeInterval(SessionSpotlightIndexer.expiration))
    }
}

#if canImport(CoreAI)
@Suite struct CoreAIAdapterTests {
    @Test func nonModelFileIsNotAnAsset() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }  // Core AI needs a 27 runtime
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boar-\(UUID().uuidString).aimodel")
        try Data("not a model".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!CoreAIModelAdapter.isModelAsset(url))
    }
}
#endif
