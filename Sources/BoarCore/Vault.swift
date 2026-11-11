import Foundation

/// Boar Avatars' rules (android engine/vault `Vault.kt`; the code says vault and truffle, the app says avatars): which
/// boar avatar unlocks when, from facts the app counts on the device. Nothing here reads the device or the clock; the app
/// feeds the facts and stores `State` in settings.json under `truffleVault`, in Android's JSON shape.
public enum Vault {
    /// What the vault knows about how BOAR has been used, all counted on the device and never sent anywhere.
    public struct Facts: Equatable, Sendable, Codable {
        public var answers = 0
        /// Answers that cited at least one source.
        public var sourcedAnswers = 0
        /// Answers given with no network at all.
        public var offlineAnswers = 0
        /// Answers asked between 02:00 and 04:00 local time.
        public var nightAnswers = 0
        public var deepResearch = 0
        public var evalRuns = 0
        public var evalShares = 0
        public var chats = 0
        public var documents = 0
        public var exports = 0
        public var packs = 0
        /// Models added from Hugging Face (not in BOAR's catalog).
        public var hfModels = 0
        public var bestTokPerSec = 0.0
        public var voice = false
        public var portuguese = false
        /// Android's PIN; the app lock on iOS.
        public var pinOn = false
        public var themeChanged = false
        public var tweaksChanged = false
        /// Not an App Store or TestFlight build: someone built it from source.
        public var sourceBuild = false
        /// Android: GrapheneOS, or no Google Play services at all.
        public var degoogled = false
        /// Daily Quiz answers right.
        public var quizRight = 0
        /// ISO dates the Daily Quiz was played, oldest first.
        public var quizDays: [String] = []
        /// ISO dates (yyyy-MM-dd) the app was opened, oldest first.
        public var usedDays: [String] = []
        /// ISO dates the app was opened in airplane mode, oldest first.
        public var airplaneDays: [String] = []

        public init(answers: Int = 0, sourcedAnswers: Int = 0, offlineAnswers: Int = 0, nightAnswers: Int = 0,
                    deepResearch: Int = 0, evalRuns: Int = 0, evalShares: Int = 0, chats: Int = 0, documents: Int = 0,
                    exports: Int = 0, packs: Int = 0, hfModels: Int = 0, bestTokPerSec: Double = 0, voice: Bool = false,
                    portuguese: Bool = false, pinOn: Bool = false, themeChanged: Bool = false, tweaksChanged: Bool = false,
                    sourceBuild: Bool = false, degoogled: Bool = false, quizRight: Int = 0, quizDays: [String] = [],
                    usedDays: [String] = [], airplaneDays: [String] = []) {
            self.answers = answers; self.sourcedAnswers = sourcedAnswers; self.offlineAnswers = offlineAnswers
            self.nightAnswers = nightAnswers; self.deepResearch = deepResearch; self.evalRuns = evalRuns
            self.evalShares = evalShares; self.chats = chats; self.documents = documents; self.exports = exports
            self.packs = packs; self.hfModels = hfModels; self.bestTokPerSec = bestTokPerSec; self.voice = voice
            self.portuguese = portuguese; self.pinOn = pinOn; self.themeChanged = themeChanged
            self.tweaksChanged = tweaksChanged; self.sourceBuild = sourceBuild; self.degoogled = degoogled
            self.quizRight = quizRight; self.quizDays = quizDays; self.usedDays = usedDays; self.airplaneDays = airplaneDays
        }

        private enum CodingKeys: String, CodingKey {
            case answers, sourcedAnswers, offlineAnswers, nightAnswers, deepResearch, evalRuns, evalShares, chats,
                 documents, exports, packs, hfModels, bestTokPerSec, voice, portuguese, pinOn, themeChanged,
                 tweaksChanged, sourceBuild, degoogled, quizRight, quizDays, usedDays, airplaneDays
        }

