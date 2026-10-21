import BoarCore
import BoarModels
import Foundation

public struct ChatSession: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String?
    public var createdAt: Int64
    public var updatedAt: Int64
    public init(id: String, title: String, summary: String?, createdAt: Int64, updatedAt: Int64) {
        self.id = id; self.title = title; self.summary = summary; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct ChatMessageRecord: Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionId: String
    /// "user" or "assistant"
    public var role: String
    public var text: String
    public var createdAt: Int64
    /// "up", "down", or nil when not rated.
    public var feedback: String?
    /// JSON the chat stores with an answer (sources, receipt, outcome); nil for older messages and user turns.
    public var meta: String?
    public init(id: String, sessionId: String, role: String, text: String, createdAt: Int64, feedback: String?, meta: String?) {
        self.id = id; self.sessionId = sessionId; self.role = role; self.text = text
        self.createdAt = createdAt; self.feedback = feedback; self.meta = meta
    }
}

/// Chat sessions and messages in the knowledge base's own tables (port of src/services/chatHistory.ts), so chats made in the
/// Expo app reopen after an upgrade. The schema is created by `KnowledgeBase`; `chat_message_meta` here.
///
/// With a PIN, `cipher` seals every text a chat stores (titles, summaries, messages, their sources) before it reaches the
/// database, and opens it on the way out; ids, times and ratings stay plain.
public final class ChatStore: @unchecked Sendable {
    private let db: any SqlDatabase
    private let now: @Sendable () -> Int64
    private let lock = NSLock()
    private var _cipher: any TextCipher = PlainCipher()

    public var cipher: any TextCipher {
        get { lock.withLock { _cipher } }
        set { lock.withLock { _cipher = newValue } }
    }

    private func seal(_ s: String) -> String { cipher.seal(s) }
    private func open(_ s: String) -> String { cipher.open(s) }

    public init(db: any SqlDatabase, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
        self.db = db; self.now = now
        try db.exec("CREATE TABLE IF NOT EXISTS chat_message_meta (message_id TEXT PRIMARY KEY REFERENCES chat_messages(id), meta TEXT NOT NULL)")
    }

