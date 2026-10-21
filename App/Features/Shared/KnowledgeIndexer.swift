import BoarCore
import BoarLlama
import BoarModels
import BoarRAG
import Foundation

/// Indexes the built-in corpus and the downloaded JSON corpus packs into the knowledge base with the embedding model
/// (setup's index step, and ModelsViewModel.index after a pack download). Already indexed documents are skipped.
enum KnowledgeIndexer {
    struct MissingEmbedder: LocalizedError {
        var errorDescription: String? { String(localized: "The search model is missing. Run setup again from Settings → Recovery.") }
    }

    static func seedAll(services: BoarServices, shouldStop: @escaping @Sendable () -> Bool = { false },
                        onProgress: @escaping @Sendable (SeedCorpus.Progress) -> Void = { _ in }) async throws {
        guard let emb = services.installed(.embedding).first else { throw MissingEmbedder() }
        let embedder = try await LlamaSession.load(path: services.fileOf(emb).path(percentEncoded: false), params: EngineParams.embedder)
        do {
            var collections: [SeedCorpus.Collection] = []
            if let url = AppPaths.bundled("corpus", ext: "json"), let text = try? String(contentsOf: url, encoding: .utf8) {
                collections.append(SeedCorpus.Collection(id: SeedCorpus.builtin, docs: try SeedCorpus.docs(collectionId: SeedCorpus.builtin, json: text)))
            }
            for p in services.catalog.corpusCatalog where p.format != "sqlite-pack" && services.isPresent(p) {
                do {
                    let text = try String(contentsOf: services.fileOf(p), encoding: .utf8)
                    collections.append(SeedCorpus.Collection(id: p.id, docs: try SeedCorpus.docs(collectionId: p.id, json: text)))
                } catch {
                    collections.append(SeedCorpus.Collection(id: p.id, docs: [], error: error.localizedDescription))
                }
            }
            _ = try await SeedCorpus(kb: services.knowledgeBase, embed: { try await embedder.embed($0) })
                .seed(collections, onProgress: onProgress, shouldStop: shouldStop)
            await embedder.close()
        } catch {
            await embedder.close()
            throw error
        }
        services.packs.reload()
    }
}
