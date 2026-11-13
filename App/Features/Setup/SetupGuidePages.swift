import BoarCore
import BoarModels
import SwiftUI
import UniformTypeIdentifiers

/// One page of setup's guide (android SetupGuide.kt's pages), under its header.
struct SetupGuidePage: View {
    let page: SetupGuide.Page
    let flow: SetupFlow
    @Environment(AppModel.self) private var model
    @State private var bridge: SettingsBridge

    init(page: SetupGuide.Page, flow: SetupFlow) {
        self.page = page
        self.flow = flow
        _bridge = State(initialValue: SettingsBridge(settings: flow.services.settings))
    }

    var body: some View {
        switch page {
        case .look: look
        case .files: GuideFilesPage(flow: flow)
        case .answers: GuideAnswersPage(flow: flow, bridge: bridge)
        case .ask: ask
        case .first: GuideFirstQuestionPage(bridge: bridge)
        case .pin: if let lock = model.lock { GuideLockPage(lock: lock) }
        case .privacy: privacy
        case .labs: GuideLabsPage()
        case .ready: GuideReadyPage(flow: flow, bridge: bridge)
        // iOS has no notifications page.
        case .notify: EmptyView()
        }
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 16) {
            TourThemePicker()
            #if !os(macOS)
            GuideNote("Text size follows your \(Platform.deviceNoun)'s Dynamic Type setting.")
            #endif
            // Below the chips, so a tap repaints the example right under the finger (as the tour's theme card).
            TourPreview(card: .theme)
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideCard {
                // With files added, how to ask about them comes first.
                ForEach((flow.files.files.isEmpty ? [] : [Self.tipFiles]) + Self.tips, id: \.key) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .foregroundStyle(.boar(.success))
                            .accessibilityHidden(true)
                        Text(tip)
                            .foregroundStyle(.boar(.primary))
                    }
                    .boarText("ui.body")
                }
            }
            TourPreview(card: .sources)
        }
    }

    private static let tipFiles: LocalizedStringResource = "To answer only from your own files, pick the Personal Files style with the style button."

    private static let tips: [LocalizedStringResource] = [
        "Ask a whole question: \"How do I make water safe to drink?\" finds more than \"water\".",
        "Follow up as you would with a person: \"and if I can't boil it?\" keeps the subject.",
        "The articles an answer used are listed under it: tap one to read it. Hold your question to copy it back.",
    ]

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideCard {
                #if !os(macOS)
                GuideSwitch("Free Memory When I Leave BOAR",
                            note: "Shortly after you leave, when nothing is being answered, BOAR unloads the model, so the phone doesn't close BOAR to get its memory back. The next answer takes a few seconds longer to start.",
                            isOn: bridge.binding({ $0.freeMemoryInBackground }, { $0.freeMemoryInBackground = $1 }))
                Divider()
                #endif
                GuideSwitch("Ask Before Deleting a Chat", note: "Deleting a chat from the menu asks first. Off: one tap deletes it.",
                            isOn: bridge.binding({ $0.confirmChatDelete }, { $0.confirmChatDelete = $1 }))
                Divider()
                GuideSwitch("Generate Chat Titles", note: "Names new chats from your first message",
                            isOn: bridge.binding({ $0.autoGenerateTitles }, { $0.autoGenerateTitles = $1 }))
                Divider()
                GuideSwitch("Dictation", note: "Show the microphone button in the chat to dictate messages.",
                            isOn: bridge.binding({ $0.voiceInputEnabled }, { $0.voiceInputEnabled = $1 }))
            }
            GuideNote("All of these are in Settings too.", role: .link)
        }
    }
}

// MARK: pages

/// The answer styles BOAR can start with, as cards with their chat icon, and Deep Research.
private struct GuideAnswersPage: View {
    let flow: SetupFlow
    let bridge: SettingsBridge
    @State private var askFiles = false

