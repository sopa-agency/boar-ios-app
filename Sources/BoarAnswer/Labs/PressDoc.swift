import BoarCore
import Foundation

/// Boar Press's projects (android engine `labs/PressDoc.kt`; adam's mock-up, Nov 13): several projects, each its own
/// document, made of blocks in order. Pure data and the changes on it; the app keeps it in one file
/// (`files/labs/press/projects.json`, written whole and swapped in) and draws it as the paper.
///
/// - Photos (phase 2): a `.picture` has a `kind` (drawing or photo), a caption and a place; a photo's `file` is a name
///   inside the project's own folder (`files/labs/press/<project id>/`, `PressFiles`), which goes with the project.
/// - Rewrites (phase 3) only replace a block's text (`Library.editText`); nothing new is stored.
/// - A block type this version doesn't know is kept as it is (`.unknown`) and written back unchanged; `version` lets a
///   later version migrate if it ever must.
public enum PressDoc {
    public static let version = 1
    /// How many projects the menu lists before "All projects".
    public static let shortListSize = 4

    public struct Source: Sendable, Equatable, Hashable {
        public var title: String
        public var source: String?
        public init(_ title: String, _ source: String? = nil) { self.title = title; self.source = source }
    }

    /// How a Designer drawing was made, read from its recipe; every field may be missing (older drawings).
    public struct Recipe: Sendable, Equatable {
        public var subject: String?
        public var style: String?
        public var size: String?
        public var seed: Int64?
        public init(subject: String? = nil, style: String? = nil, size: String? = nil, seed: Int64? = nil) {
            self.subject = subject; self.style = style; self.size = size; self.seed = seed
        }
    }

    public enum Kind: String, Sendable { case drawing, photo }

    /// Where a picture sits: centered at the full width, or left / right with the next text beside it.
    public enum Place: String, Sendable, CaseIterable {
        case center, left, right
        public static func of(_ s: String?) -> Place { allCases.first { $0.rawValue == s?.lowercased() } ?? .center }
    }

    public enum Field: Sendable { case text, heading, caption }

    /// An answer from a chat; `id` is the chat message's id, so the same answer is in a project only once.
    public struct Answer: Sendable, Equatable {
        public var id: String
        public var chatTitle: String
        public var question: String
        public var text: String
        public var sources: [Source]
        public var addedAt: Int64
        public var model: String?
        public var tokPerSec: Double?
        /// The heading the user typed; blank means the question stands as the heading.
        public var heading: String
        /// Its text was changed (typed, or a rewrite the user used): only the sources it still cites by [n] print, so a
        /// rewrite that cites nothing has no Sources line (validator G-5). An answer as it came from the chat keeps all.
        public var edited: Bool
        /// The card shown under the answer when it came to Press, with its ticks; nil for none (and before Cards).
        public var card: AnswerCard?

        public init(_ id: String, _ chatTitle: String, _ question: String, _ text: String, _ sources: [Source] = [],
                    _ addedAt: Int64 = 0, _ model: String? = nil, _ tokPerSec: Double? = nil, heading: String = "",
                    edited: Bool = false, card: AnswerCard? = nil) {
            self.id = id; self.chatTitle = chatTitle; self.question = question; self.text = text; self.sources = sources
            self.addedAt = addedAt; self.model = model; self.tokPerSec = tokPerSec; self.heading = heading
            self.edited = edited; self.card = card
        }

        /// The heading on the paper: the user's, or the question, or the chat's title.
        public var shownHeading: String {
            !isBlank(heading) ? heading : !isBlank(question) ? question : chatTitle
        }

        /// The question in italics under a heading the user changed; nil when the heading is the question.
        public var shownQuestion: String? {
            !isBlank(heading) && !isBlank(question) && question.kotlinTrim() != heading.kotlinTrim() ? question : nil
        }
    }

    /// A picture: a Designer drawing (`file` is its path in Designer's folder, `answerId` the answer it illustrates) or a
    /// photo (`file` is a name in the project's folder). `width` and `height` are its pixels, for its shape before the
    /// file is read.
    public struct Picture: Sendable, Equatable {
        public var id: String
        public var kind: Kind
        public var file: String
        public var caption: String
        public var place: Place
        public var answerId: String?
        public var recipe: Recipe?
        public var width: Int
        public var height: Int

