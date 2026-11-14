import BoarCore
import BoarModels
import SwiftUI

/// Setup's step 4 (android SetupGuide.kt): while the files download and the index builds, one page at a time to make
/// BOAR the user's own and learn to use it (SetupGuide). The download stays live in a strip on top; a tap on it shows
/// its details. Every choice is saved as it's made, with the same writes as Settings; every page can be skipped.
struct SetupGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let flow: SetupFlow
    @State private var bannerHidden = false

    var body: some View {
        let page = flow.page
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SetupProgressStrip(flow: flow) { flow.showDetails(true) }
                // The download finished before the pages: BOAR can open now, or the user finishes them first.
                if flow.finished && page != .ready && !bannerHidden {
                    SetupReadyBanner(open: model.finishSetup) { bannerHidden = true }
                }
                SetupGuideHeader(index: flow.guidePage, total: flow.pages.count, page: page)
                SetupGuidePage(page: page, flow: flow)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableWidth()
        }
        // A page of its own: Next opens it at the top, not where the last one was scrolled to.
        .id(page)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footer(page) }
        // VoiceOver stays on Next otherwise, and never hears that the page changed.
        .onChange(of: page) { AccessibilityNotification.ScreenChanged(nil).post() }
    }

    /// Open BOAR on the last page (once it's ready); else Next, or a quieter Not Now on a page with its own action (the
    /// lock's); Back from the second page on.
    private func footer(_ page: SetupGuide.Page) -> some View {
        VStack(spacing: 0) {
            if page == .ready {
                // The page's subtitle already says when it opens: no note here, so large text keeps room for the page.
                SetupBottomButton(title: "Open BOAR", enabled: flow.finished, action: model.finishSetup)
            } else if skippable(page) {
                SetupBottomButton(title: "Not Now", prominent: false, action: next)
            } else {
                SetupBottomButton(title: "tour.next", action: next)
            }
            if flow.guidePage > 0 {
                Button(action: back) {
                    Label("Back", icon: .pack(.arrowBack))
                        .foregroundStyle(.boar(.muted))
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 8)
            }
        }
        // Solid, as Android's footer: a long page (Labs) scrolls under it, not through the Back link.
        .background(Color(palette.bgTerminal).ignoresSafeArea(edges: .bottom))
    }

    /// Pages whose own action (Add Files, Lock) is the strong button: the footer's goes quiet until it's used.
    private func skippable(_ page: SetupGuide.Page) -> Bool {
        (page == .files && flow.files.files.isEmpty) || (page == .pin && model.lock?.enabled != true)
    }

    private func next() {
        withAnimation { flow.guideNext() }
    }

    private func back() {
        withAnimation { flow.guideBack() }
    }
}

// MARK: frame

/// The download under the pages: bar, line and time left; amber when it needs the user, and a tap shows the details.
private struct SetupProgressStrip: View {
    let flow: SetupFlow
    let onDetails: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let p = SetupGuideProgress(flow)
        Button(action: onDetails) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(max(p.fraction, 0), 1))
                    .tint(Color(palette.emerald500))
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: p.line)
                        .boarText("ui.subtext")
                        .fontWeight(p.problem ? .bold : nil)
                        .foregroundStyle(Color(p.problem ? palette.textAccentAmber : palette.textSecondary))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Details \(Text(verbatim: "›"))")
                        .font(.boar("ui.caption").bold())
                        .foregroundStyle(Color(palette.textAccentEmerald))
                }
            }
            .padding(12)
            .background(Color(p.problem ? palette.amberBgSubtle : palette.bgCard), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(p.problem ? palette.amberBorder : palette.borderSubtle)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: p.line))
        .accessibilityHint(Text("Shows the download's details"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("setupProgress")
    }
}

/// The strip's numbers (android tourProgress): bytes while files arrive, then the index.
struct SetupGuideProgress {
    let fraction: Double
    let line: String
    let problem: Bool

