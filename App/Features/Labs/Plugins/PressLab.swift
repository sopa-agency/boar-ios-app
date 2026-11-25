import BoarAnswer
import BoarCore
import os
import SwiftUI

/// Boar Press (android labs/plugins/printer `PrinterLab.kt`): projects as documents of blocks (BoarAnswer `PressDoc`).
/// Answers come in from any chat (More → Add to Press) into the open project; here they're reordered, edited or
/// dropped, and the project is compiled to an A4 PDF (BoarAnswer `PressPDF`) or a Markdown file, shared through the share
/// sheet (Save to Files included). This page is the basket's, kept on the new model until Press's own page (BOAR-55
/// part 6.2): it shows the open project's blocks; projects, the add toolbar, pictures and rewrites come with it.
struct PressLab: LabPlugin {
    let id = "printer"
    let order = 30
    let emoji = "🖨️"
    let art: String? = "truffle_steampunk"
    let status = LabStatus.beta
    var title: String { String(localized: "Press") }
    var body: String { String(localized: "Collect answers from any chat into a basket, then compile them into a PDF or a Markdown file.") }

    func content() -> AnyView { AnyView(PressSections()) }

    var about: String? {
        String(localized: "Answers come from a chat: under an answer, open the plugins and tap Add to Press. Here you reorder, edit or drop them, then compile the page to an A4 PDF or a Markdown file, made offline on this \(Platform.deviceNoun).")
    }

    /// 📎 in the answer's More menu: into the open project at the end, with its question, sources, chat title and the card
    /// shown under it; again takes it out.
    func answerActions(_ a: AnswerRef) -> [LabAnswerAction] {
        let store = PressStore.shared
        store.load()
        let added = store.library?.has(a.id) == true
        let project = store.library?.current.name ?? ""
        return [LabAnswerAction(id: "printer.basket",
                                title: added ? String(localized: "In \(project) (tap to remove)") : String(localized: "Add to Press: \(project)"),
                                systemImage: "paperclip", done: added) {
            if added {
                store.change { $0.removeAnswer(a.id) }
            } else {
                var card = CardsModel.shared.shown(a)
                card?.ticks = CardsModel.shared.ticks(a.id)
                store.addAnswer(PressDoc.Answer(a.id, a.chatTitle, a.question, a.text,
                                                a.sources.map { PressDoc.Source($0.0, $0.1.flatMap { $0.isEmpty ? nil : $0 }) },
                                                PressStore.now, a.model, a.tokPerSec, card: card))
            }
        }]
    }

    /// What the header sheet shows beside Press: the open project's answers (android `headerCount`; not on the icon).
    func headerCount() -> Int {
        PressStore.shared.load()  // as Android's headerCount: the sheet can open before anything read the projects
        return PressStore.shared.library?.current.answers.count ?? 0
    }
    func headerCountLabel(_ n: Int) -> String { String(localized: "\(n) in \(PressStore.shared.library?.current.name ?? "")") }

    /// The projects hold answers' text: they go with the chats (Forgot PIN, Clear all), every project and its folder;
    /// Clear Chat History keeps them unless "Also delete Press" is ticked.
    func eraseUserData(_ scope: UserDataScope) {
        if scope.erasesPress { PressStore.shared.eraseAll() }
    }

    /// One chat deleted: its answers leave every project (adam chose (a), Nov 12). Runs even when off.
    func eraseAnswers(_ answerIds: [String]) { PressStore.shared.eraseAnswers(answerIds) }
}

/// Press's projects as the app holds them (android printer `PressStore.kt`): `files/labs/press/projects.json`, read once,
/// written whole after each change; the old basket (`files/labs/basket.json`) becomes the first project, once.
@MainActor
@Observable
final class PressStore {
    static let shared = PressStore(files: AppPaths.filesDir)

    /// Nil until loaded (or while the projects file can't be read).
    private(set) var library: PressDoc.Library?
    /// The projects file is there but can't be read: nothing is written over it.
    private(set) var unreadable = false
    @ObservationIgnored private let files: URL
    /// Read successfully (or nothing saved yet). Until then nothing is written, so a file that failed to read is never
    /// replaced.
    @ObservationIgnored private var loaded = false

    init(files: URL) { self.files = files }

    nonisolated static func dir(_ files: URL) -> URL { files.appending(path: "labs/press", directoryHint: .isDirectory) }
    nonisolated static func projectsURL(_ files: URL) -> URL { dir(files).appending(path: "projects.json") }
    var dir: URL { Self.dir(files) }
    private var projectsURL: URL { Self.projectsURL(files) }
    private var basketURL: URL { files.appending(path: "labs/basket.json") }
    /// The old basket couldn't be read once: it is tried again when Press loads (G-3).
    private var pendingMarker: URL { dir.appending(path: "basket-pending") }

