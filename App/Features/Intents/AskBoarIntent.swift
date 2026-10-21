import AppIntents
import BoarAnswer
import BoarAppleAI
import BoarCore
import CoreSpotlight
import Foundation
import Observation
import os

/// Requests from outside the app (Siri, Shortcuts, Spotlight) waiting for BOAR to be ready and unlocked.
@MainActor
@Observable
final class IntentInbox {
    static let shared = IntentInbox()

    /// A question from "Ask BOAR": answered on a new chat.
    var question: String?
    /// A chat tapped in Spotlight.
    var sessionId: String?

    func ask(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { question = t }
    }

    /// A Spotlight result's user activity (CSSearchableItemActionType).
    func open(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = SessionSpotlightIndexer.sessionID(fromSearchableItemIdentifier: identifier) else { return }
        sessionId = id
    }
}

/// "Ask BOAR": opens BOAR on a new chat and starts answering, from Siri, Shortcuts, Spotlight or the Action button.
struct AskBoarIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask BOAR"
    static let description = IntentDescription("Opens BOAR on a new chat and starts answering your question with the models and library on this iPhone.")
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }
    /// Before iOS 26 the intent opens the app the old way.
    static let openAppWhenRun = true

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What do you want to ask BOAR?"))
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask BOAR \(\.$question)")
    }

    init() {}

    init(question: String) { self.question = question }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.ask(question)
        return .result()
    }
}

/// The App Shortcuts Siri and Spotlight offer without setup ("Ask BOAR").
struct BoarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskBoarIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Research with \(.applicationName)",
                "Look something up in \(.applicationName)",
            ],
            shortTitle: "Ask BOAR",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .grayGreen
}

/// Keeps Spotlight's copy of the chat list in step with the sidebar: titles and summaries only, and nothing at all
/// while the app lock is on (sealed chats stay out of the system index).
actor SpotlightDonor {
    private let indexer = SessionSpotlightIndexer()
    private var donated: Set<String> = []
    private static let log = BoarLog.logger("spotlight")

    func sync(_ sessions: [ChatSession], locked: Bool) async {
        guard SessionSpotlightIndexer.isIndexingAvailable else { return }
        do {
            if locked {
                try await indexer.deleteAll()
                donated = []
                return
            }
            let ids = Set(sessions.map(\.id))
            let gone = donated.subtracting(ids)
            if !gone.isEmpty { try await indexer.delete(sessionIDs: Array(gone)) }
            let items = sessions.map { s in
                SpotlightSession(id: s.id, title: s.title, snippet: s.summary ?? "", text: s.summary ?? "",
                                 updatedAt: Date(timeIntervalSince1970: Double(s.updatedAt) / 1000), keywords: ["BOAR"])
            }
            if !items.isEmpty { try await indexer.donate(items) }
            donated = ids
        } catch {
            Self.log.error("spotlight: \(String(describing: error), privacy: .public)")
        }
    }
}