        public init(_ id: String, _ kind: Kind, _ file: String, caption: String = "", place: Place = .center,
                    answerId: String? = nil, recipe: Recipe? = nil, width: Int = 0, height: Int = 0) {
            self.id = id; self.kind = kind; self.file = file; self.caption = caption; self.place = place
            self.answerId = answerId; self.recipe = recipe; self.width = width; self.height = height
        }
    }

    public enum Block: Sendable, Equatable {
        case heading(id: String, text: String)
        /// An aside: italic and muted, with a bar at its side; a quote in the .md.
        case note(id: String, text: String)
        /// Body text the user writes, as an answer's text looks (adam, Nov 13: a paragraph is not a note).
        case paragraph(id: String, text: String)
        /// A list, one item per line of `text` (`PressDoc.items`).
        case bullets(id: String, text: String)
        /// A thin line across the page, between parts.
        case divider(id: String)
        case answer(Answer)
        case picture(Picture)
        /// A block written by a newer BOAR: not shown, kept as it is.
        case unknown(id: String, raw: [String: JSONValue])

        public var id: String {
            switch self {
            case .heading(let id, _), .note(let id, _), .paragraph(let id, _), .bullets(let id, _), .divider(let id),
                 .unknown(let id, _): id
            case .answer(let a): a.id
            case .picture(let p): p.id
            }
        }

        public var answer: Answer? { if case .answer(let a) = self { a } else { nil } }
        public var picture: Picture? { if case .picture(let p) = self { p } else { nil } }
        /// A heading's, note's, paragraph's or list's text.
        public var text: String? {
            switch self {
            case .heading(_, let t), .note(_, let t), .paragraph(_, let t), .bullets(_, let t): t
            default: nil
            }
        }
    }

    public struct Project: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var createdAt: Int64
        public var blocks: [Block]
        /// When the user last saw this project: answers added after it make the "new answers" banner.
        public var seenAt: Int64

        public init(_ id: String, _ name: String, _ createdAt: Int64, _ blocks: [Block] = [], seenAt: Int64 = 0) {
            self.id = id; self.name = name; self.createdAt = createdAt; self.blocks = blocks; self.seenAt = seenAt
        }

