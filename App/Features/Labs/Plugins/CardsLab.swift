import BoarAnswer
import BoarCore
import BoarModels
import BoarRouting
import SwiftUI

/// Cards (android labs/plugins/canvas, v2.0.0: the Canvas plugin redesigned with adam, Nov 14; the id stays "canvas", so
/// the switch and saved cards read the same). Part of an answer becomes a native card: a chart, a table, a checklist, a
/// comparison or key facts.
/// - Only when asked: the answer's More menu has one row, which already says what the rules found ("Create a card" ·
///   "A chart of 3 numbers"). Rules first (CardRules): the app reads the answer's own text and draws at once, no model.
/// - Nothing found: "Nothing to draw here" · "Ask BOAR to make one · slower": the model makes it (Visual), its card still
///   checked against the answer and marked "made by the model · checked against the answer".
/// - The card sits under the answer's text, in the same bubble: title, where it came from, the body, one switch with only
///   the shapes that fit, ✕ to remove it.
/// - Steps are a checklist; the card and its ticks are kept in the answer's message meta, so they go with the chat.
struct CardsLab: LabPlugin {
    let id = "canvas"
    let order = 25
    let emoji = "📊"
    // Android's stand-in until Cards has its own icon (adam, Nov 10).
    let art: String? = "truffle_pixel_hacker"
    // BETA so it can start on (t9 0207 item 5).
    let status = LabStatus.beta
    var title: String { String(localized: "Cards") }
    var body: String { String(localized: "Turns part of an answer into a chart, table, checklist or key facts.") }

    /// The one row in the More menu, with what the rules found as its second line, so it is true before the tap.
    func answerActions(_ a: AnswerRef) -> [LabAnswerAction] {
        guard CardsModel.allowed(a) else { return [] }
        let model = CardsModel.shared
        let rowId = "canvas.card"
        let symbol = "chart.bar.doc.horizontal"
        if model.status(a.id) == .making {
            return [LabAnswerAction(id: rowId, title: title, systemImage: symbol, detail: String(localized: "Making a card…"), enabled: false) {}]
        }
        if model.shown(a) != nil {
            return [LabAnswerAction(id: rowId, title: title, systemImage: symbol, done: true,
                                    detail: String(localized: "The card is under the answer"), enabled: false) {}]
        }
        let cards = model.cards(a)
        let sources = CardsModel.titleSources(a)
        if let best = cards.first, let shape = best.shapes.first {
            return [LabAnswerAction(id: rowId, title: String(localized: "Create a card"), systemImage: symbol, detail: CardsModel.foundLine(cards)) {
                model.show(a, AnswerCard.of(best, shape, title: AnswerCard.titleFor(best, question: a.question, sources: sources)))
            }]
        }
        let fallback = AnswerCard.titleFor(.steps([]), question: a.question, sources: sources)
        return [LabAnswerAction(id: rowId, title: String(localized: "Nothing to draw here"), systemImage: symbol,
                                detail: String(localized: "Ask BOAR to make one · slower"), enabled: !model.busy && !a.chatBusy) {
            model.start(a, fallbackTitle: fallback)
        }]
    }

    /// Under the answer's text: the wait line, a refusal, or the card. Nil when there is none.
    func answerExtra(_ a: AnswerRef) -> AnyView? {
        let model = CardsModel.shared
        guard model.status(a.id) != nil || model.shown(a) != nil else { return nil }
        return AnyView(CardsExtra(a: a))
    }

    /// Reads the answer's card from its meta and what the rules find in it, off the main actor, once per answer.
    func prepareAnswer(_ a: AnswerRef) async {
        guard CardsModel.allowed(a) else { return }
        await CardsModel.shared.prepare(a)
    }

    /// Cards are kept in the answers' meta: they go with the chats. Here the memory (android `Canvas.eraseAll`).
    func eraseUserData(_ scope: UserDataScope) { CardsModel.shared.eraseAll() }

    func content() -> AnyView { AnyView(CardsPage()) }
}

/// Cards' state for each answer (android `Canvas`). The card shown and its ticks are read from the answer's meta and
/// written back to it; while the model makes one, or when it failed, the state is in memory only.
@MainActor
@Observable
final class CardsModel {
    static let shared = CardsModel()

