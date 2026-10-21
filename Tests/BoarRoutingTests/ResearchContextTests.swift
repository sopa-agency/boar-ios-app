import Foundation
import Testing
@testable import BoarRouting

/// A stand-in for BoarRAG's Compress.tokenizeTerms / splitSentences (ported from the Kotlin Compress.kt), so the
/// on-topic test can run in this target.
struct TestTextTools: ResearchTextTools {
    private static let stopwords: Set<String> = Set(
        ("a an the and or but if then else of to in on at by for with from as is are was were be been being "
            + "do does did doing have has had having it its this that these those there here what which who whom whose "
            + "when where why how can could should would will shall may might must i you he she we they me him her us them "
            + "my your his our their not no yes so than too very just about into over under between vs versus also "
            + "tell explain describe give me please much many more most some any all each other such only own same "
            + "o a os as um uma de do da dos das em no na nos nas por para com que qual quais quem como quando onde porque é")
            .split(whereSeparator: { $0 == " " }).map(String.init)
    )
    private static let combining = JsRegex(#"[̀-ͯ]"#)
    private static let term = JsRegex("[a-z0-9]+")

    func tokenizeTerms(_ text: String) -> [String] {
        let folded = Self.combining.replace(in: text.lowercased().decomposedStringWithCompatibilityMapping, with: "")
        return Self.term.findAll(in: folded).map(\.value).filter { $0.utf16.count > 1 && !Self.stopwords.contains($0) }.map(Self.stem)
    }

    private static func stem(_ t: String) -> String {
        let n = t.utf16.count
        if n > 5 && t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if n > 4 && (t.hasSuffix("es") || t.hasSuffix("ed")) { return String(t.dropLast(2)) }
        if n > 3 && t.hasSuffix("s") && !t.hasSuffix("ss") { return String(t.dropLast(1)) }
        if n > 5 && t.hasSuffix("ing") { return String(t.dropLast(3)) }
        return t
    }

    private static let ws = JsString.ws
    private static let nb = "(?<![A-Za-z0-9_])"
    private static let heading = try! NSRegularExpression(pattern: "^#{1,6}\(ws)+", options: [.anchorsMatchLines])
    private static let wrap = try! NSRegularExpression(pattern: #"([^\n])\n(?!\n)(?=[a-z(])|([ ,(\-–])\n(?!\n)"#)
    private static let spaces = try! NSRegularExpression(pattern: " {2,}")
    private static let boundary = try! NSRegularExpression(pattern: "[.!?]+[\"')\\]]*\(ws)+(?=[\"'(\\[]?[A-Z0-9])|\\n+")
    private static let abbrev = try! NSRegularExpression(
        pattern: "(?:\(nb)[A-Z]|\(nb)(?:e\\.g|i\\.e|etc|vs|Mr|Mrs|Dr|St|No|approx|c|ca))\\.\\z"
    )

    private static func replacing(_ re: NSRegularExpression, in s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.utf16.count), withTemplate: template)
    }

    private static func unwrapLines(_ text: String) -> String {
        let t1 = replacing(heading, in: text, "")
        let t2 = replacing(wrap, in: t1, "$1$2 ")
        return replacing(spaces, in: t2, " ")
    }

    func splitSentences(_ input: String) -> [String] {
        let text = Self.unwrapLines(input) as NSString
        var out: [String] = []
        var start = 0
        for m in Self.boundary.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let value = text.substring(with: m.range)
            let end = m.range.location + JsString.trimEnd(value).utf16.count
            let candidate = text.substring(with: NSRange(location: start, length: end - start))
            let trimmedEnd = JsString.trimEnd(candidate)
            if value.hasPrefix("."),
               Self.abbrev.firstMatch(in: trimmedEnd, range: NSRange(location: 0, length: trimmedEnd.utf16.count)) != nil { continue }
            if !JsString.trim(candidate).isEmpty { out.append(JsString.trim(candidate)) }
            start = m.range.location + m.range.length
        }
        let rest = text.substring(from: start)
        if !JsString.trim(rest).isEmpty { out.append(JsString.trim(rest)) }
        return out
    }
}

