import Foundation

/// The menu's chat list (android ChatList, rc3 f6e987fb; adam, Nov 12): grouped by day, searchable once there are many,
/// deletes undoable for a moment.
public enum ChatList {
    public enum Group: Sendable, CaseIterable { case today, yesterday, earlier }

    /// A search box shows above this many saved chats.
    public static let searchFrom = 10
    /// How long "Chat deleted · Undo" waits before the chat is really deleted.
    public static let undoMs = 5_000

    /// By the calendar day in `zone`, not by 24 hours (android groupOf). Times are milliseconds since 1970.
    public static func groupOf(updatedAt: Int64, now: Int64, zone: TimeZone = .current) -> Group {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
        let day = date(updatedAt)
        if calendar.isDate(day, inSameDayAs: date(now)) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: date(now)), calendar.isDate(day, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }

    /// Every word of `query` in the title, case and accents ignored; a blank query keeps everything.
    public static func matches(_ query: String, title: String) -> Bool {
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let t = fold(title)
        return words.allSatisfy { t.contains($0) }
    }
}
