import BoarModels
import SwiftUI

/// Plain-language names, one-line purposes and symbols for the catalog, as a lay user reads them. The engine's labels
/// (quantization, parameter counts, licences) stay for the model detail screen.
extension CatalogAsset {
    private struct Copy {
        let name: String
        let purpose: String
        let symbol: String
    }

    private var copy: Copy? {
        switch id {
        case "qwen2.5-1.5b-instruct-q4km":
            Copy(name: String(localized: "Fast"), purpose: String(localized: "Quick answers, light on memory"), symbol: "hare")
        case "qwen3-4b-instruct-2507-q4km":
            Copy(name: String(localized: "Accurate"), purpose: String(localized: "Better explanations, a little slower"), symbol: "graduationcap")
        case "qwen2.5-7b-instruct-q4km":
            Copy(name: String(localized: "Qwen 7B"), purpose: String(localized: "Stronger reasoning, needs more memory"), symbol: "cube")
        case "lfm2.5-8b-a1b-q4km":
            Copy(name: String(localized: "LFM 8B"), purpose: String(localized: "Thinks before answering, needs more memory"), symbol: "cube")
        case "gemma-4-e4b-it-q4_0":
            Copy(name: String(localized: "Gemma 4"), purpose: String(localized: "Google's on-device model, needs more memory"), symbol: "cube")
        case "phi-3.5-mini-instruct-q4km":
            Copy(name: String(localized: "Phi 3.5 Mini"), purpose: String(localized: "Compact general model"), symbol: "cube")
        case "bge-small-en-v1.5-q8":
            Copy(name: String(localized: "Search Model"), purpose: String(localized: "Finds the right passages in your library"), symbol: "magnifyingglass")
        case "corpus-standard":
            Copy(name: String(localized: "Essentials"), purpose: String(localized: "1,000 common topics"), symbol: "book.closed")
        case "corpus-full":
            Copy(name: String(localized: "Extended"), purpose: String(localized: "4,000 topics"), symbol: "book.closed")
        case "wiki-vital5":
            Copy(name: String(localized: "Wikipedia"), purpose: String(localized: "50,000 article intros"), symbol: "book.closed")
        default:
            nil
        }
    }

    /// "Fast", "Accurate", "Wikipedia"; other models keep their short name without a trailing "(…)".
    var friendlyName: String {
        if let copy { return copy.name }
        return shortName.replacing(/\s*\([^)]*\)\s*$/, with: "")
    }

    /// The model's own name without the quantization ("Qwen2.5-1.5B-Instruct"), shown next to the plain name so people
    /// know which model they get; nil for packs and when it would repeat the plain name.
    var modelName: String? {
        guard kind != .corpus else { return nil }
        // "Qwen3-4B-Instruct-2507" → "Qwen3-4B": the family and size are what people compare.
        let name = shortModelLabel(label)
            .replacing(/(?i)[-_ ](instruct|it)(-\d{4})?$/, with: "")
            .replacing(/-\d{4}$/, with: "")
        return name == friendlyName ? nil : name
    }

    /// One short line on what it is for ("Quick answers, light on memory").
    var plainPurpose: String {
        copy?.purpose ?? (kind == .corpus ? String(localized: "Library") : String(localized: "Answer model"))
    }

    /// The SF Symbol for its row.
    var symbol: String {
        copy?.symbol ?? (kind == .corpus ? "book.closed" : "cube")
    }
}

extension Compatibility {
    /// The RAM-fit verdict in plain words; nil when unknown.
    var plainLabel: LocalizedStringKey? {
        switch self {
        case .green: "Fits this \(Platform.deviceNoun)"
        case .yellow: "May be slow on this \(Platform.deviceNoun)"
        case .red: "Too big for this \(Platform.deviceNoun)"
        case .unknown: nil
        }
    }

    /// The verdict as a badge next to a model's name; nil when it fits comfortably or is unknown.
    var plainShortLabel: LocalizedStringKey? {
        switch self {
        case .yellow: "May be slow"
        case .red: "Too big"
        case .green, .unknown: nil
        }
    }

    /// Outline symbol for the verdict; nil when unknown.
    var symbol: String? {
        switch self {
        case .green: "checkmark.circle"
        case .yellow: "exclamationmark.triangle"
        case .red: "xmark.circle"
        case .unknown: nil
        }
    }

    /// The verdict's status color, from the theme (Android's RamBadge: emerald, amber, crimson).
    var style: BoarStyle {
        switch self {
        case .green: .boar(.success)
        case .yellow: .boar(.warning)
        case .red: .boar(.danger)
        case .unknown: .boar(.secondary)
        }
    }

    /// The verdict's badge tone (Android's RamBadge colors).
    var tone: ModelBadge.Tone {
        switch self {
        case .green, .unknown: .accent
        case .yellow: .warning
        case .red: .danger
        }
    }
}
