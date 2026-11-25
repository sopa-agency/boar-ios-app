import BoarAnswer
import BoarCore
import BoarModels
import SwiftUI

/// Boar Labs (android `src/labs`): unfinished experiments, hidden until the user turns on Settings → Advanced → Boar
/// Labs. Off, no lab shows anywhere and every slot is empty. Each lab has its own Enabled switch on its page; every lab
/// starts off (Android, Oct 24), and a switched-off lab fills no slot.
///
/// Slots are where a lab reaches into the app: the tool slot (answers or adds context before the model), the check slot
/// (repairs a finished answer), actions in a finished answer's More menu (android's 🧩 sheet), a badge in the chat's
/// toolbar, and the lab's own page. A CLASSIFIED lab shows its tile locked and never opens or fills a
/// slot: a teaser for what's in testing.
enum LabsBuild {
    /// Android shows Boar Labs only in builds with EXPERIMENTAL_FEATURES=true. Every iOS build is a test build until the
    /// App Store; the App Store configuration decides this in phase 4.
    static let experimental = true
}

/// LIVE: simple and proven. BETA: tested on phones. ALPHA: works, less tested. REVIEW: frozen. CLASSIFIED: a teaser.
/// In the grid's order.
enum LabStatus: Int, Comparable, Sendable {
    case live, beta, alpha, review, classified

    static func < (a: LabStatus, b: LabStatus) -> Bool { a.rawValue < b.rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .live: "LIVE"
        case .beta: "BETA"
        case .alpha: "ALPHA"
        case .review: "UNDER REVIEW"
        case .classified: "CLASSIFIED"
        }
    }
}

/// One experiment (android `LabPlugin`). Everything but the id, emoji and status has a default.
@MainActor
protocol LabPlugin {
    /// Stable id: the string keys (`labs.<id>.*` on Android), the switch.
    var id: String { get }
    /// plugin.properties `order`: the grid's order within a status.
    var order: Int { get }
    /// Stands in for the tile's art until there is a picture.
    var emoji: String { get }
    /// The tile's picture (an asset name), shown instead of the emoji when set.
    var art: String? { get }
    var status: LabStatus { get }
    var title: String { get }
    /// What it does, under the tile and in the page's header.
    var body: String { get }
    /// UNDER REVIEW: the short reason on the tile ("under 1 tok/s") and the full one on the page.
    var reviewShort: String? { get }
    var review: String? { get }

    /// The tool slot: looks at the question before the model and answers it or adds context.
    var answerTool: (any AnswerTool)? { get }
    /// Whether `query` is clearly this plugin's question (android `recognizes`): "Lunar is off" under a model answer.
    func recognizes(_ query: String) -> Bool
    /// The check slot: reads a model's finished answer and may repair it.
    var answerCheck: (any AnswerCheck)? { get }
    /// The search slot (android `PipelineStages.search`): looks at what the search found and returns the passages the model reads.
    var searchStage: (any SearchStage)? { get }
    /// The experiment's page, below the shared header.
    func content() -> AnyView
    /// The page's sheets, behind the whole page rather than on one of its rows: a row the list recycles (it leaves the
    /// screen when the device turns) would close a sheet presented from it.
    func presenter() -> AnyView?
    /// Rows in a finished answer's More menu (android `answerActions`, the 🧩 sheet).
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction]
    /// Under a finished answer's text, before the footer (android `AnswerExtra`): Cards' card, its wait line or refusal.
    func answerExtra(_ answer: AnswerRef) -> AnyView?
    /// Work done once per finished answer as it shows, off the main actor (Cards reads the answer's card and what its rules
    /// find), so the menu and the extra read it ready.
    func prepareAnswer(_ answer: AnswerRef) async
    /// Notes about a finished answer, in the footer under the separator after BOAR's own, before the receipt (android
    /// `answerNotes`, adam Nov 14): an error, a refusal. No lab here makes one yet (android's only source is Designer's
    /// "Not enough free memory to draw", and Designer isn't ported); the slot is ready for the first.
    func answerNotes(_ answer: AnswerRef) -> [LabAnswerNote]
    /// A count shown beside this plugin in the chat header's sheet (android `headerCount`); 0 shows none. Never on the icon.
    func headerCount() -> Int
    func headerCountLabel(_ n: Int) -> String
    /// "About this plugin", folded at the foot of the page: the longer explanation the list's line leaves out. A page with
    /// a "How it works" fold has none, so a page has one fold.
    var about: String? { get }
    /// The plugin lays out the whole page itself (android `fullPage`): no Form and no shared header; the page switch sits
    /// in the navigation bar. No iOS plugin is one yet.
    var fullPage: Bool { get }
    /// Erases what this lab made from the user's chats (android `eraseUserData`): runs with the chats' erase, even while
    /// the lab is switched off.
    func eraseUserData(_ scope: UserDataScope)
    /// One chat deleted: its answers (`answerIds`) leave what this lab kept of them (android `eraseAnswers`); runs even
    /// while the lab is switched off.
    func eraseAnswers(_ answerIds: [String])
}

