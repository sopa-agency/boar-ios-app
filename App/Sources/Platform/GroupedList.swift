import SwiftUI

/// A screen of sections (facts, choices, results) in the theme (`BoarForm`'s cards and text): the grouped list on
/// iPhone, a grouped form on the Mac, where an inset list stretched across a wide window reads as one flat table.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        #if os(macOS)
        Form { rows }
            .formStyle(.grouped)
            .boarListBackground()
            .font(.boar("ui.body"))
        #else
        List { rows }
            .groupedListStyle()
            .boarListBackground()
            .font(.boar("ui.body"))
        #endif
    }

    private var rows: some View {
        Group { content }
            .listRowBackground(Color(palette.bgCard))
            .listRowSeparatorTint(Color(palette.borderSubtle))
    }
}
