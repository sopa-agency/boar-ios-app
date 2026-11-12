import Foundation

extension Vault {
    /// How the app's events change the facts (android app/appearance `TruffleVault.kt` `onOpen` and `answered`, and the
    /// Daily Quiz lab's `record`). Pure: the app reads the network, the clock, the lock and its files, and passes them in.
    public enum Counting {
        /// The app opened (or came back, or left a screen that changes what's installed): the day, a day with no network
        /// at all (iOS has no airplane-mode API), and what the device and the app's files say. Flags only turn on, counts
        /// only grow.
        public static func opened(_ f: Facts, today: Day, noNetwork: Bool, pinOn: Bool, packs: Int, hfModels: Int,
                                  sourceBuild: Bool, degoogled: Bool) -> Facts {
            var f = f
            f.usedDays = Days.add(f.usedDays, today)
            if noNetwork { f.airplaneDays = Days.add(f.airplaneDays, today) }
            f.pinOn = f.pinOn || pinOn
            f.packs = max(f.packs, packs)
            f.hfModels = max(f.hfModels, hfModels)
            f.sourceBuild = f.sourceBuild || sourceBuild
            f.degoogled = f.degoogled || degoogled
            return f
        }

        /// After an answer that wrote something. `tokPerSec` is nil for an instant (Labs) answer, which generated nothing.
        public static func answered(_ f: Facts, sourced: Bool, deep: Bool, portuguese: Bool, tokPerSec: Double?,
                                    newChat: Bool, offline: Bool, night: Bool) -> Facts {
            var f = f
            f.answers += 1
            if sourced { f.sourcedAnswers += 1 }
            if offline { f.offlineAnswers += 1 }
            if night { f.nightAnswers += 1 }
            if deep { f.deepResearch += 1 }
            if newChat { f.chats += 1 }
            f.portuguese = f.portuguese || portuguese
            f.bestTokPerSec = max(f.bestTokPerSec, tokPerSec ?? 0)
            return f
        }

        /// A Daily Quiz question answered on the quiz's `day`.
        public static func quizAnswered(_ f: Facts, right: Bool, day: Day) -> Facts {
            var f = f
            if right { f.quizRight += 1 }
            f.quizDays = Days.add(f.quizDays, day)
            return f
        }

        /// The newly unlocked avatars worth a "New avatar unlocked": not the one every install starts with.
        public static func announced(_ fresh: [String]) -> [String] {
            fresh.filter { rule($0) != .ALWAYS }
        }
    }
}
