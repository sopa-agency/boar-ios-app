import Foundation

/// What BOAR knows about the user's files as files (port of OwnFiles.kt), for the Personal Files style: which files are
/// switched on, a question that asks about them as a whole ("summarize my files") or names one ("what's in my blood
/// test?"), and a card per long file that a search can match by its outline. All of it comes from the files themselves:
/// names, headings and opening lines, never text a model wrote.
public enum OwnFiles {
    /// One imported document of a switched-on collection: its file's `name` and how many parts it was cut into.
    public struct File: Sendable, Equatable {
        public var docId: String
        public var name: String
        public var parts: Int
        public init(docId: String, name: String, parts: Int) { self.docId = docId; self.name = name; self.parts = parts }
    }

    /// A card's chunk id ends with this; its document's own parts end with "-c<n>".
    public static let cardSuffix = "-card"

    /// The files the prompt lists by name; past it, "and N more".
    public static let noteMaxFiles = 20

    /// Files whose opening part a question about all of them brings (WholePassages then fits them to the context).
    public static let overviewMaxFiles = 12

    public static func isCard(_ c: Chunk) -> Bool { c.chunkId.hasSuffix(cardSuffix) }

    private static let marks = Rx("\\p{M}+")
    private static let word = Rx("[a-z0-9]+")

    /// Lower case without accents ("Resumo dos meus Arquivos" → "resumo dos meus arquivos").
    static func fold(_ s: String) -> String { marks.replace(Js.nfd(s.lowercased()), with: "") }

    private static let fileNouns = "files?|documents?|docs?|notes?|pdfs?|uploads?|arquivos?|documentos?|notas?|anotacoes|anotacao|documentacao"

    /// The user's files as a thing ("my files", "meus arquivos", "the documents I imported").
    private static let files = Rx("\\b(\(fileNouns))\\b")

    /// Asking about them as a whole: a summary, an overview, a list, whether one exists, how many.
    private static let whole = Rx(
        "\\b(summari[sz]e|summary|overview|main points|key points|main ideas|what('s| is| are)? in|what do|which|list|"
            + "do i have|how many|tell me about|resum[aoei]\\w*|visao geral|pontos principais|principais pontos|ideias principais|"
            + "o que (tem|ha|esta|dizem|diz)|quais|liste|listar|tenho (algum|alguma|um|uma)|quantos|quantas|fale sobre)\\b"
    )

    /// A question about the user's files as a whole, which no single passage is close to: "What are the main points of my
    /// files?", "Do I have a medical file?", "Resuma meus arquivos". Its passages are then each file's opening part.
    public static func aboutTheFiles(_ question: String) -> Bool {
        let q = fold(question)
        return files.contains(q) && whole.contains(q)
    }

    /// Words a file name shares with any question: they never name a file by themselves.
    private static let generic: Set<String> = [
        "the", "and", "for", "file", "files", "note", "notes", "doc", "docs", "document", "documents", "my", "new", "copy", "final", "draft",
        "txt", "pdf", "csv", "json", "md", "markdown", "arquivo", "arquivos", "nota", "notas", "documento", "documentos", "meu", "minha",
    ]

    private static func stem(_ w: String) -> String { w.u16Count > 3 && w.hasSuffix("s") ? w.u16DropLast(1) : w }

    /// Kotlin `substringBeforeLast('.')`: the whole string when there is no dot.
    private static func beforeLastDot(_ s: String) -> String {
        guard let i = s.lastIndex(of: ".") else { return s }
        return String(s[..<i])
    }

    /// A file name's words that can name it: letters, three or more, not `generic`.
    private static func nameWords(_ name: String) -> Set<String> {
        Set(
            word.all(fold(beforeLastDot(name))).map(\.value)
                .filter { $0.u16Count >= 3 && $0.contains(where: \.isLetter) && !generic.contains($0) }
                .map(stem)
        )
    }