struct TestPassage: ResearchPassage {
    var chunkId: String
    var title: String
    var body: String
}

@Suite struct ResearchContextTests {
    let rc = ResearchContext(tools: TestTextTools())

    // The three topic cases of research.json that carry their own chunks (the other 162 read the seed corpus, which is
    // not part of the golden fixtures; BoarAnswer's DeepResearch golden test covers them).
    @Test func inlineTopicGoldens() throws {
        let g = try Golden.load("research.json")
        var n = 0
        for t in g["topic"].array where !t["chunks"].isNull {
            let q = t["query"].string!
            let want = t["onTopic"].array.map(\.bool)
            let got = t["chunks"].array.map { rc.onTopic(query: q, title: $0["title"].string!, body: $0["body"].string!) }
            #expect(want == got, "onTopic \(q)")
            n += 1
        }
        #expect(n == 3)
    }

    @Test func mergedSourceNumbers() throws {
        let m = try Golden.load("research.json")["merge"]
        let c = (0..<4).map { TestPassage(chunkId: "seed:\($0)", title: "t\($0)", body: "b") }
        let got = ResearchContext.mergeSources([[c[0], c[1]], [c[1], c[2]], [], [c[2], c[0], c[3]]])
        #expect(m["sources"].array.map { $0.string! } == got.sources.map(\.chunkId))
        #expect(m["indexMaps"].array.map { $0.array.map(\.int) } == got.indexMaps)
    }

    @Test func termCoverageIsTheShareOfDistinctQuestionTerms() {
        #expect(rc.termCoverage(query: "the of", text: "anything") == 1.0)
        #expect(rc.termCoverage(query: "volcano magma", text: "A volcano erupts") == 0.5)
        #expect(rc.termCoverage(query: "volcano volcano magma", text: "volcano magma") == 1.0)
    }

    // Expectations below are traced by hand from ResearchContext.kt's rules (not from a fixture).
    @Test func aTitleNamingTheQuestionIsOnTopic() {
        #expect(rc.onTopic(query: "Tell me about Bangkok", title: "Bangkok", body: "Bangkok is the capital of Thailand."))
    }

    @Test func aYearInTheQuestionMustBeInTheSource() {
        #expect(!rc.onTopic(query: "Olympics 2016", title: "Olympics", body: "The 2012 games were in London."))
        #expect(rc.onTopic(query: "Olympics 2012", title: "Olympics", body: "The 2012 games were in London."))
    }

    @Test func aProperNounInTheQuestionMustBeInTheSource() {
        #expect(!rc.onTopic(query: "What is Tokyo famous for", title: "Paris", body: "Paris is famous for the Eiffel Tower."))
    }

    @Test func twoQuestionTermsInARowInTheFirstSentenceMakeASourceOnTopic() {
        #expect(rc.onTopic(
            query: "how do volcanoes erupt when magma rises", title: "Geology",
            body: "Volcanoes erupt when magma rises through the crust."
        ))
    }

    @Test func shortQuestionsNeedThePassageToOpenWithTheirWords() {
        #expect(!rc.onTopic(query: "causes of earthquakes", title: "Notes", body: "Earthquakes happen when plates move. The causes are tectonic."))
    }

    @Test func compoundTitlesAreMatchedOnTheirParts() {
        #expect(!rc.onTopic(query: "snakebite treatment", title: "Snake bites", body: "Treatment of snake bites starts with calm."))
        #expect(rc.onTopic(query: "snakebite treatment", title: "Snake bites", body: "A snakebite needs calm and treatment."))
    }

    @Test func aSectionHeadingBeforeTheFirstColonIsRead() {
        // "Heat stroke: ..." names the question's compound term through the heading, and the passage must then carry
        // every question word.
        #expect(!rc.onTopic(query: "heatstroke symptoms", title: "Hot weather", body: "Heat stroke: symptoms include confusion."))
        #expect(rc.onTopic(query: "heatstroke symptoms", title: "Hot weather", body: "Heat stroke: heatstroke symptoms include confusion."))
    }
}
