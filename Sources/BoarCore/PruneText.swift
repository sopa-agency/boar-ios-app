/// The text of the two "delete your oldest chats" dialogs (Settings' lower limit, and a new chat past the limit): the
/// chats named, then, when the plugins keep things made from their answers, what goes with them (android rc3 bba0ac83,
/// engine/settings/PruneText.kt). iOS has no such plugin data yet (Press projects, cards), so its dialogs pass `false`.
public enum PruneText {
    public static func of(_ chats: String, _ pluginsLine: String, pluginsOn: Bool) -> String {
        pluginsOn && !pluginsLine.allSatisfy(\.isWhitespace) ? "\(chats)\n\n\(pluginsLine)" : chats
    }
}
