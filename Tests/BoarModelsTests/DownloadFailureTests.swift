import Foundation
import Testing

@testable import BoarModels

/// Port of android UserErrorsTest's download cases (`downloadKey`), plus the causes only iOS reports.
struct DownloadFailureTests {
    private let gb: Int64 = 1_000_000_000

    private func refused(_ reason: StorageBudget.Reason, downloading: Int64) -> StorageBudget.Refused {
        StorageBudget.Refused(reason: reason, projectedBytes: 0, message: "x", budgetBytes: 50 * gb, usedBytes: 20 * gb,
                              downloadingBytes: downloading, neededBytes: 5 * gb, freeDiskBytes: 233 * gb)
    }

    @Test func downloadFailuresMapByCause() {
        #expect(DownloadFailure(AssetStore.DownloadError.storage(message: "needs 2 GB")) == .disk(nil))
        #expect(DownloadFailure(AssetStore.DownloadError.offlineBuild) == .offlineBuild)
        #expect(DownloadFailure(AssetStore.DownloadError.http(label: "g", code: 401)) == .gated)
        #expect(DownloadFailure(AssetStore.DownloadError.http(label: "g", code: 403)) == .gated)
        #expect(DownloadFailure(AssetStore.DownloadError.http(label: "g", code: 503)) == .server)
        #expect(DownloadFailure(URLError(.cannotFindHost)) == .network)
        #expect(DownloadFailure(URLError(.timedOut)) == .network)
        #expect(DownloadFailure(AssetStore.DownloadError.network("connection reset")) == .network)
        #expect(DownloadFailure(CocoaError(.featureUnsupported)) == .generic)
    }

    @Test func theCausesOnlyIOSReportsHaveTheirOwnCase() {
        #expect(DownloadFailure(AssetStore.DownloadError.noSource(label: "g")) == .noSource)
        #expect(DownloadFailure(AssetStore.DownloadError.sizeChanged(label: "g", expectedBytes: 1, serverBytes: 2)) == .sizeChanged)
        #expect(DownloadFailure(AssetStore.DownloadError.paused(label: "g", bytesDone: 1, idleSeconds: 60)) == .paused)
        #expect(DownloadFailure(AssetStore.DownloadError.checksum(label: "g")) == .checksum)
    }

    @Test func boarsOwnLimitNeverSaysThePhoneIsFull() {
        let busy = refused(.budget, downloading: 12 * gb), idle = refused(.budget, downloading: 0), disk = refused(.disk, downloading: 0)
        #expect(DownloadFailure(AssetStore.DownloadError.storage(message: "x", refused: busy)) == .budgetWithDownloads(busy))
        #expect(DownloadFailure(AssetStore.DownloadError.storage(message: "x", refused: idle)) == .budget(idle))
        #expect(DownloadFailure(AssetStore.DownloadError.storage(message: "x", refused: disk)) == .disk(disk))
    }
}