        /// A missing key keeps its default (a vault stored before a fact existed still loads), like kotlinx.serialization.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Facts()
            func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T { try c.decodeIfPresent(T.self, forKey: key) ?? fallback }
            self.init(
                answers: try v(.answers, d.answers), sourcedAnswers: try v(.sourcedAnswers, d.sourcedAnswers),
                offlineAnswers: try v(.offlineAnswers, d.offlineAnswers), nightAnswers: try v(.nightAnswers, d.nightAnswers),
                deepResearch: try v(.deepResearch, d.deepResearch), evalRuns: try v(.evalRuns, d.evalRuns),
                evalShares: try v(.evalShares, d.evalShares), chats: try v(.chats, d.chats),
                documents: try v(.documents, d.documents), exports: try v(.exports, d.exports), packs: try v(.packs, d.packs),
                hfModels: try v(.hfModels, d.hfModels), bestTokPerSec: try v(.bestTokPerSec, d.bestTokPerSec),
                voice: try v(.voice, d.voice), portuguese: try v(.portuguese, d.portuguese), pinOn: try v(.pinOn, d.pinOn),
                themeChanged: try v(.themeChanged, d.themeChanged), tweaksChanged: try v(.tweaksChanged, d.tweaksChanged),
                sourceBuild: try v(.sourceBuild, d.sourceBuild), degoogled: try v(.degoogled, d.degoogled),
                quizRight: try v(.quizRight, d.quizRight), quizDays: try v(.quizDays, d.quizDays),
                usedDays: try v(.usedDays, d.usedDays), airplaneDays: try v(.airplaneDays, d.airplaneDays))
        }

