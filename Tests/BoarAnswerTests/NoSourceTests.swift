import Foundation
import Testing

@testable import BoarAnswer

/// t9 0226 point 4: a model's answer with nothing in the library behind it says so (android NoSourceTest.kt).
struct NoSourceTests {
    @Test func theSearchFoundNothingAndTheAnswerCitesNothingTheLineShows() {
        #expect(NoSource.shows(searched: true, sources: 0, instant: false, question: "How do I change a flat bicycle tyre?", answer: "Remove the wheel, then…"))
    }

    @Test func notWithSourcesACitationAPluginsAnswerSmallTalkNoSearchOrAnEmptyAnswer() {
        #expect(!NoSource.shows(searched: true, sources: 2, instant: false, question: "Who was Marie Curie?", answer: "A physicist [1]."))
        // Golden change (validator R-C12): with 0 sources a [1] is made up and no longer hides the line.
        #expect(NoSource.shows(searched: true, sources: 0, instant: false, question: "Who was Marie Curie?", answer: "A physicist [1]."))
        #expect(NoSource.shows(searched: true, sources: 0, instant: false, question: "Write a function", answer: "return items[1]"))
        #expect(!NoSource.shows(searched: true, sources: 0, instant: true, question: "27000 mAh 3.7 V on a plane", answer: "99.9 Wh."))
        #expect(!NoSource.shows(searched: true, sources: 0, instant: false, question: "hey, what's up?", answer: "Hey! How can I help?"))
        #expect(!NoSource.shows(searched: false, sources: 0, instant: false, question: "How do I change a flat bicycle tyre?", answer: "Remove the wheel."))
        #expect(!NoSource.shows(searched: true, sources: 0, instant: false, question: "How do I change a flat bicycle tyre?", answer: ""))
    }

    /// The Kotlin test reads ChatScreen.kt and the strings XML; here the answer footer and the string catalog.
    @Test func theChatShowsItUnderTheSeparatorInEnAndPt() throws {
        let view = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Chat/AnswerFooter.swift"))
        // The note sits under the separator, in the footer (android f4e43f00; BOAR-51).
        #expect(view.contains("NoSource.shows(searched: message.receipt?.retrievalMs != nil, sources: message.sources.count, instant: message.receipt?.tool != nil,"))
        #expect(view.contains("answer: message.text, style: message.receipt?.style)"))
        // The text names this device (Platform.deviceNoun: "iPhone" or "Mac"), as Android's "this phone's".
        #expect(view.contains("No source in this \\(Platform.deviceNoun)'s library covers this; the answer is from the model alone."))
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Localizable.xcstrings"))) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        let entry = try #require(strings["No source in this %@'s library covers this; the answer is from the model alone."] as? [String: Any], "the catalog has no entry for the no-source line")
        let pt = ((entry["localizations"] as? [String: Any])?["pt"] as? [String: Any])?["stringUnit"] as? [String: Any]
        #expect(pt?["value"] as? String == "Nenhuma fonte da biblioteca deste %@ cobre isto; a resposta vem só do modelo.")
    }

    @Test func notUnderPersonalFilesOwnNotFoundLineWhichNoModelWroteRC11() {
        let notFound = "I couldn't find this in your Local Files.\n\nTry asking about something your files say."
        #expect(!NoSource.shows(searched: true, sources: 0, instant: false, question: "what did my landlord say?", answer: notFound, style: "personal"))
        #expect(NoSource.shows(searched: true, sources: 0, instant: false, question: "what did my landlord say?", answer: "He said the rent goes up.", style: "detailed"))
    }
}
