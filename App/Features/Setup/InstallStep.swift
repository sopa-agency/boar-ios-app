import BoarModels
import SwiftUI

/// Step 4: the downloads and the library index, then "Open BOAR".
struct InstallStep: View {
    @Environment(AppModel.self) private var model
    let flow: SetupFlow

    private var title: LocalizedStringKey {
        if flow.finished { "Ready" } else if flow.allPresent { "Preparing Library" } else { "Installing" }
    }

    var body: some View {
        List {
            if flow.finished {
                SetupDoneSection(flow: flow)
            } else {
                InstallProgressSection(flow: flow, title: title)
                Section {
                    ForEach(flow.downloads) { d in
                        DownloadRow(progress: d)
                    }
                    IndexRow(flow: flow)
                }
                if flow.stalled {
                    Section {
                        Button("Restart Downloads", systemImage: Symbols.retry, action: flow.restartDownloads)
                    } footer: {
                        Text("Downloads not moving? Restarting keeps the bytes already on the \(Platform.deviceNoun).")
                    }
                }
                if !flow.failed.isEmpty {
                    Section {
                        Button("Try Again", systemImage: Symbols.retry, action: flow.retry)
                        if flow.failed.contains(where: \.storage) && flow.package == .encyclopedia {
                            Button("Choose a Smaller Package", systemImage: "arrow.down.right.and.arrow.up.left", action: flow.smallerPackage)
                        }
                    } footer: {
                        if let error = flow.failed.first?.error { Text(error) }
                    }
                }
                if flow.indexPhase == .error {
                    Section {
                        Button("Try Again", systemImage: Symbols.retry, action: flow.retryIndex)
                    } footer: {
                        Text(flow.indexError ?? "")
                    }
                }
            }
        }
        .groupedListStyle()
        .readableWidth()
        // The header is the first row: no extra list margin between it and the navigation bar.
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            if flow.finished {
                SetupBottomButton(title: "Open BOAR", action: model.finishSetup)
            }
        }
        .onChange(of: flow.finished) { _, done in
            if done { AccessibilityNotification.Announcement(String(localized: "Setup finished. BOAR is ready.")).post() }
        }
    }
}