    var body: some View {
        let personalities = flow.services.personalities
        let style = bridge.binding({ $0.personalityId ?? personalities.defaultId }, { $0.personalityId = $1 })
        let deep = bridge.binding({ $0.deepResearchMode }, { $0.deepResearchMode = $1 })
        let hasFiles = !flow.files.files.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            // The styles BOAR can start with; Personal Files only once there are files to answer from.
            ForEach(["succinct", "detailed"] + (hasFiles ? ["personal"] : []), id: \.self) { id in
                let p = personalities.get(id)
                GuideModeCard(icon: p.symbol, title: p.displayLabel, detail: p.displayDescription, selected: style.wrappedValue == id) {
                    style.wrappedValue = id
                }
            }
            // Without files, Personal Files is explained, not picked: there would be nothing to answer from. A tap offers
            // the files page to add some.
            if !hasFiles {
                let p = personalities.get("personal")
                GuideModeCard(icon: p.symbol, title: p.displayLabel,
                              detail: String(localized: "Answers only from your own files. Tap to add some first."), selected: false) {
                    askFiles = true
                }
            }
            GuideModeCard(icon: Symbols.deepResearch, title: String(localized: "Deep Research"),
                          detail: String(localized: "Searches in several steps and writes a longer answer. It takes longer; you can also turn it on just for one question."),
                          selected: deep.wrappedValue) {
                deep.wrappedValue.toggle()
            }
            // Deep Research writes longer answers in several steps: on the light model that's minutes per answer.
            if deep.wrappedValue, let m = flow.chosenModel, flow.isCompact(m) {
                GuideNote("With the light model you picked, a Deep Research answer can take a few minutes.", role: .amber)
            }
            GuideNote("In the chat, the style button next to where you type shows this icon and switches it any time.", role: .link)
        }
        .alert("Add your files first?", isPresented: $askFiles) {
            Button("Add Files") { withAnimation { flow.guideTo(.files) } }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Personal Files answers only from your own files. Add some on the files page, then come back and pick it here.\n\n\(Text(GuideFilesPage.types))")
        }
    }
}

/// Notes, PDFs or spreadsheets to ask about later: copied now, imported into Personal Files once the search model is in
/// and the index isn't building.
private struct GuideFilesPage: View {
    let flow: SetupFlow
    @State private var picking = false
    @Environment(\.palette) private var palette

    /// The same kinds as Knowledge → Personal Files.
    private static let importTypes: [UTType] = [.plainText, .text, .commaSeparatedText, .json, .pdf] + [UTType(filenameExtension: "md")].compactMap { $0 }
    /// iOS reads a scanned PDF too (OCR on the device), which Android doesn't.
    static let types: LocalizedStringResource = "BOAR reads .txt, .md, .csv, .json and .pdf, scanned ones too."