    enum Status: Equatable {
        /// The model is reading the answer.
        case making
        /// `detail`: what was refused (a number, a label); `raw`: the model's reply, to see where it went wrong (this run only).
        case failed(Failure, detail: String?, raw: String?)
    }

    enum Failure: Equatable {
        case busy, noModel, failed, noCard, nothing, invented, ungrounded, unpaired

        var text: String {
            switch self {
            case .busy: String(localized: "A chat answer is being written. Try again when it ends.")
            case .noModel: String(localized: "No answer model is loaded. Ask something first, then try again.")
            case .failed: String(localized: "The model stopped before it finished. Try again.")
            case .noCard: String(localized: "The model didn't write a card BOAR can draw. Try again; bigger models do better.")
            case .nothing: String(localized: "The model found nothing in this answer worth a card.")
            case .invented: String(localized: "The card had a number that isn't in the answer, so BOAR dropped it.")
            case .ungrounded: String(localized: "The card named something that isn't in the answer, so BOAR dropped it.")
            case .unpaired: String(localized: "A number on the card belongs to another item in the answer, so BOAR dropped it.")
            }
        }

        static func of(_ reason: Visual.Reason) -> Failure {
            switch reason {
            case .nothing: .nothing
            case .inventedNumbers: .invented
            case .ungroundedLabels: .ungrounded
            case .unpaired: .unpaired
            default: .noCard
            }
        }
    }

    /// "Read, no card" (card nil) differs from "not read yet" (no entry). `text`: the answer's text when it was read; an
    /// answer written again under the same id is read again.
    private struct Shown {
        var card: AnswerCard?
        var text: Int
    }

    private struct Found {
        var cards: [CardRules.Card]
        var text: Int
    }

    private var statuses: [String: Status] = [:]
    private var shownCards: [String: Shown] = [:]
    private var ticksById: [String: Set<Int>] = [:]
    private var found: [String: Found] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// The chat whose model makes a card now: ✕ and the erase stop it there.
    @ObservationIgnored private weak var makingIn: ChatController?
    /// Meta writes, one after another, so two quick ticks can't undo each other.
    @ObservationIgnored private var writes: Task<Void, Never>?

    var busy: Bool { statuses.values.contains(.making) }

    func status(_ id: String) -> Status? { statuses[id] }

    /// The card shown under `a`, nil when none or not read yet (`prepare` reads it).
    func shown(_ a: AnswerRef) -> AnswerCard? {
        shownCards[a.id].flatMap { $0.text == a.text.hashValue ? $0.card : nil }
    }

    func ticks(_ id: String) -> Set<Int> { ticksById[id] ?? [] }

    /// The rules' cards for `a`, found off the main actor by `prepare` as the answer shows; none until then (android
    /// `cardsOf`'s empty start: the menu is built with every footer, and the rules can take a second on a long answer).
    func cards(_ a: AnswerRef) -> [CardRules.Card] {
        found[a.id].flatMap { $0.text == a.text.hashValue ? $0.cards : nil } ?? []
    }

    /// Not a tool's fixed answer, nor a health or seed-phrase one: a made-up dose table or wallet card is what BOAR must
    /// never draw.
    static func allowed(_ a: AnswerRef) -> Bool {
        a.tool == nil && a.styleNote == nil && !a.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !QueryContext.isHealthQuestion(a.question) && !QueryContext.isSeedPhraseQuestion(a.question)
    }

    /// The sources a card's title may come from: a pack's, never a user's own file (its title is its file name).
    static func titleSources(_ a: AnswerRef) -> [String] {
        AnswerCard.titleSources(a.sources.map { (title: $0.0, source: $0.1) })
    }

    /// "A chart of 3 numbers", or the best two: "A checklist of 4 steps, or a chart of 4 numbers".
    static func foundLine(_ cards: [CardRules.Card]) -> String {
        let lines = cards.prefix(2).map { card -> String in
            let (kind, n) = AnswerCard.found(card)
            switch kind {
            case .chart: return String(localized: "A chart of \(n) numbers")
            case .table: return String(localized: "A table of \(n) rows")
            case .steps: return String(localized: "A checklist of \(n) steps")
            case .facts: return String(localized: "\(n) key facts")
            case .compare:
                switch min(max(n, 2), 4) {
                case 2: return String(localized: "Two things compared")
                case 3: return String(localized: "Three things compared")
                default: return String(localized: "Four things compared")
                }
            }
        }
        guard lines.count == 2 else { return lines.first ?? "" }
        let second = lines[1].prefix(1).lowercased() + lines[1].dropFirst()
        return String(localized: "\(lines[0]), or \(second)")
    }