    static func newId(_ prefix: String) -> String { prefix + "-" + UUID().uuidString.lowercased().prefix(8) }
    static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// The first project's name: the basket's document title, if the user gave one, else "Field notes".
    private var firstName: String {
        let t = PressPrefs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? String(localized: "Field notes") : t
    }

    func load() {
        guard !loaded else { return }
        let fm = FileManager.default
        let projects: String? = fm.fileExists(atPath: projectsURL.path) ? ((try? String(contentsOf: projectsURL, encoding: .utf8)) ?? "") : nil
        let basket: String? = fm.fileExists(atPath: basketURL.path) ? ((try? String(contentsOf: basketURL, encoding: .utf8)) ?? "") : nil
        let name = firstName, now = Self.now
        switch PressDoc.load(projects: projects, basket: basket, newId: Self.newId("p"), name: name, now: now) {
        case .read(var lib):
            // The old basket couldn't be read the first time (G-3): try again, once a launch, until it can.
            if fm.fileExists(atPath: pendingMarker.path) {
                if let basket {
                    if let merged = try? PressDoc.mergeBasket(lib, basket, newId: Self.newId("p"), name: name, now: now) {
                        if merged == lib || write(merged) {
                            lib = merged
                            try? fm.removeItem(at: basketURL)
                            try? fm.removeItem(at: pendingMarker)
                        }
                    } else {
                        log.warning("press: the old basket still can't be read; will retry")
                    }
                } else {
                    try? fm.removeItem(at: pendingMarker)
                }
            }
            library = lib; loaded = true; unreadable = false
            // Copies no project uses any more (a photo removed past its Undo, a cut-short copy): only after a good read.
            for u in PressFiles.orphans(dir, lib) { try? fm.removeItem(at: u) }
        case .migrated(let lib):
            // Written first; only then the basket goes. A failed write leaves the basket for the next try.
            if write(lib) {
                library = lib; loaded = true
                try? fm.removeItem(at: basketURL)
            }
        case .fresh(let lib, let basketUnreadable):
            // Not written until the first change; a basket that can't be read stays where it is.
            if basketUnreadable {
                log.warning("press: the old basket can't be read; kept as is, retried on the next launch")
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try? Data("1".utf8).write(to: pendingMarker)
            }
            library = lib; loaded = true
        case .unreadable:
            loaded = false
            unreadable = true
            log.warning("press: projects file unreadable, kept as is; will retry")
        }
    }

    /// One change at a time, state and file together. Nothing happens before a successful load.
    func change(_ f: (PressDoc.Library) -> PressDoc.Library) {
        load()
        guard loaded, let cur = library else { return }
        let next = f(cur)
        guard next != cur else { return }
        if write(next) { library = next }
    }

    /// An answer at the end of the open project.
    func addAnswer(_ a: PressDoc.Answer, after: [PressDoc.Block] = []) { change { $0.addAnswer(a, after: after) } }

    /// The answers of a deleted chat leave every project; the header's count follows.
    func eraseAnswers(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        change { $0.eraseAnswers(ids) }
    }

    /// Projects that hold at least one block: what "Also delete Press" counts.
    var projectsWithContent: Int {
        load()
        return library?.projects.count { !$0.blocks.isEmpty } ?? 0
    }

    /// How many of `ids` are in any project.
    func countOf(_ ids: [String]) -> Int {
        load()
        return library?.countOf(ids) ?? 0
    }

    /// Deletes a project and its folder; the last one leaves an empty "Field notes" in its place.
    func deleteProject(_ id: String) {
        let now = Self.now
        let blank = PressDoc.Project(Self.newId("p"), String(localized: "Field notes"), now, seenAt: now)
        let before = library
        change { $0.deleteProject(id, blank: blank) }
        if library != before { PressFiles.deleteProject(dir, id) }
    }

    /// Erased with the chats (Forgot PIN, Clear all): every project and its folder, and the old basket, even if
    /// unreadable.
    func eraseAll() {
        PressFiles.eraseAll(dir)
        try? FileManager.default.removeItem(at: basketURL)
        library = PressDoc.emptyLibrary(Self.newId("p"), String(localized: "Field notes"), Self.now)
        unreadable = false
        loaded = true
    }

