import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import BoarAnswer

/// Boar Press's PDF (android printer `PressSelfTest`: every made-up project, empty, one answer, thirty with drawings, a
/// very long answer, other scripts, no title, every block type with a missing drawing, pictures at the sides, compiles
/// as PDF and Markdown and opens; the files kept in the temp folder for a look).
struct PressPDFTests {
    typealias Block = PressDoc.Block

    private func open(_ data: Data) -> PDFDocument? { PDFDocument(data: data) }
    private func text(_ doc: PDFDocument, _ sep: String = "\n") -> String { (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: sep) }

    static let answerText = "Boil water for at least one minute (three minutes above 2,000 m) [1], let it cool covered, and store it in a clean container [2]. "
        + "**Filtering** first through a clean cloth removes sediment.\n\n- Use a lid\n- Keep it shaded\n\n1. Boil\n2. Cool\n3. Store"

    static func answer(_ n: Int, _ question: String, _ text: String, sources: Int = 2, heading: String = "") -> PressDoc.Answer {
        PressDoc.Answer("selftest-\(n)", "Self-test", question, text, (0..<sources).map { PressDoc.Source("Article \((n + $0 + 1) % 7)", "Wikipedia") },
                        1_760_000_000_000 + Int64(n), n % 2 == 0 ? "Qwen3-4B" : "Qwen3-1.7B", 4.0 + Double(n % 5), heading: heading)
    }

