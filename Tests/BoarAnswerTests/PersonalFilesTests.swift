import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// The Personal Files style through the answer pipeline (PersonalFilesPipelineTest.kt): nothing found writes the fixed
/// line without the model.
struct PersonalFilesPipelineTests {
    private let part = Chunk(chunkId: "p", docId: "d", title: "budget", body: Array(repeating: "Rent: 1,250 EUR.", count: 20).joined(separator: " "))

    private func pipeline(_ model: FakeSession, _ found: [Chunk]) -> AnswerPipeline {
        AnswerPipeline(session: model, retrieve: { _, _ in found }, classify: { _ in "lookup" }, retrievalIrrelevant: { _ in false })
    }

    private func request() -> AnswerRequest {
        PersonalFiles.request(AnswerRequest(query: "What is my rent?", systemPrompt: "Answer only from the files.", maxTokens: 768), contextSize: 4096)
    }

    private func done(_ events: AsyncThrowingStream<AnswerEvent, Error>) async throws -> AnswerResult {
        var result: AnswerResult?
        for try await e in events { if case .done(let r) = e { result = r } }
        return try #require(result)
    }

    private func promptOf(_ r: GenerationRequest) -> String {
        switch r.input {
        case .prompt(let p): return p
        case .messages(let m): return m.map(\.content).joined(separator: "\n")
        }
    }

    @Test func nothingFoundWritesTheFixedLineAndNeverCallsTheModel() async throws {
        let model = FakeSession(template: false, pieces: ["Rent is 1,250 EUR [1]."])
        let r = try await done(pipeline(model, []).answer(request()))
        #expect(r.text == PersonalFiles.notFound)
        #expect(r.notFound)
        #expect(model.requests.all.isEmpty)
    }

    @Test func foundPartsGoInWholeWithTheFilesOnlyInstruction() async throws {
        let model = FakeSession(template: false, pieces: ["Rent is 1,250 EUR [1]."])
        let r = try await done(pipeline(model, [part]).answer(request()))
        #expect(!r.notFound)
        #expect(r.sources == [part])
        let prompt = promptOf(try #require(model.requests.all.first))
        #expect(prompt.contains(part.body))
        #expect(prompt.contains("I couldn't find this in your Personal Files."))
    }

    // F3, Oct 22: "How is my blood?" opened with the not-found line, then answered from the blood test.
    @Test func theNotFoundLineGoesWhenAnAnswerFromTheFilesFollowsIt() {
        let a = PersonalFiles.notFound + " However, according to your blood test from March, your cholesterol was 231 [1]."
        #expect(PersonalFiles.dropHedge(a) == "According to your blood test from March, your cholesterol was 231 [1].")
    }

    @Test func theNotFoundLineAloneOrWithAShortSignOffStays() {
        #expect(PersonalFiles.dropHedge(PersonalFiles.notFound) == PersonalFiles.notFound)
        let short = PersonalFiles.notFound + " Try another collection."
        #expect(PersonalFiles.dropHedge(short) == short)
    }

    @Test func withoutACitationTheRestMayBeFromMemorySoTheLineStays() {
        let a = PersonalFiles.notFound + " However, cholesterol is generally considered healthy below 200 mg/dL for most adults."
        #expect(PersonalFiles.dropHedge(a) == a)
    }

    @Test func anAnswerThatDoesntOpenWithTheLineIsUntouched() {
        let a = "Your blood type is O negative [1]. " + PersonalFiles.notFound
        #expect(PersonalFiles.dropHedge(a) == a)
    }
}

/// PersonalitiesSmallModelTest.kt.
struct PersonalitiesSmallModelTests {
    let p = try! Personalities.bundled()

    @Test func aSmallModelGetsDetailedWithoutTheDoWhatTheUserAsksSentence() {
        let small = p.promptFor("detailed", customPrompt: nil, smallModel: true)
        let big = p.promptFor("detailed", customPrompt: nil, smallModel: false)
        #expect(!small.systemPrompt.contains("Always do what the user asks"))
        #expect(big.systemPrompt.contains("Always do what the user asks"))
        #expect(small.styleReminder?.contains("Leave out examples") == true)
    }

    @Test func stylesWithoutSmallModelTextsAreTheSameForEveryModel() {
        let a = p.promptFor("succinct", customPrompt: nil, smallModel: true), b = p.promptFor("succinct", customPrompt: nil, smallModel: false)
        #expect(a.systemPrompt == b.systemPrompt && a.styleReminder == b.styleReminder)
        let c = p.promptFor("custom", customPrompt: "mine", smallModel: true)
        #expect(c.systemPrompt == "mine" && c.styleReminder == nil)
    }
}
