#if os(macOS)
import SwiftUI

/// A list beside the selected item's details, for the Mac's library screens (Models, Documents, Hugging Face): the list
/// keeps its width, the details take the rest of the window and never push the sidebar away.
struct MasterDetail<Master: View, Detail: View>: View {
    var masterWidth: CGFloat = 320
    @ViewBuilder var master: Master
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            master
                .frame(width: masterWidth)
            Divider()
            detail
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}
#endif
