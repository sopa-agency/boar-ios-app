import BoarAnswer
import BoarCore
import SwiftUI

/// Runs "Ask BOAR to rewrite it" on the chat's model (android printer `PressRewriter.kt`). It runs as the chat's own job
/// (`ChatController.runForLab`, as Cards' model card): the claim is one step on the main actor (validator G-4), a question
/// sent meanwhile waits in the chat's queue and starts after it, and the chat's Stop ends it. It only uses the model the
/// chat already has. It returns the rewrite and never touches the projects: the block changes only on "Use the new text".
@MainActor
@Observable
final class PressRewriter {
    enum Phase: Equatable {
        case idle, running
        case done(text: String, marksChanged: Bool)
    }

    private(set) var phase: Phase = .idle
    /// What the model has written so far, its reasoning hidden.
    private(set) var streamed = ""
    /// Why there is no rewrite (busy, no model, failed, no change, stopped).
    var line: String?
    /// Each run's number: what a stopped or left run still returns is dropped.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private weak var chat: ChatController?

    /// Android's 120 s, as a failed rewrite.
    private static let timeoutMs: Int64 = 120_000

    var running: Bool { phase == .running }

    static var busyText: String { String(localized: "A chat answer is being written. Try again when it ends.") }

    /// Starts a rewrite of `text`; busy (an answer or another plugin's work holds the model), it says so instead.
    func ask(_ chat: ChatController?, text: String, option: PressRewrite.Option, own: String?, languageOf: String, document: String) {
        guard !running else { return }
        line = nil
        streamed = ""
        phase = .idle
        guard let chat else {
            line = String(localized: "Rewriting needs an answer model on this \(Platform.deviceNoun).")
            return
        }
        let prompt = PressRewrite.prompt(option, text, own: own, languageOf: languageOf, document: document)
        run += 1
        let id = run
        let services = chat.services
        phase = .running
        let started = chat.runForLab { [weak self] stopped in
            await self?.generate(id, services, prompt, text, stopped)
        }
        guard started else {
            phase = .idle
            line = Self.busyText
            return
        }
        self.chat = chat
    }

    /// Stop, or the sheet left: this rewrite ends and the text stays as it was. Only while it runs, so a chat answer that
    /// started after it is never stopped.
    func stop(saying: Bool) {
        guard running else { return }
        run += 1
        phase = .idle
        if saying { line = String(localized: "Stopped. Your text is as it was.") }
        chat?.stop()
    }

    private enum End { case stopped, noModel, failed }

    private func generate(_ id: Int, _ services: BoarServices, _ p: PressRewrite.Prompt, _ text: String,
                          _ stopped: @escaping @Sendable () -> Bool) async {
        // Only the model the chat already has: a rewrite never loads one (a model that may not fit asks first, in the chat).
        let session: (any TextModelSession)? = services.backend == .llama && services.host.current == nil ? nil : await services.activeSession()
        guard run == id else { return }
        guard let session, !stopped() else { return end(id, stopped() ? .stopped : .noModel) }
        let written = PressStream()
        var result: GenResult?
        do {
            result = try await SessionEngine(session).generate(
                system: p.system, user: p.user, nPredict: p.nPredict, temperature: 0.3, timeoutMs: Self.timeoutMs
            ) { [weak self] piece in
                let (all, n) = written.append(piece)
                Task { @MainActor [weak self] in self?.show(id, all, n) }
            }
        } catch {
            result = nil
        }
        guard run == id else { return }
        if stopped() { return end(id, .stopped) }
        guard let result, !result.timedOut else { return end(id, .failed) }
        switch PressRewrite.outcome(text, raw: result.text) {
        case .failed: end(id, .failed)
        case .unchanged:
            phase = .idle
            line = String(localized: "No change. Try again or say what to change.")
        case .done(let out, let marksChanged):
            phase = .done(text: out, marksChanged: marksChanged)
        }
    }

    @ObservationIgnored private var shownPieces = 0

    private func show(_ id: Int, _ all: String, _ n: Int) {
        // Pieces can hop to the main actor out of order: only a longer text replaces what is shown.
        guard run == id, phase == .running, n > shownPieces || streamed.isEmpty else { return }
        shownPieces = n
        streamed = PressRewrite.visible(all)
    }

    private func end(_ id: Int, _ how: End) {
        guard run == id else { return }
        phase = .idle
        shownPieces = 0
        switch how {
        case .stopped: line = String(localized: "Stopped. Your text is as it was.")
        case .noModel: line = String(localized: "Rewriting needs an answer model on this \(Platform.deviceNoun).")
        case .failed: line = String(localized: "BOAR could not rewrite it. Your text is as it was.")
        }
    }