    var body: some View {
        let files = flow.files
        VStack(alignment: .leading, spacing: 16) {
            if files.files.isEmpty {
                Button { picking = true } label: {
                    Label("Add Files", icon: .pack(.add))
                        .boarText("ui.title")
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.boarProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
            } else {
                Button { picking = true } label: {
                    Label("Add More Files", icon: .pack(.add))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
            }
            Text(Self.types)
                .boarText("ui.subtext")
                .foregroundStyle(.boar(.muted))
            if !files.files.isEmpty {
                GuideCard {
                    ForEach(Array(files.files.enumerated()), id: \.element) { i, name in
                        if i > 0 { Divider() }
                        row(name, done: files.imported.contains(name) && !files.importing)
                    }
                }
            }
            ForEach(files.notes, id: \.self) { Text(verbatim: $0).boarText("ui.subtext").foregroundStyle(.boar(.secondary)) }
            ForEach(files.errors, id: \.self) { Text(verbatim: $0).boarText("ui.subtext").foregroundStyle(.boar(.danger)) }
            // A question about these files needs the Personal Files style: the default one searches the library first.
            if !files.files.isEmpty {
                GuideCard(highlight: true) {
                    Text("To ask about them, switch the chat's style to Personal Files (the style button, next to where you type). Then BOAR answers only from your files, and says so when they don't have the answer.")
                        .boarText("ui.body")
                        .foregroundStyle(.boar(.primary))
                }
            }
            GuideNote("Later: Knowledge → Personal Files", role: .link)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files.add(urls) }
        }
    }

    private func row(_ name: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(icon: .pack(done ? .check : .pending))
                .foregroundStyle(.boar(done ? .success : .secondary))
                .accessibilityHidden(true)
            Text(verbatim: name)
                .boarText("ui.body")
                .foregroundStyle(.boar(.primary))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(done ? String(localized: "Added") : waiting)
                .boarText("ui.caption")
                .foregroundStyle(.boar(done ? .success : .muted))
            // A wrong pick goes again; an imported one comes out of Personal Files too.
            Button { flow.files.remove(name) } label: {
                Image(icon: .pack(.close))
                    .foregroundStyle(.boar(.muted))
                    .padding(8)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(flow.files.importing)
            .accessibilityLabel(Text("Remove \(name)"))
        }
        .accessibilityElement(children: .contain)
    }

    private var waiting: String {
        let searchReady = flow.downloads.contains { $0.asset.kind == .embedding && $0.done }
        return if flow.files.importing {
            String(localized: "Adding…")
        } else if !searchReady {
            String(localized: "After the search model")
        } else if flow.indexPhase == .building {
            String(localized: "After the index")
        } else {
            String(localized: "Up Next")
        }
    }
}

/// One way BOAR answers, its icon big and first (the same as on the chat's style button), so a quick reader matches the
/// button to the mode without reading the text.
private struct GuideModeCard: View {
    let icon: AppIcon
    let title: String
    let detail: String
    let selected: Bool
    let pick: () -> Void
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .title) private var disc = 48

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 14) {
                Image(icon: icon)
                    .font(.system(size: disc * 0.5))
                    .foregroundStyle(.boar(.heading))
                    .frame(width: disc, height: disc)
                    .background(selected ? Color(palette.emerald500).opacity(0.25) : Color(palette.bgSubtle), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .boarText("ui.title")
                        .foregroundStyle(.boar(.heading))
                    Text(verbatim: detail)
                        .boarText("ui.subtext")
                        .foregroundStyle(.boar(.secondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(icon: .pack(.check))
                        .foregroundStyle(.boar(.success))
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .background(Color(selected ? palette.emeraldBgSubtle : palette.bgCard), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(selected ? palette.emeraldBorder : palette.borderSubtle), lineWidth: selected ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The question waiting in the chat when BOAR opens: an example, or the user's own.
private struct GuideFirstQuestionPage: View {
    let bridge: SettingsBridge
    @Environment(\.palette) private var palette

    /// android chat.suggestions q2, q4 and q8.
    private static let examples = [
        String(localized: "Pandemics and epidemics: how outbreaks spread and how they're classified"),
        String(localized: "First aid for nosebleeds: what works and what to avoid"),
        String(localized: "How monsoons form, and why they matter for farming in South Asia"),
    ]

    var body: some View {
        let question = bridge.binding({ $0.pendingFirstQuestion ?? "" }, { $0.pendingFirstQuestion = $1 })
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.examples, id: \.self) { q in
                let on = q == question.wrappedValue
                Button {
                    question.wrappedValue = on ? "" : q
                } label: {
                    Text(verbatim: q)
                        .boarText("ui.body")
                        .foregroundStyle(Color(on ? palette.textAccentEmerald : palette.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(on ? palette.emeraldBgSubtle : palette.bgCard), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(on ? palette.emeraldBorder : palette.borderSubtle), lineWidth: on ? 2 : 1))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            // The user's own question: the field shows it only when it isn't one of the examples.
            TextField("Or write your own…", text: Binding(
                get: { Self.examples.contains(question.wrappedValue) ? "" : question.wrappedValue },
                set: { question.wrappedValue = $0 }
            ), axis: .vertical)
            .lineLimit(1...4)
            .boarText("ui.body")
            .padding(12)
            .background(Color(palette.bgInput), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(palette.borderDefault)))
            .accessibilityIdentifier("firstQuestionField")
        }
    }
}

/// Lock BOAR (android's PIN page): Face ID, Touch ID or the passcode, the same switch as Settings → Privacy.
private struct GuideLockPage: View {
    let lock: AppLock
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if lock.enabled {
                GuideCard(highlight: true) {
                    Label {
                        Text("Lock on. BOAR asks for \(lock.methodName) from now on.")
                            .boarText("ui.title")
                            .foregroundStyle(.boar(.heading))
                    } icon: {
                        Image(icon: .pack(.check))
                            .foregroundStyle(.boar(.success))
                    }
                }
            } else {
                Text(TourCard.lock.text)
                    .boarText("ui.body")
                    .foregroundStyle(.boar(.primary))
                if lock.available {
                    Button {
                        Task { await lock.enable() }
                    } label: {
                        Label("Lock with \(lock.methodName)", systemImage: lock.methodSymbol)
                            .boarText("ui.title")
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.boarProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .controlSize(.large)
                    .disabled(lock.busy)
                } else {
                    GuideNote("Set a passcode for your \(Platform.deviceNoun) in the Settings app to lock BOAR.", role: .amber)
                }
            }
            if let error = lock.error {
                Text(verbatim: error)
                    .boarText("ui.subtext")
                    .foregroundStyle(.boar(.danger))
            }
        }
    }
}

/// The labs a user can switch on (live, beta and alpha), each with its switch, off until switched on.
private struct GuideLabsPage: View {
    @State private var labs = Labs.shared
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .title) private var art = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideCard {
                let shown = labs.visible.filter { $0.status <= .alpha }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, lab in
                    if i > 0 { Divider() }
                    Toggle(isOn: Binding(get: { labs.enabled(lab.id) }, set: { labs.setEnabled(lab.id, $0) })) {
                        HStack(alignment: .top, spacing: 12) {
                            picture(lab)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(verbatim: lab.title)
                                        .boarText("ui.titleSm")
                                        .foregroundStyle(.boar(.heading))
                                    LabStatusTag(status: lab.status)
                                }
                                Text(verbatim: lab.body)
                                    .boarText("ui.caption")
                                    .foregroundStyle(.boar(.muted))
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                GuideNote("Beta: tested on phones")
                GuideNote("Alpha: early, less tested")
            }
            GuideNote("Labs don't slow the answers. The ones that load a model use extra memory while they run. All of them are in Settings → Advanced → Boar Labs.",
                      role: .secondary)
        }
    }

    @ViewBuilder private func picture(_ lab: any LabPlugin) -> some View {
        Group {
            if let art = lab.shownArt {
                Image(art).resizable().scaledToFill()
            } else {
                Text(verbatim: lab.emoji).font(.system(size: art * 0.55))
            }
        }
        .frame(width: art, height: art)
        .background(Color(palette.emeraldBgSubtle))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

/// The last page: what was chosen, then the summary when BOAR is ready, else where the download is.
private struct GuideReadyPage: View {
    let flow: SetupFlow
    let bridge: SettingsBridge
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let personalities = flow.services.personalities
        let style = personalities.get(bridge.read { $0.personalityId } ?? personalities.defaultId).displayLabel
        let on = String(localized: "On"), off = String(localized: "Off")
        VStack(alignment: .leading, spacing: 16) {
            GuideCard {
                Text("Your choices")
                    .textCase(.uppercase)
                    .font(.boar("ui.micro").bold())
                    .foregroundStyle(.boar(.secondary))
                row("Answer Style", style)
                row("Deep Research", bridge.read { $0.deepResearchMode } ? on : off)
                row("Your Files", flow.files.files.isEmpty ? String(localized: "None") : flow.files.files.count.formatted())
                row("First Question", bridge.read { $0.pendingFirstQuestion } ?? String(localized: "None"))
                if let lock = model.lock { row("Lock", lock.enabled ? on : off) }
                GuideNote("Go back to change any of them, or later in Settings.")
            }
            if flow.finished {
                GuideCard {
                    Text("Ready")
                        .textCase(.uppercase)
                        .font(.boar("ui.micro").bold())
                        .foregroundStyle(.boar(.secondary))
                    if let m = flow.chosenModel { row("Answer Model", m.friendlyName) }
                    row("Library", flow.package.title)
                    row("Articles", flow.indexTotal.formatted())
                    GuideNote("Everything runs offline from now on.")
                }
            } else {
                Button("See the Download") { flow.showDetails(true) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.boar(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: value)
                .foregroundStyle(.boar(.primary))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .boarText("ui.body")
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: pieces

/// Android's Card on the guide: a rounded box on bgCard, or on the emerald wash for something done.
private struct GuideCard<Content: View>: View {
    var highlight = false
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(highlight ? palette.emeraldBgSubtle : palette.bgCard), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(highlight ? palette.emerald500 : palette.borderSubtle)))
    }
}

/// Android's Meta: a small line under a page's choices, muted or in an accent.
private struct GuideNote: View {
    let text: LocalizedStringKey
    var role: BoarStyle.Role = .muted

    init(_ text: LocalizedStringKey, role: BoarStyle.Role = .muted) {
        self.text = text
        self.role = role
    }

    var body: some View {
        Text(text)
            .boarText("ui.subtext")
            .foregroundStyle(.boar(role))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Android's SwitchRow: the setting's name, a line on what it does, and its switch.
private struct GuideSwitch: View {
    let title: LocalizedStringKey
    let note: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, note: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self.note = note
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .boarText("ui.body")
                    .foregroundStyle(.boar(.primary))
                Text(note)
                    .boarText("ui.subtext")
                    .foregroundStyle(.boar(.secondary))
            }
        }
    }
}
