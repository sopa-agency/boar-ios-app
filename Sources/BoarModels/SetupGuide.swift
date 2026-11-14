import Foundation

/// The pages setup walks through while it downloads (android SetupGuide.kt): the user makes BOAR theirs and learns to
/// use it in the same flow, instead of waiting on a progress bar. Every page can be skipped; what it sets is saved as
/// it's chosen.
public enum SetupGuide {
    /// In this order: the files come before the answer modes, so Personal Files is taught with files in hand; the first
    /// question has its own page. Notifications have their own page on Android 13 and newer, where Android asks for them;
    /// iOS never shows it (BOAR posts no notification there).
    public enum Page: String, CaseIterable, Sendable {
        case look = "LOOK", files = "FILES", answers = "ANSWERS", ask = "ASK", first = "FIRST", pin = "PIN"
        case notify = "NOTIFY", privacy = "PRIVACY", labs = "LABS", ready = "READY"
    }

    /// The pages in order. `pinSetBefore`: a PIN was already set when this setup started (setup run again from
    /// Settings → Recovery), so there's nothing to offer; a PIN set on the PIN page keeps the page, so the list doesn't
    /// shift under the user. `experimental`: the Boar Labs page, only in builds with Labs. `notifications`: the
    /// platform asks for a notification permission; the page stays once allowed, so the list never shifts.
    public static func pages(experimental: Bool, pinSetBefore: Bool, notifications: Bool) -> [Page] {
        Page.allCases.filter {
            switch $0 {
            case .pin: !pinSetBefore
            case .notify: notifications
            case .labs: experimental
            default: true
            }
        }
    }

    /// The pages and the page index of a setup that resumes in a new process. `pinPage`: whether its pages had the PIN
    /// page when it was saved (nil: saved by a build without it). A PIN set on that page must not drop the page now, or
    /// every page after it would shift by one. `page`: the saved page's name; an unknown one starts over.
    public static func resume(experimental: Bool, pinPage: Bool?, pinSetNow: Bool, notifications: Bool, page: String?) -> (pages: [Page], index: Int) {
        let pages = pages(experimental: experimental, pinSetBefore: pinPage.map { !$0 } ?? pinSetNow, notifications: notifications)
        return (pages, max(0, pages.firstIndex { $0.rawValue == page } ?? 0))
    }

    /// Whether files picked during setup can be imported now. They need the search model to embed them; and not while
    /// the index builds, which runs the search model over the same database: both at once would slow the index and hold
    /// the model twice. Nor twice at once.
    public static func canImport(searchModelPresent: Bool, indexBuilding: Bool, importing: Bool) -> Bool {
        searchModelPresent && !indexBuilding && !importing
    }

    /// The picked files not in the last finished import: an import is needed while this isn't empty.
    public static func pending(onDisk: [String], imported: [String]) -> [String] {
        onDisk.filter { !imported.contains($0) }
    }

    /// A name for a copied file that doesn't overwrite another picked one: "notes.txt", then "notes (2).txt".
    /// `taken`: the names already in the folder.
    public static func freeName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let dot = name.lastIndex(of: ".").flatMap { $0 > name.startIndex ? $0 : nil } ?? name.endIndex
        let base = name[..<dot], ext = name[dot...]
        var n = 2
        while taken.contains("\(base) (\(n))\(ext)") { n += 1 }
        return "\(base) (\(n))\(ext)"
    }
}
