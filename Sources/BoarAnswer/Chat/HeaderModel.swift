/// The model the chat header names (android `chat/HeaderModel.kt`): the one that writes the answer, from one source, never
/// a name kept apart. While adaptive routing has another model write the answer: "→ that model". Else the answering model
/// (`BoarServices.answerModel`: the user's pick, or the model answering in its place). Nil: none (the header's default line).
public enum HeaderModel {
    public static func label(answeringNow: Bool, answeringModel: String?, phoneModel: String?) -> String? {
        if answeringNow, let answeringModel { return "→ \(answeringModel)" }
        return phoneModel
    }
}
