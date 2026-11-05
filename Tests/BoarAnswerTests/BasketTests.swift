import Foundation
import Testing

@testable import BoarAnswer

/// Boar Press's basket and Markdown (android printer `Basket.kt`, `MarkdownCompiler.kt`, `PdfCompiler.kt` helpers; Android
/// has no unit test for them, only `PressSelfTest`, whose baskets are reused here).
struct BasketTests {
    static let answer = "Boil water for at least one minute (three minutes above 2,000 m), let it cool covered, and store it in a clean container. " +
        "**Filtering** first through a clean cloth removes sediment.\n\n- Use a lid\n- Keep it shaded\n\n1. Boil\n2. Cool\n3. Store"

    static func item(_ n: Int, _ question: String, _ text: String = answer, sources: Int = 2) -> Basket.Item {
        Basket.Item(id: "selftest-\(n)", chatTitle: "Self-test", question: question, text: text,
                    sources: (0..<sources).map { Basket.Source(title: "Article \($0 + 1)", source: "Wikipedia") },
                    addedAt: 1_760_000_000_000 + Int64(n), model: "Qwen3-4B", tokPerSec: 9.4)
    }

    /// PressSelfTest's baskets.
    static let baskets: [(String, String, [Basket.Item])] = [
        ("empty", "Empty basket", []),
        ("one", "Field notes", [item(1, "How do I make water safe to drink?")]),
        ("thirty", "Thirty answers", (1...30).map { item($0, "Question \($0): how do I make water safe?") }),
        ("long", "A very long answer", [item(1, "Tell me everything about knots.", (1...400).map { "Knot \($0) holds under load when dressed and set." }.joined(separator: " "))]),
        ("scripts", "Scripts", [
            item(1, "ما هي عاصمة مصر؟", "عاصمة مصر هي القاهرة، وهي أكبر مدينة في العالم العربي."),
            item(2, "中国的首都是哪里？", "中国的首都是北京。"),
            item(3, "Emoji 🐗🔥⛺", "The boar 🐗 sits by the fire 🔥 near the tent ⛺. Flags: 🇧🇷🇯🇵"),
        ]),
        ("notitle", "", [item(1, "Untitled basket?", sources: 0)]),
    ]

    private let labels = ChatExport.Labels(reasoning: "Reasoning", sources: "Sources")

    @Test func theSameAnswerGoesInOnce() {
        let a = Self.item(1, "Q")
        let list = Basket.adding(a, to: Basket.adding(a, to: []))
        #expect(list.count == 1)
        #expect(Basket.adding(Self.item(2, "R"), to: list).map(\.id) == ["selftest-1", "selftest-2"])
    }

    @Test func moveEditRemove() {
        let list = (1...3).map { Self.item($0, "Q\($0)") }
        #expect(Basket.moving("selftest-3", by: -1, in: list).map(\.id) == ["selftest-1", "selftest-3", "selftest-2"])
        #expect(Basket.moving("selftest-1", by: 1, in: list).map(\.id) == ["selftest-2", "selftest-1", "selftest-3"])
        // Past either end, or an unknown id: unchanged.
        #expect(Basket.moving("selftest-1", by: -1, in: list) == list)
        #expect(Basket.moving("selftest-3", by: 1, in: list) == list)
        #expect(Basket.moving("nope", by: 1, in: list) == list)
        #expect(Basket.editing("selftest-2", text: "new", in: list)[1].text == "new")
        #expect(Basket.editing("selftest-2", heading: "H", in: list)[1].question == "H")
        #expect(Basket.removing("selftest-2", from: list).map(\.id) == ["selftest-1", "selftest-3"])
        let off = Basket.setting("selftest-1", image: nil, in: Basket.setting("selftest-1", image: "/a.png", in: list))[0]
        #expect(off.image == nil && off.imageOff)
        let on = Basket.setting("selftest-1", image: "/a.png", in: list)[0]
        #expect(on.image == "/a.png" && !on.imageOff)
    }

