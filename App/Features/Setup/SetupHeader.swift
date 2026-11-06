import BoarCore
import SwiftUI

/// The top of a setup step: its title in large type and one or two lines on what it is for, above the choices (the
/// navigation bar only carries "Step 2 of 4" and Back). It is a section of its own, a clear row, so the list's header
/// style doesn't grey it out.
struct SetupHeader: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            content
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        }
        .compactSectionSpacing()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.boarDisplay(size: 32, relativeTo: .largeTitle))
                .boarDisplayLines()
                .foregroundStyle(Color(palette.textHeading))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .boarText("ui.body")
                .foregroundStyle(Color(palette.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
