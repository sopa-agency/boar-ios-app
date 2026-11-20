import Observation
import SwiftUI

/// What the user opened or folded in an answer (Staged's quotes, its "+N sources"), kept while BOAR runs: the chat's rows
/// are recycled as they scroll away, and a source sheet or the article reader sits over the chat, so a row's own `@State`
/// would be lost. Back in the chat, the answer is as it was left (android `ChatFolds`, adam Nov 10).
@MainActor @Observable
final class ChatFolds {
    static let shared = ChatFolds()

    private static let max = 500
    private var states: [String: Bool] = [:]
    /// Keys from the least to the most recently used.
    @ObservationIgnored private var order: [String] = []

    func isOpen(_ key: String, default initial: Bool) -> Bool { states[key] ?? initial }

    func set(_ key: String, _ value: Bool) {
        states[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.max { states[order.removeFirst()] = nil }
    }

    /// A binding to one fold of one answer: `key` is the message id and the part ("<id>/staged", "<id>/staged/more").
    func binding(_ key: String, default initial: Bool) -> Binding<Bool> {
        Binding(get: { self.isOpen(key, default: initial) }, set: { self.set(key, $0) })
    }
}
