import Foundation

/// Where BOAR keeps its files on the phone (Android `context.filesDir`): Application Support/BOAR.
///
/// Same layout under it as the Android and Expo apps, so the engine's paths need no mapping:
/// `models/`, `corpus/` (downloaded), `SQLite/aoair_knowledge.db` (knowledge base and chats),
/// `integrity.json`, `model-load.marker.json`, `setup_progress.json`, `discovered_models.json`.
enum AppPaths {
    static let filesDir: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(filePath: NSTemporaryDirectory())
        // The UI demo wipes what it finds: it gets its own folder, so the real models and chats survive a capture run.
        var dir = base.appending(path: DebugLaunch.demo ? "BOAR-demo" : "BOAR", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Like Android (data_extraction_rules.xml): chats, documents, the knowledge base, models and packs stay on this
        // device, out of iCloud and computer backups. Excluding the folder excludes everything in it; set on every launch,
        // so existing installs leave the next backup too.
        AppPaths.excludeFromBackup(&dir)
        return dir
    }()

    /// Where the settings live: the app's defaults, or a separate suite for the UI demo (it resets them every launch).
    nonisolated(unsafe) static let defaults: UserDefaults =
        DebugLaunch.demo ? UserDefaults(suiteName: "team.sopa.boar.native.demo") ?? .standard : .standard

    static var knowledgeBase: URL { directory("SQLite").appending(path: "aoair_knowledge.db") }
    static var corpusDir: URL { directory("corpus", excludedFromBackup: true) }
    static var modelsDir: URL { directory("models", excludedFromBackup: true) }
    static var loadMarker: URL { filesDir.appending(path: "model-load.marker.json") }
    static var setupProgress: URL { filesDir.appending(path: "setup_progress.json") }
    static var discoveredModels: URL { filesDir.appending(path: "discovered_models.json") }
    /// Resume data of interrupted background downloads, one file per asset id.
    static var resumeDir: URL { directory(".resume", excludedFromBackup: true) }

    /// A subdirectory of `filesDir`, created on first use.
    static func directory(_ name: String, excludedFromBackup: Bool = false) -> URL {
        var url = filesDir.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if excludedFromBackup { excludeFromBackup(&url) }
        return url
    }

    static func excludeFromBackup(_ url: inout URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// A file shipped in the app bundle (Resources/Data).
    static func bundled(_ name: String, ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }
}
