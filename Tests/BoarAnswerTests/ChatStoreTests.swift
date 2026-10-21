import BoarCore
import BoarModels
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

struct ChatStoreTests {
    private func store(clock: Cursor = Cursor()) throws -> ChatStore {
        let db = try SqliteDatabase.inMemory()
        _ = try KnowledgeBase(db: db)
        // The test clock starts at 1_000 and ticks once per read, as the Kotlin test's.
        return try ChatStore(db: db, now: { Int64(1_000 + clock.next()) })
    }

    @Test func sessionsMessagesRatingsAndMetaRoundTrip() throws {
        let s = try store()
        let a = try s.createSession()
        let b = try s.createSession(title: "Trip planning")
        try s.addMessage(sessionId: a.id, role: "user", text: "What is a black hole?", id: "u1")
        try s.upsertMessage(sessionId: a.id, role: "assistant", text: "A region", id: "a1")
        try s.upsertMessage(sessionId: a.id, role: "assistant", text: "A region of spacetime [1].", id: "a1")
        try s.setFeedback(messageId: "a1", rating: "up")
        try s.setMessageMeta(messageId: "a1", meta: #"{"sources":[]}"#)
        let msgs = try s.messages(sessionId: a.id)
        #expect(msgs.map(\.id) == ["u1", "a1"])
        #expect(msgs[1].text == "A region of spacetime [1].")
        #expect(msgs[1].feedback == "up")
        #expect(msgs[1].meta == #"{"sources":[]}"#)
        #expect(msgs[0].feedback == nil)
        // The session used last comes first.
        #expect(try s.listSessions().map(\.id) == [a.id, b.id])
        try s.setFeedback(messageId: "a1", rating: nil)
        #expect(try s.messages(sessionId: a.id)[1].feedback == nil)
        #expect(s.newId().wholeMatch(of: /\d+-[0-9a-z]{6}/) != nil)
    }

    @Test func deleteAndPruneRemoveMessagesRatingsAndMeta() throws {
        let s = try store()
        var ids: [String] = []
        for i in 1...4 {
            let session = try s.createSession(title: "s\(i)")
            try s.addMessage(sessionId: session.id, role: "user", text: "q\(i)", id: "m\(i)")
            try s.setFeedback(messageId: "m\(i)", rating: "down")
            try s.setMessageMeta(messageId: "m\(i)", meta: "{}")
            ids.append(session.id)
        }
        try s.prune(maxSessions: 2)
        #expect(try s.listSessions().map(\.id) == Array(ids.suffix(2).reversed()))
        #expect(try s.messages(sessionId: ids[0]).isEmpty)
        try s.deleteSession(sessionId: ids[3])
        #expect(try s.listSessions().map(\.id) == [ids[2]])
        try s.clearAll()
        #expect(try s.listSessions().isEmpty)
    }

    @Test func sealedTextRoundTripsAndResealSwitchesTheForm() throws {
        let s = try store()
        let key = PinKeys.newDataKey()
        let aes = AesTextCipher(key: key)
        let session = try s.createSession(title: "Secret trip")
        try s.addMessage(sessionId: session.id, role: "user", text: "Where to?", id: "u1")
        try s.setMessageMeta(messageId: "u1", meta: "{}")
        try s.setSummary(sessionId: session.id, summary: "Plans")
        try s.reseal(from: PlainCipher(), to: aes)
        // Sealed rows read back as the lock placeholder without the key, and as the text with it.
        #expect(try s.listSessions()[0].title == AesTextCipher.locked)
        s.cipher = aes
        let sealed = try s.listSessions()[0]
        #expect(sealed.title == "Secret trip" && sealed.summary == "Plans")
        #expect(try s.messages(sessionId: session.id)[0].text == "Where to?")
        try s.addMessage(sessionId: session.id, role: "assistant", text: "Lisbon", id: "a1")
        try s.reseal(from: aes, to: PlainCipher())
        s.cipher = PlainCipher()
        #expect(try s.messages(sessionId: session.id).map(\.text) == ["Where to?", "Lisbon"])
        #expect(try s.listSessions()[0].title == "Secret trip")
    }

    /// PinEncryptionTest `with a PIN, nothing a chat says reaches the database in the clear` (needs ChatStore, so it
    /// lives here rather than in BoarModelsTests).
    @Test func withAPinNothingAChatSaysReachesTheDatabaseInTheClear() throws {
        let db = try SqliteDatabase.inMemory()
        _ = try KnowledgeBase(db: db)
        let store = try ChatStore(db: db)
        let s = try store.createSession(title: "Trip to Lisbon")
        try store.addMessage(sessionId: s.id, role: "user", text: "Where can I buy a SIM card?", id: "u1")
        try store.addMessage(sessionId: s.id, role: "assistant", text: "At the airport.", id: "a1")
        try store.setMessageMeta(messageId: "a1", meta: #"{"sources":[{"title":"Lisbon"}]}"#)
        try store.setSummary(sessionId: s.id, summary: "Planning a trip.")
        // Turn the PIN on: the old rows are re-sealed in place.
        let aes = AesTextCipher(key: PinKeys.newDataKey())
        try store.reseal(from: PlainCipher(), to: aes)
        store.cipher = aes
        try store.addMessage(sessionId: s.id, role: "user", text: "And a taxi?", id: "u2")
        let raw = try db.query("SELECT text FROM chat_messages") { $0.string(0) ?? "" }
            + db.query("SELECT title || ' ' || summary FROM chat_sessions") { $0.string(0) ?? "" }
            + db.query("SELECT meta FROM chat_message_meta") { $0.string(0) ?? "" }
        #expect(!raw.isEmpty)
        #expect(!raw.contains { r in
            ["Lisbon", "SIM", "taxi", "airport"].contains { r.contains($0) } || r.localizedCaseInsensitiveContains("trip")
        })
        #expect(try store.messages(sessionId: s.id).map(\.text) == ["Where can I buy a SIM card?", "At the airport.", "And a taxi?"])
        #expect(try store.listSessions().map(\.title) == ["Trip to Lisbon"])
        // Without the key (the app before the PIN is entered) the text stays locked.
        store.cipher = PlainCipher()
        #expect(try store.messages(sessionId: s.id).first?.text == AesTextCipher.locked)
        // Turn it off: back to plain.
        try store.reseal(from: aes, to: PlainCipher())
        #expect(try db.query("SELECT text FROM chat_messages WHERE id = 'u2'") { $0.string(0) ?? "" } == ["And a taxi?"])
        #expect(try store.messages(sessionId: s.id)[1].meta == #"{"sources":[{"title":"Lisbon"}]}"#)
    }
}