        /// Answers that came in from a chat since the user last looked.
        public var unseen: Int { blocks.count { ($0.answer?.addedAt ?? Int64.min) > seenAt } }
        public var answers: [Answer] { blocks.compactMap(\.answer) }
    }

    public struct Library: Sendable, Equatable {
        public var open: String
        public var projects: [Project]

        public init(_ open: String, _ projects: [Project]) { self.open = open; self.projects = projects }

        public var current: Project { projects.first { $0.id == open } ?? projects[0] }

        private func mapProject(_ id: String, _ f: (Project) -> Project) -> Library {
            var out = self
            out.projects = projects.map { $0.id == id ? f($0) : $0 }
            return out
        }

        private func mapOpen(_ f: (Project) -> Project) -> Library { mapProject(current.id, f) }

        private func mapBlock(_ blockId: String, _ f: @escaping (Block) -> Block) -> Library {
            mapOpen { p in var q = p; q.blocks = p.blocks.map { $0.id == blockId ? f($0) : $0 }; return q }
        }

        public func switchTo(_ id: String) -> Library {
            guard projects.contains(where: { $0.id == id }) else { return self }
            var out = self
            out.open = id
            return out
        }

        /// The menu's short list (adam, Nov 12): the open project first, then the ones seen or made most recently, `n` in
        /// all. The rest are behind "All projects", with a search.
        public func shortList(_ n: Int = PressDoc.shortListSize) -> [Project] {
            let cur = current
            let rest = projects.filter { $0.id != cur.id }.enumerated()
                .sorted { a, b in
                    let x = max(a.element.seenAt, a.element.createdAt), y = max(b.element.seenAt, b.element.createdAt)
                    return x != y ? x > y : a.offset < b.offset
                }.map(\.element)
            return Array(([cur] + rest).prefix(n))
        }

        /// Every project whose name has `query` (case and accents aside), the open one first, then the most recent.
        public func search(_ query: String) -> [Project] {
            func norm(_ x: String) -> String {
                x.lowercased().decomposedStringWithCanonicalMapping
                    .replacingOccurrences(of: #"\p{M}+"#, with: "", options: .regularExpression)
            }
            let q = norm(query.kotlinTrim())
            return shortList(Int.max).filter { q.isEmpty || norm($0.name).contains(q) }
        }

        /// A new empty project, opened; it goes first in the list.
        public func newProject(_ id: String, _ name: String, _ now: Int64) -> Library {
            let n = name.kotlinTrim()
            return Library(id, [Project(id, n.isEmpty ? "-" : n, now, seenAt: now)] + projects)
        }

        public func rename(_ id: String, _ name: String) -> Library {
            let n = name.kotlinTrim()
            guard !n.isEmpty else { return self }
            return mapProject(id) { var p = $0; p.name = n; return p }
        }

        /// Deletes a project (its folder goes too). The last one can go too (adam, Nov 14): `blank`, an empty project,
        /// takes its place, as after Clear all. Without `blank` the last one stays.
        public func deleteProject(_ id: String, blank: Project? = nil) -> Library {
            guard projects.contains(where: { $0.id == id }) else { return self }
            if projects.count <= 1 {
                guard let b = blank, b.id != id else { return self }
                return Library(b.id, [b])
            }
            let rest = projects.filter { $0.id != id }
            return Library(open == id ? rest[0].id : open, rest)
        }

        /// An answer from a chat goes at the end of the open project, once; `after` (its drawing) follows it.
        public func addAnswer(_ a: Answer, after: [Block] = []) -> Library {
            mapOpen { p in
                if p.blocks.contains(where: { $0.id == a.id }) { return p }
                var q = p
                q.blocks = p.blocks + [.answer(a)] + after.filter { b in !p.blocks.contains { $0.id == b.id } }
                return q
            }
        }

        public func has(_ answerId: String) -> Bool { current.blocks.contains { $0.answer?.id == answerId } }

        /// Takes an answer out of the open project, and the drawing that came with it.
        public func removeAnswer(_ answerId: String) -> Library {
            mapOpen { p in
                var q = p
                q.blocks = p.blocks.filter { !($0.id == answerId || ($0.picture.map { $0.answerId == answerId } ?? false)) }
                return q
            }
        }

        /// Puts `b` at `at` in a project (the open one by default; clamped): a new block, or a removed one back where it
        /// was (Undo).
        public func insert(_ b: Block, at: Int, projectId: String? = nil) -> Library {
            mapProject(projectId ?? current.id) { p in
                if p.blocks.contains(where: { $0.id == b.id }) { return p }
                var q = p
                q.blocks.insert(b, at: min(max(at, 0), p.blocks.count))
                return q
            }
        }

        public func remove(_ blockId: String) -> Library {
            mapOpen { p in var q = p; q.blocks = p.blocks.filter { $0.id != blockId }; return q }
        }

        /// Moves a block up (-1) or down (+1).
        public func move(_ blockId: String, by: Int) -> Library {
            mapOpen { p in
                guard let i = p.blocks.firstIndex(where: { $0.id == blockId }), p.blocks.indices.contains(i + by) else { return p }
                var q = p
                q.blocks.insert(q.blocks.remove(at: i), at: i + by)
                return q
            }
        }

        /// Edits a text block in place: a heading's, note's, paragraph's or list's text, an answer's heading or text, a
        /// picture's caption.
        public func editText(_ blockId: String, _ field: Field, _ value: String) -> Library {
            mapBlock(blockId) { b in
                switch b {
                case .heading(let id, _): return .heading(id: id, text: value)
                case .note(let id, _): return .note(id: id, text: value)
                case .paragraph(let id, _): return .paragraph(id: id, text: value)
                case .bullets(let id, _): return .bullets(id: id, text: value)
                case .answer(var a):
                    if field == .heading {
                        a.heading = value.kotlinTrim() == a.question.kotlinTrim() ? "" : value
                        return .answer(a)
                    }
                    // The card showed the old text's figures: it goes with the edit, as `edited` tells the receipt (R-E3).
                    if value == a.text { return b }
                    a.text = value; a.edited = true; a.card = nil
                    return .answer(a)
                case .picture(var p) where field == .caption:
                    p.caption = value
                    return .picture(p)
                default: return b
                }
            }
        }

        /// A picture's place: centered at the full width, or left / right with the next text beside it.
        public func place(_ blockId: String, _ place: Place) -> Library {
            mapBlock(blockId) { b in
                guard case .picture(var p) = b else { return b }
                p.place = place
                return .picture(p)
            }
        }

        /// The user saw `projectId`'s new answers (Show, or left the page); nothing changes when there were none.
        public func markSeen(_ now: Int64, projectId: String? = nil) -> Library {
            let id = projectId ?? current.id
            guard (projects.first { $0.id == id }?.unseen ?? 0) != 0 else { return self }
            return mapProject(id) { var p = $0; p.seenAt = now; return p }
        }

        /// A deleted chat's answers leave every project, with the drawings that came with them (adam chose (a), Nov 12).
        public func eraseAnswers(_ ids: some Collection<String>) -> Library {
            let gone = Set(ids)
            if gone.isEmpty { return self }
            var out = self
            out.projects = projects.map { p in
                var q = p
                q.blocks = p.blocks.filter { b in
                    if let a = b.answer, gone.contains(a.id) { return false }
                    if let pic = b.picture, let aid = pic.answerId, gone.contains(aid) { return false }
                    return true
                }
                return q
            }
            return out
        }

        /// How many of `ids` are in any project (the chat's delete row says so).
        public func countOf(_ ids: some Collection<String>) -> Int {
            let set = Set(ids)
            return projects.reduce(0) { n, p in n + p.blocks.count { b in b.answer.map { set.contains($0.id) } ?? false } }
        }
    }

    /// A list's items: one per non-blank line, a leading "-", "*" or "•" taken off.
    public static func items(_ text: String) -> [String] {
        text.kotlinLines().map { line in
            line.kotlinTrim().replacingOccurrences(of: #"^[-*•][ \t\n\x{0B}\f\r]*"#, with: "", options: .regularExpression).kotlinTrim()
        }.filter { !$0.isEmpty }
    }

    /// A list as the paper and the PDF show it: "• " before each item.
    public static func bulleted(_ text: String) -> String { items(text).map { "•  \($0)" }.joined(separator: "\n") }

    public static func emptyLibrary(_ id: String, _ name: String, _ now: Int64) -> Library {
        Library(id, [Project(id, name, now, seenAt: now)])
    }

    static func isBlank(_ s: String) -> Bool { s.allSatisfy(\.isWhitespace) }

    // MARK: JSON

    public enum ParseError: Error { case notAProjectsFile, noProjects, badItem }

    public static func toJson(_ lib: Library) -> String {
        let o: JSONValue = .object([
            "version": .int(Int64(version)),
            "open": .string(lib.open),
            "projects": .array(lib.projects.map { p in
                .object([
                    "id": .string(p.id), "name": .string(p.name), "createdAt": .int(p.createdAt), "seenAt": .int(p.seenAt),
                    "blocks": .array(p.blocks.map(blockJson)),
                ])
            }),
        ])
        return o.jsonString
    }

    private static func str(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }

    private static func blockJson(_ b: Block) -> JSONValue {
        switch b {
        case .heading(let id, let t): return ["type": "heading", "id": .string(id), "text": .string(t)]
        case .note(let id, let t): return ["type": "note", "id": .string(id), "text": .string(t)]
        case .paragraph(let id, let t): return ["type": "paragraph", "id": .string(id), "text": .string(t)]
        case .bullets(let id, let t): return ["type": "list", "id": .string(id), "text": .string(t)]
        case .divider(let id): return ["type": "divider", "id": .string(id)]
        case .answer(let a):
            var m: [String: JSONValue] = [
                "type": "answer", "id": .string(a.id), "chatTitle": .string(a.chatTitle), "question": .string(a.question),
                "heading": .string(a.heading), "text": .string(a.text), "addedAt": .int(a.addedAt), "model": str(a.model),
                "tokPerSec": a.tokPerSec.map { .double($0) } ?? .null, "edited": .bool(a.edited),
                "sources": .array(a.sources.map { ["title": .string($0.title), "source": str($0.source)] }),
            ]
            if let card = a.card { m["card"] = AnswerCard.toJson(card, withTicks: true) }
            return .object(m)
        case .picture(let p):
            return .object([
                "type": "picture", "id": .string(p.id), "kind": .string(p.kind.rawValue), "file": .string(p.file),
                "caption": .string(p.caption), "place": .string(p.place.rawValue), "answerId": str(p.answerId),
                "width": .int(Int64(p.width)), "height": .int(Int64(p.height)),
                "recipe": p.recipe.map { r in
                    .object(["subject": str(r.subject), "style": str(r.style), "size": str(r.size), "seed": r.seed.map { .int($0) } ?? .null])
                } ?? .null,
            ])
        case .unknown(_, let raw): return .object(raw)
        }
    }

    /// Reads the projects file; throws on a file that isn't one (the app then writes nothing over it).
    public static func parse(_ text: String) throws -> Library {
        guard let root = JSONValue(jsonString: text), case .object(let o) = root,
              case .array(let list)? = o["projects"] else { throw ParseError.notAProjectsFile }
        let projects: [Project] = try list.map { e in
            guard case .object(let p) = e, let id = s(p, "id") else { throw ParseError.badItem }
            let blocks = (p["blocks"]?.arrayValue ?? []).compactMap { $0.objectValue.flatMap(parseBlock) }
            return Project(id, s(p, "name") ?? "", l(p, "createdAt") ?? 0, blocks, seenAt: l(p, "seenAt") ?? 0)
        }
        guard !projects.isEmpty else { throw ParseError.noProjects }
        let open = s(o, "open").flatMap { id in projects.contains { $0.id == id } ? id : nil } ?? projects[0].id
        return Library(open, projects)
    }

    private static func s(_ o: [String: JSONValue], _ k: String) -> String? { o[k]?.stringValue }
    private static func l(_ o: [String: JSONValue], _ k: String) -> Int64? { o[k]?.int64Value }
    private static func d(_ o: [String: JSONValue], _ k: String) -> Double? { o[k]?.doubleValue }
    private static func b(_ o: [String: JSONValue], _ k: String) -> Bool? { o[k]?.boolValue }

    private static func parseBlock(_ o: [String: JSONValue]) -> Block? {
        guard let id = s(o, "id") else { return nil }
        switch s(o, "type") {
        case "heading": return .heading(id: id, text: s(o, "text") ?? "")
        case "note": return .note(id: id, text: s(o, "text") ?? "")
        case "paragraph": return .paragraph(id: id, text: s(o, "text") ?? "")
        case "list": return .bullets(id: id, text: s(o, "text") ?? "")
        case "divider": return .divider(id: id)
        case "answer":
            return .answer(Answer(id, s(o, "chatTitle") ?? "", s(o, "question") ?? "", s(o, "text") ?? "", sources(o["sources"]),
                                  l(o, "addedAt") ?? 0, s(o, "model"), d(o, "tokPerSec"), heading: s(o, "heading") ?? "",
                                  edited: b(o, "edited") ?? false, card: AnswerCard.fromJson(o["card"])))
        case "picture":
            guard let file = s(o, "file") else { return nil }
            let recipe = o["recipe"]?.objectValue.map { r in Recipe(subject: s(r, "subject"), style: s(r, "style"), size: s(r, "size"), seed: l(r, "seed")) }
            return .picture(Picture(id, s(o, "kind") == "photo" ? .photo : .drawing, file, caption: s(o, "caption") ?? "",
                                    place: Place.of(s(o, "place")), answerId: s(o, "answerId"), recipe: recipe,
                                    width: Int(l(o, "width") ?? 0), height: Int(l(o, "height") ?? 0)))
        default:
            return .unknown(id: id, raw: o)
        }
    }

    private static func sources(_ e: JSONValue?) -> [Source] {
        (e?.arrayValue ?? []).compactMap { v in
            guard let o = v.objectValue, let title = s(o, "title") else { return nil }
            return Source(title, s(o, "source").flatMap { $0.isEmpty || $0 == "null" ? nil : $0 })
        }
    }

    // MARK: Migration from the single basket (files/labs/basket.json, Press until Nov 13)

    /// Today's basket becomes the first project, `name` ("Field notes"), in the same order, nothing left out: each
    /// answer with its question, edited heading and text, sources, model and speed; the drawing it had (the one picked,
    /// else its own illustration from `illustrations`, answer id to file, unless it was switched off) follows it as a
    /// picture. Throws on a basket that can't be read: the app then leaves the file where it is.
    public static func fromBasket(_ basketJson: String, projectId: String, name: String, now: Int64,
                                  illustrations: [String: String] = [:]) throws -> Library {
        guard let root = JSONValue(jsonString: basketJson), case .array(let items) = root else { throw ParseError.notAProjectsFile }
        var blocks: [Block] = []
        for e in items {
            guard case .object(let o) = e, let id = s(o, "id"), let text = s(o, "text") else { throw ParseError.badItem }
            // The old basket kept an edited heading in "question" itself: it stays the question, shown as the heading.
            blocks.append(.answer(Answer(id, s(o, "chatTitle") ?? "", s(o, "question") ?? "", text, sources(o["sources"]),
                                         l(o, "addedAt") ?? 0, s(o, "model").flatMap { $0.isEmpty || $0 == "null" ? nil : $0 },
                                         d(o, "tokPerSec"))))
            let picked = s(o, "image").flatMap { $0.isEmpty || $0 == "null" ? nil : $0 }
            let drawing = b(o, "imageOff") == true ? nil : picked ?? illustrations[id]
            if let drawing { blocks.append(.picture(Picture("pic-\(id)", .drawing, drawing, answerId: id))) }
        }
        // Seen now: the migrated answers aren't "new" in the banner.
        return Library(projectId, [Project(projectId, name, now, blocks, seenAt: now)])
    }

    /// The old basket that couldn't be read the first time, read now (validator G-3): its answers become one more
    /// project, after the ones there are. Throws if it still can't be read; an empty basket changes nothing.
    public static func mergeBasket(_ lib: Library, _ basket: String, newId: String, name: String, now: Int64,
                                   illustrations: [String: String] = [:]) throws -> Library {
        let old = try fromBasket(basket, projectId: newId, name: name, now: now, illustrations: illustrations)
        let adds = old.projects.filter { p in !p.blocks.isEmpty && !lib.projects.contains { $0.id == p.id } }
        if adds.isEmpty { return lib }
        var out = lib
        out.projects += adds
        return out
    }

    /// What loading found, for the app to act on.
    public enum Loaded: Sendable {
        /// The projects file, read.
        case read(Library)
        /// No projects file: the basket became the first project; write it, then the basket file can go.
        case migrated(Library)
        /// Nothing saved yet (or a basket that can't be read, which stays where it is): a first empty project.
        case fresh(Library, basketUnreadable: Bool)
        /// The projects file can't be read: nothing is written over it.
        case unreadable
    }

    /// Loads the projects (`projects` is the file's text, or nil when there's none). The basket is migrated once: only
    /// when there is no projects file yet, so after the first write it never runs again.
    public static func load(projects: String?, basket: String?, newId: String, name: String, now: Int64,
                            illustrations: [String: String] = [:]) -> Loaded {
        if let projects {
            guard let lib = try? parse(projects) else { return .unreadable }
            return .read(lib)
        }
        if let basket {
            guard let lib = try? fromBasket(basket, projectId: newId, name: name, now: now, illustrations: illustrations) else {
                return .fresh(emptyLibrary(newId, name, now), basketUnreadable: true)
            }
            return .migrated(lib)
        }
        return .fresh(emptyLibrary(newId, name, now), basketUnreadable: false)
    }
}
