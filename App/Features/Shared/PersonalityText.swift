import BoarAnswer
import Foundation

/// An answer style's name and description in the user's language (android `t("personalities.<id>.label")`): the
/// English text from personalities.json is the String Catalog key, added by hand (it isn't in the code).
extension Personality {
    var displayLabel: String { Bundle.main.localizedString(forKey: label, value: label, table: nil) }
    var displayDescription: String { Bundle.main.localizedString(forKey: description, value: description, table: nil) }
}
