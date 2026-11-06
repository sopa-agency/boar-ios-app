#if DEBUG
import BoarAnswer
import BoarCore
import BoarRAG
import Foundation
import Synchronization

/// The words, sources and receipts of the demo chats (plain data; nothing here touches the app).
enum DemoContent {
    struct Exchange {
        var question: String
        var answer: String
        var sources: [ChatSource]
        var receipt: Receipt
        var rating: String?
    }

    struct Session {
        var title: String
        /// How long before "now" the last message was written.
        var minutesAgo: Int
        var exchanges: [Exchange]
    }

    static let model = "Qwen2.5-1.5B-Instruct"

    private static func source(_ n: Int, _ title: String, _ similarity: Double, _ slug: String, _ body: String) -> ChatSource {
        ChatSource(number: n, title: title, source: "https://en.wikipedia.org/wiki/\(slug)", relevance: similarity - 0.1,
                   similarity: similarity, docId: title, body: body)
    }

    private static let seasons = [
        source(1, "Season", 0.86, "Season",
               "A season is a division of the year marked by changes in weather, ecology and the amount of daylight. On Earth, seasons result from the axial tilt of the planet: the axis is tilted about 23.5 degrees from the perpendicular to its orbital plane, so each hemisphere is tilted toward or away from the Sun for part of the year, regardless of the distance between the Earth and the Sun."),
        source(2, "Axial tilt", 0.81, "Axial_tilt",
               "When a hemisphere is tilted toward the Sun, sunlight strikes it at a steeper angle and the days are longer, so the same amount of energy is concentrated on a smaller area. Six months later the situation is reversed: the light arrives at a shallow angle, is spread over a larger area, and the days are shorter."),
        source(3, "Tropics", 0.64, "Tropics",
               "Because the Sun is high in the sky all year near the equator, the tropics have little change in day length or temperature. Their seasons are usually defined by rainfall, with a wet season and a dry season, rather than by summer and winter."),
    ]

    private static let orbit = [
        source(1, "Apsis", 0.83, "Apsis",
               "Earth reaches perihelion, its closest point to the Sun, in early January at about 147.1 million kilometres, and aphelion, its farthest point, in early July at about 152.1 million kilometres."),
        source(2, "Season", 0.79, "Season",
               "The change in distance has only a small effect: the sunlight reaching Earth varies by roughly 7 percent over the year, much less than the effect of the tilt of the axis."),
        source(3, "Daylight", 0.58, "Daylight",
               "The length of daylight changes through the year with the tilt of the Earth. The longer the day, the longer the ground has to absorb heat."),
    ]

    private static let nosebleed = [
        source(1, "Epistaxis", 0.84, "Epistaxis",
               "Most nosebleeds come from the front of the nose and can be stopped at home. Sit upright and lean forward slightly, then pinch the soft part of the nose firmly for ten minutes without letting go to check."),
        source(2, "First aid", 0.7, "First_aid",
               "Seek medical help if bleeding continues after twenty minutes of pressure, follows a head injury, or the person feels faint."),
    ]

    private static let pandemic = [
        source(1, "Pandemic", 0.88, "Pandemic",
               "A pandemic is an epidemic occurring on a scale that crosses international boundaries, usually affecting people on a worldwide scale."),
        source(2, "Epidemic", 0.8, "Epidemic",
               "An epidemic is the rapid spread of disease to a large number of hosts in a given population within a short period of time."),
    ]

    private static let plates = [
        source(1, "Plate tectonics", 0.9, "Plate_tectonics",
               "Plate tectonics describes the large-scale motion of seven large plates and the movements of a larger number of smaller plates of the Earth's lithosphere."),
    ]

    private static func receipt(total: Double, ttft: Double, rate: Double, tokens: Int, load: Double? = nil, path: String? = nil) -> Receipt {
        Receipt(totalMs: total, ttftMs: ttft, tokPerSec: rate, tokens: tokens, model: model, retrievalMs: 310, prefillMs: ttft - 900,
                contextTokens: 1180, loadMs: load, path: path)
    }

