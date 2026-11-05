import Foundation

/// Boar Press's research basket (android labs/plugins/printer `Basket.kt`): answers picked from any chat, in the order the
/// Press shows, kept in a JSON file (Android's `files/labs/basket.json` layout) until it's cleared. The list operations are
/// pure; the app holds the list, and writes the whole file after each change.
public enum Basket {
    public struct Source: Sendable, Equatable, Hashable {
        public var title: String
        public var source: String?
        public init(title: String, source: String?) { self.title = title; self.source = source }
    }

    public struct Item: Sendable, Equatable, Identifiable {
        /// The chat message id: the same answer can't go in twice.
        public var id: String
        public var chatTitle: String
        public var question: String
        public var text: String
        public var sources: [Source]
        /// Milliseconds since 1970, as Android writes it.
        public var addedAt: Int64
        public var model: String?
        public var tokPerSec: Double?
        /// The drawing picked for this answer (a file path); nil leaves it to the answer's own illustration, if any.
        public var image: String?
        /// No drawing for this answer, even if it has an illustration.
        public var imageOff: Bool

        public init(id: String, chatTitle: String, question: String, text: String, sources: [Source], addedAt: Int64,
                    model: String? = nil, tokPerSec: Double? = nil, image: String? = nil, imageOff: Bool = false) {
            self.id = id; self.chatTitle = chatTitle; self.question = question; self.text = text; self.sources = sources
            self.addedAt = addedAt; self.model = model; self.tokPerSec = tokPerSec; self.image = image; self.imageOff = imageOff
        }
    }

    // MARK: changes (Basket.kt add, remove, edit, editHeading, setImage, move)

    /// `item` at the end, unless an item with its id is already in.
    public static func adding(_ item: Item, to list: [Item]) -> [Item] {
        list.contains { $0.id == item.id } ? list : list + [item]
    }

    public static func removing(_ id: String, from list: [Item]) -> [Item] { list.filter { $0.id != id } }

    public static func editing(_ id: String, text: String, in list: [Item]) -> [Item] {
        list.map { $0.id == id ? with($0) { $0.text = text } : $0 }
    }

    /// The heading printed above an answer (its question, at first).
    public static func editing(_ id: String, heading: String, in list: [Item]) -> [Item] {
        list.map { $0.id == id ? with($0) { $0.question = heading } : $0 }
    }

    /// One drawing per answer: `path` picks it, nil means none for this answer.
    public static func setting(_ id: String, image path: String?, in list: [Item]) -> [Item] {
        list.map { $0.id == id ? with($0) { $0.image = path; $0.imageOff = path == nil } : $0 }
    }

    /// Moves an item up (-1) or down (+1); out of range leaves the list as it is.
    public static func moving(_ id: String, by: Int, in list: [Item]) -> [Item] {
        guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + by) else { return list }
        var out = list
        out.insert(out.remove(at: i), at: i + by)
        return out
    }

    private static func with(_ item: Item, _ change: (inout Item) -> Void) -> Item {
        var copy = item
        change(&copy)
        return copy
    }

    // MARK: the file

    /// What reading the file found. `unreadable` keeps the app from writing over a basket it couldn't read.
    public enum Loaded: Sendable, Equatable {
        case none
        case items([Item])
        case unreadable
    }

    public static func load(from url: URL) -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        guard let data = try? Data(contentsOf: url), let items = try? decode(data) else { return .unreadable }
        return .items(items)
    }

    /// The whole list, written to a temporary file and swapped in, so a crash can't leave half a basket.
    public static func save(_ items: [Item], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(items).write(to: url, options: .atomic)
    }

    /// Android's JSON: missing strings read as "", a "null" string or JSON null as nil, a missing `addedAt` as 0.
    public static func decode(_ data: Data) throws -> [Item] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else { throw DecodeError.notAnArray }
        return try array.map { any in
            guard let o = any as? [String: Any], let id = o["id"] as? String, let text = o["text"] as? String else {
                throw DecodeError.badItem
            }
            func optString(_ k: String) -> String? {
                guard let s = o[k] as? String, !s.isEmpty, s != "null" else { return nil }
                return s
            }
            let sources: [Source] = try ((o["sources"] as? [Any]) ?? []).map { s in
                guard let s = s as? [String: Any], let title = s["title"] as? String else { throw DecodeError.badItem }
                let src = s["source"] as? String
                return Source(title: title, source: src.flatMap { $0.isEmpty || $0 == "null" ? nil : $0 })
            }
            return Item(id: id, chatTitle: (o["chatTitle"] as? String) ?? "", question: (o["question"] as? String) ?? "",
                        text: text, sources: sources, addedAt: (o["addedAt"] as? NSNumber)?.int64Value ?? 0,
                        model: optString("model"), tokPerSec: (o["tokPerSec"] as? NSNumber)?.doubleValue,
                        image: optString("image"), imageOff: (o["imageOff"] as? Bool) ?? false)
        }
    }

    /// The same keys as Android's file, with explicit nulls.
    public static func encode(_ items: [Item]) throws -> Data {
        let array: [[String: Any]] = items.map { i in
            [
                "id": i.id, "chatTitle": i.chatTitle, "question": i.question, "text": i.text, "addedAt": i.addedAt,
                "model": i.model ?? NSNull(), "tokPerSec": i.tokPerSec ?? NSNull(), "image": i.image ?? NSNull(),
                "imageOff": i.imageOff,
                "sources": i.sources.map { ["title": $0.title, "source": $0.source ?? NSNull()] as [String: Any] },
            ]
        }
        return try JSONSerialization.data(withJSONObject: array, options: [.sortedKeys])
    }

    public enum DecodeError: Error { case notAnArray, badItem }
}

