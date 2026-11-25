/// The text of the two "delete your oldest chats" dialogs (Settings' lower limit, and a new chat past the limit): the
/// chats named, then, when the plugins keep things made from their answers, what goes with them (android rc3 bba0ac83,
/// engine/settings/PruneText.kt). Press's projects and the cards go with a deleted chat on iOS too, so both dialogs pass
/// `true` (android `UserData.pluginsKeepAnswers`).
public enum PruneText {
    public static func of(_ chats: String, _ pluginsLine: String, pluginsOn: Bool) -> String {
        pluginsOn && !pluginsLine.allSatisfy(\.isWhitespace) ? "\(chats)\n\n\(pluginsLine)" : chats
    }
}
