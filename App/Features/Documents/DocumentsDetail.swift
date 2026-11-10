#if os(macOS)
import BoarModels
import BoarRAG
import SwiftUI

/// What the Documents list has selected on the Mac: one of your collections or a part of the library.
enum DocumentsSelection: Hashable {
    case collection(String)
    case pack(String)
}

/// A collection beside the list (Mac): its facts, the switch for answers, the documents in it with a preview, export
/// and delete.
struct CollectionDetail: View {
    let collection: KnowledgeBase.Collection
    @Bindable var documents: DocumentsController
    let onDelete: () -> Void

    /// One imported document: its title and passages, read once when the collection opens.
    private struct Doc: Identifiable {
        let title: String
        let passages: Int
        let preview: String
        var id: String { title }
    }

    @State private var docs: [Doc]?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(icon: Symbols.collection)
                        .font(.title)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.quaternary, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: collection.name)
                            .font(.title2.bold())
                        Text("Added \(Date(timeIntervalSince1970: Double(collection.createdAt) / 1000), format: .dateTime.day().month().year())")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Use in Answers", isOn: $documents[activeFor: collection.id])
                LabeledContent("Documents", value: collection.docCount.formatted())
                LabeledContent("Passages", value: collection.chunkCount.formatted())
                LabeledContent("Size", value: collection.sizeBytes.formatted(.byteCount(style: .file)))
                if let file = collection.sourceFilename, !file.isEmpty {
                    LabeledContent("Imported From", value: file)
                }
            } footer: {
                Text("BOAR searches these passages when you ask. They stay on this \(Platform.deviceNoun).")
            }

            Section("Contents") {
                if let docs {
                    if docs.isEmpty {
                        Text("No readable text in this collection.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(docs) { doc in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(doc.title, systemImage: "doc.text")
                                    .font(.headline)
                                Spacer()
                                Text("^[\(doc.passages) passage](inflect: true)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(doc.preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                HStack {
                    ShareLink(item: documents.exportFile(collection), preview: SharePreview(collection.name)) {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("Delete Collection…", icon: Symbols.delete, role: .destructive, action: onDelete)
                }
            }
        }
        .task(id: collection.id) { await load() }
    }

    private func load() async {
        let id = collection.id
        let chunks = (try? await documents.services.background { try $0.knowledgeBase.collectionDocs(id) }) ?? []
        var order: [String] = []
        var grouped: [String: (count: Int, first: String)] = [:]
        for chunk in chunks {
            if let entry = grouped[chunk.title] {
                grouped[chunk.title] = (entry.count + 1, entry.first)
            } else {
                order.append(chunk.title)
                grouped[chunk.title] = (1, chunk.body)
            }
        }
        docs = order.map { Doc(title: $0, passages: grouped[$0]?.count ?? 0, preview: grouped[$0]?.first ?? "") }
    }
}

/// A part of the library beside the list (Mac): what it adds, its size and state, and download or delete.
struct PackDetail: View {
    let pack: CatalogAsset
    let controller: ModelsController
    @State private var confirmRemove = false

    private var row: ModelsController.Row { controller.rows[pack.id] ?? .init() }
    private var present: Bool { controller.isPresent(pack) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(icon: Symbols.pack)
                        .font(.title)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.quaternary, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: pack.friendlyName)
                            .font(.title2.bold())
                        Text(verbatim: pack.plainPurpose)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Status") {
                    if row.downloading {
                        CatalogDownloadProgress(asset: pack, row: row, showSpeed: controller.services.settings.showLiveStats)
                    } else if row.indexing {
                        Text("Preparing for search…")
                    } else if present {
                        Label("Installed", icon: Symbols.active).foregroundStyle(.tint)
                    } else {
                        Text("Not downloaded")
                    }
                }
                LabeledContent("Size", value: pack.sizeBytes.formatted(.byteCount(style: .file)))
                LabeledContent("License", value: pack.license)
            } footer: {
                Text(verbatim: pack.description)
            }

            Section {
                if row.downloading {
                    Button("Cancel Download", role: .cancel) { controller.cancelDownload(pack) }
                } else if !present {
                    Button("Download (\(FeatureFormat.megabytes(pack.sizeBytes)))", icon: Symbols.download) {
                        controller.download(pack)
                    }
                } else if !pack.required && !row.indexing {
                    Button("Delete…", icon: Symbols.delete, role: .destructive) { confirmRemove = true }
                } else if pack.required {
                    Text("BOAR needs this part of the library.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Delete \(pack.friendlyName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { controller.remove(pack) }
        } message: {
            Text("This frees \(FeatureFormat.megabytes(pack.sizeBytes)) on your \(Platform.deviceNoun). Its topics can't be searched until you download it again.")
        }
    }
}
#endif