/// A finished answer, as the answer slots see it (android `plugins.AnswerRef`).
struct AnswerRef {
    let id: String
    let sessionId: String?
    /// The open chat's title, "" when it has none yet.
    let chatTitle: String
    let question: String
    let text: String
    /// (title, source) of each numbered source.
    let sources: [(String, String?)]
    let model: String?
    let tokPerSec: Double?
    /// The receipt's tool code when a tool wrote it (an instant answer), nil for the model's.
    var tool: String?
    /// The style it was kept to ("health", "seed"), nil when none.
    var styleNote: String?
    /// The passages the model read (title, body), in the sources' order.
    var passages: [(title: String, body: String)] = []
    /// The chat's model is busy: an answer, a plugin's own work, a load (android `chatBusy`).
    var chatBusy = false
    /// The chat the answer is in: a plugin's own model work runs as its job (`ChatController.runForLab`).
    weak var chat: ChatController?
}

/// One row a lab adds to an answer's More menu. `done`: the action already happened (a checkmark; choosing it undoes it).
struct LabAnswerAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var done = false
    /// A second line under the title (android `LabAction.detail`): what Cards found, why it waits.
    var detail: String?
    var enabled = true
    let run: @MainActor () -> Void
}

/// A plugin's note on an answer (android `AnswerNote`): `error` shows in the error color; `at` (epoch ms) orders the notes.
struct LabAnswerNote: Identifiable {
    let id: String
    let text: String
    var error = false
    let at: Int64
}

extension LabPlugin {
    var art: String? { nil }
    var reviewShort: String? { nil }
    var review: String? { nil }
    var answerTool: (any AnswerTool)? { nil }
    func recognizes(_ query: String) -> Bool { false }
    var answerCheck: (any AnswerCheck)? { nil }
    var searchStage: (any SearchStage)? { nil }
    func content() -> AnyView { AnyView(EmptyView()) }
    func presenter() -> AnyView? { nil }
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction] { [] }
    func answerExtra(_ answer: AnswerRef) -> AnyView? { nil }
    func prepareAnswer(_ answer: AnswerRef) async {}
    func answerNotes(_ answer: AnswerRef) -> [LabAnswerNote] { [] }
    func headerCount() -> Int { 0 }
    func headerCountLabel(_ n: Int) -> String { "\(n)" }
    var about: String? { nil }
    var fullPage: Bool { false }
    func eraseUserData(_ scope: UserDataScope) {}
    func eraseAnswers(_ answerIds: [String]) {}
    /// A lab under review (frozen) shows the ice boar, whatever its own art.
    var shownArt: String? { status == .review ? "lab_frozen" : art }
}

/// A classified lab's teaser tile: no screen, no slots, its boar a silhouette until it launches. `inner`: the working lab
/// behind it, when it has code (the Daily Quiz): leaking the tile unlocks it for good, and then it opens as itself.
struct ClassifiedLab: LabPlugin {
    let id: String
    let order: Int
    let emoji: String
    let title: String
    let body: String
    var inner: (any LabPlugin)?
    var status: LabStatus { .classified }

    /// Each classified lab's boar, shown dark like a locked truffle in the vault; a different one per tile.
    var art: String? {
        ["dailyQuiz": "lab_daily_quiz", "signboard": "lab_signboard", "sanctuary": "lab_sanctuary"][id]
    }
}

/// The labs, their switches and the leaked teasers (android `LabRegistry` + `LabPrefs`), kept in the app's defaults
/// under `labs.*`. One per app: the chat reads the active tools from it at each question.
@MainActor
@Observable
final class Labs {
    static let shared = Labs(defaults: AppPaths.defaults)

    /// Every lab this build has, in plugin.properties order.
    let all: [any LabPlugin]

