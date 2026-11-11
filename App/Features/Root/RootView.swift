import SwiftUI

/// Launch → setup or the main split view, under the app lock when it's on.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        #if os(macOS)
        // The Mac's sidebar sits in its own layer above an overlay: a locked BOAR shows only the lock screen.
        if let lock = model.lock, lock.enabled, lock.locked {
            LockScreen(lock: lock)
        } else {
            main
        }
        #else
        main
        #endif
    }

    private var main: some View {
        content
            .groupedFormStyle()
            #if os(macOS)
            .overlay { cover }
            #else
            // In its own window: an overlay would sit under any open sheet or full-screen cover.
            .lockWindow(isPresented: model.lock.map { $0.enabled && ($0.locked || coversContent) } ?? false) {
                cover
                    .environment(model)
                    .environment(\.scenePhase, scenePhase)
                    .boarTheme(model.theme)
            }
            #endif
            .onChange(of: IntentInbox.shared.question) { _, _ in model.drainInbox() }
            .onChange(of: IntentInbox.shared.sessionId) { _, _ in model.drainInbox() }
    }

    /// The lock screen while BOAR is locked, else the privacy cover while it isn't in front.
    @ViewBuilder private var cover: some View {
        if let lock = model.lock, lock.enabled {
            if lock.locked {
                LockScreen(lock: lock)
            } else if coversContent {
                PrivacyCover()
            }
        }
    }

    /// The iPhone covers the chats in the app switcher; a Mac window behind another app stays readable, so the cover
    /// shows only once it is hidden or minimized.
    private var coversContent: Bool {
        #if os(macOS)
        scenePhase == .background
        #else
        scenePhase != .active
        #endif
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .launching:
            LaunchView()
        case .failed(let message):
            ContentUnavailableView {
                Label("BOAR couldn't open its library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.start() } }
                    .buttonStyle(.boarProminent)
            }
        case .setup:
            if let setup = model.setup {
                SetupView(flow: setup)
            }
        case .ready:
            if let chat = model.chat {
                MainSplitView(chat: chat)
            }
        }
    }
}
