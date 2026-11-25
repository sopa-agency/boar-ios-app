import BoarAnswer
import BoarCore
import PhotosUI
import SwiftUI

/// Press's page (android printer `PressScreen.kt`, adam's mock-up, Nov 13): the paper, what you see is what prints, then
/// one row of tools and the note bar. Nothing selected, the row adds (heading, paragraph, list, divider, photo, a chat's
/// answers); a tapped block gets the row of its tools (up, down, edit or caption, place, remove with Undo, close). The
/// bar writes a note, or with a text selected tells BOAR how to rewrite it; its ⋯ menu saves the PDF or the Markdown and
/// holds the projects (the open one and the most recent, All projects, New, Rename, Delete). The gear opens Press
/// settings. Apple's pieces: PhotosPicker, the share sheet (Save to Files), a menu, sheets, an alert.
struct PressScreen: View {
    let lab: PressLab
    @State private var store = PressStore.shared
    @State private var edit = PressEdit()
    @State private var options = PressPrefs.options
    @State private var showBreaks = PressPrefs.showBreaks
    @State private var starts: [PressPDF.PageStart] = []
    @State private var note = ""
    @State private var sheet: Sheet?
    @State private var photo: PhotosPickerItem?
    @State private var removed: Removed?
    @State private var confirmDelete = false
    /// What was typed in the bar for the selected text: the edit sheet starts BOAR's rewrite with it, once (t9 0136).
    @State private var askOwn: String?
    @State private var naming = false
    @State private var newName = ""
    @State private var toast: String?
    @State private var focusTitle = 0
    // A moved block stays in view (t9 0143): every move bumps `follow`; the scroll is measured after layout.
    @State private var follow = 0
    @State private var scroll = ScrollPosition()
    @State private var viewport = Viewport()
    @State private var frames = PaperFrames()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model

    private enum Sheet: String, Identifiable {
        case settings, chats, edit, projects
        var id: String { rawValue }
    }

    /// A block removed a moment ago, for Undo: where it was and in which project.
    private struct Removed: Equatable {
        let block: PressDoc.Block
        let index: Int
        let projectId: String
    }

    /// The scroll view's visible part, in content points.
    struct Viewport: Equatable {
        var offset: CGFloat = 0
        var top: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The paper's padding inside the scroll view.
    private static let pad: CGFloat = 14

    var body: some View {
        Group {
            if let lib = store.library {
                page(lib.current)
            } else if store.unreadable {
                Text("Press can't read its projects file. It is kept as it is, and nothing is written over it.")
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.warning))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Color.clear
            }
        }
        .onAppear { store.load() }
        #if DEBUG
        // -uiPressSheet: the edit sheet on the demo's second paragraph, or the full project list, for screenshots.
        .task {
            guard let which = DebugLaunch.pressSheet, (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            if which == "projects" { sheet = .projects; return }
            edit.select("demo-t2")
            sheet = .edit
        }
        #endif
        .toolbar {
            // The header's gear opens Press settings (android PluginSettings, adam Nov 14).
            ToolbarItem(placement: .primaryAction) {
                Button("Press settings", systemImage: "gearshape") { sheet = .settings }
            }
        }
        .navigationSubtitleIfAvailable(Text(verbatim: store.library?.current.name ?? ""))
        // Closed any way (swipe down, the close button): the bar's instruction goes with it, so the pencil never reopens the
        // sheet on a leftover and rewrites at once (adam on the F3, Nov 14; t9 0136).
        .sheet(item: $sheet, onDismiss: { askOwn = nil }) { which in
            switch which {
            case .settings:
                PressSettingsSheet(lab: lab, showBreaks: $showBreaks, options: $options)
            case .chats:
                PressChatsSheet { id, title in
                    sheet = nil
                    guard let services = model.services else { return }
                    Task { await store.addChat(services, id, title) }
                }
            case .edit:
                editSheet
            case .projects:
                if let lib = store.library {
                    PressAllProjectsSheet(library: lib) { id in
                        store.change { $0.switchTo(id) }
                        sheet = nil
                    }
                }
            }
        }
        .onChange(of: showBreaks) { _, on in PressPrefs.showBreaks = on }
        .onChange(of: options) { _, o in PressPrefs.options = o }
    }

