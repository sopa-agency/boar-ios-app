import SwiftUI

/// A usage bar with its numbers and a caption (android `UsageBar`/`UsageCaption`, Settings' Hardware section): how much
/// of `total` is used, amber past 80 % and crimson past 95 %.
struct UsageBar: View {
    let title: LocalizedStringKey
    let used: Int64
    let total: Int64
    let caption: String
    /// Memory in binary units, as iOS Settings shows RAM; storage in decimal ones, like the catalog's sizes (50 GB).
    var style: ByteCountFormatStyle.Style = .memory

    private var fraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
    private var tint: BoarStyle { .boar(fraction > 0.95 ? .danger : fraction > 0.8 ? .warning : .accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(verbatim: "\(used.formatted(.byteCount(style: style))) / \(total.formatted(.byteCount(style: style)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(tint)
            Text(verbatim: caption)
                .font(.boar("ui.subtext"))
                .foregroundStyle(.boar(.muted))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
