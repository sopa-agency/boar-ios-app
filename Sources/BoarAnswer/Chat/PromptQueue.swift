import Foundation
import Synchronization

/// Questions sent while BOAR is answering (adam, Nov 10: "let it send, adding to queue"). They wait in order and run one
/// at a time after the answer in progress, each as the chat's next turn; never two answers at once. At most `limit` wait.
/// In memory only: the app being closed drops them (the chat says so on the next start). Thread-safe: the chat runs it on
/// the main actor, but a model switch's stop-all may clear it from another thread (validator Q-1b); a lock keeps each
/// call whole (android `engine/chat/PromptQueue.kt`, `@Synchronized`).
public final class PromptQueue: Sendable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: Int64
        public let text: String
    }

    public static let defaultLimit = 5

    public let limit: Int

    private struct State {
        var items: [Item] = []
        var nextId: Int64 = 1
    }

    private let state = Mutex(State())

    public init(limit: Int = PromptQueue.defaultLimit) {
        self.limit = limit
    }

    public var waiting: [Item] { state.withLock { $0.items } }
    public var size: Int { state.withLock { $0.items.count } }
    public var isEmpty: Bool { state.withLock { $0.items.isEmpty } }

    /// Adds `text` at the end; false when `limit` questions already wait (or it's blank).
    @discardableResult
    public func add(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.withLock { s in
            if t.isEmpty || s.items.count >= limit { return false }
            s.items.append(Item(id: s.nextId, text: t))
            s.nextId += 1
            return true
        }
    }

    /// The next question to run, taken off the queue; nil when none waits.
    public func next() -> Item? {
        state.withLock { $0.items.isEmpty ? nil : $0.items.removeFirst() }
    }

    @discardableResult
    public func remove(_ id: Int64) -> Bool {
        state.withLock { s in
            let before = s.items.count
            s.items.removeAll { $0.id == id }
            return s.items.count != before
        }
    }

    /// Puts a question taken by `next()` back at the front, as it was.
    public func pushFront(_ item: Item) {
        state.withLock { $0.items.insert(item, at: 0) }
    }

    public func clear() {
        state.withLock { $0.items.removeAll() }
    }

    /// The waiting questions as one (PromptMerge), first in line; false with fewer than two to merge. A question
    /// `keepApart` picks (a safety question: the CO card) is never merged: it stays its own turn, ahead, and gets its fixed
    /// answer as when asked alone (validator M-1/M-2, Nov 13: merged, the card could be dropped, or not matched at all).
    @discardableResult
    public func merge(keepApart: (String) -> Bool = { _ in false }) -> Bool {
        state.withLock { s in
            let apart = s.items.filter { keepApart($0.text) }
            let rest = s.items.filter { !keepApart($0.text) }
            if rest.count < 2 { return false }
            let one = Item(id: s.nextId, text: PromptMerge.of(rest.map(\.text)))
            s.nextId += 1
            s.items = apart + [one]
            return true
        }
    }
}
