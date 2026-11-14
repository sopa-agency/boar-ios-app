import BoarModels
import SwiftUI

/// The memory and storage bars at the bottom of the sidebar, with Show Technical Details on (android `BoarDrawer`
/// FooterStats): BOAR's memory against what the system lets it use, BOAR's files plus what running downloads still
/// fetch against BOAR's own storage limit, then the last answer's speed. Read every 5 s while the sidebar is up.
struct SidebarStats: View {
    let services: BoarServices
    /// The last answer's speed, nil while answering or before the first answer.
    let lastTokPerSec: Double?
    @State private var footprint: Int64 = 0
    @State private var available: Int64?
    @State private var storage: Int64 = 0
    @State private var fetching: Int64 = 0
    @State private var free: Int64 = 0
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            memory
            disk
            if let lastTokPerSec {
                HStack(spacing: 4) {
                    Text(verbatim: "●")
                        .font(.system(size: 8))
                    Text("\(Receipt.rate(lastTokPerSec)) tok/s last query")
                        .font(.boar("mono.xs").weight(.semibold))
                }
                .foregroundStyle(Color(palette.cyan400))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task {
            while !Task.isCancelled {
                footprint = AppMemory.footprintBytes()
                available = DeviceMemory.availableBytes
                fetching = services.downloads.downloadingBytes()
                storage = (try? await services.background { $0.storageUsedBytes() }) ?? storage
                if let f = (try? await services.background { _ in DeviceStorage.availableBytes() }) ?? nil { free = f }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder private var memory: some View {
        // iOS doesn't tell an app what the others use: BOAR against what it can still take before iOS ends it.
        if let available {
            UsageBar(title: "Memory", used: footprint, total: footprint + available,
                     caption: String(localized: "BOAR \(footprint.formatted(.byteCount(style: .memory))) · \(available.formatted(.byteCount(style: .memory))) more before \(Platform.systemName) closes it"),
                     compact: true)
        } else {
            UsageBar(title: "Memory", used: footprint, total: DeviceStorage.physicalMemoryBytes,
                     caption: String(localized: "BOAR \(footprint.formatted(.byteCount(style: .memory))) of this \(Platform.deviceNoun)'s memory"),
                     compact: true)
        }
    }

    private var disk: some View {
        // No BOAR limit (Boar Labs): BOAR's files against what it could still take, the device's free space.
        let limit = StorageBudget.limit(catalogBudget: services.catalog.storageBudgetBytes)
        let noLimit = limit == StorageBudget.noLimit
        let caption = if noLimit {
            String(localized: "No BOAR limit: up to the \(Platform.deviceNoun)'s free space")
        } else if fetching > 0 {
            String(localized: "BOAR's storage limit · \(fetching.formatted(.byteCount(style: .file))) downloading")
        } else {
            String(localized: "BOAR's storage limit, not the \(Platform.deviceNoun)'s")
        }
        return UsageBar(title: "Storage", used: storage, total: noLimit ? storage + fetching + free : limit, caption: caption,
                        kind: .storage, pending: fetching, compact: true)
    }
}
