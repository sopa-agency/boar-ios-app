import Foundation
import Testing

@testable import BoarAnswer

/// android `engine/chat/ConnectionPillTest.kt`. The Kotlin tests that read `ChatScreen.kt` read the app's Swift source here
/// (`ConnectionLine.swift`, `ConnectionSheet.swift`, `Mascot.swift`'s `ChatTitle`, `ChatView.swift`). Not ported: the
/// 62 dp header bar and the 1.3 font-scale fit (`HeaderMetrics`: iOS has the system's navigation bar), and the compact
/// input bar (`PromptBar` `BAR_PAD`: the iOS composer is one glass pill that already has 4 pt around its 36 pt controls).
struct ConnectionPillTests {
    @Test func itShowsOnOpenAndOnARealChangeNotAgainForTheSameState() {
        #expect(ConnectionPill.shouldShow(online: false, last: nil))
        #expect(ConnectionPill.shouldShow(online: true, last: false))
        #expect(!ConnectionPill.shouldShow(online: true, last: true))
    }

    @Test func theTimesAreTheAndroidOnes() {
        #expect(ConnectionPill.showMs == 2_000 && ConnectionPill.tapShowMs == 4_000 && ConnectionPill.settleMs == 1_500)
    }

    @Test func theHeaderWaitsForTheConnectionToSettleAndRemembersWhatItShowed() throws {
        let line = try AppSource.text("App/Features/Chat/ConnectionLine.swift")
        let body = try AppSource.slice(line, after: "struct ConnectionLine: View {", before: "\n}\n")
        #expect(body.contains(".milliseconds(ConnectionPill.settleMs)") && body.contains("ConnectionPill.lastShown = online")
                && body.contains(".milliseconds(ConnectionPill.showMs)"))
        #expect(!line.contains("offlineReady"))
    }

    /// The connection is on the model line, the name turns into ONLINE or OFFLINE for 2 s, the title never changes (option D).
    @Test func theConnectionIsOnTheModelLineTheNameTurnsIntoTheWordForTwoSeconds() throws {
        let mascot = try AppSource.text("App/Features/Shared/Mascot.swift")
        let title = try AppSource.slice(mascot, after: "struct ChatTitle: View {", before: "\n}\n")
        // The title line stays the chat's; the second line is the connection line with the model's name.
        #expect(title.contains("ConnectionLine(online: online, model: subtitle, onDetails: onConnection)"))
        let line = try AppSource.text("App/Features/Chat/ConnectionLine.swift")
        let body = try AppSource.slice(line, after: "struct ConnectionLine: View {", before: "\n}\n")
        // One line, one style, cross-faded: nothing changes size. Reduce Motion: instant.
        #expect(body.contains(".opacity(expanded ? 0 : 1)") && body.contains(".opacity(expanded ? 1 : 0)"))
        #expect(body.contains("reduceMotion ? nil : .easeInOut(duration: 0.25)"))
        // Two steps (adam, Nov 13): a tap shows the word for 4 s, a tap on the word opens the sheet; VoiceOver opens it at once.
        #expect(body.contains("if expanded { onDetails() } else { tapped += 1 }"))
        #expect(body.contains(".milliseconds(ConnectionPill.tapShowMs)"))
        #expect(body.contains(".accessibilityAction(.default, onDetails)") && body.contains(".accessibilityAddTraits(.isButton)"))
        // A filled amber dot online, a moon-blue ring offline.
        let dot = try AppSource.slice(line, after: "struct ConnectionDot: View {", before: "\n}\n")
        #expect(dot.contains("if online {") && dot.contains("Circle().fill(.boar(.warning))") && dot.contains("strokeBorder(.boar(.moon).opacity(0.55)"))
        // The details are a sheet, not an alert.
        let view = try AppSource.text("App/Features/Chat/ChatView.swift")
        #expect(view.contains(".sheet(isPresented: $showingConnection)") && view.contains("ConnectionSheet(online:"))
        let sheet = try AppSource.text("App/Features/Chat/ConnectionSheet.swift")
        #expect(sheet.contains("**downloading models or packs**") && !sheet.contains(".alert("))
    }

    @Test func theDialogTextsAreShortParagraphsWithBoldMarksInEnglishAndPortuguese() throws {
        let sheet = try AppSource.text("App/Features/Chat/ConnectionSheet.swift")
        let onlineEn = "BOAR works the same with or without signal.\n\nThe connection is only for **downloading models or packs**, **searching Hugging Face** and sharing evaluation results, if you turn that on."
        let offlineEn = "BOAR doesn't need the internet.\n\nYour library is **on this device**, so ask away."
        #expect(sheet.contains(onlineEn.replacingOccurrences(of: "\n", with: "\\n")) && sheet.contains(offlineEn.replacingOccurrences(of: "\n", with: "\\n")))
        for key in [onlineEn, offlineEn] {
            let pt = try #require(try AppSource.portuguese(key), Comment(rawValue: key))
            #expect(pt.contains("**"))
        }
        // It ends with what the connection is used for: no airplane-mode dare (adam chose (a), Nov 13).
        #expect(onlineEn.hasSuffix("turn that on.") && !onlineEn.contains("airplane"))
        #expect(try #require(try AppSource.portuguese(onlineEn)).hasSuffix("ligar isso."))
        for key in ["Online, but we don't need it.", "Offline, as intended.", "ONLINE", "OFFLINE"] {
            #expect(try AppSource.portuguese(key) != nil, Comment(rawValue: key))
        }
    }

    /// adam, Nov 13: a tap opens a sheet that says the dot is only an indicator, lists the answer models on the phone and
    /// links the catalog.
    @Test func theConnectionSheetListsTheInstalledAnswerModelsAndOpensTheCatalog() throws {
        let sheet = try AppSource.text("App/Features/Chat/ConnectionSheet.swift")
        #expect(sheet.contains("The dot only shows the connection."))
        #expect(sheet.contains("models?.isPresent($0) == true") && sheet.contains("models?.answerModels"))
        // The switch goes through the catalog's own controller.
        #expect(sheet.contains("models?.use(asset)"))
        // No switch while an answer is being written.
        #expect(sheet.contains("busy || models?.activating != nil") && sheet.contains("Wait for the answer to finish to change the model."))
        #expect(sheet.contains("Open the Model Catalog"))
        let view = try AppSource.text("App/Features/Chat/ChatView.swift")
        #expect(view.contains("model.selection = .screen(.models)") && view.contains("busy: chat.isAnswering"))
        for key in ["The dot only shows the connection. BOAR answers the same offline.", "Answer model", "No answer model on this device yet.",
                    "Wait for the answer to finish to change the model.", "Open the Model Catalog", "Double tap for details"] {
            #expect(try AppSource.portuguese(key) != nil, Comment(rawValue: key))
        }
    }

    /// The chat's header names the model from one source (HeaderModel), and adaptive routing's other model shows while it writes.
    @Test func theHeaderNamesTheModelFromOneSource() throws {
        let view = try AppSource.text("App/Features/Chat/ChatView.swift")
        #expect(view.contains("HeaderModel.label(answeringNow: chat.isAnswering, answeringModel: chat.answeringModel"))
        let chat = try AppSource.text("App/Sources/Model/ChatController.swift")
        #expect(chat.contains("case .routed(let name): answeringModel = name"))
        #expect(try AppSource.slice(chat, after: "answeringId = nil\n", before: "\n        activity = nil").contains("answeringModel = nil"))
    }
}
