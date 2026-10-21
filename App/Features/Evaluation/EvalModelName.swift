import BoarModels
import Foundation

/// A model as the Benchmark screen names it: the plain catalog name ("Fast") and, when it differs, the model's own name
/// without the quantization ("Qwen2.5-1.5B-Instruct").
struct EvalModelName: Equatable {
    let plain: String
    let model: String?

    init(asset: CatalogAsset?, label: String) {
        let bare = label.replacing(/\s*\([^)]*\)\s*$/, with: "")
        let plain = asset?.friendlyName ?? bare
        self.plain = plain
        model = bare == plain ? nil : bare
    }

    /// "Fast · Qwen2.5-1.5B-Instruct".
    var full: String { [plain, model].compactMap { $0 }.joined(separator: " · ") }
}
