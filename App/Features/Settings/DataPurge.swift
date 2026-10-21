import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import Foundation

/// Settings → Erase All Data (Android's "clear app data", which iOS has no API for): every downloaded file, document,
/// chat and BOAR setting. The knowledge base file stays open and is emptied instead of deleted.
enum DataPurge {
    @MainActor
    static func eraseAll(services: BoarServices, lock: AppLock?) async {
        await services.host.unload()
        await services.embedder.unload()
        services.packs.reload()
        _ = try? await services.background { s in
            try s.chats.clearAll()
            for c in try s.knowledgeBase.collections() { try s.knowledgeBase.deleteCollection(c.id) }
            _ = try s.knowledgeBase.deleteSeedChunksWithPrefix("wiki-")
            let fm = FileManager.default
            for name in ["models", "corpus", ".resume", "integrity.json", "setup_progress.json", "discovered_models.json", "model-load.marker.json"] {
                try? fm.removeItem(at: s.filesDir.appending(path: name))
            }
            return ()
        }
        if let lock, lock.enabled { await lock.eraseChatsAndReset() }
        services.settings.resetPreferences()
        for key in ["activeModelId", "modelRoleAssignments", "lastLoadedModelId", ModelBackend.settingsKey] {
            services.settings.setJSONValue(nil, forKey: key)
        }
        await SpotlightDonor().sync([], locked: true)
    }
}
