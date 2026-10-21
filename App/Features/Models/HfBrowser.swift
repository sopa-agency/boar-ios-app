import BoarCore
import BoarModels
import CryptoKit
import Foundation

/// Searching Hugging Face for GGUF models beyond the curated catalog (android `HfBrowser.kt`, src/services/modelBrowser.ts).
/// One of the two places BOAR uses the network, only while the user searches; never during chat. Results aren't
/// vetted: the download is pinned to the commit that was listed, and checked against the LFS sha256 when there is one.
enum HfBrowser {
    /// A repo as listed, with the facts from its GGUF header: parameter count, architecture, context length.
    struct Repo: Identifiable, Hashable, Sendable {
        var id: String
        var downloads: Int64?
        var likes: Int64?
        var params: Int64?
        var architecture: String?
        var contextLength: Int64?
        var tags: [String] = []
    }

    struct GgufFile: Identifiable, Hashable, Sendable {
        var filename: String
        var sizeBytes: Int64
        var sha256: String?
        var revision: String?
        var id: String { filename }
    }

    struct Page: Sendable {
        var repos: [Repo]
        var next: String?
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "BOAR-native"]
        return URLSession(configuration: c)
    }()

    private static func get(_ url: String) async throws -> (Data, String?) {
        guard let u = URL(string: url) else { throw Failure(message: "Bad URL: \(url)") }
        let (data, response) = try await session.data(from: u)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure(message: String(localized: "Hugging Face answered \(code)")) }
        return (data, http?.value(forHTTPHeaderField: "Link"))
    }

    /// One page of the search (`HfQuery.searchUrl`, or the previous page's `next`): text-generation GGUF repos whose
    /// architecture BOAR can chat with, without uncensored ones. A page can come back shorter than asked, or empty with a next.
    static func browse(_ url: String) async throws -> Page {
        guard url.hasPrefix("\(HfQuery.api)/models?") else { throw Failure(message: "Not a Hugging Face model listing: \(url)") }
        let (data, link) = try await get(url)
        guard let root = JSONValue(jsonString: String(decoding: data, as: UTF8.self)), let list = root.arrayValue else {
            throw Failure(message: String(localized: "Hugging Face sent an unexpected answer."))
        }
        let repos = list.compactMap { o -> Repo? in
            let g = o["gguf"]
            let tags = o["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let repo = Repo(id: o["id"]?.stringValue ?? "", downloads: o["downloads"]?.int64Value, likes: o["likes"]?.int64Value,
                            params: g?["total"]?.int64Value, architecture: g?["architecture"]?.stringValue,
                            contextLength: g?["context_length"]?.int64Value, tags: tags)
            guard !repo.id.isEmpty, HfQuery.chatArchitecture(repo.architecture) else { return nil }
            // Uncensored and adult models stay out of this build (Android: only with ALLOW_UNCENSORED_MODELS).
            return HfQuery.uncensored(repo.id, tags: repo.tags) ? nil : repo
        }
        return Page(repos: repos, next: HfQuery.nextUrl(link))
    }


    /// "owner/name" only: anything else could reach another API path.
    static func checkRepo(_ repoId: String) throws -> String {
        guard repoId.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*/) != nil, !repoId.contains("..") else { throw Failure(message: "Not a Hugging Face repo id: \(repoId)") }
        return repoId
    }

    /// java.net.URLEncoder with "+" as "%20": letters, digits and `.-*_` stay, everything else is percent-encoded.
    private static func enc(_ segment: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    private static func repoPath(_ repoId: String) throws -> String {
        try checkRepo(repoId).split(separator: "/").map { enc(String($0)) }.joined(separator: "/")
    }

    /// The repo's whole GGUF files BOAR can add, smallest first.
    static func files(_ repoId: String) async throws -> [GgufFile] {
        let (data, _) = try await get("\(HfQuery.api)/models/\(try repoPath(repoId))?blobs=true")
        guard let o = JSONValue(jsonString: String(decoding: data, as: UTF8.self)) else { throw Failure(message: String(localized: "Hugging Face sent an unexpected answer.")) }
        let revision = o["sha"]?.stringValue.flatMap { $0.wholeMatch(of: /[0-9a-f]{40}/) != nil ? $0 : nil }
        return (o["siblings"]?.arrayValue ?? [])
            .map { s in GgufFile(filename: s["rfilename"]?.stringValue ?? "", sizeBytes: s["size"]?.int64Value ?? 0, sha256: s["lfs"]?["oid"]?.stringValue, revision: revision) }
            .filter { HfQuery.addableFile($0.filename, sizeBytes: $0.sizeBytes) }
            .sorted { $0.sizeBytes < $1.sizeBytes }
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().replacing(/[^a-z0-9]+/, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// toCatalogModel: the same id and file name as the Expo and Android apps, so a model added in either is the same file.
    static func toAsset(repoId: String, file f: GgufFile) throws -> CatalogAsset {
        guard !f.filename.contains(".."), !f.filename.hasPrefix("/") else { throw Failure(message: "Unsafe file name: \(f.filename)") }
        let full = "hf-\(slug(repoId))-\(slug(f.filename))"
        let id: String
        if full.count <= 120 {
            id = full
        } else {
            let digest = Insecure.SHA1.hash(data: Data(full.utf8)).map { String(format: "%02x", $0) }.joined()
            id = String(full.prefix(111)) + "-" + String(digest.prefix(8))
        }
        var label = f.filename
        for suffix in [".gguf", ".GGUF"] where label.hasSuffix(suffix) { label = String(label.dropLast(suffix.count)) }
        let path = f.filename.split(separator: "/", omittingEmptySubsequences: false).map { enc(String($0)) }.joined(separator: "/")
        return CatalogAsset(
            id: id, kind: .llm, label: label, filename: "models/\(id).gguf", sizeBytes: f.sizeBytes, sha256: f.sha256 ?? "",
            sourceUrl: "https://huggingface.co/\(try repoPath(repoId))/resolve/\(enc(f.revision ?? "main"))/\(path)",
            license: "Unknown — check the model's Hugging Face page",
            description: "\(repoId) — added via model search, not vetted by aoair", required: false
        )
    }
}
