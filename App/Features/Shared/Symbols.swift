import BoarAnswer
import BoarCore

/// One icon per concept, shared by every screen: Android's Boar icon pack where Android draws that concept with it
/// (BoarDrawer, SettingsScreen, ChatScreen, SetupScreen, ModelsScreen), an SF Symbol otherwise (outline in rows,
/// `.fill` only for a selected or active state).
enum Symbols {
    static let newChat = AppIcon.pack(.add)
    static let send = AppIcon.pack(.send)
    static let stop = AppIcon.pack(.stop)
    static let mic = AppIcon.pack(.mic)
    static let close = AppIcon.pack(.close)
    static let deepResearch = AppIcon.pack(.deepResearch)
    static let sources: AppIcon = "books.vertical"
    static let thinking: AppIcon = "brain"
    /// In use, installed, done (android ic_check).
    static let active = AppIcon.pack(.check)
    static let fits: AppIcon = "checkmark.circle"
    /// A warning or a failed step (android ic_settings_recovery, the pack's triangle).
    static let caution = AppIcon.pack(.settingsRecovery)
    /// A Detailed pick answered short (ShortAnswer: health, seed phrases).
    static let shortAnswer: AppIcon = "text.append"
    static let tooBig: AppIcon = "xmark.circle"
    static let error = AppIcon.pack(.settingsRecovery)
    static let retry = AppIcon.pack(.refresh)
    static let download: AppIcon = "arrow.down.circle"
    static let delete = AppIcon.pack(.delete)
    static let search = AppIcon.pack(.search)
    /// BOAR's knowledge and the topic packs (android "knowledge", ic_settings_knowledge).
    static let library = AppIcon.pack(.settingsKnowledge)
    static let pack = AppIcon.pack(.settingsKnowledge)
    /// Personal Files (android DocumentsScreen's section, ic_style_personal).
    static let collection = AppIcon.pack(.stylePersonal)
    static let model = AppIcon.pack(.settingsModels)
    static let fastTier: AppIcon = "hare"
    static let accurateTier: AppIcon = "graduationcap"
    static let otherModel: AppIcon = "cube"
    static let storage: AppIcon = "internaldrive"
    static let memory = AppIcon.pack(.settingsMemory)
    static let offline: AppIcon = "wifi.slash"
    static let advanced = AppIcon.pack(.settingsTweaks)
    static let benchmark = AppIcon.pack(.settingsHardware)
    static let performance: AppIcon = "speedometer"
    static let settings = AppIcon.pack(.styleCustom)
    static let labs = AppIcon.pack(.settingsExperimental)
    static let lock = AppIcon.pack(.settingsPin)
    static let theme = AppIcon.pack(.settingsDisplay)
    static let tone = AppIcon.pack(.settingsTone)
    static let voice = AppIcon.pack(.settingsVoice)
}

extension Personality {
    /// The answer style's icon (android StyleIcon; the catalog's emoji is never shown).
    var symbol: AppIcon {
        switch id {
        case "succinct": .pack(.styleQuick)
        case "detailed": .pack(.settingsKnowledge)
        case "personal": .pack(.stylePersonal)
        case "custom": .pack(.styleCustom)
        default: .pack(.settingsKnowledge)
        }
    }
}

extension TweakPreset {
    /// The preset's symbol (the engine's emoji is never shown).
    var symbol: AppIcon {
        switch self {
        case .run: "flame"
        case .path: "gauge.with.dots.needle.50percent"
        case .forage: "leaf"
        case .cool: "thermometer.snowflake"
        }
    }
}
