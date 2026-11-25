import BoarAnswer
import BoarCore
import os
import SwiftUI

/// Boar Press (android labs/plugins/printer `PrinterLab.kt`): projects as documents of blocks (BoarAnswer `PressDoc`).
/// Each project is a page of blocks: answers sent from a chat (More → Add to Press, or Answers from a chat on the page),
/// headings, paragraphs, lists, notes, dividers and photos. The page in the app is what the PDF prints (`PressScreen`);
/// every document ends with how it was made.
struct PressLab: LabPlugin {
    let id = "printer"
    let order = 30
    let emoji = "🖨️"
    let art: String? = "truffle_steampunk"
    let status = LabStatus.beta
    var title: String { String(localized: "Press") }
    var body: String { String(localized: "Projects as documents: chat answers, headings, notes and photos, saved as a PDF.") }

    /// The paper fills the page under the navigation bar; About this plugin is in Press settings (android `fullPage`).
    var fullPage: Bool { true }

    func content() -> AnyView { AnyView(PressScreen(lab: self)) }

    var about: String? {
        String(localized: "Each project is its own document. The white page is what the PDF prints: A4, made offline on this \(Platform.deviceNoun). Tap a block to move it, edit it or remove it. Answers come from a chat, and every document ends with how it was made: the date, the models and their speed, and one numbered list of the sources.")
    }

    /// 📎 in the answer's More menu: into the open project at the end, with its question, sources, chat title and the card
    /// shown under it; again takes it out.
    func answerActions(_ a: AnswerRef) -> [LabAnswerAction] {
        let store = PressStore.shared
        store.load()
        // An unreadable projects file offers nothing: no "Add to Press: " with a blank name (pr-review #66; Android
        // still shows the row).
        guard let lib = store.library, !store.unreadable else { return [] }
        let added = lib.has(a.id)
        let project = lib.current.name
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

    /// Every answer of a chat, into the open project at the end (android `PressStore.addChat`, Press's "Answers from a
    /// chat"): each with the question before it, its sources and its card from the chat's meta; no model or speed, as
    /// Android. Read off the main actor.
    func addChat(_ services: BoarServices, _ sessionId: String, _ title: String) async {
        let records = (try? await services.background { try $0.chats.messages(sessionId: sessionId) }) ?? []
        var question = ""
        var answers: [PressDoc.Answer] = []
        for m in records {
            if m.role == "user" { question = m.text; continue }
            if m.role != "assistant" || m.text.allSatisfy(\.isWhitespace) { continue }
            let sources = MessageMeta.sources(m.meta).map { PressDoc.Source($0.title, $0.source.flatMap { $0.isEmpty ? nil : $0 }) }
            answers.append(PressDoc.Answer(m.id, title, question, m.text, sources, Self.now, card: AnswerCard.fromMeta(m.meta)))
        }
        for a in answers { addAnswer(a) }
    }

    /// A photo picked on the device, copied into `projectId`'s folder off the main actor; nil when it can't be read (the
    /// reason goes to the log, never the photo).
    func copyPhoto(_ data: Data, projectId: String) async -> PressDoc.Picture? {
        let dir = dir, id = Self.newId("pic"), name = Self.newId("photo") + ".jpg"
        do {
            return try await Task.detached(priority: .userInitiated) {
                try PressFiles.copyPhoto(data, pressDir: dir, projectId: projectId, blockId: id, name: name)
            }.value
        } catch {
            log.warning("press: photo copy failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// A photo block was removed: its copy goes when the Undo is over, if no block uses it again (validator G-1). The
    /// cleanup at load stays as the safety net.
    func dropPhotoLater(_ projectId: String, _ name: String, after: Duration) {
        let dir = dir
        Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: after)) != nil, let self, self.loaded, let lib = self.library, PressFiles.unused(lib, projectId, name) else { return }
            try? FileManager.default.removeItem(at: PressFiles.photoFile(dir, projectId, name))
        }
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

    /// "Show page breaks" (Press settings): on unless switched off (android LabPrefs `printer.pageBreaks`).
    static var showBreaks: Bool {
        get { d.string(forKey: "labs.printer.pageBreaks") != "off" }
        set { d.set(newValue ? "on" : "off", forKey: "labs.printer.pageBreaks") }
    }

    static var labels: PressReceipt.Labels {
        var l = PressReceipt.Labels()
        l.madeWith = String(localized: "Made offline with BOAR · {{date}}")
        l.ownFile = String(localized: "Your own file")
        return l
    }

    static var today: String { Date().formatted(date: .long, time: .omitted) }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// A project as it prints: a user's own file names scrubbed first (validator Q-B3), the words and switches set. The
    /// paper on screen (`scrub: false`) keeps the blocks as they are, so what is typed there is the project's own text;
    /// its Sources section hides own file names all the same.
    static func page(_ project: PressDoc.Project, options: PressReceipt.Options, scrub: Bool = true) -> PressPage {
        let l = labels
        return PressPage(project: scrub ? PressReceipt.scrubOwnFiles(project, ownFile: l.ownFile) : project, date: today, version: version, labels: l,
                         sourcesLabel: String(localized: "Sources"), options: options,
                         cardByModel: String(localized: "made by the model · checked against the answer"))
    }
}