    /// A picture's file for the PDF: a drawing's own path, a photo in its project's folder; nil when it is gone.
    nonisolated static func fileOf(_ dir: URL, _ projectId: String) -> @Sendable (PressDoc.Picture) -> URL? {
        { p in
            let u = p.kind == .photo ? PressFiles.photoFile(dir, projectId, p.file) : URL(fileURLWithPath: p.file)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }

    private func write(_ lib: PressDoc.Library) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(PressDoc.toJson(lib).utf8).write(to: projectsURL, options: .atomic)
            return true
        } catch {
            log.warning("press not saved: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @ObservationIgnored private let log = BoarLog.logger("labs")
}

/// What prints besides the blocks, kept between visits (android LabPrefs `printer.show*`, "on"/"off"), and the
/// document's words from the catalog.
enum PressPrefs {
    private static var d: UserDefaults { AppPaths.defaults }

    /// The basket's document title before projects: it names the first project, once.
    static var title: String { d.string(forKey: "labs.printer.title") ?? "" }

    /// Android's defaults: the date, the sources and the models on, the speed off. Before projects iOS kept the date
    /// and the sources under `labs.printer.date` / `labs.printer.sources`: those choices carry over.
    static var options: PressReceipt.Options {
        get {
            func on(_ key: String, old: String? = nil, _ def: Bool) -> Bool {
                switch d.string(forKey: key) ?? old.flatMap({ d.string(forKey: $0) }) {
                case "on": true
                case "off": false
                default: def
                }
            }
            return PressReceipt.Options(date: on("labs.printer.showDate", old: "labs.printer.date", true),
                                        sources: on("labs.printer.showSources", old: "labs.printer.sources", true),
                                        models: on("labs.printer.showModels", true), speed: on("labs.printer.showSpeed", false))
        }
        set {
            d.set(newValue.date ? "on" : "off", forKey: "labs.printer.showDate")
            d.set(newValue.sources ? "on" : "off", forKey: "labs.printer.showSources")
            d.set(newValue.models ? "on" : "off", forKey: "labs.printer.showModels")
            d.set(newValue.speed ? "on" : "off", forKey: "labs.printer.showSpeed")
        }
    }

    static var labels: PressReceipt.Labels {
        var l = PressReceipt.Labels()
        l.madeWith = String(localized: "Made offline with BOAR · {{date}}")
        l.ownFile = String(localized: "Your own file")
        return l
    }

    static var today: String { Date().formatted(date: .long, time: .omitted) }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// A project as it prints: a user's own file names scrubbed first (validator Q-B3), the words and switches set.
    static func page(_ project: PressDoc.Project, options: PressReceipt.Options) -> PressPage {
        let l = labels
        return PressPage(project: PressReceipt.scrubOwnFiles(project, ownFile: l.ownFile), date: today, version: version, labels: l,
                         sourcesLabel: String(localized: "Sources"), options: options,
                         cardByModel: String(localized: "made by the model · checked against the answer"))
    }
}

private struct PressSections: View {
    @State private var store = PressStore.shared
    @State private var name = ""
    @State private var options = PressPrefs.options
    @State private var preview = false
    @State private var editing: PressDoc.Answer?

    private var project: PressDoc.Project? { store.library?.current }
    private var blocks: [PressDoc.Block] { project?.blocks ?? [] }

    var body: some View {
        Group {
            if blocks.isEmpty {
                Section {
                    Text("The basket is empty.")
                } footer: {
                    BoarFooter {
                        Text("Under any answer in a chat, open More (…) and add it to the basket. Collect from as many chats as you like, then come back to arrange and compile.")
                    }
                }
            } else if let project {
                Section("Document title") {
                    TextField(text: $name, prompt: Text(verbatim: project.name)) { Text("Document title") }
                }
                Section("Print") {
                    Toggle("Date under the title", isOn: optionBinding(\.date))
                    Toggle("Sources at the end", isOn: optionBinding(\.sources))
                    Toggle("Models", isOn: optionBinding(\.models))
                    Toggle("Model speed", isOn: optionBinding(\.speed))
                        .disabled(!options.models)
                }
                Section {
                    Picker("Show", selection: $preview) {
                        Text("Arrange").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if preview {
                    Section { PressPreview(page: PressPrefs.page(project, options: options)) }
                        .listRowInsets(EdgeInsets())
                } else {
                    blocksSection
                }
                Section {
                    ShareLink(item: pdfFile(project), preview: SharePreview(Text(verbatim: PressReceipt.slug(project.name) + ".pdf"))) {
                        Label("Print to PDF", systemImage: "printer")
                    }
                    ShareLink(item: markdownFile(project), preview: SharePreview(Text(verbatim: PressReceipt.slug(project.name) + ".md"))) {
                        Label("Save as Markdown", systemImage: "doc.text")
                    }
                }
            }
        }
        .onAppear {
            store.load()
            name = project?.name ?? ""
            // The user looked: the project's answers are no longer new.
            store.change { $0.markSeen(PressStore.now) }
        }
        .task(id: name) {
            // Renamed a moment after typing stops; a blank name keeps the old one.
            // A key typed meanwhile cancels this wait: only the last one renames (pr-review #66).
            guard (try? await Task.sleep(for: .milliseconds(800))) != nil else { return }
            if let id = project?.id, name != project?.name { store.change { $0.rename(id, name) } }
        }
        .sheet(item: $editing) { a in PressAnswerEditor(answer: a) }
    }

    private var blocksSection: some View {
        let answers = blocks.compactMap(\.answer)
        return Section {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { i, block in
                Group {
                    if let a = block.answer {
                        Button { editing = a } label: { PressItemRow(number: (answers.firstIndex { $0.id == a.id } ?? 0) + 1, answer: a) }
                            .buttonStyle(.plain)
                    } else {
                        PressBlockRow(block: block)
                    }
                }
                .accessibilityAction(named: Text("Move up")) { store.change { $0.move(block.id, by: -1) } }
                .accessibilityAction(named: Text("Move down")) { store.change { $0.move(block.id, by: 1) } }
                .contextMenu {
                    if let a = block.answer { Button("Edit", systemImage: "pencil") { editing = a } }
                    Button("Move up", systemImage: "arrow.up") { store.change { $0.move(block.id, by: -1) } }
                        .disabled(i == 0)
                    Button("Move down", systemImage: "arrow.down") { store.change { $0.move(block.id, by: 1) } }
                        .disabled(i == blocks.count - 1)
                    Button("Remove", systemImage: "trash", role: .destructive) { store.change { $0.remove(block.id) } }
                }
            }
            .onMove { from, to in
                store.change { lib in
                    var out = lib
                    guard let k = out.projects.firstIndex(where: { $0.id == lib.current.id }) else { return lib }
                    out.projects[k].blocks.move(fromOffsets: from, toOffset: to)
                    return out
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { blocks[$0].id }
                store.change { lib in ids.reduce(lib) { $0.remove($1) } }
            }
        } header: {
            HStack {
                Text(answers.count == 1 ? String(localized: "1 item") : String(localized: "\(answers.count) items"))
                Spacer()
                // Android's Clear (PrinterLab.kt): crimson400 in mono.xs. Empties the open project.
                Button("Clear", role: .destructive) {
                    store.change { lib in lib.current.blocks.reduce(lib) { $0.remove($1.id) } }
                }
                .boarText("mono.xs")
                .bold()
                .foregroundStyle(.boar(.danger))
            }
        } footer: {
            BoarFooter {
                if blocks.count > 1 { Text("Touch and hold an answer, then drag it to change the order.") }
            }
        }
    }

    private func optionBinding(_ key: WritableKeyPath<PressReceipt.Options, Bool>) -> Binding<Bool> {
        Binding(get: { options[keyPath: key] }, set: { options[keyPath: key] = $0; PressPrefs.options = options })
    }

    /// The A4 PDF, compiled when the share sheet asks for it.
    private func pdfFile(_ project: PressDoc.Project) -> ExportedFile {
        let page = PressPrefs.page(project, options: options)
        let fileOf = PressStore.fileOf(store.dir, project.id)
        return ExportedFile(filename: PressReceipt.slug(project.name) + ".pdf") { PressPDF.compile(page, fileOf: fileOf) }
    }

    private func markdownFile(_ project: PressDoc.Project) -> ExportedFile {
        let md = PressPrefs.page(project, options: options).markdown(drawingLabel: String(localized: "Drawing"), photoLabel: String(localized: "Photo"))
        return ExportedFile(filename: PressReceipt.slug(project.name) + ".md") { Data(md.utf8) }
    }
}

extension PressDoc.Answer: @retroactive Identifiable {}

/// One answer in the project: its number, heading, the start of its text and how many sources it has.
private struct PressItemRow: View {
    let number: Int
    let answer: PressDoc.Answer

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.boar("mono.xs").weight(.heavy))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: PressPage.oneLine(answer.shownHeading))
                    .font(.boar("ui.titleSm"))
                    .lineLimit(2)
                Text(verbatim: PressReceipt.plain(answer.text))
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
                    .lineLimit(3)
                if !answer.sources.isEmpty {
                    Text(answer.sources.count == 1 ? String(localized: "1 source") : String(localized: "\(answer.sources.count) sources"))
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.dim))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// A block that isn't an answer (a heading, a note, a list, a picture, from Android's Press or a later version): shown,
/// moved and removed here; edited on Press's own page (part 6.2).
private struct PressBlockRow: View {
    let block: PressDoc.Block

    var body: some View {
        switch block {
        case .heading(_, let t):
            Text(verbatim: PressPage.oneLine(t)).font(.boar("ui.titleSm"))
        case .divider:
            Divider()
        case .picture(let p):
            Label(p.caption.allSatisfy(\.isWhitespace) ? (p.kind == .photo ? String(localized: "Photo") : String(localized: "Drawing")) : p.caption, systemImage: "photo")
                .foregroundStyle(.boar(.muted))
        case .bullets(_, let t):
            Text(verbatim: PressDoc.bulleted(t)).font(.boar("ui.caption")).lineLimit(4)
        default:
            Text(verbatim: block.text ?? "").font(.boar("ui.caption")).italic().foregroundStyle(.boar(.muted)).lineLimit(4)
        }
    }
}

/// The heading printed above an answer, then its text; both saved as you type. A changed text drops the answer's card,
/// as Android's Press does (it showed the old text's figures).
private struct PressAnswerEditor: View {
    let answer: PressDoc.Answer
    @State private var heading = ""
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BoarForm {
                Section {
                    TextField(text: $heading, prompt: Text(verbatim: answer.question)) { Text("Heading") }
                } header: {
                    BoarHeader {
                        Text("Heading")
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 240)
                }
            }
            .navigationTitle(Text(verbatim: PressPage.oneLine(answer.shownHeading)))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            heading = answer.shownHeading
            text = answer.text
        }
        .onChange(of: heading) { _, h in PressStore.shared.change { $0.editText(answer.id, .heading, h) } }
        .onChange(of: text) { _, t in PressStore.shared.change { $0.editText(answer.id, .text, t) } }
    }
}

/// The document as it will print, on paper colors: the same blocks, switches, Sources section and footer as the PDF.
/// Press's own page (part 6.2) replaces it with the paper itself.
private struct PressPreview: View {
    let page: PressPage

