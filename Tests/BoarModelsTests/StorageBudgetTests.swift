import Foundation
import Testing
@testable import BoarModels

/// Port of src/models/storageBudget.test.ts and the formatBytes cases of units.test.ts.
@Suite struct StorageBudgetTests {
    let gb: Int64 = 1_000_000_000
    var base: StorageBudget.Input { .init(usedBytes: 4 * gb, reservedBytes: 0, downloadBytes: 5 * gb, alreadyDownloadedBytes: 0, freeDiskBytes: 300 * gb, budgetBytes: 50 * gb) }

    func with(_ f: (inout StorageBudget.Input) -> Void) -> StorageBudget.Input { var i = base; f(&i); return i }

    @Test func allowsADownloadThatFitsTheBudgetAndTheDisk() {
        #expect(StorageBudget.check(base) == .ok(projectedBytes: StorageBudget.appReserveBytes + 9 * gb))
    }

    @Test func refusesADownloadThatWouldPassThe50GBBudget() {
        let r = StorageBudget.check(with { $0.usedBytes = 40 * gb; $0.downloadBytes = 10 * gb })
        guard case .refused(let reason, _, let message) = r else { Issue.record("expected refusal"); return }
        #expect(reason == .budget)
        #expect(message.range(of: "50 GB storage budget.*10 GB download.*51 GB", options: .regularExpression) != nil, "\(message)")
    }

    @Test func countsTheFullSizeOfOtherDownloadsStillRunning() {
        #expect(!StorageBudget.check(with { $0.usedBytes = 30 * gb; $0.reservedBytes = 12 * gb; $0.downloadBytes = 8 * gb }).isOk)
        #expect(StorageBudget.check(with { $0.usedBytes = 30 * gb; $0.reservedBytes = 12 * gb; $0.downloadBytes = 7 * gb }).isOk)
    }

    @Test func refusesWhenThePhoneLacksFreeSpaceKeepingAMargin() {
        let r = StorageBudget.check(with { $0.freeDiskBytes = 5 * gb })
        guard case .refused(let reason, _, let message) = r else { Issue.record("expected refusal"); return }
        #expect(reason == .disk)
        #expect(message.contains("the download needs 5 GB and only 5 GB is free"))
        #expect(StorageBudget.check(with { $0.freeDiskBytes = 5 * gb + StorageBudget.freeSpaceMarginBytes }).isOk)
    }

    @Test func onlyNeedsFreeSpaceForThePartAPausedDownloadHasntFetchedYet() {
        #expect(StorageBudget.check(with { $0.freeDiskBytes = 2 * gb; $0.alreadyDownloadedBytes = 4 * gb }).isOk)
    }

    @Test func skipsTheDiskCheckWhenFreeSpaceIsUnknown() {
        #expect(StorageBudget.check(with { $0.freeDiskBytes = nil }).isOk)
    }

    @Test func formatsSizesLikeAndroid() {
        #expect(Units.formatBytes(18_600_000) == "18.6 MB")
        #expect(Units.formatBytes(986_048_768) == "986 MB")
        #expect(Units.formatBytes(2_497_281_120) == "2.5 GB")
        #expect(Units.formatBytes(12) == "1 kB")
        #expect(Units.formatBytes(0) == "0 kB")
        #expect(Units.formatBytes(999_600_000) == "1 GB")
        #expect(Units.formatBytes(18_600_000, locale: Locale(identifier: "pt-BR")) == "18,6 MB")
        // the units.test.ts cases
        #expect(Units.formatBytes(35_962_880) == "36 MB")
        #expect(Units.formatBytes(24 * gb) == "24 GB")
        #expect(Units.formatBytes(99_940_000) == "99.9 MB")
        #expect(Units.formatBytes(99_960_000) == "100 MB")
        #expect(Units.formatBytes(128 * gb) == "128 GB")
        #expect(Units.formatBytes(999_400) == "999 kB")
        #expect(Units.formatBytes(999_600) == "1 MB")
        #expect(Units.formatBytes(999_400_000) == "999 MB")
        #expect(Units.formatBytes(999_999_999) == "1 GB")
        #expect(Units.formatBytes(1_500) == "2 kB")
        #expect(Units.formatBytes(-5) == "0 kB")
    }

    @Test func halfUpRoundingLikeIntl() {
        #expect(Units.formatBytes(18_650_000) == "18.7 MB")
    }

    @Test func deviceFactsAreReadable() {
        #expect(DeviceMemory.totalBytes > 0)
        #expect(DiskSpace.freeBytes(at: FileManager.default.temporaryDirectory.appendingPathComponent("not/yet/here")) != nil)
    }
}
