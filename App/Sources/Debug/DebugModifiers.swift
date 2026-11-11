import SwiftUI

/// One-line hooks for screens that open something by themselves in the UI audit (`-uiScreen`). In Release they return the
/// view untouched.
extension View {
    /// Pushes `destination` when the app was launched with `-uiScreen <screen>`.
    func debugPush<Destination: View>(_ screen: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        #if DEBUG
        modifier(DebugPush(screen: screen, destination: destination))
        #else
        self
        #endif
    }

    /// Opens the tour on its card for `-uiScreen tour-<card>`.
    func debugTour() -> some View {
        #if DEBUG
        modifier(DebugTour())
        #else
        self
        #endif
    }

    /// Opens the citation sheet or the answer style sheet for `-uiScreen citation-sheet / tone-sheet`.
    func debugChatSheets(source: Binding<ChatSource?>, tones: Binding<Bool>, chat: ChatController) -> some View {
        #if DEBUG
        modifier(DebugChatSheets(source: source, tones: tones, chat: chat))
        #else
        self
        #endif
    }

    /// Goes back to the sessions list for `-uiScreen sidebar` (iPhone: the chat is the first column on screen).
    func debugSidebar(_ column: Binding<NavigationSplitViewColumn>) -> some View {
        #if DEBUG
        modifier(DebugSidebar(column: column))
        #else
        self
        #endif
    }

    /// Opens a receipt sheet for `-uiScreen receipt` (the first answer's).
    func debugReceipt(_ isOpen: Binding<Bool>) -> some View {
        #if DEBUG
        modifier(DebugReceipt(isOpen: isOpen))
        #else
        self
        #endif
    }
}

#if DEBUG
/// The screens `-uiScreen` already pushed: once per launch, so going back doesn't push it again every time the parent
/// reappears (on the iPhone, leaving iPhone & Storage bounced straight back into it).
@MainActor private var pushedScreens: Set<String> = []

private struct DebugPush<Destination: View>: ViewModifier {
    let screen: String
    let destination: () -> Destination
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $pushed, destination: destination)
            .task {
                guard DebugLaunch.isScreen(screen), !pushedScreens.contains(screen) else { return }
                pushedScreens.insert(screen)
                try? await Task.sleep(for: .milliseconds(700))
                pushed = true
            }
    }
}

private struct DebugTour: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .tourCover(isPresented: $shown, index: DebugLaunch.tourCard.flatMap { card in
                TourCard.cards(experimental: LabsBuild.experimental).firstIndex(of: card)
            } ?? 0)
            .task {
                guard DebugLaunch.tourCard != nil else { return }
                try? await Task.sleep(for: .milliseconds(700))
                shown = true
            }
    }
}

private struct DebugSidebar: ViewModifier {
    @Binding var column: NavigationSplitViewColumn
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task {
            guard DebugLaunch.isScreen("sidebar") else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            // A selected row keeps its detail on screen in the compact layout: deselect, then go back.
            model.selection = nil
            column = .sidebar
        }
    }
}

private struct DebugChatSheets: ViewModifier {
    @Binding var source: ChatSource?
    @Binding var tones: Bool
    let chat: ChatController

    func body(content: Content) -> some View {
        content.task(id: chat.messages.count) {
            guard chat.messages.count >= 2 else { return }
            if DebugLaunch.isScreen("citation-sheet") || DebugLaunch.isScreen("source-reader"), source == nil,
               let first = chat.messages.last(where: { !$0.isUser })?.sources.first {
                try? await Task.sleep(for: .milliseconds(600))
                source = first
            }
            if DebugLaunch.isScreen("tone-sheet"), !tones {
                try? await Task.sleep(for: .milliseconds(600))
                tones = true
            }
        }
    }
}

/// Only the first receipt button that appears opens, so two answers don't fight over one sheet.
@MainActor private var receiptClaimed = false

private struct DebugReceipt: ViewModifier {
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        content.task {
            guard DebugLaunch.isScreen("receipt"), !receiptClaimed else { return }
            receiptClaimed = true
            try? await Task.sleep(for: .milliseconds(900))
            isOpen = true
        }
    }
}
#endif
