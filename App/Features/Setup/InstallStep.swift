import BoarModels
import SwiftUI

/// Step 4's details, opened from the guide's download strip: the downloads and the library index, with the fixes when one
/// stops, and the way back to the guide.
struct InstallStep: View {
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
                    .boarRowBackground()
                    IndexRow(flow: flow)
                        .boarRowBackground()
                }
                if flow.stalled {
                    Section {
                        Button("Restart Downloads", icon: Symbols.retry, action: flow.restartDownloads)
                    } footer: {
                        Text("Downloads not moving? Restarting keeps the bytes already on the \(Platform.deviceNoun).")
                    }
                    .boarRowBackground()
                }
                if !flow.failed.isEmpty {
                    Section {
                        Button("Try Again", icon: Symbols.retry, action: flow.retry)
                        if flow.failed.contains(where: \.storage) && flow.package == .encyclopedia {
                            Button("Choose a Smaller Package", systemImage: "arrow.down.right.and.arrow.up.left", action: flow.smallerPackage)
                        }
                    } footer: {
                        if let error = flow.failed.first?.error { Text(error) }
                    }
                    .boarRowBackground()
                }
                if flow.indexPhase == .error {
                    Section {
                        Button("Try Again", icon: Symbols.retry, action: flow.retryIndex)
                    } footer: {
                        Text(flow.indexError ?? "")
                    }
                    .boarRowBackground()
                }
            }
        }
        .groupedListStyle()
        .boarListBackground()
        .readableWidth()
        // The header is the first row: no extra list margin between it and the navigation bar.
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            // Back to the page the user was on; the download keeps going under it.
            SetupBottomButton(title: "Back to Setup") { flow.showDetails(false) }
        }
        .onChange(of: flow.finished) { _, done in
            if done { AccessibilityNotification.Announcement(String(localized: "Setup finished. BOAR is ready.")).post() }
        }
    }
}