    @ObservationIgnored private let defaults: UserDefaults
    private var on: Bool
    /// What the user chose, per plugin (nil: never switched, so the default list decides; android `LabPrefs.stored`).
    private var stored: [String: Bool]
    /// Plugins the user switched off from their own pages: the header sheet lists them as off (PluginReach).
    private var offFromPage: Set<String>
    /// The plugins used last, newest first (RecentPlugins); kept apart from settings.
    private var recent: [String]
    private var unlockedIds: Set<String>
    /// Classified tiles leaked with the easter egg: they last while Boar Labs is open (Android, Oct 19).
    private var revealedIds: Set<String> = []
    private var storageLimitChoice: String

    init(defaults: UserDefaults, labs: [any LabPlugin] = Labs.registry) {
        self.defaults = defaults
        all = labs.sorted { $0.order < $1.order }
        // The master switch starts on; a plugin never switched follows the default list (LabDefaults) until the user flips it.
        on = defaults.object(forKey: "labs.on") as? Bool ?? true
        stored = Dictionary(uniqueKeysWithValues: all.compactMap { lab in
            // `bool(forKey:)` also reads a launch argument's "YES"; object(forKey:) tells never-set from off.
            defaults.object(forKey: "labs.enabled.\(lab.id)") == nil ? nil : (lab.id, defaults.bool(forKey: "labs.enabled.\(lab.id)"))
        })
        offFromPage = Set(defaults.stringArray(forKey: "labs.offFromPage") ?? [])
        recent = defaults.stringArray(forKey: "labs.recent") ?? []
        unlockedIds = Set(all.map(\.id).filter { defaults.bool(forKey: "labs.unlocked.\($0)") })
        storageLimitChoice = defaults.string(forKey: Self.storageLimitKey) ?? "auto"
    }

    /// The master switch at the bottom of Advanced: off, no lab shows anywhere.
    var labsOn: Bool {
        get { LabsBuild.experimental && on }
        set {
            DebugLog.settingChanged("labs.on", old: on, new: newValue)
            on = newValue
            defaults.set(newValue, forKey: "labs.on")
        }
    }

    /// BOAR's storage limit while Boar Labs is on (android `LabHooks` STORAGE_LIMIT): "auto" (the catalog's 50 GB), a
    /// number of GB, or "none" (only the phone's free space).
    var storageLimit: String {
        get { storageLimitChoice }
        set {
            storageLimitChoice = newValue
            defaults.set(newValue, forKey: Self.storageLimitKey)
        }
    }

    static let storageLimitChoices = ["auto", "25", "100", "200", "none"]
    nonisolated private static let storageLimitKey = "labs.storageLimit"

    /// Hands the downloads the user's limit, read at each download: theirs while Boar Labs is on, else nil (the catalog's).
    nonisolated static func installStorageLimit() {
        StorageBudget.userLimit = {
            let defaults = AppPaths.defaults
            guard LabsBuild.experimental, defaults.object(forKey: "labs.on") as? Bool ?? true else { return nil }
            return StorageBudget.limitBytes(choice: defaults.string(forKey: storageLimitKey))
        }
    }

    /// In the list's order: live, then beta, alpha, under review, classified; plugin.properties order within each. A
    /// deprecated plugin (Polyglot) is not listed (android `LabRegistry.visible`).
    var visible: [any LabPlugin] {
        all.enumerated().filter { !LabDefaults.deprecated.contains($0.element.id) }
            .sorted { ($0.element.status, $0.offset) < ($1.element.status, $1.offset) }.map(\.element)
    }

    /// The lab a tile opens: itself, a classified one's working lab once the user unlocked it, else nil.
    func opened(_ lab: any LabPlugin) -> (any LabPlugin)? {
        if lab.status != .classified { return lab }
        if let classified = lab as? ClassifiedLab, let inner = classified.inner, unlocked(lab.id) { return inner }
        return nil
    }

    func byId(_ id: String) -> (any LabPlugin)? {
        visible.first { $0.id == id }.flatMap(opened)
    }

    /// The labs that fill slots: open (not classified, or unlocked) and switched on, with Plugins on. A deprecated one
    /// (Polyglot) fills none, whatever its switch said before.
    var active: [any LabPlugin] {
        guard labsOn else { return [] }
        return visible.compactMap(opened).filter { enabled($0.id) && !LabDefaults.deprecated.contains($0.id) }
    }

    /// The tool slot's tools: safety first (Cohazard), then Boar Polyglot, then grid order.
    var activeTools: [any AnswerTool] {
        active.enumerated()
            .sorted { (LabTools.slotRank($0.element.id), $0.offset) < (LabTools.slotRank($1.element.id), $1.offset) }
            .compactMap(\.element.answerTool)
    }

