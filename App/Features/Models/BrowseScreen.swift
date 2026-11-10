import BoarModels
import SwiftUI

/// Hugging Face models on a page of their own (android BrowseScreen.kt): a search with size and sort filters, results
/// that page in as the list ends, and a repo's GGUF files to add. Only text-generation GGUF repos BOAR can run are
/// listed. The network is used only while this page is open.
struct BrowseScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var controller: ModelsController

    private var noResults: Bool {
        !controller.hfSearching && controller.hfError == nil && controller.hfSearched && controller.hfResults.isEmpty && controller.hfNext == nil
    }

    var body: some View {
        Group {
            #if os(macOS)
            // Results on the left, the selected model's files on the right.
            MasterDetail {
                List(selection: openRepo) { listContent }
                    .overlay { if noResults { ContentUnavailableView.search } }
            } detail: {
                RepoDetail(repo: controller.hfResults.first { $0.id == controller.hfOpenRepo }, controller: controller)
            }
            #else
            List { listContent.boarListRows() }
                .groupedListStyle()
                .boarList()
                .overlay { if noResults { ContentUnavailableView.search } }
            #endif
        }
        .navigationTitle("Find More Models")
        .inlineNavigationTitle()
        .searchable(text: $controller.hfQuery, placement: .alwaysVisible, prompt: Text("Search models"))
        .onSubmit(of: .search, browse)
        // Opening the page lists what's trending in the default bucket, without typing anything.
        .task { if !controller.hfSearched { controller.hfBrowse() } }
    }

    @ViewBuilder private var listContent: some View {
        if !model.connectivity.online {
            Section {
                Label("You're offline. Connect to the internet to search for models.", icon: Symbols.offline)
                    .foregroundStyle(.boar(.warning))
            }
        }

        if let added = controller.hfAdded {
            Section {
                Label("Added \(added) to Models.", icon: Symbols.active)
                    .foregroundStyle(.boar(.success))
            }
        }

        if let error = controller.hfError {
            Section {
                Label(error, icon: Symbols.error)
                    .foregroundStyle(.boar(.danger))
            }
        }

        Section {
            Picker("Size", selection: $controller.hfSizeChoice) {
                ForEach(HfQuery.Size.allCases, id: \.self) { size in
                    Text(Self.label(size)).tag(size)
                }
            }
            Picker("Sort", selection: $controller.hfSortChoice) {
                Text("Trending").tag(HfQuery.Sort.trending)
                Text("Most Downloaded").tag(HfQuery.Sort.downloads)
                Text("Most Liked").tag(HfQuery.Sort.likes)
                Text("Newest").tag(HfQuery.Sort.newest)
            }
        } footer: {
            BoarFooter {
                Text("Bigger models can answer better but need more memory.")
            }
        }

        Section {
            ForEach(controller.hfResults) { repo in
                RepoRow(repo: repo, controller: controller)
                    .onAppear {
                        if repo.id == controller.hfResults.last?.id { controller.hfMore() }
                    }
            }
            if controller.hfSearching {
                ProgressView(controller.hfResults.isEmpty ? "Searching…" : "Loading more…")
                    .frame(maxWidth: .infinity)
            } else if controller.hfNext != nil {
                Button("Load More", action: controller.hfMore)
            }
        } header: {
            if !controller.hfResults.isEmpty { Text("Hugging Face") }
        } footer: {
            if !controller.hfResults.isEmpty {
                BoarFooter {
                    Text("Not checked by BOAR. Look at the model's page for its license before you use it.")
                }
            }
        }
    }

    #if os(macOS)
    /// The list selection is the open repo: selecting one loads its files beside the list.
    private var openRepo: Binding<String?> {
        Binding(get: { controller.hfOpenRepo }, set: { id in
            if let id, id != controller.hfOpenRepo { controller.hfOpen(id) }
        })
    }
    #endif

    private func browse() {
        controller.hfBrowse()
    }

    private static func label(_ s: HfQuery.Size) -> LocalizedStringKey {
        switch s {
        case .any: "Any"
        case .under1B: "Tiny"
        case .b1_3: "Small"
        case .b3_6: "Medium"
        case .b6_9: "Large"
        case .b9_20: "Very Large"
        }
    }
}
