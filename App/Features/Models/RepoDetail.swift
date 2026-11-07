#if os(macOS)
import BoarModels
import SwiftUI

/// A Hugging Face model beside the results (Mac): who made it, how popular and how big it is, its page, and the GGUF
/// files BOAR can run, each with its fit on this Mac and an Add button.
struct RepoDetail: View {
    let repo: HfBrowser.Repo?
    let controller: ModelsController

    var body: some View {
        if let repo {
            BoarForm {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: RepoDetail.name(repo.id))
                            .font(.boar("ui.titleLg"))
                            .foregroundStyle(.boar(.heading))
                        Text(verbatim: repo.id.split(separator: "/").first.map(String.init) ?? "")
                            .foregroundStyle(.boar(.secondary))
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if let downloads = repo.downloads {
                        LabeledContent("Downloads", value: downloads.formatted(.number.notation(.compactName)))
                    }
                    if let likes = repo.likes {
                        LabeledContent("Likes", value: likes.formatted(.number.notation(.compactName)))
                    }
                    if let params = repo.params, params > 0 {
                        LabeledContent("Parameters", value: params.formatted(.number.notation(.compactName)))
                    }
                    if let arch = repo.architecture, !arch.isEmpty {
                        LabeledContent("Architecture", value: arch)
                    }
                    if let context = repo.contextLength, context > 0 {
                        LabeledContent("Context", value: String(localized: "\(context.formatted()) tokens"))
                    }
                    if let url = URL(string: "https://huggingface.co/\(repo.id)") {
                        Link(destination: url) {
                            Label("Model Page", systemImage: "safari")
                        }
                        .tint(BoarStyle(role: .link))
                    }
                } footer: {
                    BoarFooter {
                        Text("Not checked by BOAR. Look at the model's page for its license before you use it.")
                    }
                }

                Section {
                    if controller.hfBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if controller.hfFiles.isEmpty {
                        Text("No files BOAR can use in this model.")
                            .foregroundStyle(.boar(.muted))
                    }
                    GgufFileList(repo: repo.id, controller: controller)
                        .id(repo.id)
                } header: {
                    Text("Versions")
                } footer: {
                    BoarFooter {
                        Text("The same model at different sizes: smaller versions are faster and lighter, larger ones answer a little better. Downloads also appear in Models.")
                    }
                }
            }
        } else {
            ContentUnavailableView("Select a Model", systemImage: "square.stack.3d.up",
                                   description: Text("Its files, sizes and fit on this \(Platform.deviceNoun) appear here."))
        }
    }

    /// "Llama-3.2-3B-Instruct" for "bartowski/Llama-3.2-3B-Instruct-GGUF".
    static func name(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.replacing(/[-_.]gguf$/.ignoresCase(), with: "")
    }
}
#endif
