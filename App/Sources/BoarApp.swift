import CoreSpotlight
import SwiftUI

/// BOAR: an offline research assistant. First-run setup until the required models are on the phone, then the chat
/// with past sessions in the sidebar.
@main
struct BoarApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BrandFonts.register()
        #if DEBUG && os(macOS)
        DebugSnapshot.probeWindows()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // One main window (the chat and its sidebar share one model), the Settings window (⌘,) and About in the app menu.
        Window(Text(verbatim: "BOAR"), id: "main") {
            root
                .frame(minWidth: 1040, minHeight: 560)
                .onOpenURL { url in if url.scheme == "boar-source" { model.citationRequest = url } }
        }
        // The chat window opens at every launch, also one started in the background (UI capture).
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands { BoarCommands(model: model) }
        .onChange(of: scenePhase, phaseChanged)
        .backgroundTask(.urlSession(BackgroundDownloads.identifier)) {
            await BackgroundDownloads.shared.handleEvents()
        }

        Settings {
            MacSettingsView()
                .environment(model)
                .boarTheme(model.theme)
        }

        Window("About BOAR", id: "about") {
            AboutScreen()
                .frame(width: 440, height: 600)
                .boarTheme(model.theme)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        #else
        WindowGroup {
            root
        }
        .onChange(of: scenePhase, phaseChanged)
        // Downloads that finished while BOAR was suspended or not running.
        .backgroundTask(.urlSession(BackgroundDownloads.identifier)) {
            await BackgroundDownloads.shared.handleEvents()
        }
        #endif
    }

    private var root: some View {
        RootView()
            .environment(model)
            .boarTheme(model.theme)
            .task { await model.start() }
            // A chat tapped in Spotlight.
            .onContinueUserActivity(CSSearchableItemActionType) { IntentInbox.shared.open($0) }
            #if os(macOS)
            // ⌘Q during or right after a load is a quit, not a load kill: drop the LoadGuard marker before the process
            // ends, or the next launch blocks the model (a Mac app never goes to the background the way an iPhone app does).
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.services?.host.appWillQuit()
            }
            #endif
    }

    private func phaseChanged(_ old: ScenePhase, _ phase: ScenePhase) {
        switch phase {
        case .background: model.didEnterBackground()
        case .active: model.didBecomeActive()
        default: break
        }
    }
}
