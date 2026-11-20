import BoarAnswer

/// A new chat would delete the oldest under the user's limit, so the first question waits for a choice (android rc3
/// 6a974612). `title`: the oldest chat it deletes; `more`: how many others go with it; `max`: the user's limit.
struct PruneNote: Equatable {
    let title: String
    let more: Int
    let max: Int
}

/// The question the note holds, with the answer limit it was asked under.
struct PrunedQuestion: Equatable {
    let text: String
    let limit: Int?
}