    /// Reads `a`'s card and ticks from its meta, and what the rules find in its text, off the main actor.
    func prepare(_ a: AnswerRef) async {
        let id = a.id, question = a.question, text = a.text, hash = a.text.hashValue
        if found[id]?.text != hash {
            let cards = await Task.detached(priority: .utility) {
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : CardRules.find(question, text)
            }.value
            found[id] = Found(cards: cards, text: hash)
        }
        guard shownCards[id]?.text != hash, let services = a.chat?.services, !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }
        let meta = (try? await services.background { try $0.chats.messageMeta(messageId: id) }) ?? nil
        shownCards[id] = Shown(card: AnswerCard.fromMeta(meta), text: hash)
        ticksById[id] = AnswerCard.ticksFromMeta(meta)
    }

    /// Shows `card` under `a` (or removes it, nil), saved in the answer's meta.
    func show(_ a: AnswerRef, _ card: AnswerCard?) {
        shownCards[a.id] = Shown(card: card, text: a.text.hashValue)
        if card == nil {
            ticksById[a.id] = []
            statuses[a.id] = nil
        }
        writeMeta(a.chat?.services, a.id) { AnswerCard.withCard($0, card) }
    }

    /// Ticks or unticks step `i` of `a`'s checklist, saved with the answer.
    func tick(_ a: AnswerRef, _ i: Int) {
        var now = ticks(a.id)
        if now.contains(i) { now.remove(i) } else { now.insert(i) }
        ticksById[a.id] = now
        let ticks = now
        writeMeta(a.chat?.services, a.id) { AnswerCard.withTicks($0, ticks) }
    }

    private func writeMeta(_ services: BoarServices?, _ id: String, _ change: @escaping @Sendable (String?) -> String?) {
        guard let services else { return }
        let previous = writes
        writes = Task {
            await previous?.value
            // An answer with no meta row yet is a message all the same: the card or ticks start one.
            _ = try? await services.background { s in
                if let meta = change(try s.chats.messageMeta(messageId: id)) { try s.chats.setMessageMeta(messageId: id, meta: meta) }
            }
        }
    }

    /// The model's card for `a`, only when the rules found nothing (the "slower" row). It runs as the chat's own work, so
    /// a question sent meanwhile waits its turn; busy now, it says so instead.
    func start(_ a: AnswerRef, fallbackTitle: String) {
        guard !busy, let chat = a.chat else { return }
        let id = a.id
        let job = ModelJob(id: id, sessionId: a.sessionId, question: a.question, text: a.text, passages: a.passages,
                           fallbackTitle: fallbackTitle, services: chat.services)
        guard chat.runForLab({ [weak self] in await self?.make(job) }) else {
            statuses[id] = .failed(.busy, detail: nil, raw: nil)
            return
        }
        makingIn = chat
        statuses[id] = .making
    }

    /// What the model's card is made from, read when it starts.
    private struct ModelJob: @unchecked Sendable {
        let id: String
        let sessionId: String?
        let question: String
        let text: String
        let passages: [(title: String, body: String)]
        let fallbackTitle: String
        let services: BoarServices
    }

    private func make(_ job: ModelJob) async {
        let services = job.services
        // Only the model the chat already has: a card never loads one (a model that may not fit asks first, in the chat).
        let session: (any TextModelSession)? = services.backend == .llama && services.host.current == nil ? nil : await services.activeSession()
        let earlier = (try? await services.background { s in try Self.earlier(s.chats, job) }) ?? .none
        // A number the answer leaves out may be in its own sources (Brazil's area in "Economy of Brazil").
        let fromSources = VisualContext.fromSources(job.question, job.text, job.passages)
        let context = [earlier.sourceText, fromSources.sourceText].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        var raw: String?
        var threw = false
        if let session {
            do {
                raw = try await SessionEngine(session).generate(
                    system: Visual.prompt, user: VisualContext.prompt(job.question, job.text, earlier, fromSources),
                    nPredict: 700, temperature: 0.2, timeoutMs: 180_000, onToken: nil
                ).text
            } catch {
                threw = true
            }
        }
        let grounding = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? job.text : job.text + "\n" + context
        let reply = raw
        let parsed = await Task.detached(priority: .userInitiated) { reply.map { Visual.parse($0, answer: grounding, userText: job.question) } }.value
        makingIn = nil
        // Removed (✕) or erased while it was being made: nothing is kept.
        guard statuses[job.id] == .making else { return }
        switch parsed {
        case .ok(let visual, let leftOut):
            statuses[job.id] = nil
            let card = AnswerCard.ofVisual(visual, leftOut: leftOut, fallbackTitle: job.fallbackTitle, answer: job.text)
            shownCards[job.id] = Shown(card: card, text: job.text.hashValue)
            writeMeta(services, job.id) { AnswerCard.withCard($0, card) }
        case .rejected(let reason, let detail):
            statuses[job.id] = .failed(.of(reason), detail: detail.map { String($0.prefix(60)) }, raw: raw)
        case nil:
            statuses[job.id] = .failed(threw ? .failed : .noModel, detail: nil, raw: nil)
        }
    }

    /// The earlier exchanges of the chat, before this answer (VisualContext keeps the ones on the same topic).
    nonisolated private static func earlier(_ chats: ChatStore, _ job: ModelJob) throws -> VisualContext.Earlier {
        guard let session = job.sessionId else { return .none }
        var exchanges: [VisualContext.Exchange] = []
        var question: String?
        for m in try chats.messages(sessionId: session) {
            if m.id == job.id { break }
            if m.role == "user" {
                question = m.text
            } else if m.role == "assistant", let q = question {
                exchanges.append(VisualContext.Exchange(q, AnswerText.stripThinking(m.text)))
                question = nil
            }
        }
        return VisualContext.earlier(VisualContext.Exchange(job.question, job.text), exchanges)
    }

    /// Stops the model's card for `id` and forgets its state (✕ on a wait or a failure).
    func cancel(_ id: String) {
        if statuses[id] == .making { makingIn?.stop() }
        statuses[id] = nil
    }

    func eraseAll() {
        if busy { makingIn?.stop() }
        statuses = [:]
        shownCards = [:]
        ticksById = [:]
        found = [:]
    }
}

