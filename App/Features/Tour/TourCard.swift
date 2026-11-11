import SwiftUI

/// One card of BOAR's tour (android ui/tour/TourScreen.kt `TourCard`, `tourCards`), in Android's order. The copy is
/// Android's (native.tour.<key>.*) with three iOS changes: "phone" is this device's name, the "where" lines name the
/// iOS screens (the sidebar is Android's menu; Advanced holds Adaptive Routing and Boar Labs), and the PIN and Labs
/// cards say what the iOS app has (Face ID or the passcode instead of a PIN; the labs ported so far).
enum TourCard: String, CaseIterable, Identifiable, Sendable {
    case welcome, theme, styles, deep, sources, knowledge, models, adaptive, lock, labs, end

    var id: String { rawValue }

    /// The tour's cards; Adaptive Routing and Boar Labs only in builds with the Experimental section, as on Android.
    static func cards(experimental: Bool) -> [TourCard] {
        allCases.filter { experimental || ($0 != .adaptive && $0 != .labs) }
    }

    /// What sits above the title: the brand avatar, the mascot, or the Boar icon pack's drawing (the same as in
    /// Settings).
    enum Art: Hashable { case avatar, mascot, icon(AppIcon) }

    var art: Art? {
        switch self {
        case .welcome: .avatar
        case .end: .mascot
        case .lock: .icon(Symbols.lock)
        case .labs: .icon(Symbols.labs)
        default: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .welcome: "Meet BOAR"
        case .theme: "Make it yours"
        case .styles: "Pick how BOAR answers"
        case .deep: "Deep Research"
        case .sources: "Sources and receipts"
        case .knowledge: "BOAR Knowledge and your Personal Files"
        case .models: "Models"
        case .adaptive: "Adaptive routing"
        case .lock: "Lock BOAR"
        case .labs: "Boar Labs"
        case .end: "That's the tour"
        }
    }

    var text: LocalizedStringResource {
        switch self {
        case .welcome:
            "BOAR answers on your \(Platform.deviceNoun), from its own offline library, and shows where each answer came from. Here's a quick look around while it gets ready."
        case .theme: "Pick a theme. It changes right away, and you can change it again any time."
        case .styles:
            "Succinct & Direct for quick replies, Thorough & Detailed for full explanations (the default), Personal Files to answer only from your own documents."
        case .deep:
            "For big questions: BOAR searches in several steps and writes a longer answer. It takes more time. When it's on, the chat glows and the 🔬 lights up, so you always know."
        case .sources:
            "An answer from the library lists the articles it used: tap one to read it. A receipt shows the model, the speed and the time."
        case .knowledge:
            "BOAR Knowledge is the Vital Articles library on your \(Platform.deviceNoun). Import your notes, PDFs and spreadsheets into Personal Files, then ask about them with the Personal Files style."
        case .models: "Swap the answer model, find more on Hugging Face, and let BOAR free the memory when you leave it."
        case .adaptive:
            "Off by default. Switch it on and BOAR picks which of your installed models answers each question, and how. Worth it when you have more than one model."
        case .lock:
            "Face ID, Touch ID or your passcode seals your chats and hides BOAR's screen in the app switcher. Imported documents aren't encrypted yet."
        case .labs:
            "Experiments, labelled beta or alpha. They all start off: switch on the ones you want.\n\nAlso try Boar Press, which turns answers into a PDF.\n\nIf one misbehaves, switch it off and, if you can, open an issue on GitHub."
        case .end: "BOAR is ready when the download is. You can see this tour again from Settings."
        }
    }

    /// Where to find it in the app; none on the welcome and end cards.
    var place: LocalizedStringResource? {
        switch self {
        case .welcome, .end: nil
        case .theme: "Settings → Display"
        case .styles, .deep: "The style button in the chat, or Settings → Answers"
        case .sources: "Under every answer"
        case .knowledge: "Menu → Knowledge"
        case .models: "Menu → Models"
        case .adaptive: "Settings → Advanced, with Show Technical Details on"
        case .lock: "Settings → Privacy"
        case .labs: "Settings → Advanced → Boar Labs"
        }
    }
}