    static let sessions: [Session] = [
        Session(title: "Why do we have seasons on Earth?", minutesAgo: 4, exchanges: [
            Exchange(
                question: "Why do we have seasons on Earth?",
                answer: """
                Earth has seasons because its axis is tilted about 23.5° relative to its orbit around the Sun, not because the distance to the Sun changes [1].

                **How the tilt works**

                - In June the Northern Hemisphere leans toward the Sun, so sunlight arrives at a steeper angle and the days are longer, which warms the ground and the air [2].
                - Six months later the same hemisphere leans away: the light is spread over a larger area and the days are short [2].

                Near the equator the effect is small, which is why the tropics have wet and dry seasons instead of summer and winter [3].

                In short: **tilt, not distance**, makes the seasons.
                """,
                sources: seasons, receipt: receipt(total: 21_800, ttft: 6_400, rate: 9.1, tokens: 212, load: 3_900, path: "deep"), rating: "up"),
            Exchange(
                question: "Is Earth closer to the Sun in summer?",
                answer: """
                No. Earth is closest to the Sun (perihelion) in early January, during the Northern Hemisphere's winter, at about 147 million km, and farthest in early July at about 152 million km [1].

                That difference changes the sunlight reaching Earth by only about 7%, far less than the effect of the tilt [2].

                1. The tilt sets the angle of the sunlight.
                2. The angle sets how concentrated the heat is [2].
                3. The day length adds to the effect [3].
                """,
                sources: orbit, receipt: receipt(total: 14_200, ttft: 4_100, rate: 10.4, tokens: 138)),
        ]),
        Session(title: "How do I stop a nosebleed?", minutesAgo: 60 * 26, exchanges: [
            Exchange(
                question: "How do I stop a nosebleed?",
                answer: "Sit upright, lean slightly forward and pinch the soft part of your nose firmly for ten minutes without checking [1]. Get medical help if it lasts more than twenty minutes or follows a head injury [2].",
                sources: nosebleed, receipt: receipt(total: 9_300, ttft: 3_000, rate: 10.8, tokens: 66)),
        ]),
        Session(title: "Pandemic versus epidemic", minutesAgo: 60 * 24 * 3, exchanges: [
            Exchange(
                question: "What is the difference between a pandemic and an epidemic?",
                answer: "An epidemic is a rapid spread of a disease within a population over a short time [2]. A pandemic is an epidemic that crosses international borders and affects people worldwide [1].",
                sources: pandemic, receipt: receipt(total: 8_700, ttft: 2_900, rate: 11.2, tokens: 58)),
        ]),
        Session(title: "What is plate tectonics?", minutesAgo: 60 * 24 * 9, exchanges: [
            Exchange(
                question: "What is plate tectonics?",
                answer: "Plate tectonics is the theory that Earth's outer shell is broken into large plates that slowly move, which causes earthquakes, volcanoes and mountain building [1].",
                sources: plates, receipt: receipt(total: 7_400, ttft: 2_500, rate: 10.1, tokens: 51)),
        ]),
    ]

    /// `-uiBasket YES`: Boar Press's basket holds the demo chats' answers, as if added from each chat's More menu.
    static func writeBasket() {
        let pairs = sessions.flatMap { s in s.exchanges.map { (s.title, $0) } }
        let items = pairs.enumerated().map { n, pair in
            Basket.Item(id: "demo-basket-\(n)", chatTitle: pair.0, question: pair.1.question, text: pair.1.answer,
                        sources: pair.1.sources.map { Basket.Source(title: $0.title, source: $0.source) },
                        addedAt: 1_793_000_000_000 + Int64(n), model: model, tokPerSec: pair.1.receipt.tokPerSec)
        }
        try? Basket.save(items, to: AppPaths.filesDir.appending(path: "labs/basket.json"))
    }

    /// The question and the text so far of the answer shown in progress.
    static let liveQuestion = "What is the difference between a pandemic and an epidemic?"
    static let liveText = "An **epidemic** is a sudden rise in the number of cases of a disease in one community or region. A **pandemic** is an epidemic that has spread across several countries or continents, so it affects a very large number of people. The word"

    struct DocumentSet {
        var name: String
        var files: [DocumentImport.File]
        var active: Bool
    }

