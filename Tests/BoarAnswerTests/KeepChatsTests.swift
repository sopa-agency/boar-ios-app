import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// Android rc3's keep-chats feature: KeepChatsTest (6a974612, e2530996), PruneTextTest (bba0ac83, 90770ebe) and
/// ClearHistoryPressTest (a2f6eaf8, 3f15cccd). The Kotlin tests that read the Android sources are ported as checks on the
/// string catalog and the model's wiring; the Press ones run on the scope the basket's erase reads.
struct KeepChatsTests {
    private func store() throws -> ChatStore {
        let db = try SqliteDatabase.inMemory()
        _ = try KnowledgeBase(db: db)
        let clock = Cursor()
        return try ChatStore(db: db, now: { Int64(1_000 + clock.next()) })
    }

    private func settingsFile(_ text: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("keepchats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("settings.json")
        try text.write(to: f, atomically: true, encoding: .utf8)
        return f
    }

    private func catalog() throws -> [String: Any] {
        let c = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.root.appending(path: "App/Resources/Localizable.xcstrings"))) as? [String: Any]
        return c?["strings"] as? [String: Any] ?? [:]
    }

    private func pt(_ key: String) throws -> String? {
        let l = (try catalog()[key] as? [String: Any])?["localizations"] as? [String: Any]
        return ((l?["pt"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    // MARK: KeepChatsTest

    @Test("All is the default, an install that never chose keeps every chat, a chosen limit stays")
    func allIsTheDefaultAnInstallThatNeverChoseKeepsEveryChatAChosenLimitStays() throws {
        let never = try settingsFile("{}")
        #expect(AppSettings(store: JSONFileKeyValueStore(url: never)).maxSavedSessions == AppSettings.keepAllChats)
        let chose = try settingsFile(#"{"maxSavedSessions":10}"#)
        #expect(AppSettings(store: JSONFileKeyValueStore(url: chose)).maxSavedSessions == 10)
        AppSettings(store: JSONFileKeyValueStore(url: never)).maxSavedSessions = 25
        #expect(AppSettings(store: JSONFileKeyValueStore(url: never)).maxSavedSessions == 25)
    }

    @Test("keeping all deletes nothing, however many chats")
    func keepingAllDeletesNothingHoweverManyChats() throws {
        let s = try store()
        for i in 0..<30 { _ = try s.createSession(title: "chat \(i)") }
        #expect(try s.pushedOutByNew(maxSessions: AppSettings.keepAllChats).isEmpty)
        try s.prune(maxSessions: AppSettings.keepAllChats)
        #expect(try s.listSessions().count == 30)
    }

    @Test("with a limit, the chats a new one would delete are named first, oldest first, and only when full")
    func withALimitTheChatsANewOneWouldDeleteAreNamedFirstOldestFirstAndOnlyWhenFull() throws {
        let s = try store()
        for i in 0..<4 { _ = try s.createSession(title: "chat \(i)") }
        #expect(try s.pushedOutByNew(maxSessions: 5).isEmpty)
        _ = try s.createSession(title: "chat 4")
        #expect(try s.pushedOutByNew(maxSessions: 5).map(\.title) == ["chat 0"])
        // Over the limit (it was lowered): every chat past it, the oldest first.
        for i in 0..<2 { _ = try s.createSession(title: "chat \(5 + i)") }
        #expect(try s.pushedOutByNew(maxSessions: 5).map(\.title) == ["chat 0", "chat 1", "chat 2"])
        // What the warning names is what the prune then deletes.
        let named = Set(try s.pushedOutByNew(maxSessions: 5).map(\.id))
        _ = try s.createSession(title: "chat 7")
        let before = Set(try s.listSessions().map(\.id))
        try s.prune(maxSessions: 5)
        #expect(before.subtracting(try s.listSessions().map(\.id)) == named)
    }

    @Test("the chat asks before the first question of a new chat, and its answers are wired")
    func theChatAsksBeforeTheFirstQuestionOfANewChatAndItsAnswersAreWired() throws {
        // The model holds the question while the note is up (iOS has no Kotlin source to read: the app target is checked here).
        let chat = try Fixtures.text(Fixtures.root.appending(path: "App/Sources/Model/ChatController.swift"))
        #expect(chat.contains("pushedOutByNew(maxSessions: max)"))
        #expect(chat.contains("guard sessionId == nil, !pruneAccepted, pruneNote == nil"))
        for f in ["func pruneKeepAll()", "func pruneDelete()", "func pruneCancel()"] { #expect(chat.contains(f), Comment(rawValue: f)) }
        #expect(chat.contains("services.settings.maxSavedSessions = AppSettings.keepAllChats"))
        let view = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Chat/ChatView.swift"))
        for w in ["chat.pruneKeepAll()", "chat.pruneDelete()", "chat.pruneCancel()"] { #expect(view.contains(w), Comment(rawValue: w)) }
        for k in ["Delete your oldest chat?", "You keep %lld chats, so starting this one deletes “%@”.",
                  "You keep %lld chats, so starting this one deletes “%@” and %lld more.", "Keep All Chats", "Delete It", "All Chats"] {
            #expect(try pt(k) != nil, Comment(rawValue: "pt \(k)"))
        }
    }

    @Test("lowering the limit names the chats it would delete, and asks first (validator R-A4)")
    func loweringTheLimitNamesTheChatsItWouldDeleteAndAsksFirst() throws {
        let s = try store()
        for i in 0..<8 { _ = try s.createSession(title: "chat \(i)") }
        #expect(try s.pushedOutAt(maxSessions: 5).map(\.title) == ["chat 0", "chat 1", "chat 2"])
        #expect(try s.pushedOutAt(maxSessions: 10).isEmpty && s.pushedOutAt(maxSessions: AppSettings.keepAllChats).isEmpty)
        // Settings: the pick waits behind the dialog when chats would go; Keep All sets All; Delete Them prunes; Cancel changes nothing.
        let st = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Settings/SettingsMemorySection.swift"))
        #expect(st.contains("if going.isEmpty {\n            bridge.settings.maxSavedSessions = value"))
        #expect(st.contains("bridge.settings.maxSavedSessions = AppSettings.keepAllChats"))
        #expect(st.contains("$0.chats.pruneAnswers(maxSessions: max).answers"))
        // The deleted chats' answers leave Press only after their delete went through (BOAR-55 6.3).
        #expect(st.contains("Labs.shared.eraseAnswers(gone)"))
        for k in ["Delete your oldest chats?", "Keeping %lld chats deletes “%@”.", "Keeping %lld chats deletes “%@” and %lld more.", "Delete Them"] {
            #expect(try pt(k) != nil, Comment(rawValue: "pt \(k)"))
        }
    }

    // MARK: PruneTextTest

    @Test("with Boar Labs on, the dialog adds the plugins' line after the chats")
    func withBoarLabsOnTheDialogAddsThePluginsLineAfterTheChats() {
        #expect(PruneText.of("Keeping 5 chats deletes “A”.", "Their answers…", pluginsOn: true) == "Keeping 5 chats deletes “A”.\n\nTheir answers…")
        #expect(PruneText.of("Keeping 5 chats deletes “A”.", "Their answers…", pluginsOn: false) == "Keeping 5 chats deletes “A”.")
        #expect(PruneText.of("Keeping 5 chats deletes “A”.", "  ", pluginsOn: true) == "Keeping 5 chats deletes “A”.")
    }

    @Test("both dialogs use it")
    func bothDialogsUseIt() throws {
        // `both dialogs use it, and Boar Labs says when it applies`: plugins are on in every profile (v2.0.0), and a deleted
        // chat's answers leave Press, so both dialogs add the plugins' line (BOAR-55 6.3).
        let chat = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Chat/ChatView.swift"))
        let settings = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Settings/SettingsMemorySection.swift"))
        for s in [chat, settings] { #expect(s.contains("PruneText.of(") && s.contains("Labs.prunePluginsLine, pluginsOn: true")) }
        #expect(try pt("Their answers also leave your Press projects, and the cards made from them are deleted.") != nil)
    }

    // MARK: ClearHistoryPressTest

    @Test("off keeps every project - Press skips the keep-Press scope, and off is the default")
    func offKeepsEveryProjectPressSkipsTheKeepPressScopeAndOffIsTheDefault() {
        #expect(!UserDataScope.chatsKeepPress.erasesPress)
        // Fails safe (validator R-A6): Press goes only when ticked.
        #expect(UserDataScope.clearHistory(alsoPress: false) == .chatsKeepPress)
    }

    @Test("on erases them, as before")
    func onErasesThemAsBefore() {
        #expect(UserDataScope.clearHistory(alsoPress: true) == .chats)
        #expect(UserDataScope.chats.erasesPress)
    }

    @Test("with no Press projects there is no choice")
    func withNoPressProjectsThereIsNoChoice() throws {
        #expect(!UserDataScope.offersPressChoice(pressItems: 0))
        #expect(UserDataScope.offersPressChoice(pressItems: 3))
        #expect(try pt("Clear and Also Delete Press Projects (%lld)") != nil)
    }

    @Test("Forgot PIN still erases Press")
    func forgotPinStillErasesPress() throws {
        #expect(UserDataScope.everything.erasesPress)
        let lock = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Security/AppLock.swift"))
        #expect(lock.contains("Labs.shared.eraseUserData(.everything)"))
        // Every lab but Press treats the new scope as chats: none of them reads the scope except Press.
        let labs = try FileManager.default.contentsOfDirectory(at: Fixtures.root.appending(path: "App/Features/Labs/Plugins"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(try labs.filter { try Fixtures.text($0).contains("scope.erasesPress") }.count == 1)
    }
}
