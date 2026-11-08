import SwiftUI

/// A usage bar with its numbers and a caption (android `UsageBar`/`UsageCaption` in BoarDrawer.kt, Settings' Hardware
/// section): how much of `total` is used, in the bar's own color (emerald400 for memory, cyan400 for storage), crimson500
/// only once it passes the total.
struct UsageBar: View {
    enum Kind {
        /// Binary units, as iOS Settings shows RAM; emerald400.
        case memory
        /// Decimal units, like the catalog's sizes (50 GB); cyan400.
        case storage
    }

    let title: LocalizedStringKey
    let used: Int64
    let total: Int64
    let caption: String
    var kind: Kind = .memory
    @Environment(\.palette) private var palette

    private var fraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
    private var over: Bool { total > 0 && used > total }
    private var style: ByteCountFormatStyle.Style { kind == .memory ? .memory : .file }
    private var tint: Color {
        Color(over ? palette.crimson500 : kind == .memory ? palette.emerald400 : palette.cyan400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.boar("ui.subtext").bold())
                    .foregroundStyle(.boar(.secondary))
                Spacer()
                Text(verbatim: "\(used.formatted(.byteCount(style: style))) / \(total.formatted(.byteCount(style: style)))")
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.muted))
            }
            ProgressView(value: fraction)
                .tint(tint)
            Text(verbatim: caption)
                .font(.boar("ui.subtext"))
                .foregroundStyle(.boar(.dim))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