    @MainActor
    init(_ flow: SetupFlow) {
        let downloading = !flow.allPresent
        fraction = downloading ? (flow.totalBytes > 0 ? Double(flow.doneBytes) / Double(flow.totalBytes) : 0)
            : flow.indexTotal > 0 ? Double(flow.indexDone) / Double(flow.indexTotal) : flow.finished ? 1 : 0
        let eta = FeatureFormat.eta((downloading ? flow.etaSeconds : flow.indexEtaSeconds).map(Double.init))
            .map { " · " + String(localized: "About \($0) left") } ?? ""
        problem = flow.stalled || !flow.failed.isEmpty || flow.indexPhase == .error
        line = if flow.finished {
            String(localized: "tour.done")
        } else if problem {
            String(localized: "Setup paused · tap to see it")
        } else if !downloading && flow.indexTotal == 0 {
            String(localized: "Preparing the index…")
        } else if downloading {
            String(localized: "Downloading · \(Int(fraction * 100))%") + eta
        } else {
            String(localized: "Building the index · \(flow.indexDone.formatted()) of \(flow.indexTotal.formatted())") + eta
        }
    }
}

private struct SetupReadyBanner: View {
    let open: () -> Void
    let keep: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BOAR is ready")
                .boarText("ui.title")
                .foregroundStyle(Color(palette.textHeading))
            HStack(spacing: 8) {
                Button(action: open) {
                    Text("Open BOAR").frame(maxWidth: .infinity)
                }
                .buttonStyle(.boarProminent)
                Button(action: keep) {
                    Text("Keep Going").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color(palette.emeraldBgSubtle), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(palette.emerald500)))
    }
}

/// The page's dots and "3 OF 8", its title and what it's for.
private struct SetupGuideHeader: View {
    let index: Int
    let total: Int
    let page: SetupGuide.Page
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { n in
                    Circle()
                        .fill(Color(n <= index ? palette.emerald500 : palette.bgSubtle))
                        .frame(width: 6, height: 6)
                }
                Text("\(index + 1) of \(total)")
                    .textCase(.uppercase)
                    .font(.boar("ui.micro").bold())
                    .foregroundStyle(Color(palette.textAccentEmerald))
                    .padding(.leading, 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(index + 1) of \(total)"))
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .boarText("ui.headline")
                    .boarDisplayLines()
                    .foregroundStyle(Color(palette.textHeading))
                    .accessibilityAddTraits(.isHeader)
                Text(page.subtitle)
                    .boarText("ui.body")
                    .foregroundStyle(Color(palette.textSecondary))
            }
        }
    }
}

extension SetupGuide.Page {
    var title: LocalizedStringResource {
        switch self {
        case .look: "Make it yours"
        case .files: "Your own files"
        case .answers: "How BOAR answers"
        case .ask: "How to ask"
        case .first: "Your first question"
        case .pin: "Lock BOAR?"
        case .notify: "Notifications"
        case .privacy: "Privacy and memory"
        case .labs: "Boar Labs"
        case .ready: "Almost there"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        // Text size follows the system on iOS: the page offers the theme only.
        case .look: "Pick a theme. It changes right away, and you can change it again in Settings."
        case .files: "Add notes, PDFs or spreadsheets now and ask about them later. They stay on this \(Platform.deviceNoun)."
        case .answers: "The style BOAR starts with. In the chat, the style button switches it for any question."
        case .ask: "BOAR searches its library for your question, then answers from what it found."
        case .first: "Pick one, or write your own. It will be waiting in the chat when BOAR opens; you send it."
        case .pin: "Only for BOAR: your \(Platform.deviceNoun)'s own lock doesn't change."
        case .notify: "One notification, only while BOAR answers."
        case .privacy: "How BOAR treats your chats and your \(Platform.deviceNoun)'s memory."
        case .labs: "Experiments, labelled beta or alpha. They all start off: switch on the ones you want."
        case .ready: "BOAR opens as soon as the download and the index are done."
        }
    }
}