    /// Same shape as the TS: "<ms>-<6 base-36 chars>".
    public func newId() -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return "\(now())-" + String((0..<6).map { _ in alphabet[Int.random(in: 0..<36)] })
    }

    @discardableResult
    public func createSession(title: String = "New chat") throws -> ChatSession {
        let t = now()
        let s = ChatSession(id: newId(), title: title, summary: nil, createdAt: t, updatedAt: t)
        try db.execute("INSERT INTO chat_sessions (id, title, summary, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", args: [.text(s.id), .text(seal(s.title)), .null, .integer(t), .integer(t)])
        return s
    }

    public func listSessions() throws -> [ChatSession] {
        try db.query("SELECT id, title, summary, created_at, updated_at FROM chat_sessions ORDER BY updated_at DESC", args: []) { r in
            ChatSession(id: r.string(0)!, title: self.open(r.string(1)!), summary: r.string(2).map(self.open), createdAt: r.long(3), updatedAt: r.long(4))
        }
    }

    public func messages(sessionId: String) throws -> [ChatMessageRecord] {
        try db.query(
            """
            SELECT m.id, m.session_id, m.role, m.text, m.created_at, f.rating, x.meta
            FROM chat_messages m
            LEFT JOIN answer_feedback f ON f.message_id = m.id
            LEFT JOIN chat_message_meta x ON x.message_id = m.id
            WHERE m.session_id = ? ORDER BY m.created_at ASC
            """,
            args: [.text(sessionId)]
        ) { r in
            ChatMessageRecord(id: r.string(0)!, sessionId: r.string(1)!, role: r.string(2)!, text: self.open(r.string(3)!), createdAt: r.long(4), feedback: r.string(5), meta: r.string(6).map(self.open))
        }
    }

    public func setMessageMeta(messageId: String, meta: String) throws {
        try db.execute("INSERT OR REPLACE INTO chat_message_meta (message_id, meta) VALUES (?, ?)", args: [.text(messageId), .text(seal(meta))])
    }

    public func addMessage(sessionId: String, role: String, text: String, id: String? = nil) throws {
        let t = now()
        try db.execute("INSERT INTO chat_messages (id, session_id, role, text, created_at) VALUES (?, ?, ?, ?, ?)", args: [.text(id ?? newId()), .text(sessionId), .text(role), .text(seal(text)), .integer(t)])
        try db.execute("UPDATE chat_sessions SET updated_at = ? WHERE id = ?", args: [.integer(t), .text(sessionId)])
    }

    /// Inserts, or replaces the text of an existing message (a streamed answer saved as it grows).
    public func upsertMessage(sessionId: String, role: String, text: String, id: String) throws {
        let t = now()
        try db.execute(
            """
            INSERT INTO chat_messages (id, session_id, role, text, created_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET text = excluded.text
            """,
            args: [.text(id), .text(sessionId), .text(role), .text(seal(text)), .integer(t)]
        )
        try db.execute("UPDATE chat_sessions SET updated_at = ? WHERE id = ?", args: [.integer(t), .text(sessionId)])
    }

    /// `rating` "up" or "down"; nil removes the rating.
    public func setFeedback(messageId: String, rating: String?) throws {
        if let rating {
            try db.execute("INSERT OR REPLACE INTO answer_feedback (message_id, rating, created_at) VALUES (?, ?, ?)", args: [.text(messageId), .text(rating), .integer(now())])
        } else {
            try db.execute("DELETE FROM answer_feedback WHERE message_id = ?", args: [.text(messageId)])
        }
    }

    public func setTitle(sessionId: String, title: String) throws {
        try db.execute("UPDATE chat_sessions SET title = ? WHERE id = ?", args: [.text(seal(title)), .text(sessionId)])
    }

    public func setSummary(sessionId: String, summary: String) throws {
        try db.execute("UPDATE chat_sessions SET summary = ? WHERE id = ?", args: [.text(seal(summary)), .text(sessionId)])
    }

    public func deleteSession(sessionId: String) throws {
        try db.transaction {
            let inSession = "SELECT id FROM chat_messages WHERE session_id = ?"
            try db.execute("DELETE FROM chat_message_meta WHERE message_id IN (\(inSession))", args: [.text(sessionId)])
            try db.execute("DELETE FROM answer_feedback WHERE message_id IN (\(inSession))", args: [.text(sessionId)])
            try db.execute("DELETE FROM chat_messages WHERE session_id = ?", args: [.text(sessionId)])
            try db.execute("DELETE FROM chat_sessions WHERE id = ?", args: [.text(sessionId)])
        }
    }

    public func clearAll() throws {
        try db.transaction {
            for t in ["chat_message_meta", "answer_feedback", "chat_messages", "chat_sessions"] { try db.execute("DELETE FROM \(t)") }
        }
    }

    /// Re-stores every chat text with `to`, reading it with `from`: turning the PIN on (plain → sealed) or off (sealed → plain).
    /// One transaction, so a crash leaves either all rows in the old form or all in the new.
    public func reseal(from: any TextCipher, to: any TextCipher) throws {
        try db.transaction {
            let sessions = try db.query("SELECT id, title, summary FROM chat_sessions", args: []) { ($0.string(0)!, $0.string(1)!, $0.string(2)) }
            for (id, title, summary) in sessions {
                try db.execute(
                    "UPDATE chat_sessions SET title = ?, summary = ? WHERE id = ?",
                    args: [.text(to.seal(from.open(title))), summary.map { .text(to.seal(from.open($0))) } ?? .null, .text(id)]
                )
            }
            let messages = try db.query("SELECT id, text FROM chat_messages", args: []) { ($0.string(0)!, $0.string(1)!) }
            for (id, text) in messages {
                try db.execute("UPDATE chat_messages SET text = ? WHERE id = ?", args: [.text(to.seal(from.open(text))), .text(id)])
            }
            let metas = try db.query("SELECT message_id, meta FROM chat_message_meta", args: []) { ($0.string(0)!, $0.string(1)!) }
            for (id, meta) in metas {
                try db.execute("UPDATE chat_message_meta SET meta = ? WHERE message_id = ?", args: [.text(to.seal(from.open(meta))), .text(id)])
            }
        }
    }

    /// Keeps the `maxSessions` most recently used sessions.
    public func prune(maxSessions: Int) throws {
        if maxSessions <= 0 { return }
        let ids = try db.query("SELECT id FROM chat_sessions ORDER BY updated_at DESC LIMIT -1 OFFSET ?", args: [.integer(Int64(maxSessions))]) { $0.string(0)! }
        for id in ids { try deleteSession(sessionId: id) }
    }
}