/// Under an answer's text: the wait line, a refusal, or the card with its switch.
private struct CardsExtra: View {
    let a: AnswerRef

    var body: some View {
        let model = CardsModel.shared
        VStack(alignment: .leading, spacing: 8) {
            switch model.status(a.id) {
            case .making:
                Text("📊 BOAR is reading the answer to make a card…")
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.success))
            case .failed(let failure, let detail, let raw):
                CardFailed(id: a.id, failure: failure, detail: detail, raw: raw)
            case nil:
                EmptyView()
            }
            if let card = model.shown(a) {
                // The switch: every shape of every card the rules found; none for the model's card (it has the one it made).
                let cards = card.byModel ? [] : model.cards(a)
                let choices = AnswerCard.choices(cards)
                let current = choices.first { ch in
                    ch.shape == card.shape && AnswerCard.of(cards[ch.card], ch.shape, title: "").body == card.body
                }
                CardView(card: card, choices: choices, current: current, ticks: model.ticks(a.id),
                         onPick: { ch in
                             let picked = cards[ch.card]
                             model.show(a, AnswerCard.of(picked, ch.shape, title: AnswerCard.titleFor(picked, question: a.question, sources: CardsModel.titleSources(a))))
                         },
                         onTick: { model.tick(a, $0) },
                         onRemove: { model.show(a, nil) })
            }
        }
    }
}

/// Why the model's card wasn't drawn, what was refused, and the model's reply on demand; ✕ forgets it.
private struct CardFailed: View {
    let id: String
    let failure: CardsModel.Failure
    let detail: String?
    let raw: String?
    @State private var open = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: failure.text)
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
                Button("Close", systemImage: "xmark") { CardsModel.shared.cancel(id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.boar("mono.xs"))
                    .foregroundStyle(.boar(.dim))
            }
            if let detail {
                Text("Refused: \(detail) (not in the answer)")
                    .font(.boar("mono.xs").weight(.bold))
                    .foregroundStyle(.boar(.warning))
            }
            if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(open ? "Hide what the model wrote" : "Show what the model wrote") { open.toggle() }
                    .buttonStyle(.plain)
                    .font(.boar("mono.xs").weight(.bold))
                    .foregroundStyle(.boar(.link))
                if open {
                    Text(verbatim: String(raw.prefix(4000)))
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.secondary))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(palette.bgSubtle), in: .rect(cornerRadius: 8))
                }
            }
        }
    }
}

