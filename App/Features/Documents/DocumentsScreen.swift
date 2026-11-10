import BoarRAG
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Knowledge (android DocumentsScreen.kt, Oct 24): BOAR Knowledge, the library everyone has (Essentials, Extended,
/// Wikipedia), first; then Personal Files, the user's own collections, added from Files or from photos of pages with the
/// toolbar's Add menu, which the Personal Files style answers from.
struct DocumentsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let documents: DocumentsController
    let models: ModelsController

    /// What was picked, waiting for its collection name.
    private enum Pending {
        case files([URL])
        case photos([Data])
    }

    @State private var pickingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pending: Pending?
    @State private var naming = false
    @State private var name = ""
    @State private var removing: KnowledgeBase.Collection?
    #if os(macOS)
    @State private var selection: DocumentsSelection?
    #endif

    private static let importTypes: [UTType] = [.plainText, .text, .commaSeparatedText, .json, .pdf] + [UTType(filenameExtension: "md")].compactMap { $0 }

    var body: some View {
        Group {
            #if os(macOS)
            // The list on the left, the selected collection or library part on the right.
            MasterDetail {
                List(selection: $selection) { listContent }
            } detail: {
                macDetail
            }
            .onAppear(perform: selectFirst)
            .onChange(of: documents.collections.map(\.id)) { old, new in
                // A collection just imported opens beside the list; a deleted one hands over to the first.
                if let added = new.first(where: { !old.contains($0) }) {
                    selection = .collection(added)
                } else {
                    selectFirst()
                }
            }
            // Files dragged from the Finder, and File → Import Documents….
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard let first = files.first, !documents.busy else { return false }
                pending = .files(files)
                askName(first.deletingPathExtension().lastPathComponent)
                return true
            }
            .onChange(of: model.importRequest, initial: true) { _, wanted in
                guard wanted else { return }
                model.importRequest = false
                pickFiles()
            }
            #else
            List { listContent }
                .groupedListStyle()
            #endif
        }
        .navigationTitle(AppScreen.documents.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }
        .task { await documents.refresh() }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true, onCompletion: filesPicked)
        .onChange(of: photoItems) { _, items in photosPicked(items) }
        .alert("Name This Collection", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Import", action: startImport)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel, action: cancelNaming)
        } message: {
            Text("Answers can cite it by this name.")
        }
        .confirmationDialog("Delete this collection?", item: $removing, titleVisibility: .visible) { c in
            Button("Delete", role: .destructive) { documents.remove(c.id) }
        } message: { c in
            Text("This deletes \"\(c.name)\" from BOAR. This can't be undone: export it first to keep a copy.")
        }
        .onChange(of: documents.imported) { _, imported in
            if let imported { AccessibilityNotification.Announcement(String(localized: "Imported \(imported)")).post() }
        }
        .modelsToast(models)
    }

    @ViewBuilder private var listContent: some View {
        if let stage = documents.stage {
            Section {
                ImportProgress(stage: stage, onCancel: documents.cancelImport)
            }
        }
        if let error = documents.error {
            Section {
                Label("Import failed: \(error)", icon: Symbols.error)
                    .foregroundStyle(.red)
            }
        }

        if !models.knowledgePacks.isEmpty {
            Section {
                ForEach(models.knowledgePacks) { pack in
                    PackRow(pack: pack, controller: models)
                        #if os(macOS)
                        .tag(DocumentsSelection.pack(pack.id))
                        #endif
                }
            } header: {
                Text("BOAR Knowledge")
            } footer: {
                Text("What BOAR searches offline, besides your Personal Files. Wikipedia text is CC BY-SA 4.0.")
            }
        }

        // After an import: the default styles answer from everything, so point to the style that answers from the files.
        if documents.stage == nil, let imported = documents.imported {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Imported into \"\(imported)\". To ask about these files, switch the answer style to Personal Files: it answers only from your files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Ask About Them", systemImage: "bubble.left.and.text.bubble.right") { model.askAboutFiles() }
                        .buttonStyle(.boarProminent)
                }
                .padding(.vertical, 4)
            }
        }

        Section {
            if documents.collections.isEmpty {
                ContentUnavailableView {
                    Label("No Collections Yet", icon: Symbols.library)
                } description: {
                    Text("Add files or photos of pages. BOAR reads them on this \(Platform.deviceNoun) and never uploads them.")
                } actions: {
                    addMenu
                        .buttonStyle(.bordered)
                }
            }
            ForEach(documents.collections, id: \.id) { c in
                CollectionRow(collection: c, documents: documents)
                    #if os(macOS)
                    .tag(DocumentsSelection.collection(c.id))
                    #endif
                    .swipeActions(edge: .trailing) {
                        Button("Delete", icon: Symbols.delete, role: .destructive) { removing = c }
                    }
                    .swipeActions(edge: .leading) {
                        ShareLink(item: documents.exportFile(c), preview: SharePreview(c.name)) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(palette.accent)
                    }
                    .contextMenu {
                        ShareLink(item: documents.exportFile(c), preview: SharePreview(c.name)) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button("Delete", icon: Symbols.delete, role: .destructive) { removing = c }
                    }
            }
        } header: {
            Text("Personal Files")
        } footer: {
            if !documents.collections.isEmpty {
                Text("Ask about them with the Personal Files style. Turned-off collections are not used in answers.")
            }
        }

        }

    #if os(macOS)
    @ViewBuilder private var macDetail: some View {
        switch selection {
        case .collection(let id):
            if let c = documents.collections.first(where: { $0.id == id }) {
                CollectionDetail(collection: c, documents: documents) { removing = c }
            } else {
                emptyDetail
            }
        case .pack(let id):
            if let pack = models.knowledgePacks.first(where: { $0.id == id }) {
                PackDetail(pack: pack, controller: models)
            } else {
                emptyDetail
            }
        case nil:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView("Nothing Selected", icon: Symbols.library,
                               description: Text("Select a collection or a part of the library to see what's in it."))
    }

    /// A gone selection (deleted) moves to the first collection, else the first part of the library.
    private func selectFirst() {
        switch selection {
        case .collection(let id) where documents.collections.contains(where: { $0.id == id }): return
        case .pack: return
        default: break
        }
        if let c = documents.collections.first {
            selection = .collection(c.id)
        } else if let pack = models.knowledgePacks.first {
            selection = .pack(pack.id)
        }
    }
    #endif

    private var addMenu: some View {
        Menu("Add Documents", systemImage: "plus") {
            Button("Import Files", systemImage: "doc.badge.plus", action: pickFiles)
            PhotosPicker(selection: $photoItems, maxSelectionCount: 50, matching: .images) {
                Label("Photos of Pages", systemImage: "doc.viewfinder")
            }
        }
        .disabled(documents.busy)
    }

    private func pickFiles() {
        pickingFiles = true
    }

    private func filesPicked(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let first = urls.first else { return }
            pending = .files(urls)
            askName(first.deletingPathExtension().lastPathComponent)
        case .failure(let e):
            documents.error = e.localizedDescription
        }
    }

    private func photosPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
            }
            guard !images.isEmpty else { return }
            pending = .photos(images)
            askName(String(localized: "Scanned Pages"))
        }
    }

    private func askName(_ suggestion: String) {
        name = suggestion
        naming = true
    }

    private func startImport() {
        let collection = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collection.isEmpty, let picked = pending else { return }
        pending = nil
        switch picked {
        case .files(let urls): documents.importFiles(urls, name: collection)
        case .photos(let images): documents.importPhotos(images, name: collection)
        }
    }

    private func cancelNaming() {
        pending = nil
    }
}