    /// The one file the question names: every naming word of a file name with one or two of them ("blood-test-2026.txt"
    /// by "blood test"), at least two of a longer name's. None when no file or two different files do ("compare my car
    /// insurance with the trip plan"); then the search runs on all the files as before. A file that is a list of documents
    /// (JSON) is several `File`s with one name: the caller searches all of them (`docsOf`).
    public static func named(_ question: String, _ files: [File]) -> File? {
        let words = Set(word.all(fold(question)).map { stem($0.value) })
        var seenNames = Set<String>()
        let scored: [File] = files.filter { seenNames.insert($0.name).inserted }.compactMap { f in
            let name = nameWords(f.name)
            let hit = name.filter { words.contains($0) }.count
            let enough = name.count <= 2 ? !name.isEmpty && hit == name.count : hit >= 2
            return enough ? f : nil
        }
        return scored.count == 1 ? scored[0] : nil
    }

    /// Every document of `file`'s file: one, or each of a JSON list's.
    public static func docsOf(_ file: File, _ files: [File]) -> [String] { files.filter { $0.name == file.name }.map(\.docId) }

    /// The prompt's line naming the switched-on files, or nil without any.
    public static func note(_ files: [File]) -> String? {
        var seen = Set<String>()
        let names = files.map(\.name).filter { seen.insert($0).inserted }
        if names.isEmpty { return nil }
        let shown = names.prefix(noteMaxFiles).joined(separator: "; ")
        let more = names.count > noteMaxFiles ? "; and \(names.count - noteMaxFiles) more" : ""
        return "The user's Personal Files (\(names.count)): \(shown)\(more)."
    }

    private static let heading = Rx("^#{1,3} +(.+)$")
    /// Java's `\s` (ASCII whitespace), not ICU's Unicode one.
    private static let space = Rx("[ \\t\\n\\x0B\\f\\r]+")
    private static let lineBreak = Rx("\\r\\n|\\n|\\r")

    /// How the card says the file's kind.
    private static func kind(_ name: String) -> String {
        let ext = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]) } ?? ""
        switch ext.lowercased() {
        case "md", "markdown": return "Markdown"
        case "pdf": return "PDF"
        case "csv": return "spreadsheet (CSV)"
        case "json": return "JSON"
        default: return "text"
        }
    }

    /// A card for one long document (cut into more than one part): its file, kind, size and part count, its Markdown
    /// headings as an outline, and how it starts. A search matches the file as a whole by it, where one part each is only
    /// a slice. A one-part document has no card: its part already is the whole file. `size` is formatted by the caller.
    public static func card(docId: String, collectionId: String, title: String, fileName: String, body: String, parts: Int, size: String) -> Chunk? {
        if parts <= 1 { return nil }
        var seen = Set<String>()
        let headings = lineBreak.split(body)
            .compactMap { heading.find(kotlinTrim($0))?.group(1).map(kotlinTrim) }
            .filter { seen.insert($0).inserted }
            .prefix(15)
        let trimmed = kotlinTrim(body)
        let start = space.replace(trimmed, with: " ").u16Take(300)
        var text = "File: \(fileName) (\(kind(fileName)), \(size), \(parts) parts)."
        if !headings.isEmpty { text += "\nSections: \(headings.joined(separator: "; "))." }
        text += "\nStarts: \(start)\(trimmed.u16Count > 300 ? "…" : "")"
        return Chunk(chunkId: "\(docId)\(cardSuffix)", docId: docId, title: "\(title) (about this file)", body: text, source: fileName, collectionId: collectionId)
    }

    /// An overview's passages: up to `hits` of what the search found (cards left out: the file's own opening says more),
    /// then `openings` (each file's opening part) for every file those hits don't cover, up to `limit` in all. Each file
    /// gets its opening before a second hit from any file does.
    public static func withOpenings(_ found: [Chunk], _ openings: [Chunk], hits: Int, limit: Int) -> [Chunk] {
        let first = Array(found.filter { !isCard($0) }.prefix(max(0, hits)))
        let docs = Set(first.map(\.docId))
        var seen = Set<String>()
        return Array((first + openings.filter { !docs.contains($0.docId) }).filter { seen.insert($0.chunkId).inserted }.prefix(max(0, limit)))
    }

    /// A card is there to find its file: once a part of the same file is among the passages, it only repeats it.
    public static func dropCoveredCards(_ chunks: [Chunk]) -> [Chunk] {
        let withPart = Set(chunks.filter { !isCard($0) }.map(\.docId))
        return chunks.filter { !isCard($0) || !withPart.contains($0.docId) }
    }
}