/// The card under an answer's text, in the same bubble (adam, Nov 14): a rule above it, the title and where it came from,
/// ✕, the body, then the switch when more than one shape fits. Theme tokens only.
struct CardView: View {
    let card: AnswerCard
    let choices: [AnswerCard.Choice]
    let current: AnswerCard.Choice?
    let ticks: Set<Int>
    let onPick: (AnswerCard.Choice) -> Void
    let onTick: (Int) -> Void
    let onRemove: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Color(palette.borderSubtle))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if !card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: card.title)
                            .font(.boar("ui.titleSm").weight(.semibold))
                            .foregroundStyle(.boar(.heading))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(card.byModel ? "made by the model · checked against the answer" : "from this answer")
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.dim))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onRemove {
                    Button("Remove the card", systemImage: "xmark", action: onRemove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.boar("ui.body"))
                        .foregroundStyle(.boar(.muted))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
            }
            CardBody(card: card, ticks: ticks, onTick: onTick)
            if !card.leftOut.isEmpty {
                Text("⚠ Left out, not in the answer, the earlier answers or the sources: \(card.leftOut.prefix(8).joined(separator: ", ")). Check the sources before trusting this card.")
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.warning))
            }
            if choices.count > 1 {
                FlowChips(spacing: 6) {
                    ForEach(choices, id: \.self) { ch in
                        ShapePill(shape: ch.shape, on: ch == current) { onPick(ch) }
                    }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

/// One shape in the switch: the accent ring and tint when on, as the plugin pages' pills.
private struct ShapePill: View {
    let shape: CardRules.Shape
    let on: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(Self.label(shape))
                .font(.boar("ui.caption"))
                .lineLimit(1)
                .foregroundStyle(on ? Color(palette.textAccentEmerald) : Color(palette.textSecondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(on ? Color(palette.emeraldBgSubtle) : Color(palette.bgCard), in: .capsule)
                .overlay { Capsule().strokeBorder(on ? Color(palette.emerald400) : Color(palette.borderDefault), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func label(_ shape: CardRules.Shape) -> LocalizedStringResource {
        switch shape {
        case .bars: "Bars"
        case .line: "Line"
        case .pie: "Pie"
        case .table: "Table"
        case .checklist: "Steps"
        case .facts: "Facts"
        case .compare: "Side by side"
        }
    }
}

private struct CardBody: View {
    let card: AnswerCard
    let ticks: Set<Int>
    let onTick: (Int) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        switch card.body {
        case .series(let unit, let points):
            switch card.shape {
            case .pie: CardPie(unit: unit, points: points)
            case .line: CardLine(points: points)
            case .table: CardTable(header: [], rows: points.map { [$0.label, $0.written] })
            default: CardBars(points: points)
            }
        case .table(let header, let rows):
            CardTable(header: header, rows: rows)
        case .steps(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, step in
                    stepRow(i, step)
                }
                Text("\(ticks.filter { items.indices.contains($0) }.count) of \(items.count) done · kept with this chat")
                    .font(.boar("mono.xs"))
                    .foregroundStyle(.boar(.dim))
            }
        case .compare(let sides):
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(sides.enumerated()), id: \.offset) { _, side in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: side.name)
                                .font(.boar("ui.titleSm").weight(.semibold))
                                .foregroundStyle(.boar(.success))
                            ForEach(Array(side.points.enumerated()), id: \.offset) { _, point in
                                Text(verbatim: "• \(point)")
                                    .font(.boar("ui.caption"))
                                    .foregroundStyle(.boar(.primary))
                            }
                        }
                        .padding(10)
                        .frame(width: sides.count <= 2 ? 160 : 140, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(palette.bgSubtle), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .scrollIndicators(.hidden)
        case .facts(let facts):
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(verbatim: fact.label)
                            .font(.boar("ui.caption"))
                            .foregroundStyle(.boar(.secondary))
                        Text(verbatim: fact.value)
                            .font(.boar("ui.body"))
                            .foregroundStyle(.boar(.primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// A checkbox VoiceOver reads as checked or not, 44 pt tall at least.
    private func stepRow(_ i: Int, _ step: String) -> some View {
        let done = ticks.contains(i)
        return Button { onTick(i) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Color(palette.emerald500) : Color(palette.bgSubtle))
                    Circle().strokeBorder(done ? Color(palette.emerald500) : Color(palette.borderDefault), lineWidth: 1)
                    Text(verbatim: done ? "✓" : "\(i + 1)")
                        .font(.boar("mono.xs").weight(.bold))
                        .foregroundStyle(done ? Color(palette.textInverse) : Color(palette.textSecondary))
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                Text(verbatim: step)
                    .font(.boar("ui.body"))
                    .foregroundStyle(done ? Color(palette.textMuted) : Color(palette.textPrimary))
                    .strikethrough(done)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(done ? Text("Checked") : Text("Not checked"))
    }
}

/// Each label, its value as the answer writes it, and a bar from zero.
private struct CardBars: View {
    let points: [CardRules.Point]
    @Environment(\.palette) private var palette

    var body: some View {
        let max = points.map { abs($0.value) }.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: p.label)
                            .font(.boar("ui.caption"))
                            .foregroundStyle(.boar(.primary))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: p.written)
                            .font(.boar("mono.xs"))
                            .foregroundStyle(.boar(.secondary))
                    }
                    Capsule()
                        .fill(Color(palette.bgSubtle))
                        .frame(height: 10)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule()
                                    .fill(Color(palette.emerald500))
                                    .frame(width: g.size.width * min(1, Swift.max(0.02, abs(p.value) / max)))
                            }
                        }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A table: an optional header in small capitals, a hairline between rows; wide ones scroll sideways.
private struct CardTable: View {
    let header: [String]
    let rows: [[String]]
    @Environment(\.palette) private var palette

    private var columns: Int { Swift.max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        if columns > 2 {
            ScrollView(.horizontal) { grid(wide: true) }
                .scrollIndicators(.hidden)
        } else {
            grid(wide: false)
        }
    }

    private func grid(wide: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            if header.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { i in
                        Text(verbatim: (i < header.count ? header[i] : "").uppercased())
                            .font(.boar("ui.micro").weight(.bold))
                            .foregroundStyle(.boar(.secondary))
                            .padding(.bottom, 4)
                            .frame(minWidth: wide ? 72 : nil, maxWidth: wide ? 180 : .infinity, alignment: .leading)
                    }
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle()
                    .fill(Color(palette.borderSubtle))
                    .frame(height: 1)
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<columns, id: \.self) { i in
                        let last = !wide && i == columns - 1 && columns == 2
                        Text(verbatim: i < row.count ? row[i] : "")
                            .font(.boar("ui.body"))
                            .foregroundStyle(.boar(.primary))
                            .multilineTextAlignment(last ? .trailing : .leading)
                            .padding(.vertical, 6)
                            .frame(minWidth: wide ? 72 : nil, maxWidth: wide ? 180 : .infinity, alignment: last ? .trailing : .leading)
                    }
                }
            }
        }
    }
}