    @Test func androidsFileReadsAndWritesBack() throws {
        // As Android's toJson writes it (org.json, nulls explicit), with one older item missing optional keys.
        let json = #"""
        [{"id":"m1","chatTitle":"Trip","question":"Q?","text":"A.","addedAt":1760000000001,"model":"Qwen3-4B","tokPerSec":9.4,
          "image":null,"imageOff":false,"sources":[{"title":"Sky","source":"pack:wiki"},{"title":"Sea","source":null}]},
         {"id":"m2","text":"B.","model":"null","sources":[]}]
        """#
        let items = try Basket.decode(Data(json.utf8))
        #expect(items == [
            Basket.Item(id: "m1", chatTitle: "Trip", question: "Q?", text: "A.",
                        sources: [Basket.Source(title: "Sky", source: "pack:wiki"), Basket.Source(title: "Sea", source: nil)],
                        addedAt: 1_760_000_000_001, model: "Qwen3-4B", tokPerSec: 9.4),
            Basket.Item(id: "m2", chatTitle: "", question: "", text: "B.", sources: [], addedAt: 0),
        ])
        #expect(try Basket.decode(Basket.encode(items)) == items)
        let back = try JSONSerialization.jsonObject(with: Basket.encode(items)) as? [[String: Any]]
        #expect(back?[1]["model"] is NSNull)
        #expect(Set(back?[0].keys ?? [:].keys) == ["id", "chatTitle", "question", "text", "addedAt", "model", "tokPerSec", "image", "imageOff", "sources"])
    }

    @Test func aFileThatCantBeReadIsNotTakenAsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "basket-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "labs/basket.json")
        #expect(Basket.load(from: url) == .none)
        try Basket.save([Self.item(1, "Q")], to: url)
        #expect(Basket.load(from: url) == .items([Self.item(1, "Q")]))
        try Data("{not json".utf8).write(to: url)
        #expect(Basket.load(from: url) == .unreadable)
    }

    @Test func plainText() {
        #expect(Press.plain("## Title\n**Bold** and `code`\n* star\n  - dash\n\n\n\nend  ") == "Title\nBold and code\n• star\n• dash\n\nend")
        #expect(Press.plain(Self.answer).contains("• Use a lid"))
    }

    @Test func modelAndSourceLines() {
        let i = Self.item(1, "Q")
        #expect(Press.modelLine(i) == "Qwen3-4B · 9.4 tok/s")
        #expect(Press.modelLine(Basket.Item(id: "x", chatTitle: "", question: "", text: "", sources: [], addedAt: 0)) == nil)
        #expect(Press.sourceLines(i) == "[1] Article 1 — Wikipedia\n[2] Article 2 — Wikipedia")
    }

    @Test func placements() {
        #expect((0..<4).map { Press.Placement.alternate.side(of: $0) } == [.right, .left, .right, .left])
        #expect(Press.Placement.left.side(of: 1) == .left)
        #expect(Press.Placement.of("RIGHT") == .right && Press.Placement.of(nil) == .center && Press.Placement.of("x") == .center)
    }

    /// PressSelfTest's Markdown check: every question is in the file.
    @Test func everyQuestionIsInTheMarkdown() {
        for (_, title, items) in Self.baskets {
            let md = Press.markdown(title: title, items: items, footer: "compiled offline with BOAR", meta: Press.Meta(model: true),
                                    labels: labels, date: "November 5, 2026")
            #expect(items.allSatisfy { md.contains($0.question) })
            #expect(md.hasPrefix("# \(title)\n\n_November 5, 2026 · compiled offline with BOAR_\n\n"))
        }
    }

    @Test func theMarkdownFollowsTheSwitches() {
        let items = [Self.item(1, "Q1", "A1", sources: 1), Self.item(2, " ", "A2", sources: 0)]
        let md = Press.markdown(title: " Notes\nhere ", items: items, footer: "f", meta: Press.Meta(date: false, model: true, sources: true),
                                labels: labels, date: "d")
        #expect(md == "# Notes here\n\n_f_\n\n## Q1\n\nA1\n\n**Sources**\n\n1. Article 1 — Wikipedia\n\n_Qwen3-4B · 9.4 tok/s_\n\n---\n\n## Self-test\n\nA2\n\n_Qwen3-4B · 9.4 tok/s_\n")
        let bare = Press.markdown(title: "T", items: [items[0]], footer: "f", meta: Press.Meta(model: false, sources: false), labels: labels, date: "d")
        #expect(bare == "# T\n\n_d · f_\n\n## Q1\n\nA1\n")
    }
}