    #if DEBUG
    /// `-uiPressSheet rewritten`: a finished rewrite to look at, with no model.
    func showDemo(_ text: String, marksChanged: Bool) { phase = .done(text: text, marksChanged: marksChanged) }
    #endif
}

/// The model's pieces as they come, from the generation's thread.
private final class PressStream: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var pieces = 0

    func append(_ piece: String) -> (String, Int) {
        lock.withLock {
            text += piece
            pieces += 1
            return (text, pieces)
        }
    }
}

/// The edit sheet's presets, in their order on the two lines (android `REWRITE_PRESETS`).
let pressRewritePresets: [(PressRewrite.Option, LocalizedStringResource)] = [
    (.shorter, "Shorter"), (.simpler, "Simpler words"), (.fix, "Fix the wording"), (.list, "As a list"),
    (.paragraph, "As a paragraph"), (.formal, "More formal"),
]

/// The pencil on a text block (android `EditSheet`, adam's mock-up): "Edit it yourself" (type on the page) or "Ask BOAR to
/// rewrite it" (six presets, or the user's own words). The rewrite streams, then NOW and REWRITTEN; nothing in the block
/// changes before "Use the new text". Keep mine, Stop and closing the sheet leave it as it was. Not while a chat answer
/// is being written.
struct PressEditSheet: View {
    let block: PressDoc.Block
    /// The rest of the document, for an instruction in the user's own words (`PressRewrite.documentContext`).
    let document: String
    /// Typed in the note bar for this text: BOAR starts on it as the sheet opens, once.
    let typed: String?
    let onTypedUsed: () -> Void
    let onSelf: () -> Void
    let onUse: (String) -> Void
    @State private var rewriter = PressRewriter()
    @State private var own = ""
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var current: String { PressEdit.textOf(block) ?? "" }

    /// An answer's language is told by its question and text; a block's by its own text.
    private var languageOf: String {
        if case .answer(let a) = block { return a.question + "\n" + a.text }
        return current
    }

    /// The chat writing an answer (or a plugin's work on the model): say so, and the options wait.
    private var chatBusy: Bool { !rewriter.running && (model.chat?.modelBusy ?? false) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch rewriter.phase {
                    case .running:
                        PressVersion(label: "NOW", text: PressReceipt.plain(current), new: false)
                        PressVersion(label: "BOAR IS REWRITING…", text: rewriter.streamed, new: true)
                        PressSheetButton("Stop", primary: false) { rewriter.stop(saying: true) }
                    case .done(let text, let marksChanged):
                        PressVersion(label: "NOW", text: PressReceipt.plain(current), new: false)
                        PressVersion(label: "REWRITTEN", text: PressReceipt.plain(text), new: true,
                                     warning: marksChanged ? String(localized: "Some source marks changed") : nil)
                        // The one place the rewrite reaches the block.
                        PressSheetButton("Use the new text", primary: true) { onUse(text) }
                        PressSheetButton("Keep mine", primary: false) { dismiss() }
                    case .idle:
                        options
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle(Text(rewriter.phase == .idle ? "Edit this text" : "Ask BOAR to rewrite it"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
            }
        }
        .macSheetSize(height: 560)
        .presentationDetents([.medium, .large])
        // Leaving the sheet (closed, swiped down) stops a rewrite still running; the block stays as it was.
        .onDisappear { rewriter.stop(saying: false) }
        // Typed in the note bar: BOAR starts on it as the sheet opens, once; the words stay in the sheet's own field.
        .task {
            #if DEBUG
            if DebugLaunch.pressSheet == "rewritten" {
                rewriter.showDemo("The crust is mostly salt. Rain washes it off the rocks, rivers carry it to the sea, and the sun dries the water away.", marksChanged: false)
                return
            }
            #endif
            guard let typed, !typed.allSatisfy(\.isWhitespace) else { return }
            own = typed
            ask(.own, typed)
            onTypedUsed()
        }
    }

    @ViewBuilder private var options: some View {
        Button(action: onSelf) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .frame(width: 22)
                Text("Edit it yourself")
                    .font(.boar("ui.body"))
                Spacer()
                Text("type on the page")
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
            }
            .foregroundStyle(.boar(.primary))
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        Divider()
        Text("Ask BOAR to rewrite it")
            .font(.boar("ui.body").bold())
            .foregroundStyle(.boar(.heading))
            .padding(.top, 12)
            .padding(.bottom, 6)
        if chatBusy {
            Text(PressRewriter.busyText)
                .font(.boar("ui.caption"))
                .foregroundStyle(.boar(.warning))
                .padding(.bottom, 6)
        }
        // Six presets on two lines (adam, Nov 14: "2 more to fill the second line"); longer words wrap, never cut.
        FlowChips(spacing: 6) {
            ForEach(pressRewritePresets, id: \.0) { option, label in
                Button { ask(option, nil) } label: {
                    Text(label)
                        .font(.boar("ui.body"))
                        .foregroundStyle(.boar(.primary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(.boar(.border).opacity(0.18), in: .capsule)
                        .overlay(Capsule().strokeBorder(.boar(.border)))
                }
                .buttonStyle(.plain)
                .disabled(chatBusy)
                .opacity(chatBusy ? 0.4 : 1)
            }
        }
        TextField("Or say what to change, for example: for a 10-year-old", text: $own)
            .font(.boar("ui.body"))
            .textFieldStyle(.plain)
            .padding(12)
            .background(.boar(.border).opacity(0.18), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.boar(.border)))
            .padding(.top, 12)
            .onChange(of: own) { _, v in if v.count > 120 { own = String(v.prefix(120)) } }
            .onSubmit { askOwn() }
        PressSheetButton("Ask BOAR", primary: false, enabled: !chatBusy && !own.allSatisfy(\.isWhitespace)) { askOwn() }
        if let line = rewriter.line {
            Text(line)
                .font(.boar("ui.caption"))
                .foregroundStyle(.boar(.warning))
                .padding(.top, 8)
        }
        Text("BOAR rewrites it on this \(Platform.deviceNoun) with your model. You see both versions before anything changes.")
            .font(.boar("ui.caption"))
            .foregroundStyle(.boar(.muted))
            .padding(.top, 8)
    }

    private func askOwn() {
        guard !chatBusy, !own.allSatisfy(\.isWhitespace) else { return }
        ask(.own, own)
    }

    private func ask(_ option: PressRewrite.Option, _ ownText: String?) {
        rewriter.ask(model.chat, text: current, option: option, own: ownText, languageOf: languageOf, document: document)
    }
}

/// One version of the text: NOW or REWRITTEN, with a warning line under it if any (android `Version`).
private struct PressVersion: View {
    let label: LocalizedStringResource
    let text: String
    let new: Bool
    var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.boar("mono.xs").bold())
                .foregroundStyle(.boar(.muted))
            Text(verbatim: text)
                .font(.boar("ui.body"))
                .foregroundStyle(.boar(.primary))
                .textSelection(.enabled)
            if let warning {
                Text(warning)
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.warning))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.boar(.border).opacity(0.12), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(new ? AnyShapeStyle(.boar(.accent)) : AnyShapeStyle(.boar(.border))))
        .padding(.vertical, 6)
    }
}