/// The parts of a whole (a pie only when the rules or the model say they are): a donut and each part's value and share.
private struct CardPie: View {
    let unit: String
    let points: [CardRules.Point]
    @Environment(\.palette) private var palette

    var body: some View {
        let values = points.map { Swift.max(0, $0.value) }
        let total = values.reduce(0, +) > 0 ? values.reduce(0, +) : 1
        let percents = AnswerCard.percents(points)
        let colors = CardColors.of(palette)
        HStack(spacing: 16) {
            ZStack {
                ForEach(Array(values.enumerated()), id: \.offset) { i, _ in
                    let start = values.prefix(i).reduce(0, +) / total
                    let end = start + values[i] / total
                    Circle()
                        .trim(from: start, to: end)
                        .stroke(colors[i % colors.count], lineWidth: 104 * 0.22)
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(104 * 0.11)
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[i % colors.count])
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(verbatim: "\(p.label)  \(p.written)" + (unit != "%" && i < percents.count ? "  (\(percents[i])%)" : ""))
                            .font(.boar("ui.caption"))
                            .foregroundStyle(.boar(.primary))
                    }
                }
            }
        }
    }
}

/// Points in order (a line only for years in order, or the model's line), each with its value; the labels under it.
private struct CardLine: View {
    let points: [CardRules.Point]
    @Environment(\.palette) private var palette

