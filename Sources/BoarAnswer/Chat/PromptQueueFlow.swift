import Foundation

/// How many questions wait, kept outside the app's memory so a closed app can say what it dropped (android
/// `ChatViewModel.queuePrefs`, key QUEUE_WAITING).
public struct QueueCountStore: Sendable {
    public var read: @Sendable () -> Int
    public var write: @Sendable (Int) -> Void

    public init(read: @escaping @Sendable () -> Int, write: @escaping @Sendable (Int) -> Void) {
        self.read = read
        self.write = write
    }

    /// In `defaults`, under `key`.
    public static func defaults(_ defaults: UserDefaults, key: String) -> QueueCountStore {
        // UserDefaults is documented thread-safe, but isn't marked Sendable.
        nonisolated(unsafe) let d = defaults
        return QueueCountStore(read: { d.integer(forKey: key) }, write: { d.set($0, forKey: key) })
    }
}

/// The chat's queue decisions (android `ChatViewModel`'s send / runNext / publishQueue / dropQueueWithNote), apart from
/// the chat so they are testable: whether a question runs, waits or is refused, what runs next, what a closed app lost.
/// The chat keeps what is on screen (`onChange`) and starts the questions this hands it.
@MainActor
public final class PromptQueueFlow {
    /// What happens to a question handed to `admit`.
    public enum Admission: Equatable, Sendable {
        /// Nothing runs and nothing waits: it runs now.
        case start
        /// It joined the end of the queue. `startNow`: nothing is running and no note is up, so the oldest waiting question
        /// starts now (a question sent behind a note the user already answered).
        case queued(startNow: Bool)
        /// Up to `limit` wait already; the chat says so.
        case full(startNow: Bool)
    }

    public let queue: PromptQueue
    private let store: QueueCountStore
    /// Called whenever the queue changed (the chat shows it, and the count is kept).
    public var onChange: (@MainActor () -> Void)?

    public init(queue: PromptQueue = PromptQueue(), store: QueueCountStore) {
        self.queue = queue
        self.store = store
    }

    public var waiting: [PromptQueue.Item] { queue.waiting }
    public var isEmpty: Bool { queue.isEmpty }

    /// Questions that were waiting when the app was closed are gone: how many, once (a start after a close says so).
    public func droppedAtStart() -> Int? {
        let n = store.read()
        guard n > 0 else { return nil }
        store.write(0)
        return n
    }

    /// While an answer runs, or while questions wait, a question joins the end of the queue, so nothing jumps it (validator
    /// Q-2). `fromQueue`: the queue itself starting it. `behindNote`: a held question waits for the user's choice in a
    /// load note, and this one waits behind it (validator Q-4); `noteUp`: any such note is on screen.
    public func admit(_ text: String, running: Bool, fromQueue: Bool, behindNote: Bool, noteUp: Bool) -> Admission {
        if running || (!fromQueue && !queue.isEmpty) {
            let added = queue.add(text)
            publish()
            let startNow = !running && !noteUp
            return added ? .queued(startNow: startNow) : .full(startNow: startNow)
        }
        if behindNote {
            let added = queue.add(text)
            publish()
            return added ? .queued(startNow: false) : .full(startNow: false)
        }
        return .start
    }

    /// The oldest waiting question, taken off the queue to run; nil when none waits. With something running meanwhile it
    /// goes back to the front, not the end (defensive).
    public func takeNext(running: Bool) -> String? {
        guard let next = queue.next() else { return nil }
        if running {
            queue.pushFront(next)
            publish()
            return nil
        }
        publish()
        return next.text
    }

    public func remove(_ id: Int64) {
        queue.remove(id)
        publish()
    }

    /// Clear queue; also what Stop-all, a deleted open chat and the PIN's erase do.
    public func clear() {
        guard !queue.isEmpty else { return }
        queue.clear()
        publish()
    }

    /// The waiting questions become one, answered together. A safety question (the CO card) stays its own turn, ahead of
    /// the merged one, whether Cohazard is on or not.
    public func merge(keepApart: (String) -> Bool) {
        if queue.merge(keepApart: keepApart) { publish() }
    }

    /// The load note closed, or the model didn't load: the waiting questions need that model too, so they go. How many.
    public func dropWithNote() -> Int? {
        let n = queue.size
        guard n > 0 else { return nil }
        queue.clear()
        publish()
        return n
    }

    private func publish() {
        store.write(queue.size)
        onChange?()
    }
}
