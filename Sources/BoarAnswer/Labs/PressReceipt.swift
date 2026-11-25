import BoarRAG
import BoarRouting
import Foundation

/// What every Press document prints besides its blocks (android engine `labs/PressReceipt.kt`): ONE numbered list of
/// sources for the whole document, each answer's "Sources [n]" pointing into it (`build` numbers them in the order they
/// first appear; a source two answers share keeps one number), and the footer under a short rule (the models; "Made
/// offline with BOAR" and the date, always). The paper, the PDF and the Markdown all use it. `rows` is the older
/// "How this document was made" receipt, kept for its words (the paper and the PDF draw the footer since Nov 13).
public enum PressReceipt {
    public enum Shape: Sendable, Equatable {
        case square, portrait, wide

        public static func of(_ width: Int, _ height: Int) -> Shape? {
            if width <= 0 || height <= 0 { return nil }
            if width * 10 > height * 11 { return .wide }
            if height * 10 > width * 11 { return .portrait }
            return .square
        }
    }

    /// One model's answers: how many, and its speed (one value, or the slowest to the fastest).
    public struct ModelLine: Sendable, Equatable {
        public var model: String
        public var answers: Int
        public var minTokPerSec: Double?
        public var maxTokPerSec: Double?
        public init(_ model: String, _ answers: Int, _ minTokPerSec: Double?, _ maxTokPerSec: Double?) {
            self.model = model; self.answers = answers; self.minTokPerSec = minTokPerSec; self.maxTokPerSec = maxTokPerSec
        }
    }

    public struct Drawing: Sendable, Equatable {
        public var style: String?
        public var shape: Shape?
        public var width: Int
        public var height: Int
        public var seed: Int64?
        public init(_ style: String?, _ shape: Shape?, _ width: Int, _ height: Int, _ seed: Int64?) {
            self.style = style; self.shape = shape; self.width = width; self.height = height; self.seed = seed
        }
    }

    public struct Receipt: Sendable, Equatable {
        public var answers: Int
        public var models: [ModelLine]
        public var drawings: [Drawing]
        public var photos: Int
        /// The document's sources, in number order: [n] is sources[n - 1].
        public var sources: [PressDoc.Source]
        /// Each answer block's numbers, in its own sources' order: the ones it cites when its text was changed (G-5).
        public var refs: [String: [Int]]
        /// Each answer's own [k] → the document's number; a [k] not in it prints as nothing (G-5b).
        public var local: [String: [Int: Int]]
    }

    private struct SourceKey: Hashable { let title: String; let source: String? }

    /// `recipeOf` reads a drawing's recipe (the app reads Designer's files; the block's own copy by default), `sizeOf`
    /// its pixels when the block doesn't know them.
    public static func build(_ project: PressDoc.Project,
                             recipeOf: (PressDoc.Picture) -> PressDoc.Recipe? = { $0.recipe },
                             sizeOf: (PressDoc.Picture) -> (Int, Int)? = { _ in nil }) -> Receipt {
        var sources: [PressDoc.Source] = []
        var numberOf: [SourceKey: Int] = [:]
        var refs: [String: [Int]] = [:]
        var local: [String: [Int: Int]] = [:]
        var modelOrder: [String] = []
        var speeds: [String: [Double?]] = [:]
        var drawings: [Drawing] = []
        var photos = 0
        var answers = 0
        for block in project.blocks {
            switch block {
            case .answer(let b):
                answers += 1
                // A changed text keeps only the sources it still cites (G-5); the chat's answer as it came keeps them all.
                let cited = b.edited ? PressRewrite.marks(b.text) : nil
                var map: [Int: Int] = [:]
                var order: [Int] = []
                for (i, s) in b.sources.enumerated() {
                    if let cited, !cited.contains(i + 1) { continue }
                    let key = SourceKey(title: s.title.kotlinTrim().lowercased(), source: s.source?.kotlinTrim().lowercased())
                    let n: Int
                    if let known = numberOf[key] { n = known } else { sources.append(s); n = sources.count; numberOf[key] = n }
                    map[i + 1] = n
                    order.append(n)
                }
                var seen = Set<Int>()
                refs[b.id] = order.filter { seen.insert($0).inserted }
                local[b.id] = map
                if let m = b.model, !PressDoc.isBlank(m) {
                    if speeds[m] == nil { modelOrder.append(m); speeds[m] = [] }
                    speeds[m]!.append(b.tokPerSec)
                }
            case .picture(let b):
                if b.kind == .photo { photos += 1; continue }
                let r = recipeOf(b) ?? b.recipe
                let (w, h) = b.width > 0 && b.height > 0 ? (b.width, b.height) : sizeOf(b) ?? (0, 0)
                drawings.append(Drawing(r?.style, Shape.of(w, h), w, h, r?.seed))
            default:
                break
            }
        }
        let models = modelOrder.map { m in
            let list = speeds[m] ?? []
            let known = list.compactMap { $0 }.filter { $0 > 0 }
            return ModelLine(m, list.count, known.min(), known.max())
        }
        return Receipt(answers: answers, models: models, drawings: drawings, photos: photos, sources: sources, refs: refs, local: local)
    }

