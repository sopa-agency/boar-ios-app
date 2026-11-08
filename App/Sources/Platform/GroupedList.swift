import SwiftUI

/// A screen of sections (facts, choices, results) in the theme (`BoarForm`'s cards, text colors and fonts): the grouped list on
/// iPhone, a grouped form on the Mac, where an inset list stretched across a wide window reads as one flat table.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        #if os(macOS)
        Form { rows }
            .formStyle(.grouped)
            .boarListBackground()
            .boarFormText()
        #else
        List { rows }
            .groupedListStyle()
            .boarListBackground()
            .boarFormText()
        #endif
    }

    private var rows: some View {
        Group { content }
            .listRowBackground(Color(palette.bgCard))
            .listRowSeparatorTint(Color(palette.borderSubtle))
    }
}
