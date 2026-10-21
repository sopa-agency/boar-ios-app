import BoarCore
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// One chat session as Spotlight should know it.
public struct SpotlightSession: Sendable, Equatable {
    public var id: String
    public var title: String
    /// A short preview (first question / last answer).
    public var snippet: String
    /// Full text to make searchable (questions + answers); trimmed to `SessionSpotlightIndexer.maxTextLength`.
    public var text: String
    public var updatedAt: Date
    public var keywords: [String]

    public init(id: String, title: String, snippet: String, text: String = "", updatedAt: Date, keywords: [String] = []) {
        self.id = id; self.title = title; self.snippet = snippet; self.text = text; self.updatedAt = updatedAt; self.keywords = keywords
    }
}

/// Donates chat sessions to Core Spotlight (system search, and the iOS 27 Spotlight search tool in `AppleDocumentTools`).
///
/// All items share one domain (`domainIdentifier`), and an item's unique identifier is `"<domain>/<session id>"`, so the app can
/// map a Spotlight hit back (`sessionID(fromSearchableItemIdentifier:)`) and wipe everything at once (privacy reset, PIN lock).
public actor SessionSpotlightIndexer {
    public static let domainIdentifier = "team.sopa.boar.chat-sessions"
    public static let maxTextLength = 10_000
    /// Items expire after this long without a re-donation (Spotlight's default is 30 days).
    public static let expiration: TimeInterval = 365 * 24 * 3600

    private let index: CSSearchableIndex

    /// `indexName` gives the app its own named index (protection class `completeUntilFirstUserAuthentication`).
    public init(indexName: String = "team.sopa.boar") {
        index = CSSearchableIndex(name: indexName, protectionClass: .completeUntilFirstUserAuthentication)
    }

    public static var isIndexingAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }

    /// The Spotlight unique identifier of a session.
    public static func searchableItemIdentifier(sessionID: String) -> String { "\(domainIdentifier)/\(sessionID)" }

    /// The session id behind a Spotlight hit (the `CSSearchableItemActivityIdentifier` user activity
    /// carries it under `CSSearchableItemActivityIdentifier`); nil for an item that is not a BOAR session.
    public static func sessionID(fromSearchableItemIdentifier identifier: String) -> String? {
        let prefix = domainIdentifier + "/"
        guard identifier.hasPrefix(prefix), identifier.count > prefix.count else { return nil }
        return String(identifier.dropFirst(prefix.count))
    }

    /// The attribute set a session is indexed with (pure; exposed for tests).
    public static func attributes(for session: SpotlightSession) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = session.title
        attrs.displayName = session.title
        attrs.contentDescription = session.snippet
        attrs.textContent = String(session.text.prefix(maxTextLength))
        attrs.contentModificationDate = session.updatedAt
        attrs.lastUsedDate = session.updatedAt
        attrs.keywords = session.keywords.isEmpty ? nil : session.keywords
        attrs.domainIdentifier = domainIdentifier
        return attrs
    }

    public static func item(for session: SpotlightSession) -> CSSearchableItem {
        let item = CSSearchableItem(
            uniqueIdentifier: searchableItemIdentifier(sessionID: session.id), domainIdentifier: domainIdentifier,
            attributeSet: attributes(for: session))
        item.expirationDate = session.updatedAt.addingTimeInterval(expiration)
        return item
    }

    /// Adds or replaces sessions.
    public func donate(_ sessions: [SpotlightSession]) async throws {
        guard !sessions.isEmpty else { return }
        try await index.indexSearchableItems(sessions.map(Self.item(for:)))
    }

    public func delete(sessionIDs: [String]) async throws {
        guard !sessionIDs.isEmpty else { return }
        try await index.deleteSearchableItems(withIdentifiers: sessionIDs.map(Self.searchableItemIdentifier(sessionID:)))
    }

    /// Removes every BOAR session from Spotlight.
    public func deleteAll() async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
    }
}