    var activeChecks: [any AnswerCheck] { active.compactMap(\.answerCheck) }

    /// The id of a plugin that's off but would have answered `query` (Lunar for "what phase is the moon"), named under the
    /// model's answer; nil otherwise, and always with Plugins off (android `AnswerTools.offPlugin`, Nov 12).
    func offPlugin(_ query: String) -> String? {
        guard labsOn else { return nil }
        return visible.compactMap(opened).first { !enabled($0.id) && $0.recognizes(query) }?.id
    }

    /// The search stages of the labs switched on now, in grid order.
    var activeSearchStages: [any SearchStage] { active.compactMap(\.searchStage) }

    /// The More menu's lab rows for a finished answer, in grid order.
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction] { active.flatMap { $0.answerActions(answer) } }

    /// What the switched-on labs show under a finished answer's text, in grid order.
    func answerExtras(_ answer: AnswerRef) -> [(id: String, view: AnyView)] {
        active.compactMap { lab in lab.answerExtra(answer).map { (lab.id, $0) } }
    }

    /// A finished answer shows: each switched-on lab prepares what it reads of it.
    func prepareAnswer(_ answer: AnswerRef) async {
        for lab in active { await lab.prepareAnswer(answer) }
    }

    /// The footer's plugin notes for a finished answer, oldest first, so a new one is always the last line (android
    /// `LabHooks.AnswerNotes`: `sortedBy { it.at }`, a stable sort).
    func answerNotes(_ answer: AnswerRef) -> [LabAnswerNote] {
        active.flatMap { $0.answerNotes(answer) }.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }

    /// The chat erased: every lab drops what it made from it, switched on or not (android `UserData.Scope.CHATS`).
    func eraseUserData(_ scope: UserDataScope = .chats) { all.forEach { $0.eraseUserData(scope) } }

    /// One chat deleted: every lab drops what it kept of its answers, switched on or not (android `UserData.eraseAnswers`).
    func eraseAnswers(_ answerIds: [String]) {
        guard !answerIds.isEmpty else { return }
        all.forEach { $0.eraseAnswers(answerIds) }
    }

    /// What Press holds that "Also delete Press" would delete: its projects with something in them (android
    /// `UserData.pressProjects`, `PressStore.projectsWithContent`).
    var pressItems: Int { PressStore.shared.projectsWithContent }

    /// The switch as shown: the user's own choice, else the default-on list (`LabDefaults.switchOf`).
    func enabled(_ id: String) -> Bool { LabDefaults.switchOf(id, stored: stored[id]) }

    /// The user's own choice, nil while they never switched it (what an update turned on, what makes an install Pro).
    func storedChoice(_ id: String) -> Bool? { stored[id] }

    /// `fromPage`: the switch on the plugin's own page; an off plugin from there stays listed in the header sheet. A safety
    /// plugin goes off only once its question was answered (`confirmed`; `PluginReach.allowsSet`).
    func setEnabled(_ id: String, _ value: Bool, fromPage: Bool = false, confirmed: Bool = false) {
        guard PluginReach.allowsSet(id, on: value, confirmed: confirmed) else { return }
        DebugLog.settingChanged("labs.enabled.\(id)", old: enabled(id), new: value)
        stored[id] = value
        offFromPage = PluginReach.offFromPageAfter(offFromPage, id: id, on: value, fromPage: fromPage)
        defaults.set(value, forKey: "labs.enabled.\(id)")
        defaults.set(offFromPage.sorted(), forKey: "labs.offFromPage")
    }

    /// The header sheet's Off section: plugins switched off from their pages, and an off safety plugin.
    var offListed: [any LabPlugin] {
        guard labsOn else { return [] }
        let ids = PluginReach.offListed(visible.compactMap(opened).map(\.id), enabled: enabled, offFromPage: offFromPage)
        return ids.compactMap(byId)
    }

    /// The chat header's plugins icon: any plugin on, or one listed as off.
    var headerIconShown: Bool {
        labsOn && PluginReach.headerIconShown(activeIds: active.map(\.id), offListed: offListed.map(\.id))
    }

    /// The plugins in the header sheet: the last three used among those on (RecentPlugins).
    var recentShown: [any LabPlugin] {
        RecentPlugins.pick(active: active.map(\.id), recent: recent).compactMap { id in active.first { $0.id == id } }
    }

    /// A plugin's page opened, or one of its actions used: it moves to the front of the recent list.
    func used(_ id: String) {
        recent = RecentPlugins.used(recent, id: id)
        defaults.set(recent, forKey: "labs.recent")
    }

    /// Default-on plugins this install never switched: on because of the update (the one-time note names them).
    var turnedOnByUpdate: [any LabPlugin] {
        guard labsOn else { return [] }
        let ids = LabDefaults.turnedOnByUpdate(ids: visible.compactMap(opened).map(\.id), stored: { stored[$0] })
        return ids.compactMap(byId)
    }

    func revealed(_ id: String) -> Bool { revealedIds.contains(id) }
    func reveal(_ id: String) { revealedIds.insert(id) }
    /// Leaving Boar Labs covers every leaked tile again; ten-odd taps reveal it again.
    func coverAll() { if !revealedIds.isEmpty { revealedIds = [] } }

    /// A classified lab with code that the user leaked: unlocked for good, it opens like any lab.
    func unlocked(_ id: String) -> Bool { unlockedIds.contains(id) }

    func unlock(_ id: String) {
        unlockedIds.insert(id)
        defaults.set(true, forKey: "labs.unlocked.\(id)")
    }

    /// Who wrote an instant answer, from its receipt's tool code: the lab speaks by its tile's name, so the chat and the
    /// switch to turn it off say the same thing. `canBypass`: "Ask BOAR instead" is offered (not for the CO safety answer).
    struct Speaker: Equatable {
        let id: String
        let title: String
        let art: String?
        let emoji: String
        let canBypass: Bool
    }

    /// android LabHooks' AnswerTools.speaker: nil keeps BOAR.
    func speaker(tool: String) -> Speaker? {
        let code = tool.split(separator: "+", maxSplits: 1).first.map(String.init) ?? tool
        let id: String? = switch code {
        case "safety-fact-co-hazard", LabTools.coAcute: "cohazard"
        case _ where code.hasPrefix("calculator-travel-distance"): "distance"
        case _ where code.hasPrefix("calculator-"): "calc"
        case _ where code.hasPrefix("facts-"): "facts"
        case "language": "polyglot"
        case _ where code.hasPrefix("lunar-"): "lunar"
        case _ where code.hasPrefix("compass-"): "compass"
        case _ where code.hasPrefix("vitals-"): "pulse"
        default: nil
        }
        guard let lab = id.flatMap(byId) else { return nil }
        return Speaker(id: lab.id, title: lab.title, art: lab.art, emoji: lab.emoji, canBypass: lab.id != "cohazard")
    }
}

