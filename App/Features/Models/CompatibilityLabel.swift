import BoarModels
import SwiftUI

/// The RAM-fit verdict for this iPhone as one small line ("May be slow on this \(Platform.deviceNoun)"), outline symbol in its status color.
struct CompatibilityLabel: View {
    let fit: Compatibility

    var body: some View {
        if let text = fit.plainLabel, let symbol = fit.symbol {
            Label(text, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(fit.color)
        }
    }
}
