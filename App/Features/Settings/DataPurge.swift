import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import Foundation

/// Settings → Erase All Data (Android's "clear app data", which iOS has no API for): every downloaded file, document,
/// chat and BOAR setting, including the network server and its API key. The knowledge base file stays open and is emptied instead of deleted.
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
            for name in AppPaths.downloadDirs + ["integrity.json", "setup_progress.json", "discovered_models.json", "model-load.marker.json"] {
                try? fm.removeItem(at: s.filesDir.appending(path: name))
            }
            // On the Mac the download folders are excluded one by one: recreate them excluded before the next download.
            AppPaths.markFilesDir(s.filesDir)
            return ()
        }
        Labs.shared.eraseUserData()
        if let lock, lock.enabled { await lock.eraseChatsAndReset() }
        services.settings.resetPreferences()
        // Boar Avatars: counts, unlocked avatars and the Boarverse switch (outside preferenceKeys, as Reset settings keeps them).
        services.vault.erase()
        // The network server's address (a setting outside preferenceKeys) and its API key (Keychain, which also
        // outlives an uninstall).
        RemoteConfig.setAddress("", services.settings)
        RemoteConfig.setApiKey("")
        for key in ["activeModelId", "modelRoleAssignments", "lastLoadedModelId", ModelBackend.settingsKey] {
            services.settings.setJSONValue(nil, forKey: key)
        }
        await SpotlightDonor().sync([], locked: true)
    }
}
