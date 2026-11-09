import BoarModels
import SwiftUI

/// A Hugging Face repo in the results: its name, uploader and downloads; expanding it lists its GGUF files to add.
struct RepoRow: View {
    let repo: HfBrowser.Repo
    let controller: ModelsController

    private var open: Binding<Bool> {
        Binding(get: { controller.hfOpenRepo == repo.id }, set: { _ in controller.hfOpen(repo.id) })
    }

    private var owner: String { repo.id.split(separator: "/").first.map(String.init) ?? "" }

    /// "Llama-3.2-3B-Instruct" for "bartowski/Llama-3.2-3B-Instruct-GGUF".
    private var name: String {
        let last = repo.id.split(separator: "/").last.map(String.init) ?? repo.id
        return last.replacing(/[-_.]gguf$/.ignoresCase(), with: "")
    }

    var body: some View {
        #if os(macOS)
        // The files open beside the list (RepoDetail).
        label
            .tag(repo.id)
        #else
        DisclosureGroup(isExpanded: open) {
            if controller.hfOpenRepo == repo.id {
                if controller.hfBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if controller.hfFiles.isEmpty {
                    Text("No files BOAR can use in this model.")
                        .font(.boar("ui.subtext"))
                        .foregroundStyle(.boar(.muted))
                }
                GgufFileList(repo: repo.id, controller: controller)
            }
        } label: {
            label
        }
        #endif
    }

    /// Android's result row: the name in the heading color, the facts under it in subtext.
    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name)
                .font(.boar("ui.body").weight(.semibold))
                .foregroundStyle(.boar(.heading))
            Text("\(owner) · \((repo.downloads ?? 0).formatted(.number.notation(.compactName))) downloads")
                .font(.boar("ui.subtext"))
                .monospacedDigit()
                .foregroundStyle(.boar(.secondary))
        }
    }
}
