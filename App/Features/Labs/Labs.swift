import BoarAnswer
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
    /// The check slot: reads a model's finished answer and may repair it.
    var answerCheck: (any AnswerCheck)? { get }
    /// The experiment's page, below the shared header.
    func content() -> AnyView
    /// Rows in a finished answer's More menu (android `answerActions`, the 🧩 sheet).
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction]
    /// A small badge in the chat's toolbar (android `HeaderBadge`); `open` shows this lab's page.
    func headerBadge(open: @escaping () -> Void) -> AnyView?
    /// Erases what this lab made from the user's chats (android `eraseUserData`): runs with the chats' erase, even while
    /// the lab is switched off.
    func eraseUserData()
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
}

/// One row a lab adds to an answer's More menu. `done`: the action already happened (a checkmark; choosing it undoes it).
struct LabAnswerAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var done = false
    let run: @MainActor () -> Void
}

extension LabPlugin {
    var art: String? { nil }
    var reviewShort: String? { nil }
    var review: String? { nil }
    var answerTool: (any AnswerTool)? { nil }
    var answerCheck: (any AnswerCheck)? { nil }
    func content() -> AnyView { AnyView(EmptyView()) }
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction] { [] }
    func headerBadge(open: @escaping () -> Void) -> AnyView? { nil }
    func eraseUserData() {}
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
    private var enabledIds: Set<String>
    private var unlockedIds: Set<String>
    /// Classified tiles leaked with the easter egg: they last while Boar Labs is open (Android, Oct 19).
    private var revealedIds: Set<String> = []

    init(defaults: UserDefaults, labs: [any LabPlugin] = Labs.registry) {
        self.defaults = defaults
        all = labs.sorted { $0.order < $1.order }
        // The Labs build opens with Boar Labs on; every lab in it starts off.
        on = defaults.object(forKey: "labs.on") as? Bool ?? true
        enabledIds = Set(all.map(\.id).filter { defaults.bool(forKey: "labs.enabled.\($0)") })
        unlockedIds = Set(all.map(\.id).filter { defaults.bool(forKey: "labs.unlocked.\($0)") })
    }

    /// The master switch at the bottom of Advanced: off, no lab shows anywhere.
    var labsOn: Bool {
        get { LabsBuild.experimental && on }
        set {
            on = newValue
            defaults.set(newValue, forKey: "labs.on")
        }
    }

    /// In the grid's order: live, then beta, alpha, under review, classified; plugin.properties order within each.
    var visible: [any LabPlugin] {
        all.enumerated().sorted { ($0.element.status, $0.offset) < ($1.element.status, $1.offset) }.map(\.element)
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

    /// The labs that fill slots: open (not classified, or unlocked) and switched on, with Boar Labs on.
    var active: [any LabPlugin] {
        guard labsOn else { return [] }
        return visible.compactMap(opened).filter { enabled($0.id) }
    }

    /// The tool slot's tools: safety first (Boar Cohazard), then Boar Polyglot, then grid order.
    var activeTools: [any AnswerTool] {
        active.enumerated()
            .sorted { (LabTools.slotRank($0.element.id), $0.offset) < (LabTools.slotRank($1.element.id), $1.offset) }
            .compactMap(\.element.answerTool)
    }

    var activeChecks: [any AnswerCheck] { active.compactMap(\.answerCheck) }

    /// The More menu's lab rows for a finished answer, in grid order.
    func answerActions(_ answer: AnswerRef) -> [LabAnswerAction] { active.flatMap { $0.answerActions(answer) } }

    /// The chat erased: every lab drops what it made from it, switched on or not (android `UserData.Scope.CHATS`).
    func eraseUserData() { all.forEach { $0.eraseUserData() } }

    func enabled(_ id: String) -> Bool { enabledIds.contains(id) }

    func setEnabled(_ id: String, _ value: Bool) {
        if value { enabledIds.insert(id) } else { enabledIds.remove(id) }
        defaults.set(value, forKey: "labs.enabled.\(id)")
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
        let title: String
        let art: String?
        let emoji: String
        let canBypass: Bool
    }

    /// android LabHooks' AnswerTools.speaker: nil keeps BOAR.
    func speaker(tool: String) -> Speaker? {
        let code = tool.split(separator: "+", maxSplits: 1).first.map(String.init) ?? tool
        let id: String? = switch code {
        case "safety-fact-co-hazard": "cohazard"
        case _ where code.hasPrefix("calculator-travel-distance"): "distance"
        case _ where code.hasPrefix("calculator-"): "calc"
        case _ where code.hasPrefix("facts-"): "facts"
        case "language": "polyglot"
        default: nil
        }
        guard let lab = id.flatMap(byId) else { return nil }
        return Speaker(title: lab.title, art: lab.art, emoji: lab.emoji, canBypass: lab.id != "cohazard")
    }
}

/// The name and picture an instant answer speaks with, over its text.
struct LabSpeakerLabel: View {
    let speaker: Labs.Speaker

    var body: some View {
        HStack(spacing: 6) {
            if let art = speaker.art {
                Image(art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Text(verbatim: speaker.emoji).font(.subheadline)
            }
            Text(verbatim: speaker.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Answered by \(speaker.title)"))
    }
}

extension Labs {
    /// Every lab folder Android ships that iOS has (android `GENERATED_LABS`); each port adds its lab here. Designer,
    /// Press, Big Boar and Wisp are studied in docs/labs-ios.md before any port.
    static var registry: [any LabPlugin] {
        [
            VitalsLab(),
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
                          // Android's tile adds "Right answers unlock Boar Avatars."; the iOS app has no Vault yet.
                          body: String(localized: "A short daily quiz from BOAR's library, offline."),
                          inner: DailyQuizLab()),
            ClassifiedLab(id: "sanctuary", order: 85, emoji: "📚", title: String(localized: "Sanctuary"),
                          body: String(localized: "Knowledge packs you collect, keep and open on this \(Platform.deviceNoun): whole libraries, offline.")),
            ClassifiedLab(id: "signboard", order: 90, emoji: "📷", title: String(localized: "Signboard"),
                          body: String(localized: "Point the camera at a sign or a menu: read and translated, offline.")),
        ]
    }
}
