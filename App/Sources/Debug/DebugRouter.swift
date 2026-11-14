#if DEBUG
import BoarModels
import SwiftUI

/// `-uiScreen <name>`: puts the running app on that screen once it is ready, without a tap.
///
/// setup, setup-model, setup-knowledge, setup-install, setup-index, setup-guide-<page> (look, answers, ask, first, pin, privacy,
/// labs, ready), chat-empty, chat-error, chat-no-model, chat-load-crash, chat, chat-top, chat-streaming, chat-retrieving, chat-research,
/// sidebar, citation-sheet, source-reader, receipt, tone-sheet, models, model-detail, models-downloading, models-browse, documents,
/// settings, settings-advanced, settings-engine, device-info, evaluation, about, lock, tour-<card>.
@MainActor
enum DebugRouter {
    static func apply(_ model: AppModel) async {
        if let file = DebugLaunch.importFile, await waitReady(model) {
            model.selection = .screen(.documents)
            model.documents?.importFiles([URL(filePath: file)], name: "Test Import")
        }
        if let style = DebugLaunch.style, await waitReady(model) { model.chat?.setTone(style) }
        if !DebugLaunch.questions.isEmpty, await waitReady(model) {
            await ask(DebugLaunch.questions, model)
            return
        }
        guard let screen = DebugLaunch.screen else { return }
        if screen.hasPrefix("setup") {
            await setup(screen, model)
            return
        }
        guard await waitReady(model) else { return }
        // The split view has to be on screen before a selection change reaches `onChange`.
        try? await Task.sleep(for: .milliseconds(700))
        switch screen {
        case "chat", "chat-top", "citation-sheet", "source-reader", "receipt", "tone-sheet":
            await openFirstSession(model)
        case "chat-streaming":
            await openFirstSession(model)
            model.chat?.debugShowAnswering(question: DemoContent.liveQuestion, partial: DemoContent.liveText, activity: .generating, deepResearch: false)
        case "chat-retrieving":
            await openFirstSession(model)
            model.chat?.debugShowAnswering(question: DemoContent.liveQuestion, partial: "", activity: .retrieving, deepResearch: false)
        case "chat-research":
            await openFirstSession(model)
            model.chat?.debugShowAnswering(question: DemoContent.liveQuestion, partial: "", activity: .researching(.researching, index: 2, count: 4), deepResearch: true)
        case "chat-error", "chat-no-model":
            await openFirstSession(model)
            model.chat?.debugShowFailure(question: DemoContent.liveQuestion, noModel: screen == "chat-no-model")
        case "chat-load-crash":
            model.chat?.debugShowLoadCrash()
        case "models", "model-detail": model.selection = .screen(.models)
        case "models-downloading":
            model.models?.debugShowDownload()
            model.selection = .screen(.models)
        case "models-browse":
            model.models?.debugShowBrowse(DemoContent.repos)
            model.selection = .screen(.models)
        case "documents": model.selection = .screen(.documents)
        case "settings", "settings-engine", "settings-advanced", "device-info", "avatars", _ where screen.hasPrefix("tour-"):
            model.selection = .screen(.settings)
        case "evaluation": model.selection = .screen(.evaluation)
        case "about": model.selection = .screen(.about)
        case "labs", _ where screen.hasPrefix("lab-"): model.selection = .screen(.labs)
        default: break
        }
        if let scroll = DebugLaunch.scroll {
            // Lists fill in lazily: a second pass lands on the right offset once the rows are there.
            try? await Task.sleep(for: .seconds(2.2))
            #if canImport(UIKit)
            DebugScroll.scroll(to: scroll)
            try? await Task.sleep(for: .milliseconds(500))
            DebugScroll.scroll(to: scroll)
            #endif
        }
    }

    private static func setup(_ screen: String, _ model: AppModel) async {
        guard await waitPhase(model, { if case .launching = $0 { false } else { true } }) else { return }
        // Not a fresh phone (no -uiDemo): the wizard again, as Settings → Recovery opens it.
        if case .ready = model.phase { model.reopenSetup() }
        try? await Task.sleep(for: .milliseconds(500))
        // The download's details, as a tap on the guide's strip opens them.
        if screen == "setup-install" || screen == "setup-index" {
            model.setup?.debugShowInstall(indexing: screen == "setup-index")
            model.setup?.showDetails(true)
            return
        }
        // The guide on that page, over a download in progress.
        if screen.hasPrefix("setup-guide-"), let page = SetupGuide.Page(rawValue: screen.dropFirst(12).uppercased()) {
            model.setup?.debugShowInstall(indexing: false)
            model.setup?.guideTo(page)
            model.setup?.files.add(DebugLaunch.setupFiles)
            return
        }
        let steps = screen == "setup-model" ? 1 : screen == "setup-knowledge" ? 2 : 0
        for _ in 0..<steps { model.setup?.next() }
    }

    /// `-uiAsk`: once an import is done, one new chat gets the questions, each after the previous answer.
    private static func ask(_ questions: [String], _ model: AppModel) async {
        // An import started above runs in the background: wait for it (up to 5 minutes for a long PDF).
        try? await Task.sleep(for: .milliseconds(500))
        for _ in 0..<3000 where model.documents?.busy == true { try? await Task.sleep(for: .milliseconds(100)) }
        model.selection = .newChat
        try? await Task.sleep(for: .milliseconds(700))
        guard let chat = model.chat else { return }
        for q in questions {
            chat.send(q)
            try? await Task.sleep(for: .milliseconds(300))
            // Up to 10 minutes per answer: a first load plus a long answer on the simulator's CPU.
            for _ in 0..<6000 where chat.isAnswering { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func openFirstSession(_ model: AppModel) async {
        var waited = 0
        while model.sessions.isEmpty && waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard let first = model.sessions.first else { return }
        model.selection = .session(first.id)
        waited = 0
        while (model.chat?.messages.isEmpty ?? true) && waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
    }

    private static func waitReady(_ model: AppModel) async -> Bool {
        await waitPhase(model) { if case .ready = $0 { true } else { false } }
    }

    private static func waitPhase(_ model: AppModel, _ wanted: (AppModel.Phase) -> Bool) async -> Bool {
        for _ in 0..<100 {
            if wanted(model.phase) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
#endif
