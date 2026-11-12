import BoarCore

/// Boar Avatars' names and clues (android strings_native.xml `native_truffle_*`, `native_rule_*`), as literals so the
/// String Catalog picks them up. Clues about airplane mode, the PIN, the APK and Play Services say what iOS counts
/// instead (docs/truffle-vault-ios.md).
enum AvatarCopy {
    /// The avatar's name; BOAR for nil (its own).
    static func name(_ id: String?) -> String {
        switch id {
        case nil: "BOAR"
        case "cosmo": String(localized: "Cosmo Boar")
        case "quantum": String(localized: "Quantum Boar")
        case "tactical": String(localized: "Tactical Boar")
        case "hacker": String(localized: "Code Boar")
        case "solarpunk": String(localized: "Solarpunk Boar")
        case "nomad": String(localized: "Nomad Boar")
        case "synthetic": String(localized: "Cyber Boar")
        case "senior": String(localized: "Senior Boar")
        case "mecha": String(localized: "Mecha Boar")
        case "plasma": String(localized: "Plasma Boar")
        case "steampunk": String(localized: "Steampunk Boar")
        case "retrowave": String(localized: "Retrowave Boar")
        case "ice": String(localized: "Frost Boar")
        case "volcanic": String(localized: "Magma Boar")
        case "astronaut": String(localized: "Astro Boar")
        case "stealth": String(localized: "Stealth Boar")
        case "biolum": String(localized: "Neon Boar")
        case "knight": String(localized: "Knight Boar")
        case "void": String(localized: "Void Boar")
        case "atomic": String(localized: "Atomic Boar")
        case "lunar": String(localized: "Lunar Boar")
        case "digital_nomad": String(localized: "Data Nomad")
        case "chrono": String(localized: "Chrono Boar")
        case "ethereal": String(localized: "Ethereal Boar")
        case "sovereign": String(localized: "Sovereign Boar")
        case "guardian": String(localized: "Solar Guardian")
        case "tactical_city": String(localized: "Urban Boar")
        case "pixel_hacker": String(localized: "Pixel Boar")
        case "moe": String(localized: "Tensor Boar")
        case "explorer": String(localized: "Field Boar")
        case "spirit": String(localized: "Spirit Boar")
        case "planter": String(localized: "Forest Boar")
        case "cloud": String(localized: "Airgap Boar")
        case "elder": String(localized: "Elder Boar")
        case "fomo_unicorn": String(localized: "Unicorn Boar")
        case "tactical_ii": String(localized: "SpecOps Boar")
        case "totem": String(localized: "Totem Boar")
        case "hammock": String(localized: "Hammock Boar")
        case "snow": String(localized: "Snow Boar")
        case "hacker_ii": String(localized: "Kernel Boar")
        default: id ?? "BOAR"
        }
    }

    /// What unlocks it, shown while it's locked.
    static func clue(_ rule: Vault.Rule) -> String {
        switch rule {
        case .ALWAYS: String(localized: "Night-vision gear, issued to everyone.")
        case .FIRST_ANSWER: String(localized: "Ask BOAR your first question.")
        case .FIRST_SOURCED: String(localized: "Get an answer that cites a source.")
        case .ANSWERS_10: String(localized: "10 answers.")
        case .ANSWERS_50: String(localized: "50 answers.")
        case .ANSWERS_100: String(localized: "100 answers.")
        case .ANSWERS_500: String(localized: "500 answers.")
        case .ANSWERS_1000: String(localized: "1,000 answers. Only the sovereign get here.")
        case .FIRST_OFFLINE: String(localized: "Get an answer with no network at all.")
        case .OFFLINE_10: String(localized: "10 answers with no network.")
        case .NIGHT: String(localized: "The forest is quietest between 2 AM and 4 AM.")
        case .NIGHT_5: String(localized: "Five questions in the quiet hours.")
        case .DEEP_RESEARCH: String(localized: "Run a Deep Research.")
        case .DEEP_RESEARCH_10: String(localized: "10 Deep Researches.")
        case .EVAL_RUN: String(localized: "Measure, don't guess: run an evaluation.")
        case .EVAL_RUNS_5: String(localized: "Run 5 evaluations.")
        case .EVAL_SHARED: String(localized: "Share an evaluation's results.")
        case .CHATS_10: String(localized: "Start 10 chats.")
        case .CHATS_100: String(localized: "Start 100 chats.")
        case .DOCUMENT: String(localized: "Feed BOAR a document of your own.")
        case .EXPORT: String(localized: "Export a collection.")
        case .PACK: String(localized: "Download a knowledge pack.")
        case .PACKS_2: String(localized: "Carry two knowledge packs.")
        case .HF_MODEL: String(localized: "Add a model from Hugging Face.")
        case .FAST_8: String(localized: "Push local silicon past 8 tokens per second.")
        case .FAST_15: String(localized: "Push local silicon past 15 tokens per second.")
        case .VOICE: String(localized: "Speak to BOAR.")
        case .PORTUGUESE: String(localized: "Ask in Portuguese.")
        case .PIN: String(localized: "Lock BOAR.")
        case .PIN_DARK: String(localized: "Locked, and opened with no network at all.")
        case .THEME: String(localized: "Change the colors.")
        case .TWEAKS: String(localized: "Tinker with the engine in Advanced tweaks.")
        case .SOURCE_BUILD: String(localized: "Don't trust the App Store. Build the boar with your own hands.")
        case .DEGOOGLED: String(localized: "Running without Google Play services.")
        case .DAYS_3: String(localized: "Use BOAR on 3 different days.")
        case .DAYS_7: String(localized: "Use BOAR on 7 different days.")
        case .DAYS_30: String(localized: "Use BOAR on 30 different days.")
        case .AIRPLANE_STREAK_3: String(localized: "Open BOAR with no network at all, 3 days in a row.")
        case .AIRPLANE_STREAK_7: String(localized: "Forage deep in the woods: no network, 7 days in a row.")
        case .AIRPLANE_DAYS_14: String(localized: "14 days off the grid, in any order.")
        case .QUIZ_FIRST: String(localized: "Somewhere in Boar Labs, a question is waiting.")
        case .QUIZ_DAYS_7: String(localized: "Answer the same lab’s questions for a week.")
        case .ALL_OTHERS: String(localized: "The legendary avatar: unlock every other one.")
        }
    }
}
