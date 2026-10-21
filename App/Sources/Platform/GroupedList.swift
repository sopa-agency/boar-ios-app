import SwiftUI

/// A screen of sections (facts, choices, results): the grouped list on iPhone, a grouped form in the System Settings look
/// on the Mac, where an inset list stretched across a wide window reads as one flat table.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        Form { content }
            .formStyle(.grouped)
        #else
        List { content }
            .groupedListStyle()
        #endif
    }
}