    /// The words, from the app's strings. `madeValue` has {{date}} and {{version}}; `seed` has {{seed}}; `styleName`
    /// turns a Designer style key into its name.
    public struct Labels: Sendable {
        public var title = "HOW THIS DOCUMENT WAS MADE"
        public var made = "Made"
        public var madeValue = "{{date}}, offline, on this phone · BOAR {{version}}"
        public var answers = "Answers"
        public var drawings = "Drawings"
        public var photos = "Photos"
        public var photosValue = "{{count}} from this phone"
        public var sources = "Sources"
        public var footer = "compiled offline with BOAR"
        /// The footer's last line, after the models; {{date}}.
        public var madeWith = "Made offline with BOAR · {{date}}"
        public var designer = "Designer"
        public var seed = "seed {{seed}}"
        public var square = "square"
        public var portrait = "portrait"
        public var wide = "wide"
        public var low = "low quality"
        public var medium = "medium quality"
        public var high = "high quality"
        /// A user's own file in the Sources section: its name never prints (validator R-A1).
        public var ownFile = "Your own file"
        public var styleName: @Sendable (String) -> String = { k in k.prefix(1).uppercased() + k.dropFirst() }

        public init() {}
    }

    /// One row of the receipt: its label, its lines; `numbered` for the sources (1., 2., …).
    public struct Row: Sendable, Equatable {
        public var label: String
        public var lines: [String]
        public var numbered: Bool
        public init(_ label: String, _ lines: [String], numbered: Bool = false) { self.label = label; self.lines = lines; self.numbered = numbered }
    }

    static func one(_ v: Double) -> String { JavaNumber.fixed(v, decimals: 1) }

    public static func speed(_ v: Double) -> String { one(v) + " tok/s" }

    public static func modelText(_ m: ModelLine) -> String {
        guard let lo = m.minTokPerSec, let hi = m.maxTokPerSec else { return m.model }
        return one(lo) == one(hi) ? "\(m.model) · \(speed(lo))" : "\(m.model) · \(one(lo))–\(one(hi)) tok/s"
    }

    public static func drawingText(_ d: Drawing, _ l: Labels) -> String {
        var parts = [l.designer]
        if let style = d.style, !PressDoc.isBlank(style) { parts.append(l.styleName(style)) }
        // Shape and quality in words, as Designer says them; no pixel numbers.
        if let s = d.shape {
            var t = switch s { case .square: l.square; case .portrait: l.portrait; case .wide: l.wide }
            if d.width > 0 && d.height > 0 {
                let q = switch DesignerCanvas.Size(d.width, d.height).quality { case .low: l.low; case .medium: l.medium; case .high: l.high }
                t += ", " + q
            }
            parts.append(t)
        }
        if let seed = d.seed { parts.append(l.seed.replacingOccurrences(of: "{{seed}}", with: String(seed))) }
        return parts.joined(separator: " · ")
    }