        /// Only what differs from the default, like Android's `encodeDefaults = false`.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            let d = Facts()
            func put<T: Encodable & Equatable>(_ value: T, _ fallback: T, _ key: CodingKeys) throws {
                if value != fallback { try c.encode(value, forKey: key) }
            }
            try put(answers, d.answers, .answers); try put(sourcedAnswers, d.sourcedAnswers, .sourcedAnswers)
            try put(offlineAnswers, d.offlineAnswers, .offlineAnswers); try put(nightAnswers, d.nightAnswers, .nightAnswers)
            try put(deepResearch, d.deepResearch, .deepResearch); try put(evalRuns, d.evalRuns, .evalRuns)
            try put(evalShares, d.evalShares, .evalShares); try put(chats, d.chats, .chats)
            try put(documents, d.documents, .documents); try put(exports, d.exports, .exports); try put(packs, d.packs, .packs)
            try put(hfModels, d.hfModels, .hfModels); try put(bestTokPerSec, d.bestTokPerSec, .bestTokPerSec)
            try put(voice, d.voice, .voice); try put(portuguese, d.portuguese, .portuguese); try put(pinOn, d.pinOn, .pinOn)
            try put(themeChanged, d.themeChanged, .themeChanged); try put(tweaksChanged, d.tweaksChanged, .tweaksChanged)
            try put(sourceBuild, d.sourceBuild, .sourceBuild); try put(degoogled, d.degoogled, .degoogled)
            try put(quizRight, d.quizRight, .quizRight); try put(quizDays, d.quizDays, .quizDays)
            try put(usedDays, d.usedDays, .usedDays); try put(airplaneDays, d.airplaneDays, .airplaneDays)
        }
    }

    /// Unlock rules, with Android's names (the clue's string key is `native.rule.<NAME>`). Each avatar has one; the app
    /// shows the rule's clue while the avatar is locked.
    public enum Rule: String, CaseIterable, Sendable {
        case ALWAYS, FIRST_ANSWER, FIRST_SOURCED, ANSWERS_10, ANSWERS_50, ANSWERS_100, ANSWERS_500, ANSWERS_1000
        case FIRST_OFFLINE, OFFLINE_10, NIGHT, NIGHT_5, DEEP_RESEARCH, DEEP_RESEARCH_10, EVAL_RUN, EVAL_RUNS_5, EVAL_SHARED
        case CHATS_10, CHATS_100, DOCUMENT, EXPORT, PACK, PACKS_2, HF_MODEL, FAST_8, FAST_15, VOICE, PORTUGUESE, PIN
        case PIN_DARK, THEME, TWEAKS, SOURCE_BUILD, DEGOOGLED, DAYS_3, DAYS_7, DAYS_30, AIRPLANE_STREAK_3
        case AIRPLANE_STREAK_7, AIRPLANE_DAYS_14, QUIZ_FIRST, QUIZ_DAYS_7
        /// The legendary avatar: every other one unlocked. Decided in `apply`, which sees what's unlocked.
        case ALL_OTHERS

        public func test(_ f: Facts, _ today: Day) -> Bool {
            switch self {
            case .ALWAYS: true
            case .FIRST_ANSWER: f.answers >= 1
            case .FIRST_SOURCED: f.sourcedAnswers >= 1
            case .ANSWERS_10: f.answers >= 10
            case .ANSWERS_50: f.answers >= 50
            case .ANSWERS_100: f.answers >= 100
            case .ANSWERS_500: f.answers >= 500
            case .ANSWERS_1000: f.answers >= 1000
            case .FIRST_OFFLINE: f.offlineAnswers >= 1
            case .OFFLINE_10: f.offlineAnswers >= 10
            case .NIGHT: f.nightAnswers >= 1
            case .NIGHT_5: f.nightAnswers >= 5
            case .DEEP_RESEARCH: f.deepResearch >= 1
            case .DEEP_RESEARCH_10: f.deepResearch >= 10
            case .EVAL_RUN: f.evalRuns >= 1
            case .EVAL_RUNS_5: f.evalRuns >= 5
            case .EVAL_SHARED: f.evalShares >= 1
            case .CHATS_10: f.chats >= 10
            case .CHATS_100: f.chats >= 100
            case .DOCUMENT: f.documents >= 1
            case .EXPORT: f.exports >= 1
            case .PACK: f.packs >= 1
            case .PACKS_2: f.packs >= 2
            case .HF_MODEL: f.hfModels >= 1
            case .FAST_8: f.bestTokPerSec >= 8.0
            case .FAST_15: f.bestTokPerSec > 15.0
            case .VOICE: f.voice
            case .PORTUGUESE: f.portuguese
            case .PIN: f.pinOn
            case .PIN_DARK: f.pinOn && Days.streak(f.airplaneDays, today) >= 1
            case .THEME: f.themeChanged
            case .TWEAKS: f.tweaksChanged
            case .SOURCE_BUILD: f.sourceBuild
            case .DEGOOGLED: f.degoogled
            case .DAYS_3: f.usedDays.count >= 3
            case .DAYS_7: f.usedDays.count >= 7
            case .DAYS_30: f.usedDays.count >= 30
            case .AIRPLANE_STREAK_3: Days.streak(f.airplaneDays, today) >= 3
            case .AIRPLANE_STREAK_7: Days.streak(f.airplaneDays, today) >= 7
            case .AIRPLANE_DAYS_14: f.airplaneDays.count >= 14
            case .QUIZ_FIRST: f.quizRight >= 1
            case .QUIZ_DAYS_7: f.quizDays.count >= 7
            case .ALL_OTHERS: false
            }
        }
    }

    /// Each avatar's rule, in the vault's order (Android's art/icons/truffles.json has the same ids in the same order).
    public static let rules: [(id: String, rule: Rule)] = [
        ("cosmo", .FIRST_ANSWER),
        ("quantum", .FAST_15),
        ("tactical", .ALWAYS),
        ("hacker", .SOURCE_BUILD),
        ("solarpunk", .ANSWERS_10),
        ("nomad", .AIRPLANE_STREAK_7),
        ("synthetic", .HF_MODEL),
        ("senior", .DEEP_RESEARCH),
        ("mecha", .EVAL_RUN),
        ("plasma", .VOICE),
        ("steampunk", .DAYS_3),
        ("retrowave", .PORTUGUESE),
        ("ice", .AIRPLANE_STREAK_3),
        ("volcanic", .FAST_8),
        ("astronaut", .DAYS_7),
        ("stealth", .DEGOOGLED),
        ("biolum", .NIGHT_5),
        ("knight", .QUIZ_FIRST),
        ("void", .CHATS_10),
        ("atomic", .EVAL_RUNS_5),
        ("lunar", .NIGHT),
        ("digital_nomad", .DOCUMENT),
        ("chrono", .DAYS_30),
        ("ethereal", .ANSWERS_500),
        ("sovereign", .ANSWERS_1000),
        ("guardian", .FIRST_SOURCED),
        ("tactical_city", .PIN),
        ("pixel_hacker", .THEME),
        ("moe", .PACKS_2),
        ("explorer", .FIRST_OFFLINE),
        ("spirit", .DEEP_RESEARCH_10),
        ("planter", .ANSWERS_50),
        ("cloud", .OFFLINE_10),
        ("elder", .QUIZ_DAYS_7),
        ("fomo_unicorn", .ALL_OTHERS),
        ("tactical_ii", .PIN_DARK),
        ("totem", .PACK),
        ("hammock", .ANSWERS_100),
        ("snow", .AIRPLANE_DAYS_14),
        ("hacker_ii", .TWEAKS),
    ]

    public static func rule(_ id: String) -> Rule? { rules.first { $0.id == id }?.rule }

    /// Everything the vault stores: the facts, when each avatar was unlocked (epoch ms), and themes plugins granted.
    public struct State: Equatable, Sendable, Codable {
        public var facts = Facts()
        public var unlocked: [String: Int64] = [:]
        public var themes: [String: Int64] = [:]

        public init(facts: Facts = Facts(), unlocked: [String: Int64] = [:], themes: [String: Int64] = [:]) {
            self.facts = facts; self.unlocked = unlocked; self.themes = themes
        }

        private enum CodingKeys: String, CodingKey { case facts, unlocked, themes }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            facts = try c.decodeIfPresent(Facts.self, forKey: .facts) ?? Facts()
            unlocked = try c.decodeIfPresent([String: Int64].self, forKey: .unlocked) ?? [:]
            themes = try c.decodeIfPresent([String: Int64].self, forKey: .themes) ?? [:]
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if facts != Facts() { try c.encode(facts, forKey: .facts) }
            if !unlocked.isEmpty { try c.encode(unlocked, forKey: .unlocked) }
            if !themes.isEmpty { try c.encode(themes, forKey: .themes) }
        }
    }

    /// `state` with `facts` and every avatar they newly unlock, stamped `now`; also the ids that are new, in the vault's
    /// order with the legendary last.
    public static func apply(_ state: State, facts: Facts, today: Day, now: Int64) -> (state: State, fresh: [String]) {
        let found = rules.filter { state.unlocked[$0.id] == nil && $0.rule.test(facts, today) }.map(\.id)
        let have = Set(state.unlocked.keys).union(found)
        let legends = rules.filter { entry in
            entry.rule == .ALL_OTHERS && !have.contains(entry.id) && rules.allSatisfy { $0.id == entry.id || have.contains($0.id) }
        }.map(\.id)
        let fresh = found + legends
        var next = state
        next.facts = facts
        for id in fresh { next.unlocked[id] = now }
        return (next, fresh)
    }

    public static func toJson(_ state: State) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The stored state, or an empty one for nil or junk (like Android's `runCatching`).
    public static func fromJson(_ text: String?) -> State {
        guard let text, let state = try? JSONDecoder().decode(State.self, from: Data(text.utf8)) else { return State() }
        return state
    }

    /// A calendar date (Kotlin's LocalDate as the vault uses it): ISO text and whole-day steps.
    public struct Day: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// Days since 1970-01-01 (LocalDate.toEpochDay).
        public let epochDay: Int64

        public init(epochDay: Int64) { self.epochDay = epochDay }

        public init(year: Int, month: Int, day: Int) {
            // Days from civil (Howard Hinnant's algorithm), proleptic Gregorian like java.time.
            let y = Int64(month <= 2 ? year - 1 : year)
            let era = (y >= 0 ? y : y - 399) / 400
            let yoe = y - era * 400
            let m = Int64(month)
            let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + Int64(day) - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            epochDay = era * 146097 + doe - 719468
        }

        /// "yyyy-MM-dd", or nil when it isn't one.
        public init?(iso: String) {
            let parts = iso.split(separator: "-")
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
                  (1...12).contains(m), (1...31).contains(d) else { return nil }
            self.init(year: y, month: m, day: d)
        }

        /// Today in `calendar`'s time zone (LocalDate.now()).
        public static func today(_ date: Date = Date(), calendar: Calendar = .current) -> Day {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return Day(year: c.year!, month: c.month!, day: c.day!)
        }

        public func minusDays(_ n: Int64) -> Day { Day(epochDay: epochDay - n) }

        public var components: (year: Int, month: Int, day: Int) {
            // Civil from days (Hinnant).
            let z = epochDay + 719468
            let era = (z >= 0 ? z : z - 146096) / 146097
            let doe = z - era * 146097
            let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            let mp = (5 * doy + 2) / 153
            let d = doy - (153 * mp + 2) / 5 + 1
            let m = mp < 10 ? mp + 3 : mp - 9
            return (Int(yoe + era * 400 + (m <= 2 ? 1 : 0)), Int(m), Int(d))
        }

        /// ISO "yyyy-MM-dd" (LocalDate.toString for years 0...9999).
        public var description: String {
            let (y, m, d) = components
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
    }

    /// Day lists: distinct ISO dates, oldest first, at most `keep`.
    public enum Days {
        public static let keep = 64

        public static func add(_ days: [String], _ day: Day) -> [String] {
            Array(Array(Set(days + [day.description])).sorted().suffix(keep))
        }

        /// Days in a row that end today (or yesterday, so a streak isn't lost before the first open of the day).
        public static func streak(_ days: [String], _ today: Day) -> Int {
            let set = Set(days)
            var d = set.contains(today.description) ? today : today.minusDays(1)
            var n = 0
            while set.contains(d.description) { n += 1; d = d.minusDays(1) }
            return n
        }
    }

    /// 02:00 to 03:59 local time.
    public static func isNight(hour: Int) -> Bool { (2...3).contains(hour) }
}
