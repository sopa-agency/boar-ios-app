/// Settings → Advanced → Answer Length: plain names over the engine's max output token values.
enum AnswerLength: CaseIterable, Identifiable {
    case auto, short, medium, long

    var id: Self { self }

    /// The stored `maxTokensChoice` (nil is Auto).
    var tokens: Int? {
        switch self {
        case .auto: nil
        case .short: 256
        case .medium: 512
        case .long: 1024
        }
    }

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .short: String(localized: "Short")
        case .medium: String(localized: "Medium")
        case .long: String(localized: "Long")
        }
    }

    /// The nearest choice for a stored value (an older build could store 2048, shown as Long).
    init(tokens: Int?) {
        guard let tokens else { self = .auto; return }
        self = tokens <= 256 ? .short : tokens <= 512 ? .medium : .long
    }
}
