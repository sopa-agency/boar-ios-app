import BoarCore
import BoarRAG
import Foundation
import os

/// After an app update adds articles to the built-in library (corpus.json), indexes them in the background on the next
/// launch, so the home's questions find their sources without running setup again. Checks chunk ids first: the search
/// model loads only when an article is missing.
@MainActor
enum BuiltinLibraryRefresh {
    private static var checked = false
    nonisolated private static let log = BoarLog.logger("seed")

    static func run(services: BoarServices) {
        guard !checked else { return }
        checked = true
        Task.detached(priority: .utility) {
            do {
                guard let url = AppPaths.bundled("corpus", ext: "json") else { return }
                let docs = try SeedCorpus.docs(collectionId: SeedCorpus.builtin, json: String(contentsOf: url, encoding: .utf8))
                let missing = try docs.filter { try !services.knowledgeBase.hasChunk($0.id) }.count
                guard missing > 0 else { return }
                log.info("indexing \(missing, privacy: .public) new built-in articles")
                try await KnowledgeIndexer.seedAll(services: services)
            } catch {
                log.error("built-in library refresh failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
