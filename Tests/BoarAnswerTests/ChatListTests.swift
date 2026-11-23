import Foundation
import Testing

@testable import BoarAnswer

/// android ChatListTest (rc3 f6e987fb).
struct ChatListTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let now: Int64 = 1_762_871_400_000  // 2025-11-11 14:30 UTC
    private let hour: Int64 = 3_600_000

    @Test func todayYesterdayAndEarlierByTheCalendarDayNot24Hours() {
        #expect(ChatList.groupOf(updatedAt: now - 14 * hour, now: now, zone: utc) == .today)
        #expect(ChatList.groupOf(updatedAt: now - 15 * hour, now: now, zone: utc) == .yesterday)
        #expect(ChatList.groupOf(updatedAt: now - 38 * hour, now: now, zone: utc) == .yesterday)
        #expect(ChatList.groupOf(updatedAt: now - 39 * hour, now: now, zone: utc) == .earlier)
    }

    @Test func searchByTheTitlesWordsAccentsAndCaseIgnored() {
        #expect(ChatList.matches("brasilia", title: "Por que Brasília foi construída"))
        #expect(ChatList.matches("napoleon WARS", title: "Napoleon: his rise, his wars"))
        #expect(!ChatList.matches("moon", title: "Napoleon"))
        #expect(ChatList.matches("", title: "anything"))
    }

    @Test func searchShowsAboveTenChatsAndAnUndoWaitsFiveSeconds() {
        #expect(ChatList.searchFrom == 10 && ChatList.undoMs == 5_000)
    }

    /// The drawer part of android Wave4Test: the list is grouped by day, search above ten, a long press has Rename and Delete,
    /// a delete waits for Undo. The app has no test host, so this reads its source. "Add to Press" is left out: Press is BOAR-55.
    @Test func theSidebarGroupsSearchesAndDeletesWithUndo() throws {
        let side = try AppSource.text("App/Features/Sidebar/SessionsSidebar.swift")
        #expect(side.contains("ChatList.groupOf"))
        #expect(side.contains("ChatList.searchFrom"))
        #expect(side.contains("ChatList.matches"))
        #expect(side.contains("ChatList.undoMs"))
        #expect(side.contains(".contextMenu"))
        #expect(!side.contains("Button(\"Add to Press\""))
        for key in ["Today", "Yesterday", "Earlier", "Undo", "Search Chats"] { #expect(try AppSource.portuguese(key) != nil, "\(key)") }
        #expect(try AppSource.portuguese("Deleted: %@") != nil)
    }
}