/// The name and picture an instant answer speaks with, over its text (BoarSpeakerLabel's row, with the lab's art).
/// A tap opens that plugin's page over the chat (android 18352f05: the picture and the name open the plugin's page).
struct LabSpeakerLabel: View {
    let speaker: Labs.Speaker
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .caption) private var side = 20

    var body: some View {
        Button { model.openPlugin(speaker.id) } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Answered by \(speaker.title)"))
            .accessibilityHint(Text("Open \(speaker.title)"))
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let art = speaker.art {
                Image(art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Text(verbatim: speaker.emoji).font(.subheadline)
            }
            Text(verbatim: speaker.title)
                .speakerStyle()
        }
        .contentShape(.rect)
    }
}

extension Labs {
    /// Every lab folder Android ships that iOS has (android `GENERATED_LABS`); each port adds its lab here. Designer,
    /// Press, Big Boar and Wisp are studied in docs/labs-ios.md before any port.
    static var registry: [any LabPlugin] {
        [
            DesignerLab(),
            VitalsLab(),
            CardsLab(),
            PressLab(),
            CompassLab(),
            LunarLab(),
            PolyglotLab(),
            CalcLab(),
            DistanceLab(),
            FactsLab(),
            GuardLab(),
            CoHazardLab(),
            ClassifiedLab(id: "dailyQuiz", order: 80, emoji: "❔", title: String(localized: "Daily Quiz"),
                          body: String(localized: "A short daily quiz from BOAR's library, offline. Right answers unlock Boar Avatars."),
                          inner: DailyQuizLab()),
            ClassifiedLab(id: "sanctuary", order: 85, emoji: "📚", title: String(localized: "Sanctuary"),
                          body: String(localized: "Knowledge packs you collect, keep and open on this \(Platform.deviceNoun): whole libraries, offline.")),
            ClassifiedLab(id: "signboard", order: 90, emoji: "📷", title: String(localized: "Signboard"),
                          body: String(localized: "Point the camera at a sign or a menu: read and translated, offline.")),
        ]
    }
}
