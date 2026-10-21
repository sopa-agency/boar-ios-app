import BoarAnswer
import SwiftUI

/// Shares a finished run: judge-ready traces per model, or every row as JSONL or CSV.
struct EvalShareMenu: View {
    let controller: EvaluationController
    let configs: [EvalSummary.Config]

    var body: some View {
        Menu("Share Results", systemImage: "square.and.arrow.up") {
            Section("Traces for the Judge") {
                ForEach(configs) { config in
                    if let file = controller.traceFile(configId: config.configId) {
                        ShareLink(item: file, preview: SharePreview(Text(verbatim: file.filename))) {
                            Label(controller.name(configId: config.configId, label: config.label).full, systemImage: "doc.badge.gearshape")
                        }
                    }
                }
            }
            Section("All Answers") {
                if let jsonl = controller.exportFile(jsonl: true) {
                    ShareLink(item: jsonl, preview: SharePreview(Text(verbatim: jsonl.filename))) {
                        Label("Rows as JSONL", systemImage: "doc.text")
                    }
                }
                if let csv = controller.exportFile(jsonl: false) {
                    ShareLink(item: csv, preview: SharePreview(Text(verbatim: csv.filename))) {
                        Label("Rows as CSV", systemImage: "tablecells")
                    }
                }
            }
        }
    }
}