    /// The receipt's rows; "Made" is always there, the others when the document has them.
    public static func rows(_ r: Receipt, _ l: Labels, date: String, version: String) -> [Row] {
        var out = [Row(l.made, [l.madeValue.replacingOccurrences(of: "{{date}}", with: date).replacingOccurrences(of: "{{version}}", with: version)])]
        if r.answers > 0 { out.append(Row(l.answers, [String(r.answers)] + r.models.map(modelText))) }
        if !r.drawings.isEmpty { out.append(Row(l.drawings, r.drawings.map { drawingText($0, l) })) }
        if r.photos > 0 { out.append(Row(l.photos, [l.photosValue.replacingOccurrences(of: "{{count}}", with: String(r.photos))])) }
        if !r.sources.isEmpty { out.append(Row(l.sources, r.sources.map { sourceText($0, ownFile: l.ownFile) }, numbered: true)) }
        return out
    }

    /// What a document prints besides its blocks, from Press settings (adam, Nov 14): the date under the title, the
    /// sources at the end, the models and their speed; "Made with BOAR" always.
    public struct Options: Sendable, Equatable {
        public var date: Bool
        public var sources: Bool
        public var models: Bool
        public var speed: Bool
        public init(date: Bool = true, sources: Bool = true, models: Bool = true, speed: Bool = false) {
            self.date = date; self.sources = sources; self.models = models; self.speed = speed
        }
    }

    /// The Sources section at the end: one line per source, by its [n], with the pack it came from ("Wikipedia").
    public static func sourceLines(_ r: Receipt, _ o: Options, ownFile: String = Labels().ownFile) -> [String] {
        o.sources ? r.sources.enumerated().map { i, s in "[\(i + 1)] " + sourceText(s, ownFile: ownFile).kotlinTrim() } : []
    }

    /// A model with its speed in brackets: "Qwen3 4B (9.5 tok/s)", or the slowest to the fastest.
    public static func modelWithSpeed(_ m: ModelLine) -> String {
        guard let lo = m.minTokPerSec, let hi = m.maxTokPerSec else { return m.model }
        return one(lo) == one(hi) ? "\(m.model) (\(speed(lo)))" : "\(m.model) (\(one(lo))–\(one(hi)) tok/s)"
    }

    /// The footer under the Sources section (adam, Nov 14): the models on their own line when `Options.models` (each with
    /// its speed when `Options.speed`), then "Made offline with BOAR" and the date, always.
    public static func footer(_ r: Receipt, _ l: Labels, date: String, _ o: Options) -> [String] {
        var out: [String] = []
        if o.models && !r.models.isEmpty { out.append(r.models.map { o.speed ? modelWithSpeed($0) : $0.model }.joined(separator: "  ·  ")) }
        out.append(l.madeWith.replacingOccurrences(of: "{{date}}", with: date))
        return out
    }

    /// A source as the Sources section prints it. A pack's prints its title and "Label — https://…"; a user's own file
    /// (its source is the file name, its title the file name without the extension) prints `ownFile` only, under its own
    /// [n] (validator R-A1).
    public static func sourceText(_ s: PressDoc.Source, ownFile: String = Labels().ownFile) -> String {
        guard let src = s.source, !PressDoc.isBlank(src) else { return s.title }
        return shareable(src) ? s.title + " — " + src : ownFile
    }