    /// A dark square with an orange disc, as Android's self-test draws.
    static func png(_ url: URL, _ w: Int, _ h: Int) throws {
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 34 / 255, green: 25 / 255, blue: 19 / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 122 / 255, blue: 61 / 255, alpha: 1))
        let r = Double(min(w, h)) / 3
        ctx.fillEllipse(in: CGRect(x: Double(w) / 2 - r, y: Double(h) / 2 - r, width: 2 * r, height: 2 * r))
        let img = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    struct Files {
        let dir: URL, square: URL, tall: URL, wide: URL
    }

    static func files() throws -> Files {
        let dir = FileManager.default.temporaryDirectory.appending(path: "press-selftest-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = Files(dir: dir, square: dir.appending(path: "square.png"), tall: dir.appending(path: "tall.png"), wide: dir.appending(path: "wide.png"))
        try png(f.square, 384, 384); try png(f.tall, 384, 512); try png(f.wide, 640, 320)
        return f
    }

    static func picture(_ f: URL, _ n: Int, _ caption: String = "", place: PressDoc.Place = .center, size: (Int, Int)) -> Block {
        .picture(PressDoc.Picture("pic-\(n)", .drawing, f.path, caption: caption, place: place, width: size.0, height: size.1))
    }

    static func projects(_ f: Files) -> [(String, PressDoc.Project)] {
        func project(_ name: String, _ blocks: [Block]) -> PressDoc.Project { PressDoc.Project("selftest-\(name)", name, 0, blocks) }
        return [
            ("empty", project("Empty project", [])),
            ("one", project("Field notes", [.answer(answer(1, "How do I make water safe to drink?", answerText))])),
            ("thirty", project("Thirty answers", (1...30).flatMap { n -> [Block] in
                let a = Block.answer(answer(n, "Question \(n): how do I make water safe?", answerText))
                switch n % 4 {
                case 0: return [a, picture(f.square, n, "Drawing \(n)", size: (384, 384))]
                case 1: return [a, picture(f.tall, n, size: (384, 512))]
                case 2: return [a, picture(f.wide, n, size: (640, 320))]
                default: return [a]
                }
            })),
            ("long", project("A very long answer", [.answer(answer(1, "Tell me everything about knots.",
                                                                   (1...400).map { "Knot \($0) holds under load when dressed and set." }.joined(separator: " ")))])),
            ("scripts", project("Scripts", [
                .answer(answer(1, "ما هي عاصمة مصر؟", "عاصمة مصر هي القاهرة، وهي أكبر مدينة في العالم العربي.")),
                .answer(answer(2, "中国的首都是哪里？", "中国的首都是北京。")),
                .answer(answer(3, "Emoji 🐗🔥⛺", "The boar 🐗 sits by the fire 🔥 near the tent ⛺. Flags: 🇧🇷🇯🇵")),
            ])),
            ("notitle", project("", [.answer(answer(1, "Untitled project?", answerText, sources: 0))])),
            ("blocks", project("Every block", [
                .heading(id: "h1", text: "Day 1: the coast"),
                .answer(answer(1, "Why is the sea salty?", answerText, heading: "Salty seas")),
                picture(f.tall, 1, "A boar, engraved", size: (384, 512)),
                .note(id: "n1", text: "Ask about the lighthouse tomorrow."),
                .picture(PressDoc.Picture("gone", .drawing, f.dir.appending(path: "deleted.png").path)),
                .heading(id: "h2", text: Array(repeating: "long", count: 40).joined(separator: " ")),
                .paragraph(id: "t1", text: "A paragraph of plain body text, not a note."),
                .divider(id: "d1"),
                .bullets(id: "l1", text: "Salt\nWater\nSun"),
            ])),
            ("sides", project("Sides", [
                picture(f.tall, 10, "On the left, a caption that wraps over two lines at least", place: .left, size: (384, 512)),
                .answer(answer(10, "Why is the sea salty?", answerText + "\n\n" + answerText)),
                picture(f.wide, 11, place: .right, size: (640, 320)),
                .note(id: "n10", text: "A note beside a wide picture on the right."),
                picture(f.square, 12, "Before a heading", place: .right, size: (384, 384)),
                .heading(id: "h10", text: "A heading never starts beside a picture"),
                .answer(answer(11, "Short?", "Yes.")),
                .picture(PressDoc.Picture("photo", .photo, f.wide.path, caption: "A photo copied into the project", place: .left, width: 640, height: 320)),
                .answer(answer(12, "Tide pools", answerText)),
                picture(f.tall, 13, place: .left, size: (384, 512)),
            ])),
        ]
    }

    private static func fileOf(_ p: PressDoc.Picture) -> URL? {
        let u = URL(fileURLWithPath: p.file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    @Test func everyProjectCompilesAndOpensAndItsMarkdownHasEveryAnswer() throws {
        let f = try Self.files()
        for (name, project) in Self.projects(f) {
            let page = PressPage(project: project, date: "November 5, 2026", version: "2.0.0")
            let data = PressPDF.compile(page, fileOf: Self.fileOf)
            try data.write(to: f.dir.appending(path: "\(name).pdf"))
            let doc = try #require(open(data), "\(name) didn't open")
            #expect(doc.pageCount > 0, "\(name)")
            // Every page has its number at the foot.
            for p in 0..<doc.pageCount { #expect(doc.page(at: p)?.string?.contains("\(p + 1)") == true, "\(name) p\(p + 1)") }
            // The paper's page starts follow the same layout: one per page after the first.
            #expect(PressPDF.pageStarts(page, fileOf: Self.fileOf).count == doc.pageCount - 1, "\(name)")
            let md = page.markdown(drawingLabel: "Drawing", photoLabel: "Photo")
            try md.write(to: f.dir.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
            let missing = project.answers.filter { !md.contains(PressPage.oneLine($0.shownHeading)) }.map(\.id)
            #expect(missing.isEmpty, "\(name).md missing \(missing)")
            #expect(page.footer.allSatisfy { md.contains($0) }, "\(name).md footer")
        }
    }

    @Test func theTextIsAllThereAndInOrder() throws {
        let f = try Self.files()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let project = try #require(Self.projects(f).first { $0.0 == "thirty" }?.1)
        let doc = try #require(open(PressPDF.compile(PressPage(project: project, date: "d", version: "v", options: PressReceipt.Options(speed: true)), fileOf: Self.fileOf)))
        #expect(doc.pageCount >= 5)
        let text = text(doc)
        var at = text.startIndex
        for n in 1...30 {
            let r = try #require(text.range(of: "Question \(n): how do I make water safe?", range: at..<text.endIndex), "question \(n)")
            at = r.upperBound
        }
        // The footer: the models with their speed, then "Made offline with BOAR", after the Sources section.
        let sources = try #require(text.range(of: "[1] Article 2 — Wikipedia"))
        let models = try #require(text.range(of: "Qwen3-1.7B (4.0–8.0 tok/s)"))
        let made = try #require(text.range(of: "Made offline with BOAR · d"))
        #expect(sources.lowerBound < models.lowerBound && models.lowerBound < made.lowerBound)
        // Markdown is gone: bullets as •, no **.
        #expect(text.contains("• Use a lid") && !text.contains("**"))
    }

    @Test func aLongAnswerFlowsOntoNewPages() throws {
        let f = try Self.files()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let project = try #require(Self.projects(f).first { $0.0 == "long" }?.1)
        let page = PressPage(project: project, date: "d", version: "v")
        let doc = try #require(open(PressPDF.compile(page, fileOf: Self.fileOf)))
        #expect(doc.pageCount >= 3)
        let text = text(doc, " ")
        #expect(text.contains("Knot 1 holds") && text.contains("Knot 400 holds"))
        // The second page starts inside the answer, some way into it.
        let starts = PressPDF.pageStarts(page, fileOf: Self.fileOf)
        #expect(starts.first?.unit == "selftest-1" && (starts.first?.intoPt ?? 0) > 0)
    }

    @Test func theSwitchesLeaveOutTheDateSourcesAndModelsNeverMadeWithBOAR() throws {
        let project = PressDoc.Project("p", "T", 0, [.answer(Self.answer(1, "Q1", "A1 [1].", sources: 1))])
        let with = try #require(open(PressPDF.compile(PressPage(project: project, date: "DATE-MARK", version: "v"), fileOf: { _ in nil })))
        let without = try #require(open(PressPDF.compile(PressPage(project: project, date: "DATE-MARK", version: "v",
                                                                   options: PressReceipt.Options(date: false, sources: false, models: false)), fileOf: { _ in nil })))
        let on = text(with), off = text(without)
        #expect(on.contains("DATE-MARK") && on.contains("Article 2") && on.contains("Qwen3-1.7B") && on.contains("[1]"), "\(on)")
        #expect(!off.contains("Article 2") && !off.contains("Qwen3-1.7B") && !off.contains("[1]"), "\(off)")
        // The date leaves the title; "Made offline with BOAR" and its date stay.
        #expect(off.components(separatedBy: "DATE-MARK").count - 1 == 1 && off.contains("Made offline with BOAR · DATE-MARK"), "\(off)")
    }

    @Test func aCardPrintsUnderItsAnswer() throws {
        let card = AnswerCard(.checklist, "Purify water", .steps(["Collect it.", "Boil it.", "Let it cool."]), byModel: true, ticks: [1])
        let project = PressDoc.Project("p", "Cards", 0, [.answer(PressDoc.Answer("m1", "Chat", "How?", "Collect, boil, cool.", card: card))])
        let doc = try #require(open(PressPDF.compile(PressPage(project: project, date: "d", version: "v", cardByModel: "made by the model · checked against the answer"),
                                                     fileOf: { _ in nil })))
        let text = text(doc)
        let answer = try #require(text.range(of: "Collect, boil, cool."))
        let title = try #require(text.range(of: "Purify water"))
        #expect(answer.lowerBound < title.lowerBound)
        #expect(text.contains("Boil it.") && text.contains("made by the model"), "\(text)")
    }
}
