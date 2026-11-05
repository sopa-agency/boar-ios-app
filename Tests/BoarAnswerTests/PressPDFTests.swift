import Foundation
import PDFKit
import Testing

@testable import BoarAnswer

/// Boar Press's PDF (android `PressSelfTest`: every made-up basket compiles and opens, the files kept for a look).
struct PressPDFTests {
    private func open(_ data: Data) -> PDFDocument? { PDFDocument(data: data) }

    @Test func everyBasketCompilesAndOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "press-selftest")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, title, items) in BasketTests.baskets {
            for model in [false, true] {
                let data = PressPDF.compile(title: title, items: items, footer: "compiled offline with BOAR",
                                            meta: Press.Meta(model: model), date: "November 5, 2026")
                try data.write(to: dir.appending(path: "\(name)\(model ? "-model" : "").pdf"))
                let doc = try #require(open(data), "\(name) didn't open")
                #expect(doc.pageCount > 0, "\(name)")
                // Every page has its number at the foot.
                for p in 0..<doc.pageCount { #expect(doc.page(at: p)?.string?.contains("\(p + 1)") == true, "\(name) p\(p + 1)") }
            }
        }
    }

    @Test func theTextIsAllThereAndInOrder() throws {
        let items = BasketTests.baskets[2].2 // thirty answers
        let doc = try #require(open(PressPDF.compile(title: "Thirty answers", items: items, footer: "f", meta: Press.Meta(model: true), date: "d")))
        #expect(doc.pageCount >= 5)
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        var at = text.startIndex
        for n in 1...30 {
            let r = try #require(text.range(of: "Question \(n): how do I make water safe?", range: at..<text.endIndex), "question \(n)")
            at = r.upperBound
        }
        #expect(text.contains("Qwen3-4B · 9.4 tok/s"))
        #expect(text.contains("[2] Article 2 — Wikipedia"))
        // Markdown is gone: bullets as •, no **.
        #expect(text.contains("• Use a lid") && !text.contains("**"))
    }

    @Test func aLongAnswerFlowsOntoNewPages() throws {
        let doc = try #require(open(PressPDF.compile(title: "A very long answer", items: BasketTests.baskets[3].2, footer: "f", meta: Press.Meta(), date: "d")))
        #expect(doc.pageCount >= 3)
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: " ")
        #expect(text.contains("Knot 1 holds") && text.contains("Knot 400 holds"))
    }

    @Test func theSwitchesLeaveOutTheDateAndSources() throws {
        let items = [BasketTests.item(1, "Q1", "A1", sources: 1)]
        let with = try #require(open(PressPDF.compile(title: "T", items: items, footer: "f", meta: Press.Meta(), date: "DATE-MARK")))
        let without = try #require(open(PressPDF.compile(title: "T", items: items, footer: "f", meta: Press.Meta(date: false, sources: false), date: "DATE-MARK")))
        #expect(with.page(at: 0)?.string?.contains("DATE-MARK") == true)
        #expect(with.page(at: 0)?.string?.contains("Article 1") == true)
        #expect(without.page(at: 0)?.string?.contains("DATE-MARK") == false)
        #expect(without.page(at: 0)?.string?.contains("Article 1") == false)
    }
}