    private static let packStyle = try! NSRegularExpression(pattern: #"\A[^—\n]{1,60} — https?://[^ \t\n\x{0B}\f\r]+(?: \([^)\n]{1,60}\))?\z"#)

    /// A source that may print in a shared PDF or .md (validator A-1): a pack's or the corpus's "Wikipedia — https://…",
    /// or a pack's bare label. For the user's own files the source is the file name ("imposto-2025.pdf"): never.
    public static func shareable(_ source: String) -> Bool {
        let s = source.kotlinTrim()
        if s.isEmpty { return false }
        if packStyle.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil { return true }
        // BOAR's own guide and FAQ (BoarPack): public text, never a user's file.
        if BoarPack.isBoarSource(s) { return true }
        return Packs.sourceLabel.values.contains(s)
    }

    /// The project as it is shared (PDF, .md): each user's own file named in what came from the chat (the question, the
    /// chat title, the answer's text, its card's title and body) reads `ownFile` (validator Q-B3). What the user typed in
    /// Press (headings, notes, the project's name) is theirs and stays. The sources aren't touched: they already print
    /// as `ownFile`.
    public static func scrubOwnFiles(_ project: PressDoc.Project, ownFile: String) -> PressDoc.Project {
        var names: [String] = []
        for s in project.answers.flatMap(\.sources) {
            guard let file = s.source?.kotlinTrim(), !file.isEmpty, !shareable(file) else { continue }
            let stem = file.lastIndex(of: ".").map { String(file[..<$0]) } ?? file
            for n in [file, stem, s.title.kotlinTrim()] where n.utf16.count >= 4 && !names.contains(n) { names.append(n) }
        }
        if names.isEmpty { return project }
        let longestFirst = names.enumerated().sorted { a, b in
            a.element.utf16.count != b.element.utf16.count ? a.element.utf16.count > b.element.utf16.count : a.offset < b.offset
        }.map(\.element)
        // Kotlin's Regex(IGNORE_CASE) adds UNICODE_CASE: "RELATÓRIO" matches "Relatório", as ICU's .caseInsensitive.
        let re = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])(?:"# + longestFirst.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")(?![\p{L}\p{N}_])"#,
                                          options: .caseInsensitive)
        let template = NSRegularExpression.escapedTemplate(for: ownFile)
        func x(_ t: String) -> String {
            re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: template)
        }
        var out = project
        out.blocks = project.blocks.map { b in
            guard case .answer(var a) = b else { return b }
            a.question = x(a.question); a.chatTitle = x(a.chatTitle); a.text = x(a.text)
            if var card = a.card {
                card.title = x(card.title)
                card.body = scrubBody(card.body, x)
                a.card = card
            }
            return .answer(a)
        }
        return out
    }

    /// Every text a card's body holds, through `x` (CodeRabbit on all73: a Facts value could still hold the file's name).
    private static func scrubBody(_ b: AnswerCard.Body, _ x: (String) -> String) -> AnswerCard.Body {
        switch b {
        case .series(let unit, let points):
            return .series(unit: x(unit), points: points.map { var p = $0; p.label = x(p.label); p.written = x(p.written); return p })
        case .table(let header, let rows): return .table(header: header.map(x), rows: rows.map { $0.map(x) })
        case .steps(let items): return .steps(items.map(x))
        case .facts(let pairs): return .facts(pairs.map { CardFact(x($0.label), x($0.value)) })
        case .compare(let sides): return .compare(sides.map { CardSide(x($0.name), $0.points.map(x)) })
        }
    }

    /// "Sources [1] [3]" under an answer; nil when it has none.
    public static func refsLine(_ numbers: [Int]?, _ label: String) -> String? {
        guard let numbers, !numbers.isEmpty else { return nil }
        return label + " " + numbers.map { "[\($0)]" }.joined(separator: " ")
    }

    /// An answer's own [k] marks, if its text kept any, become the document's numbers (`refs` in its sources' order).
    public static func renumber(_ text: String, _ refs: [Int]) -> String {
        renumber(text, Dictionary(uniqueKeysWithValues: refs.enumerated().map { ($0.offset + 1, $0.element) }))
    }

    private static let ownMark = try! NSRegularExpression(pattern: #"\[([0-9]{1,3})]"#)

    /// An answer's own [k] marks become the document's numbers (`map`); a [k] the answer has no source for is taken out,
    /// so it never reads as another answer's source (validator G-5b).
    public static func renumber(_ text: String, _ map: [Int: Int]) -> String {
        PressText.replaceGroups(ownMark, in: text) { g in Int(g[1] ?? "").flatMap { map[$0] }.map { "[\($0)]" } ?? "" }
            .replacingOccurrences(of: #"(?<=[^ \t\n\x{0B}\f\r]) +([.,;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[^ \t\n\x{0B}\f\r]) {2,}(?=[^ \t\n\x{0B}\f\r])"#, with: " ", options: .regularExpression)
    }

    /// An answer's markdown as plain text for the paper: no ** or #, bullets as •.
    public static func plain(_ md: String) -> String {
        md.kotlinLines().map { line in
            line.replacingOccurrences(of: #"^#{1,6}[ \t\n\x{0B}\f\r]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[ \t\n\x{0B}\f\r]*[-*][ \t\n\x{0B}\f\r]+"#, with: "• ", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
        }.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).kotlinTrim()
    }

    private static func oneLine(_ s: String) -> String { s.kotlinTrim().replacingOccurrences(of: "\n", with: " ") }

    /// The document as Markdown (Save as Markdown): the same title, date, blocks, Sources section and footer as the
    /// paper. Pictures stay out (a line says where one was, with its caption if it has one).
    public static func markdown(_ project: PressDoc.Project, _ l: Labels, date: String, version: String, sourcesLabel: String,
                                drawingLabel: String, receipt: Receipt? = nil, photoLabel: String? = nil, options o: Options = Options()) -> String {
        let r = receipt ?? build(project)
        var out = "# " + oneLine(project.name) + "\n\n"
        if o.date { out += "_" + date + "_\n\n" }
        for block in project.blocks {
            switch block {
            case .heading(_, let t): if !PressDoc.isBlank(t) { out += "## " + oneLine(t) + "\n\n" }
            case .note(_, let t): if !PressDoc.isBlank(t) { out += t.kotlinTrim().kotlinLines().map { "> " + $0 }.joined(separator: "\n") + "\n\n" }
            case .paragraph(_, let t): if !PressDoc.isBlank(t) { out += t.kotlinTrim() + "\n\n" }
            case .bullets(_, let t):
                let items = PressDoc.items(t)
                if !items.isEmpty { out += items.map { "- " + $0 }.joined(separator: "\n") + "\n\n" }
            case .divider: out += "* * *\n\n"
            case .answer(let b):
                // Sources off: no "Sources [n]" line and no [n] in the text, which would point at nothing.
                let refs = o.sources ? r.refs[b.id] ?? [] : []
                let local = o.sources ? r.local[b.id] ?? [:] : [:]
                out += "### " + oneLine(b.shownHeading) + "\n\n"
                if let q = b.shownQuestion { out += "_" + oneLine(q) + "_\n\n" }
                out += renumber(b.text.kotlinTrim(), local).kotlinTrim() + "\n\n"
                if let line = refsLine(refs, sourcesLabel) { out += line + "\n\n" }
                // Its card, when it came with one: in the form Markdown has for it, after the answer's own lines.
                if let card = b.card { out += AnswerCard.markdown(card) + "\n\n" }
            case .picture(let b):
                let cap = b.caption.kotlinTrim()
                out += "_" + (b.kind == .photo ? photoLabel ?? drawingLabel : drawingLabel) + (cap.isEmpty ? "" : ": " + cap) + "_\n\n"
            case .unknown:
                break
            }
        }
        // The Sources section, then the footer, as on the paper (adam, Nov 14), the footer in small italics under a rule.
        let lines = sourceLines(r, o, ownFile: l.ownFile)
        if !lines.isEmpty { out += "## " + sourcesLabel + "\n\n" + lines.joined(separator: "  \n") + "\n\n" }
        out += "---\n\n" + footer(r, l, date: date, o).map { "_\($0)_" }.joined(separator: "  \n") + "\n"
        return out
    }

    /// The file name before ".pdf" or ".md" (PressScreen.kt `slug`): lowercase ASCII letters and digits, the rest as
    /// dashes, at most 48 characters, "boar-document" when nothing is left.
    public static func slug(_ s: String) -> String {
        var out = ""
        var dash = false
        for u in s.lowercased().unicodeScalars {
            if ("a"..."z").contains(u) || ("0"..."9").contains(u) {
                if dash, !out.isEmpty { out += "-" }
                dash = false
                out.unicodeScalars.append(u)
            } else {
                dash = true
            }
        }
        let cut = String(out.prefix(48))
        return cut.isEmpty ? "boar-document" : cut
    }
}