/// What Boar Press prints (android `PdfCompiler.kt` helpers and `MarkdownCompiler.kt`), shared by the PDF and the
/// Markdown file.
public enum Press {
    /// Where the drawings go: centred on their own, or right or left with the text beside them, or alternating.
    public enum Placement: String, Sendable, CaseIterable {
        case center, right, left, alternate

        /// The side of the `index`th drawing: alternate starts on the right.
        public func side(of index: Int) -> Placement {
            self == .alternate ? (index % 2 == 0 ? .right : .left) : self
        }

        public static func of(_ s: String?) -> Placement { allCases.first { $0.rawValue == s?.lowercased() } ?? .center }
    }

    /// What prints besides the text: the date under the title, each answer's model and speed, each answer's sources.
    /// `drawingFirst`: the drawing above its heading; off (default), the heading comes first.
    public struct Meta: Sendable, Equatable {
        public var date = true
        public var model = false
        public var sources = true
        public var images = Placement.center
        public var drawings = true
        public var drawingFirst = false
        public init(date: Bool = true, model: Bool = false, sources: Bool = true, images: Placement = .center,
                    drawings: Bool = true, drawingFirst: Bool = false) {
            self.date = date; self.model = model; self.sources = sources; self.images = images
            self.drawings = drawings; self.drawingFirst = drawingFirst
        }
    }

    /// "Qwen3-4B · 12.3 tok/s", or nil when the answer has neither.
    public static func modelLine(_ i: Basket.Item) -> String? {
        let parts = [i.model, i.tokPerSec.map { String(format: "%.1f tok/s", locale: Locale(identifier: "en_US_POSIX"), $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "[1] Title — source" lines.
    public static func sourceLines(_ i: Basket.Item) -> String {
        i.sources.enumerated().map { n, s in "[\(n + 1)] \(s.title)" + (s.source.map { " — \($0)" } ?? "") }.joined(separator: "\n")
    }

    /// The file name before ".pdf" or ".md" (PrinterLab.kt `slug`): lowercase ASCII letters and digits, the rest as
    /// dashes, at most 48 characters, "boar-document" when nothing is left. Unlike ChatExport's, accents aren't folded.
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

    /// The heading an item prints under: its question, or its chat's title when the question is blank.
    public static func heading(_ i: Basket.Item) -> String {
        i.question.allSatisfy(\.isWhitespace) ? i.chatTitle : i.question
    }

    /// The answer's markdown as plain text: no ** or #, bullets as •.
    public static func plain(_ md: String) -> String {
        let lines = md.kotlinLines().map { line in
            line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).kotlinTrim()
    }

    /// The basket as a Markdown file: the same title, order, headings and switches as the PDF, as plain text (no
    /// drawings). `date` is the long date the caller formats (Android: `DateFormat.LONG` of today).
    public static func markdown(title: String, items: [Basket.Item], footer: String, meta: Meta, labels: ChatExport.Labels, date: String) -> String {
        var out = "# " + title.kotlinTrim().replacingOccurrences(of: "\n", with: " ") + "\n\n"
        out += "_" + (meta.date ? date + " · " : "") + footer + "_\n\n"
        out += items.map { i in
            ChatExport.turn(ChatExport.Turn(question: heading(i), answer: i.text, reasoning: nil,
                                            sources: meta.sources ? i.sources.map { ($0.title, $0.source) } : [],
                                            details: meta.model ? modelLine(i) : nil), labels)
        }.joined(separator: "\n---\n\n")
        return out
    }
}
