import BoarCore
import Foundation

/// A source under an answer, read whole (port of SourceArticle.kt, Oct 24): the article or file the passage came from,
/// as it is on the phone, found by the source's docId. Nothing goes online: a pack that was removed, or a collection
/// deleted since the answer, reads as nil.
public enum SourceArticle {
    /// `markdown`: the text has "#" headings (a pack article, a .md file) and is shown as Markdown.
    public struct Article: Sendable, Equatable {
        public var title: String
        public var text: String
        public var source: String?
        public var markdown: Bool
    }

    private static let packArticle = Rx("^pack:(.+):a(\\d+)$")
    private static let packTitle = Rx("^pack:([^:]+):(.+)$")
    private static let part = Rx("-c(\\d+)$")

    /// The whole of `docId`'s source: a format-2 pack article ("pack:<pack>:a<id>"), a format-1 pack's passages with
    /// that title ("pack:<pack>:<title>"), else the knowledge base's parts of that document (the built-in library,
    /// Personal Files). `title`: the source's title, shown when the store has none of its own.
    public static func read(docId: String, title: String, kb: KnowledgeBase, packs: [OpenPack]) -> Article? {
        if let m = packArticle.find(docId) {
            let packId = m.group(1), articleId = m.group(2).flatMap { Int64($0) }
            guard let articleId, let pack = packs.lazy.compactMap({ p -> WikiPack? in
                if case .format2(let id, let wp) = p, id == packId { return wp } else { return nil }
            }).first, let a = try? pack.article(articleId) else { return nil }
            let label = Packs.sourceLabel[a.source] ?? "Source"
            let license = (a.license ?? "").isEmpty ? "" : " (\(a.license!))"
            return Article(title: a.title, text: a.text, source: "\(label) — \(Packs.articleUrl(a.title, a.source, url: a.url))\(license)", markdown: true)
        }
        if let m = packTitle.find(docId) {
            guard let packId = m.group(1), let packTitle = m.group(2), let db = packs.lazy.compactMap({ p -> (any SqlDatabase)? in
                if case .format1(let id, let db) = p, id == packId { return db } else { return nil }
            }).first else { return nil }
            let rows = (try? db.query("SELECT body, source FROM chunks WHERE title = ? ORDER BY id", args: [.text(packTitle)]) { r in
                (r.string(0) ?? "", r.string(1))
            }) ?? []
            if rows.isEmpty { return nil }
            return Article(title: packTitle, text: rows.map(\.0).joined(separator: "\n\n"), source: rows.lazy.compactMap(\.1).first, markdown: false)
        }
        let parts = ((try? kb.docParts(docId)) ?? []).stableSorted(by: { partNumber($0) < partNumber($1) })
        guard let first = parts.first else { return nil }
        let source = parts.lazy.compactMap(\.source).first
        let name = first.title.components(separatedBy: " (part ").first ?? first.title
        let lower = (source ?? "").lowercased()
        return Article(
            title: Js.trim(name).isEmpty ? title : name, text: join(parts.map(\.body)), source: source,
            markdown: lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
        )
    }

    private static func partNumber(_ c: Chunk) -> Int { part.find(c.chunkId)?.group(1).flatMap { Int($0) } ?? 0 }

    /// Parts cut with an overlap (DocumentImport.chunkText) joined back: each part's start that repeats the text so far
    /// goes. Lengths in UTF-16 units, as the Kotlin counts them.
    public static func join(_ parts: [String]) -> String {
        parts.reduce("") { acc, part in
            if acc.isEmpty { return part }
            let a = acc as NSString, p = part as NSString
            let maxK = min(DocumentImport.overlapChars, a.length, p.length)
            var k = 0
            if maxK >= 20 {
                for n in stride(from: maxK, through: 20, by: -1) where a.hasSuffix(p.substring(to: n)) {
                    k = n
                    break
                }
            }
            return k > 0 ? acc + p.substring(from: k) : acc + "\n\n" + part
        }
    }

    private static let sectionPrefix = Rx("^[^\\n:]{1,120}: ")

    /// Where the passage the model read sits in `text`: as is, else without the pack's "Section: " prefix
    /// (Packs.packHitToChunk), else by its first 120 characters. Nil when it isn't there (compressed, or edited since).
    /// The range is in UTF-16 offsets (NSRange), as the Kotlin's.
    public static func passageAt(_ text: String, _ passage: String) -> NSRange? {
        let p = passage.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        if p.length == 0 { return nil }
        let t = text as NSString
        var tries: [String] = [p as String]
        if let m = sectionPrefix.find(p as String) { tries.append(p.substring(from: m.end)) }
        if p.length > 120 { tries.append(p.substring(to: 120)) }
        for candidate in tries {
            let r = t.range(of: candidate)
            if r.location != NSNotFound {
                let c = candidate as NSString
                // A cut passage marks only what was found, not past it.
                let len = c.length == 120 && candidate != p as String ? min(p.length, t.length - r.location) : c.length
                return NSRange(location: r.location, length: len)
            }
        }
        return nil
    }
}
