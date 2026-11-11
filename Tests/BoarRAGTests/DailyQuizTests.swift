import BoarCore
import Foundation
import Testing

@testable import BoarRAG

/// android DailyQuizTest.kt: questions from the library's opening sentences, the title hidden.
struct DailyQuizTests {
    private let library: [(title: String, body: String)] = [
        ("Boiling", "Boiling is the rapid vaporization of a liquid, which occurs when it is heated to its boiling point. More."),
        ("Monsoon", "A monsoon is traditionally a seasonal reversing wind accompanied by corresponding changes in precipitation."),
        ("Water purification", "Water purification is the process of removing undesirable chemicals and contaminants from water."),
        ("Nosebleed", "A nosebleed, also known as epistaxis, is an instance of bleeding from the nose."),
        ("Plate tectonics", "Plate tectonics is the scientific theory that the Earth's lithosphere comprises a number of large plates."),
        ("Greenhouse effect", "The greenhouse effect occurs when greenhouse gases in a planet's atmosphere insulate the planet from losing heat."),
        ("Kyoto", "Kyoto is the capital city of Kyoto Prefecture in the Kansai region of Japan, and the former imperial capital."),
        ("Tsunami", "A tsunami is a series of waves in a water body caused by the displacement of a large volume of water."),
    ]

    /// LocalDate.of(2026, 10, 24).toEpochDay().
    private let oct24: Int64 = 20_750

    @Test func theTitlesWordsAreHiddenWithCasePluralAndAccents() {
        #expect(DailyQuiz.mask("Boiling is the rapid vaporization of a liquid.", title: "Boiling") == "▢▢▢ is the rapid vaporization of a liquid.")
        #expect(DailyQuiz.mask("Water purifications are processes that remove chemicals.", title: "Water purification") == "▢▢▢ ▢▢▢ are processes that remove chemicals.")
        #expect(DailyQuiz.mask("Brasília é a capital do Brasil.", title: "Brasilia") == "▢▢▢ é a capital do Brasil.")
        // Short words of the title ("of") stay; every other word of it goes, wherever it appears.
        #expect(DailyQuiz.mask("The Code of Hammurabi is a legal code.", title: "Code of Hammurabi") == "The ▢▢▢ of ▢▢▢ is a legal ▢▢▢.")
    }

    @Test func theClueIsTheArticlesFirstSentenceNeverAFragment() {
        #expect(DailyQuiz.opening(library[0].body) == "Boiling is the rapid vaporization of a liquid, which occurs when it is heated to its boiling point.")
        #expect(DailyQuiz.opening("Too short.") == nil)
    }

    @Test func theSameDayGivesTheSameQuizAnotherDayAnother() {
        let a = DailyQuiz.daily(library, epochDay: oct24)
        #expect(a == DailyQuiz.daily(library, epochDay: oct24))
        #expect(a.count == 5)
        #expect(a != DailyQuiz.daily(library, epochDay: oct24 + 1))
    }

    @Test func fourDifferentOptionsTheAnswerAmongThemTheClueHidingIt() {
        for q in DailyQuiz.daily(library, epochDay: oct24) {
            #expect(q.options.count == 4)
            #expect(Set(q.options).count == 4)
            #expect((0...3).contains(q.answer))
            #expect(q.clue.contains(DailyQuiz.mask), "\(q.clue)")
            #expect(q.clue.range(of: q.options[q.answer], options: .caseInsensitive) == nil, "\(q.clue)")
        }
    }

    @Test func aSmallLibraryGivesFewerQuestionsNeverACrash() {
        #expect(DailyQuiz.daily(Array(library.prefix(3)), epochDay: oct24).isEmpty)
        // An opening that never names its title can't hide anything: skipped.
        let noTitle = Array(library.prefix(4)) + [("Zebra", "This striped animal of Africa lives in herds on the open plains and grasslands.")]
        #expect(DailyQuiz.daily(noTitle, epochDay: oct24, count: 10).allSatisfy { $0.options[$0.answer] != "Zebra" })
    }

    @Test func theLibrarysArticlesNeverTheUsersFilesADifferentHandfulPerSeed() throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        for (i, a) in library.enumerated() {
            try kb.insertChunk(Chunk(chunkId: "wiki-\(i)", docId: "wiki-\(i)", title: a.title, body: a.body), embedding: [1])
        }
        try kb.createCollection(id: "c", name: "mine", sourceFilename: "secret.txt", docCount: 1, chunkCount: 1, sizeBytes: 10, now: 1)
        try kb.insertChunk(Chunk(chunkId: "c-doc0-secret-c0", docId: "c-doc0-secret", title: "secret", body: "My bank PIN is 4471 and nobody should see it.", collectionId: "c"), embedding: [1])
        let all = try kb.seedArticles(seed: 1, limit: 100)
        #expect(all.count == library.count)
        #expect(!all.contains { $0.title == "secret" })
        #expect(try kb.seedArticles(seed: 1, limit: 3).map(\.title) != kb.seedArticles(seed: 2, limit: 3).map(\.title))
    }

    @Test func epochDayIsTheLocalDate() {
        var sp = Calendar(identifier: .gregorian)
        sp.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        // 2026-10-24 23:30 in São Paulo is already the 25th in UTC: still day 20,750 there.
        let late = sp.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23, minute: 30))!
        #expect(DailyQuiz.epochDay(late, timeZone: sp.timeZone) == oct24)
        #expect(DailyQuiz.epochDay(late, timeZone: TimeZone(identifier: "UTC")!) == oct24 + 1)
    }
}

/// KotlinRandom against Kotlin's own algorithm: the properties the stdlib guarantees, plus the shapes a port gets wrong.
struct KotlinRandomTests {
    @Test func sameSeedSameSequenceAndBoundsHold() {
        var a = KotlinRandom(seed: 20_750)
        var b = KotlinRandom(seed: 20_750)
        for bound in [1, 2, 3, 4, 7, 8, 100, 1_000_003] {
            for _ in 0..<200 {
                let x = a.nextInt(bound)
                #expect(x == b.nextInt(bound))
                #expect((0..<bound).contains(x))
            }
        }
        var c = KotlinRandom(seed: 20_751)
        var d = KotlinRandom(seed: 20_750)
        #expect((0..<10).map { _ in c.nextInt() } != (0..<10).map { _ in d.nextInt() })
    }

    @Test func shuffleIsAPermutationAndRoughlyUniform() {
        var r = KotlinRandom(seed: 7)
        var firsts = [Int](repeating: 0, count: 4)
        for _ in 0..<4_000 {
            let s = r.shuffled([0, 1, 2, 3])
            #expect(s.sorted() == [0, 1, 2, 3])
            firsts[s[0]] += 1
        }
        #expect(firsts.allSatisfy { $0 > 850 && $0 < 1_150 }, "\(firsts)")
    }

    @Test func aNegativeOrHugeSeedStillWorks() {
        var r = KotlinRandom(seed: -1)
        var s = KotlinRandom(seed: Int64.max)
        #expect((0..<100).allSatisfy { _ in (0..<5).contains(r.nextInt(5)) && (0..<5).contains(s.nextInt(5)) })
    }
}
