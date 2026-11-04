import BoarAnswer
import BoarCore

/// One SF Symbol per concept, shared by every screen (outline in rows, `.fill` only for a selected or active state).
enum Symbols {
    static let newChat = "square.and.pencil"
    static let send = "arrow.up"
    static let stop = "stop.fill"
    static let deepResearch = "flask"
    static let sources = "books.vertical"
    static let thinking = "brain"
    static let active = "checkmark.circle.fill"
    static let fits = "checkmark.circle"
    static let caution = "exclamationmark.triangle"
    static let tooBig = "xmark.circle"
    static let error = "exclamationmark.circle.fill"
    static let retry = "arrow.clockwise"
    static let download = "arrow.down.circle"
    static let delete = "trash"
    static let recommended = "star.fill"
    static let library = "books.vertical"
    static let pack = "book.closed"
    static let collection = "folder"
    static let model = "cpu"
    static let fastTier = "hare"
    static let accurateTier = "graduationcap"
    static let otherModel = "cube"
    static let storage = "internaldrive"
    static let memory = "memorychip"
    static let offline = "wifi.slash"
    static let advanced = "gearshape.2"
    static let benchmark = "gauge.with.dots.needle.67percent"
    static let performance = "speedometer"
}

extension Personality {
    /// The answer style's symbol (the catalog's emoji is never shown).
    var symbol: String {
        switch id {
        case "succinct": "bolt"
        case "detailed": "text.alignleft"
        case "personal": "folder"
        case "custom": "slider.horizontal.3"
        default: "text.alignleft"
        }
    }
}

extension TweakPreset {
    /// The preset's symbol (the engine's emoji is never shown).
    var symbol: String {
        switch self {
        case .run: "flame"
        case .path: "gauge.with.dots.needle.50percent"
        case .forage: "leaf"
        case .cool: "thermometer.snowflake"
        }
    }
}
