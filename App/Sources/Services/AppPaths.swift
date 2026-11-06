import BoarCore
import Foundation
import os

/// Where BOAR keeps its files on the phone (Android `context.filesDir`): Application Support/BOAR.
///
/// Same layout under it as the Android and Expo apps, so the engine's paths need no mapping:
/// `models/`, `corpus/` (downloaded), `SQLite/aoair_knowledge.db` (knowledge base and chats),
/// `integrity.json`, `model-load.marker.json`, `setup_progress.json`, `discovered_models.json`.
enum AppPaths {
    private static let log = BoarLog.logger("storage")

    static let filesDir: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(filePath: NSTemporaryDirectory())
        // The UI demo wipes what it finds: it gets its own folder, so the real models and chats survive a capture run.
        let dir = base.appending(path: DebugLaunch.demo ? "BOAR-demo" : "BOAR", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppPaths.markFilesDir(dir)
        return dir
    }()

    /// Like Android (data_extraction_rules.xml), on iPhone and iPad the whole folder (chats, documents, the knowledge
    /// base, models, packs) stays out of iCloud and computer backups. Excluding the folder excludes everything in it;
    /// set on every launch, so existing installs leave the next backup too. On the Mac it would also leave Time Machine,
    /// the user's own backup, so there only the downloads (models, packs, partial files) are excluded.
    static func markFilesDir(_ dir: URL) {
        #if os(iOS)
        var url = dir
        excludeFromBackup(&url)
        #endif
    }

    /// Where the settings live: the app's defaults, or a separate suite for the UI demo (it resets them every launch).
    nonisolated(unsafe) static let defaults: UserDefaults =
        DebugLaunch.demo ? UserDefaults(suiteName: "team.sopa.boar.native.demo") ?? .standard : .standard

    static var knowledgeBase: URL { directory("SQLite").appending(path: "aoair_knowledge.db") }
    // Downloads are excluded on their own too: the Mac keeps the rest of the folder in Time Machine.
    static var corpusDir: URL { directory("corpus", excludedFromBackup: true) }
    static var modelsDir: URL { directory("models", excludedFromBackup: true) }
    static var loadMarker: URL { filesDir.appending(path: "model-load.marker.json") }
    static var setupProgress: URL { filesDir.appending(path: "setup_progress.json") }
    static var discoveredModels: URL { filesDir.appending(path: "discovered_models.json") }
    /// Resume data of interrupted background downloads, one file per asset id.
    static var resumeDir: URL { directory(".resume", excludedFromBackup: true) }

    /// A subdirectory of `filesDir`, created on first use.
    static func directory(_ name: String, excludedFromBackup: Bool = false) -> URL {
        let url = filesDir.appending(path: name, directoryHint: .isDirectory)
        return excludedFromBackup ? backupExcludedDirectory(url) : created(url)
    }

    /// A folder, created on first use and kept out of iCloud, computer and Time Machine backups.
    @discardableResult static func backupExcludedDirectory(_ url: URL) -> URL {
        var url = created(url)
        excludeFromBackup(&url)
        return url
    }

    /// Keeps a file or folder out of backups. The privacy policy relies on it, so a refusal is logged.
    static func excludeFromBackup(_ url: inout URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            let name = url.lastPathComponent
            log.error("exclude from backup: \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func created(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file shipped in the app bundle (Resources/Data).
    static func bundled(_ name: String, ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }
}