    @ViewBuilder private func page(_ project: PressDoc.Project) -> some View {
        let paper = PressPrefs.page(project, options: options, scrub: false)
        VStack(spacing: 0) {
            ScrollView {
                PressPaperView(page: paper, dir: store.dir, starts: showBreaks ? starts : [], edit: $edit, focusTitle: focusTitle,
                               frames: frames)
                    .padding(Self.pad)
                    .readableWidth(760)
            }
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: Viewport.self) { g in
                Viewport(offset: g.contentOffset.y, top: g.contentOffset.y + g.contentInsets.top,
                         height: g.containerSize.height - g.contentInsets.top - g.contentInsets.bottom)
            } action: { _, v in viewport = v }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.baseBackground)
            bottom(project)
        }
        // The PDF's own page breaks (PressPDF.pageStarts, a layout without drawing), redone a moment after the document
        // changes: the lines on the paper are where the PDF really breaks, not an estimate (adam, Nov 12).
        .task(id: PageKey(page: paper, on: showBreaks)) {
            guard showBreaks else { starts = []; return }
            // A change meanwhile cancels this wait: a cancelled sleep must not fall through (pr-review #66).
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            let fileOf = PressStore.fileOf(store.dir, project.id)
            starts = await Task.detached(priority: .utility) { PressPDF.pageStarts(paper, fileOf: fileOf) }.value
        }
        .task(id: follow) { await keepInView() }
        // Another project opened: the one left is marked seen (the menu's recent projects are ordered by it).
        .onChange(of: project.id) { old, _ in
            store.change { $0.markSeen(PressStore.now, projectId: old) }
            edit = PressEdit()
        }
        // Leaving the page (or another project) marks it seen.
        .onDisappear { store.change { $0.markSeen(PressStore.now, projectId: project.id) } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await addPhoto(item, projectId: project.id) }
        }
        .confirmationDialog(Text("Delete “\(project.name)”?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete “\(project.name)” and all it holds", role: .destructive) {
                let name = project.name
                store.deleteProject(project.id)
                edit = PressEdit()
                toast = String(localized: "“\(name)” deleted")
            }
        }
        .alert("New project", isPresented: $naming) {
            TextField("Name, for example Trip to Lisbon", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createProject() }
        }
        .onChange(of: newName) { _, n in if n.count > 60 { newName = String(n.prefix(60)) } }
        .overlay(alignment: .top) { ToastView(message: $toast).padding(.top, 8) }
        .animation(.default, value: toast)
    }

    /// The paper's change that moves the page breaks: the document and the switch.
    private struct PageKey: Equatable {
        let project: PressDoc.Project
        let options: PressReceipt.Options
        let on: Bool
        init(page: PressPage, on: Bool) { project = page.project; options = page.options; self.on = on }
    }

    // MARK: the bars

    @ViewBuilder private func bottom(_ project: PressDoc.Project) -> some View {
        VStack(spacing: 0) {
            if let removed {
                PressUndoBar { undo(removed) }
                    .task(id: removed.block.id) {
                        guard (try? await Task.sleep(for: .milliseconds(ChatList.undoMs))) != nil else { return }
                        withAnimation { self.removed = nil }
                    }
            }
            Divider()
            if let i = project.blocks.firstIndex(where: { $0.id == edit.selected }) {
                actionBar(project.blocks[i], i, project)
            } else {
                addBar(project)
            }
            noteBar(project)
        }
        .background(.bar)
        .animation(.default, value: removed)
    }

    /// One short row that fits without scrolling (adam, Nov 12): up, down, the pencil (a text: edit on the page) or, on a
    /// picture, its caption and where it sits (one button, each tap the next place), remove, close.
    private func actionBar(_ b: PressDoc.Block, _ i: Int, _ project: PressDoc.Project) -> some View {
        let open = edit.editing == b.id
        return HStack(spacing: 0) {
            PressTool("Move up", "arrow.up", enabled: i > 0) { move(b.id, -1) }
            PressTool("Move down", "arrow.down", enabled: i < project.blocks.count - 1) { move(b.id, 1) }
            if PressEdit.textOf(b) != nil {
                // The pencil opens the edit sheet (edit it yourself, or ask BOAR); a block being typed in closes with it.
                PressTool(open ? "Done editing" : "Edit text", open ? "checkmark" : "pencil", on: open) {
                    if open { edit.editing = nil } else { sheet = .edit }
                }
            }
            if let p = b.picture {
                PressTool(open ? "Done with the caption" : "Caption", open ? "checkmark" : "text.below.photo", on: open) { edit.toggleEditing() }
                let place: (LocalizedStringResource, String) = switch p.place {
                case .left: ("Place left, text beside", "rectangle.lefthalf.inset.filled")
                case .right: ("Place right, text beside", "rectangle.righthalf.inset.filled")
                case .center: ("Place in the center, full width", "rectangle.center.inset.filled")
                }
                PressTool(place.0, place.1, on: true, hint: "Tap for the next place") {
                    store.change { $0.place(p.id, p.place.next) }
                }
            }
            PressTool("Remove", "trash", danger: true) { remove(b, i, project.id) }
            PressTool("Close", "xmark") { edit.close() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// What can be added, one row of icons with spoken names, from the left, never scrolling (android AddBar): heading,
    /// paragraph, list, divider, photo (adam's order, Nov 13), then a chat's answers.
    private func addBar(_ project: PressDoc.Project) -> some View {
        HStack(spacing: 0) {
            ForEach(PressEdit.AddTool.allCases, id: \.self) { tool in
                switch tool {
                case .heading:
                    PressTool("Heading", "textformat.size") {
                        add(.heading(id: PressStore.newId("h"), text: String(localized: "New heading")), project)
                    }
                case .paragraph:
                    PressTool("Paragraph", "text.alignleft") { add(.paragraph(id: PressStore.newId("t"), text: ""), project) }
                case .list:
                    PressTool("List", "list.bullet") { add(.bullets(id: PressStore.newId("l"), text: ""), project) }
                case .divider:
                    PressTool("Divider", "minus") { add(.divider(id: PressStore.newId("d")), project, opens: false) }
                case .photo:
                    PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                        PressToolLabel(systemImage: "photo")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Photo from this \(Platform.deviceNoun)"))
                    .help(Text("Photo from this \(Platform.deviceNoun)"))
                case .chat:
                    PressTool("Answers from a chat", "bubble.left.and.text.bubble.right") { sheet = .chats }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// The selected block when it has text: what the bar's words ask BOAR to change.
    private func target(_ project: PressDoc.Project) -> PressDoc.Block? {
        project.blocks.first { $0.id == edit.selected && PressEdit.textOf($0) != nil }
    }

    /// The note bar (android PromptBar on Press): ⋯ opens the menu. With a text selected, what is typed tells BOAR how to
    /// change it (NOW and REWRITTEN in the edit sheet, nothing changes before Use); with nothing selected it becomes a
    /// note, placed after the selection (or the last note) but neither selected nor opened.
    private func noteBar(_ project: PressDoc.Project) -> some View {
        let asking = target(project) != nil
        return HStack(spacing: 8) {
            menu(project)
            TextField(asking ? "Tell BOAR how to change this text…" : "Write a note…", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .font(.boar("ui.body"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.boar(.border).opacity(0.25), in: .rect(cornerRadius: 18))
                .onSubmit { addNote(project) }
            Button { addNote(project) } label: {
                Image(systemName: asking ? "arrow.up.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.boar(.accent))
            }
            .buttonStyle(.plain)
            .disabled(note.allSatisfy(\.isWhitespace))
            .accessibilityLabel(asking ? Text("Ask BOAR") : Text("Add the note"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// Press's menu, grouped (android ProjectsSheet, adam Nov 12): Save as .pdf or .md (the share sheet, Save to Files
    /// included), then the projects: the open one and the most recent (`PressDoc.shortListSize`), All projects (N) with a
    /// search when there are more, New project, rename on the page, delete.
    private func menu(_ project: PressDoc.Project) -> some View {
        Menu {
            Section("Save as…") {
                ShareLink(item: pdfFile(project), preview: SharePreview(Text(verbatim: PressReceipt.slug(project.name) + ".pdf"))) {
                    Label { Text(verbatim: ".pdf") } icon: { Image(systemName: "doc.richtext") }
                }
                .disabled(project.blocks.isEmpty)
                ShareLink(item: markdownFile(project), preview: SharePreview(Text(verbatim: PressReceipt.slug(project.name) + ".md"))) {
                    Label { Text(verbatim: ".md") } icon: { Image(systemName: "doc.plaintext") }
                }
            }
            Section("Projects") {
                if let lib = store.library {
                    ForEach(lib.shortList(), id: \.id) { p in
                        Button { store.change { $0.switchTo(p.id) } } label: {
                            Label {
                                Text(verbatim: p.name)
                                Text("\(p.blocks.count) blocks")
                            } icon: {
                                Image(systemName: p.id == project.id ? "checkmark" : "folder")
                            }
                        }
                    }
                    if lib.projects.count > PressDoc.shortListSize {
                        Button("All projects (\(lib.projects.count))", systemImage: "folder") { sheet = .projects }
                    }
                }
                Button("New project", systemImage: "plus") {
                    newName = ""
                    naming = true
                }
                Button("Rename “\(project.name)”", systemImage: "pencil") {
                    edit.close()
                    withAnimation { scroll.scrollTo(edge: .top) }
                    focusTitle += 1
                }
                Button("Delete “\(project.name)”", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 24))
                .foregroundStyle(.boar(.secondary))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Press menu"))
    }

    // MARK: actions

    /// A new block goes after the selected one (or after the last note the bar added), or at the end; it is selected and
    /// open for typing with its text selected (a divider has nothing to type).
    private func add(_ b: PressDoc.Block, _ project: PressDoc.Project, opens: Bool = true) {
        let at = edit.insertIndex(project.blocks)
        store.change { $0.insert(b, at: at) }
        edit.added(b.id, opens: opens)
        follow += 1
    }

    private func addNote(_ project: PressDoc.Project) {
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        // A text selected: the words go to BOAR in the edit sheet, used once (set here only).
        if target(project) != nil {
            askOwn = typed
            edit.editing = nil
            note = ""
            sheet = .edit
            return
        }
        let id = PressStore.newId("n")
        store.change { $0.insert(.note(id: id, text: typed), at: edit.insertIndex(project.blocks)) }
        edit.addedNote(id)
        note = ""
        follow += 1
    }

    /// A new empty project, opened (android `onNew`): a blank name is "Field notes".
    private func createProject() {
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? String(localized: "Field notes") : typed
        store.change { $0.newProject(PressStore.newId("p"), name, PressStore.now) }
        newName = ""
    }

    /// The pencil's sheet on the selected text; with none left (removed meanwhile) it closes.
    @ViewBuilder private var editSheet: some View {
        if let project = store.library?.current, let target = target(project) {
            PressEditSheet(block: target, document: Self.document(project, without: target.id), typed: askOwn,
                           onTypedUsed: { askOwn = nil },
                           onSelf: {
                               askOwn = nil
                               sheet = nil
                               edit.editing = target.id
                           },
                           onUse: { text in
                               store.change { $0.editText(target.id, .text, text) }
                               toast = String(localized: "Text updated.")
                               sheet = nil
                           })
        } else {
            Color.clear.onAppear { sheet = nil }
        }
    }

    /// The rest of the document, for an instruction in the user's own words (android `PressRewrite.documentContext` with
    /// each other block's text, an answer as its heading and plain text).
    static func document(_ project: PressDoc.Project, without id: String) -> String {
        PressRewrite.documentContext(project.name, project.blocks.filter { $0.id != id }.compactMap { b in
            if case .answer(let a) = b { return a.shownHeading + "\n" + PressReceipt.plain(a.text) }
            return PressEdit.textOf(b)
        })
    }

    private func addPhoto(_ item: PhotosPickerItem, projectId: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let pic = await store.copyPhoto(data, projectId: projectId) else {
            toast = String(localized: "That photo could not be read.")
            return
        }
        // The user may have left for another project meanwhile: the copy waits for the load's cleanup.
        guard let project = store.library?.current, project.id == projectId else { return }
        add(.picture(pic), project)
    }

    private func move(_ id: String, _ by: Int) {
        store.change { $0.move(id, by: by) }
        edit.editing = nil
        follow += 1
    }

    private func remove(_ b: PressDoc.Block, _ i: Int, _ projectId: String) {
        store.change { $0.remove(b.id) }
        edit.close()
        removed = Removed(block: b, index: i, projectId: projectId)
        // A photo's copy goes once the Undo is over (G-1), with room for a toast still waiting its turn.
        if let p = b.picture, p.kind == .photo {
            store.dropPhotoLater(projectId, PressFilesName.of(p.file), after: .milliseconds(ChatList.undoMs + 10_000))
        }
    }

    private func undo(_ r: Removed) {
        store.change { $0.insert(r.block, at: r.index, projectId: r.projectId) }
        removed = nil
    }

    /// Scrolls a moved or added block into view when it isn't fully visible (PressLayout.scrollToShow), after layout.
    private func keepInView() async {
        guard follow > 0, let id = edit.selected ?? edit.barNote else { return }
        // Two frames: the block is laid out in its new place before it is measured.
        guard (try? await Task.sleep(for: .milliseconds(50))) != nil, let f = frames.rects[id] else { return }
        let top = Self.pad + f.minY - viewport.top
        guard let delta = PressLayout.scrollToShow(viewHeight: viewport.height, blockTop: top, blockHeight: f.height, room: 16) else { return }
        let y = max(viewport.offset + delta, 0)
        if reduceMotion { scroll.scrollTo(y: y) } else { withAnimation { scroll.scrollTo(y: y) } }
    }

    // MARK: files

    /// The A4 PDF, laid out and compiled when the share sheet asks for it.
    private func pdfFile(_ project: PressDoc.Project) -> ExportedFile {
        let options = options
        let fileOf = PressStore.fileOf(store.dir, project.id)
        return ExportedFile(filename: PressReceipt.slug(project.name) + ".pdf") {
            let page = await MainActor.run { PressPrefs.page(project, options: options) }
            return PressPDF.compile(page, fileOf: fileOf)
        }
    }

    /// The Markdown, built when the share sheet asks for it, not on every redraw of the page (pr-review #66).
    private func markdownFile(_ project: PressDoc.Project) -> ExportedFile {
        let options = options
        let drawing = String(localized: "Drawing"), photo = String(localized: "Photo")
        return ExportedFile(filename: PressReceipt.slug(project.name) + ".md") {
            let page = await MainActor.run { PressPrefs.page(project, options: options) }
            return Data(page.markdown(drawingLabel: drawing, photoLabel: photo).utf8)
        }
    }
}

/// A picture's file name, as `PressFiles.fileName` (Java `File(path).name`).
enum PressFilesName {
    static func of(_ path: String) -> String { (path as NSString).lastPathComponent }
}

/// Press's tools: round icon buttons with spoken names (android PluginTool), 44 points, the name on a long press (Mac:
/// on hover).
struct PressTool: View {
    let label: LocalizedStringResource
    let systemImage: String
    var enabled = true
    var on = false
    var danger = false
    var hint: LocalizedStringResource?
    let action: () -> Void

    init(_ label: LocalizedStringResource, _ systemImage: String, enabled: Bool = true, on: Bool = false, danger: Bool = false,
         hint: LocalizedStringResource? = nil, action: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.enabled = enabled; self.on = on; self.danger = danger
        self.hint = hint; self.action = action
    }

    var body: some View {
        Button(action: action) {
            PressToolLabel(systemImage: systemImage, on: on, danger: danger)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
        .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
        .help(Text(label))
        .frame(maxWidth: 56)
    }
}

struct PressToolLabel: View {
    let systemImage: String
    var on = false
    var danger = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(danger ? .boar(.danger) : on ? .boar(.accent) : .boar(.primary))
            .frame(width: 44, height: 44)
            .background(on ? AnyShapeStyle(.boar(.accent).opacity(0.14)) : AnyShapeStyle(.clear), in: .circle)
            .contentShape(.circle)
    }
}

/// "Removed from the page · Undo", above the tools for `ChatList.undoMs`.
private struct PressUndoBar: View {
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text("Removed from the page")
            Spacer()
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}

/// Press settings (android SettingsSheet, adam Nov 14): the paper's page breaks, and what the document prints besides
/// its blocks: the date under the title, the Sources section at the end, the models and their speed. "Made offline with
/// BOAR" always prints. They apply to every project, the paper, the PDF and the Markdown. About this plugin lives here.
private struct PressSettingsSheet: View {
    let lab: PressLab
    @Binding var showBreaks: Bool
    @Binding var options: PressReceipt.Options
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BoarForm {
                Section {
                    Toggle("Show page breaks", isOn: $showBreaks)
                } footer: {
                    BoarFooter { Text("Dashed lines on the page where the PDF's pages end.") }
                }
                Section {
                    Toggle("Date under the title", isOn: $options.date)
                    Toggle("Sources at the end", isOn: $options.sources)
                } footer: {
                    BoarFooter { Text("Each source by its number, with the pack it came from. Off, the answers print without [n].") }
                }
                Section {
                    Toggle("Models", isOn: Binding(get: { options.models }, set: { on in
                        options.models = on
                        options.speed = on && options.speed
                    }))
                    if options.models { Toggle("Model speed", isOn: $options.speed) }
                } footer: {
                    BoarFooter { Text("\"Made offline with BOAR\" always prints at the end.") }
                }
                if let about = lab.about { AboutPluginFold(about: about) }
            }
            .navigationTitle(Text("Press settings"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .macSheetSize()
    }
}

/// The latest chats (android ChatsSheet): a tap adds that chat's answers at the end, as Add to Press under each answer.
private struct PressChatsSheet: View {
    let onChat: (String, String) -> Void
    @State private var chats: [ChatSession]?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BoarForm {
                Section {
                    ForEach(chats ?? []) { c in
                        let title = c.title.allSatisfy(\.isWhitespace) ? "…" : c.title
                        Button { onChat(c.id, title) } label: {
                            Label(title, systemImage: "plus")
                                .lineLimit(2)
                        }
                    }
                } footer: {
                    BoarFooter { Text("Answers come from a chat: under an answer, open More (…) and tap Add to Press.") }
                }
            }
            .navigationTitle(Text("Answers from a chat"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
            }
        }
        .macSheetSize()
        .task {
            guard let services = model.services else { chats = []; return }
            chats = ((try? await services.background { try $0.chats.listSessions() }) ?? []).prefix(12).map { $0 }
        }
    }
}
