/// What an erase reaches (android `plugins.UserData.Scope`). `chatsKeepPress`: Clear Chat History with "Also delete Press"
/// off: every lab erases as for `chats` except Press, whose basket stays with the answers already in it (android rc3
/// a2f6eaf8). Forgot PIN and Erase All Data are `everything`.
public enum UserDataScope: Sendable, Equatable {
    case chats, chatsKeepPress, everything

    /// Press (the answers basket) is erased by every scope but `chatsKeepPress`.
    public var erasesPress: Bool { self != .chatsKeepPress }

    /// Clear Chat History: Press goes only when the user chose it, so a count that couldn't be read keeps it too
    /// (android rc3 3f15cccd, R-A6).
    public static func clearHistory(alsoPress: Bool) -> UserDataScope { alsoPress ? .chats : .chatsKeepPress }

    /// The choice is shown only when Press holds something; with nothing in it there is nothing to choose.
    public static func offersPressChoice(pressItems: Int) -> Bool { pressItems > 0 }
}
