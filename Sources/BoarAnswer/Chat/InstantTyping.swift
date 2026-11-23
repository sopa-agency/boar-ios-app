import Foundation

/// A plugin's instant answer shown at typing speed (android InstantTyping, rc3 bd041e73; adam, Nov 12: so fast that
/// nothing seemed to change as the keyboard closed). Presentation only: the receipt keeps the real time and says
/// "instant", never a speed. Not for the safety answer (shown at once), nor with Reduce Motion or VoiceOver on.
public enum InstantTyping {
    /// About 20 tokens a second.
    public static let charsPerSecond = 80
    public static let stepMs = 50
    /// A long answer still ends within this.
    public static let maxMs = 6_000

    public static func typed(tool: String, animationsOff: Bool, screenReader: Bool) -> Bool {
        !tool.hasPrefix("safety-") && !animationsOff && !screenReader
    }

    /// The text in pieces, one per `stepMs`, ending within `maxMs` (longer answers type faster). A piece never ends inside a
    /// character (android: an emoji's surrogate pair, Lunar's moons showed as a box for a frame, validator T-1); words may
    /// split. Counts are in Characters, android's in UTF-16 units; the pace is the same for text without emoji.
    public static func pieces(_ text: String) -> [String] {
        let chars = Array(text)
        if chars.isEmpty { return [] }
        let steps = max(1, min(chars.count * 1000 / charsPerSecond / stepMs, maxMs / stepMs))
        let size = max(1, (chars.count + steps - 1) / steps)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            let end = min(chars.count, i + size)
            out.append(String(chars[i..<end]))
            i = end
        }
        return out
    }
}
