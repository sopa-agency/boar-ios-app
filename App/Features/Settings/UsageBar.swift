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
    /// Bytes on their way (running downloads), drawn after `used` in a lighter tint and counted in the numbers.
    var pending: Int64 = 0
    /// The sidebar's small version (android `UsageBar(large = false)`): smaller text and a 5 pt bar.
    var compact = false
    @Environment(\.palette) private var palette

    private var fraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
    private var pendingFraction: Double { total > 0 ? min(Double(used + pending) / Double(total), 1) - fraction : 0 }
    private var over: Bool { total > 0 && used + pending > total }
    private var style: ByteCountFormatStyle.Style { kind == .memory ? .memory : .file }
    private var tint: Color {
        Color(over ? palette.crimson500 : kind == .memory ? palette.emerald400 : palette.cyan400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(compact ? .boar("mono.xs").bold() : .boar("ui.subtext").bold())
                    .foregroundStyle(.boar(compact ? .dim : .secondary))
                Spacer()
                Text(verbatim: "\((used + pending).formatted(.byteCount(style: style))) / \(total.formatted(.byteCount(style: style)))")
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.muted))
            }
            // Android's bar (UsageBar, large): 9 pt on the theme's track(0.5), a borderDefault outline, 3 pt corners.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Color.black.opacity(palette.trackAlpha(0.5))
                    HStack(spacing: 0) {
                        tint.frame(width: g.size.width * fraction)
                        tint.opacity(0.35).frame(width: g.size.width * pendingFraction)
                    }
                }
            }
            .frame(height: compact ? 5 : 9)
            .clipShape(.rect(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(palette.borderDefault), lineWidth: 1))
            Text(verbatim: caption)
                .font(compact ? .boar("mono.xs") : .boar("ui.subtext"))
                .foregroundStyle(.boar(.dim))
        }
        .padding(.vertical, compact ? 0 : 4)
        .accessibilityElement(children: .combine)
        // The percentage the system ProgressView used to speak, on top of the numbers.
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