/// A full-width sheet button (android `SheetButton`): the primary one filled.
private struct PressSheetButton: View {
    let title: LocalizedStringResource
    let primary: Bool
    var enabled = true
    let action: () -> Void

    init(_ title: LocalizedStringResource, primary: Bool, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.enabled = enabled; self.action = action
    }

    var body: some View {
        Group {
            if primary {
                Button(action: action) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(!enabled)
        .padding(.top, 10)
    }

    private var label: some View {
        Text(title)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
    }
}

/// Every project, the open one first, then the most recent, with a search by name (android `AllProjectsSheet`, adam Nov
/// 12).
struct PressAllProjectsSheet: View {
    let library: PressDoc.Library
    let onSwitch: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let found = library.search(query)
            List {
                if found.isEmpty {
                    Text("No project with that name.")
                        .font(.boar("ui.caption"))
                        .foregroundStyle(.boar(.muted))
                }
                ForEach(found, id: \.id) { p in
                    Button { onSwitch(p.id) } label: {
                        PressProjectRow(project: p, open: p.id == library.current.id)
                    }
                }
            }
            .searchable(text: $query, placement: Self.searchPlacement, prompt: Text("Search projects"))
            .onChange(of: query) { _, q in if q.count > 60 { query = String(q.prefix(60)) } }
            .navigationTitle(Text("All projects (\(library.projects.count))"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
            }
        }
        .macSheetSize()
    }

    private static var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }
}

/// A project in the menu or the full list: a check on the open one, a folder on the others, and how many blocks it holds.
struct PressProjectRow: View {
    let project: PressDoc.Project
    let open: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: open ? "checkmark" : "folder")
                .foregroundStyle(open ? .boar(.accent) : .boar(.primary))
                .frame(width: 22)
            Text(verbatim: project.name)
                .foregroundStyle(open ? .boar(.accent) : .boar(.primary))
                .lineLimit(2)
            Spacer()
            Text("\(project.blocks.count) blocks")
                .font(.boar("ui.caption"))
                .foregroundStyle(.boar(.muted))
        }
        .font(.boar("ui.body"))
        .contentShape(.rect)
    }
}
