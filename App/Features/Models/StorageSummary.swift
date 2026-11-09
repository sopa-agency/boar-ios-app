import SwiftUI

/// What BOAR takes on this iPhone, read at a glance: the size in large type, a capacity bar against the free space,
/// and the free space under it.
struct StorageSummary: View {
    let usedBytes: Int64?
    let freeBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(usedBytes.map(Self.format) ?? "—")
                    .font(.boar("ui.titleLg"))
                    .monospacedDigit()
                    .foregroundStyle(.boar(.heading))
                    .contentTransition(.numericText())
                Text("used by BOAR")
                    .foregroundStyle(.boar(.secondary))
            }
            if let usedBytes, let freeBytes, usedBytes + freeBytes > 0 {
                Gauge(value: Double(usedBytes), in: 0...Double(usedBytes + freeBytes)) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .accessibilityHidden(true)
            }
            Label {
                Text("\(freeBytes.map(Self.format) ?? "—") free on this \(Platform.deviceNoun)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: Symbols.storage)
            }
            .font(.boar("ui.subtext"))
            .foregroundStyle(.boar(.muted))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