    static let documents: [DocumentSet] = [
        DocumentSet(name: "Project Specs", files: [
            DocumentImport.File(name: "api-spec.md", sizeBytes: 18_400, text: "# API specification\n\nThe service exposes a REST interface. Every request is authenticated with a bearer token and every response is JSON.\n\n## Endpoints\n\nGET /reports lists the reports. POST /reports creates one."),
            DocumentImport.File(name: "meeting-notes.txt", sizeBytes: 6_200, text: "Weekly sync, Tuesday. Decisions: ship the offline export first, move the sharing work to next month, review the budget on Friday."),
        ], active: true),
        DocumentSet(name: "Hiking Notes", files: [
            DocumentImport.File(name: "kebnekaise-route.txt", sizeBytes: 9_800, text: "Kebnekaise route notes. Start at Nikkaluokta, 19 km to the mountain station. Bring a stove, the huts are closed in early September."),
        ], active: false),
    ]

    static let repos: [HfBrowser.Repo] = [
        HfBrowser.Repo(id: "bartowski/Llama-3.2-3B-Instruct-GGUF", downloads: 412_380, likes: 318, params: 3_212_749_888, architecture: "llama", contextLength: 131_072),
        HfBrowser.Repo(id: "unsloth/gemma-3-1b-it-GGUF", downloads: 238_911, likes: 142, params: 999_885_952, architecture: "gemma3", contextLength: 32_768),
        HfBrowser.Repo(id: "Qwen/Qwen2.5-3B-Instruct-GGUF", downloads: 187_004, likes: 96, params: 3_085_938_688, architecture: "qwen2", contextLength: 32_768),
        HfBrowser.Repo(id: "bartowski/Phi-3.5-mini-instruct-GGUF", downloads: 96_450, likes: 74, params: 3_821_079_552, architecture: "phi3", contextLength: 131_072),
        HfBrowser.Repo(id: "ggml-org/SmolLM3-3B-GGUF", downloads: 41_238, likes: 38, params: 3_075_098_624, architecture: "smollm3", contextLength: 65_536),
    ]
}

/// A clock the seeding moves by hand, so the demo sessions get dates ("4 minutes ago", "Yesterday", "Last week").
private final class SeedClock: Sendable {
    private let value: Atomic<Int64>
    init(_ start: Int64) { value = Atomic(start) }
    func set(_ ms: Int64) { value.store(ms, ordering: .relaxed) }
    func advance(_ ms: Int64) { _ = value.wrappingAdd(ms, ordering: .relaxed) }
    var now: Int64 { value.load(ordering: .relaxed) }
}

/// Writes the demo chats and documents into BOAR's own stores (the real `ChatStore` and `DocumentImport` code), through a
/// second connection to the knowledge base so the dates are the demo's.
@MainActor
enum DemoSeed {
    static func run(services: BoarServices) async {
        guard DebugLaunch.demo else { return }
        seedChats()
        for set in DemoContent.documents {
            let id = try? await DocumentImport.importDocuments(kb: services.knowledgeBase, embed: { _ in [] }, files: set.files, collectionName: set.name)
            if let id, !set.active { try? services.knowledgeBase.setCollectionActive(id, false) }
        }
        if DebugLaunch.isScreen("lock") {
            services.settings.setJSONValue(.bool(true), forKey: AppLock.settingsKey)
        }
    }

    private static func seedChats() {
        guard let db = try? SqliteDatabase(path: AppPaths.knowledgeBase.path(percentEncoded: false)) else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let clock = SeedClock(nowMs)
        guard let store = try? ChatStore(db: db, now: { clock.now }) else { return }
        for session in DemoContent.sessions {
            let end = nowMs - Int64(session.minutesAgo) * 60_000
            clock.set(end - Int64(session.exchanges.count) * 120_000)
            guard let created = try? store.createSession(title: session.title) else { continue }
            for exchange in session.exchanges {
                clock.advance(30_000)
                try? store.addMessage(sessionId: created.id, role: "user", text: exchange.question)
                clock.advance(30_000)
                let answerId = store.newId()
                try? store.addMessage(sessionId: created.id, role: "assistant", text: exchange.answer, id: answerId)
                try? store.setMessageMeta(messageId: answerId, meta: MessageMeta.encode(exchange.sources, exchange.receipt))
                if let rating = exchange.rating { try? store.setFeedback(messageId: answerId, rating: rating) }
                clock.advance(30_000)
            }
        }
    }
}
#endif