    private static let ink = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
    private static let dim = Color(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: PressPage.oneLine(page.project.name)).font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Self.ink)
            if page.options.date {
                Text(verbatim: page.date.uppercased()).font(.system(size: 10)).foregroundStyle(Self.dim)
            }
            ForEach(page.project.blocks, id: \.id) { block in
                switch block {
                case .answer(let a):
                    Text(verbatim: PressPage.oneLine(a.shownHeading))
                        .font(.system(size: 14, weight: .bold, design: .serif)).foregroundStyle(Self.ink)
                        .padding(.top, 6)
                    if let q = a.shownQuestion {
                        Text(verbatim: q).font(.system(size: 11, design: .serif)).italic().foregroundStyle(Self.dim)
                    }
                    Text(verbatim: page.answerText(a))
                        .font(.system(size: 12, design: .serif)).lineSpacing(5).foregroundStyle(Self.ink)
                    if let refs = page.refsLine(a) {
                        Text(verbatim: refs).font(.system(size: 9)).foregroundStyle(Self.dim)
                    }
                case .heading(_, let t):
                    Text(verbatim: PressPage.oneLine(t)).font(.system(size: 16, weight: .bold, design: .serif)).foregroundStyle(Self.ink).padding(.top, 6)
                case .divider:
                    Rectangle().fill(Self.dim.opacity(0.4)).frame(height: 1)
                case .bullets(_, let t):
                    Text(verbatim: PressDoc.bulleted(t)).font(.system(size: 12, design: .serif)).foregroundStyle(Self.ink)
                case .note(_, let t), .paragraph(_, let t):
                    Text(verbatim: t).font(.system(size: 12, design: .serif)).foregroundStyle(Self.ink)
                default:
                    EmptyView()
                }
            }
            if !page.sourceLines.isEmpty {
                Text(verbatim: page.sourcesLabel).font(.system(size: 11, weight: .bold, design: .serif)).foregroundStyle(Self.ink).padding(.top, 10)
                ForEach(page.sourceLines, id: \.self) { Text(verbatim: $0).font(.system(size: 9)).foregroundStyle(Self.dim) }
            }
            Rectangle().fill(Self.dim.opacity(0.4)).frame(width: 40, height: 1).padding(.top, 10)
            ForEach(page.footer, id: \.self) { Text(verbatim: $0).font(.system(size: 9)).foregroundStyle(Self.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