    var body: some View {
        let values = points.map(\.value)
        let axis = VisualScale.axis(values, fromZero: false)
        let line = Color(palette.emerald500)
        let grid = Color(palette.borderSubtle)
        let valueColor = Color(palette.textSecondary)
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let span = axis.max - axis.min > 0 ? axis.max - axis.min : 1
                func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - axis.min) / span) }
                func x(_ i: Int) -> CGFloat { values.count == 1 ? size.width / 2 : size.width * CGFloat(i) / CGFloat(values.count - 1) }
                for tick in axis.ticks {
                    var rule = Path()
                    rule.move(to: CGPoint(x: 0, y: y(tick)))
                    rule.addLine(to: CGPoint(x: size.width, y: y(tick)))
                    context.stroke(rule, with: .color(grid), lineWidth: 1)
                }
                var path = Path()
                for (i, v) in values.enumerated() {
                    if i == 0 { path.move(to: CGPoint(x: x(i), y: y(v))) } else { path.addLine(to: CGPoint(x: x(i), y: y(v))) }
                }
                context.stroke(path, with: .color(line), lineWidth: 2)
                for (i, v) in values.enumerated() {
                    let c = CGPoint(x: x(i), y: y(v))
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(line))
                    let text = context.resolve(Text(verbatim: points[i].written).font(.boar("mono.xs")).foregroundStyle(valueColor))
                    let w = text.measure(in: size).width
                    let left = Swift.min(Swift.max(0, c.x - w / 2), Swift.max(0, size.width - w))
                    context.draw(text, at: CGPoint(x: left, y: c.y - 6), anchor: .bottomLeading)
                }
            }
            .frame(height: 150)
            .padding(.top, 14)
            .padding(.horizontal, 6)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: points.map { "\($0.label): \($0.written)" }.joined(separator: ", ")))
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    Text(verbatim: p.label)
                        .font(.boar("ui.micro"))
                        .foregroundStyle(.boar(.secondary))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The parts' colours: the theme's own accents and their shades, no fixed hues.
private enum CardColors {
    static func of(_ p: BoarPalette) -> [Color] {
        [p.emerald500, p.cyan400, p.amber400, p.crimson400, p.textAccentViolet, p.emerald600, p.cyan600, p.amber600].map { Color($0) }
    }
}

/// The plugin page: its example is a live card (bars or a table), and the Try rows ask questions whose answers hold one.
private struct CardsPage: View {
    @State private var shape = CardRules.Shape.bars

    private var example: AnswerCard {
        AnswerCard(shape, String(localized: "Highest mountains"), .series(unit: "m", points: [
            CardRules.Point("Everest", "8,849 m", 8849), CardRules.Point("K2", "8,611 m", 8611),
            CardRules.Point("Kangchenjunga", "8,586 m", 8586),
        ]))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("EXAMPLE")
                    .font(.boar("ui.caption").weight(.bold))
                    .foregroundStyle(.boar(.muted))
                Text("From an answer about the highest mountains:")
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.secondary))
                let choices = [AnswerCard.Choice(0, .bars), AnswerCard.Choice(0, .table)]
                CardView(card: example, choices: choices, current: choices.first { $0.shape == shape }, ticks: [],
                         onPick: { shape = $0.shape }, onTick: { _ in }, onRemove: nil)
            }
            .padding(.vertical, 4)
        }
        PluginPage(
            tries: [String(localized: "What are the three highest mountains, and how tall is each?"),
                    String(localized: "How do you purify water in the wild, step by step?")],
            how: String(localized: "• Under any answer, open More (⋯). The Cards row already says what it can draw: \"A chart of 3 numbers\", \"A checklist of 5 steps\".\n• Create a card draws it at once, from the answer's own text, with no second model run: a chart, a table, a checklist, a comparison or key facts.\n• The card sits under the answer. When more than one shape fits, switch between them; a pie only for parts of a whole, a line only for years in order.\n• Tick the steps of a checklist; the ticks are kept with the chat.\n• Nothing to draw? Ask BOAR to make one. It is slower, and its card is still checked against the answer: a number or name that isn't there is left out.\n• Nothing for health or seed-phrase questions."),
            tryHint: String(localized: "Ask one of these, then open More (⋯) under the answer."))
    }
}
