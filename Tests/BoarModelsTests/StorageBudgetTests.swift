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
        guard case .refused(let refused) = r else { Issue.record("expected refusal"); return }
        #expect(refused.reason == .budget)
        #expect(refused.message.range(of: "50 GB storage budget.*10 GB download.*51 GB", options: .regularExpression) != nil, "\(refused.message)")
        // The numbers the error text fills in (android UserErrors.downloadArgs).
        #expect(refused.budgetBytes == 50 * gb && refused.usedBytes == 40 * gb && refused.neededBytes == 10 * gb && refused.freeDiskBytes == 300 * gb)
    }

    @Test func countsTheFullSizeOfOtherDownloadsStillRunning() {
        #expect(!StorageBudget.check(with { $0.usedBytes = 30 * gb; $0.reservedBytes = 12 * gb; $0.downloadBytes = 8 * gb }).isOk)
        #expect(StorageBudget.check(with { $0.usedBytes = 30 * gb; $0.reservedBytes = 12 * gb; $0.downloadBytes = 7 * gb }).isOk)
        guard case .refused(let r) = StorageBudget.check(with { $0.usedBytes = 30 * gb; $0.reservedBytes = 12 * gb; $0.downloadBytes = 8 * gb }) else {
            Issue.record("expected refusal"); return
        }
        #expect(r.downloadingBytes == 12 * gb)
    }

    @Test func theUsersLimitReplacesTheCatalogsAndNoLimitLeavesOnlyTheDisk() {
        #expect(StorageBudget.limit(catalogBudget: 50 * gb, user: nil) == 50 * gb)
        #expect(StorageBudget.limit(catalogBudget: 50 * gb, user: 200 * gb) == 200 * gb)
        let huge = with { $0.usedBytes = 120 * gb; $0.downloadBytes = 30 * gb; $0.budgetBytes = StorageBudget.noLimit }
        #expect(StorageBudget.check(huge).isOk)
        guard case .refused(let r) = StorageBudget.check(with { $0.usedBytes = 120 * gb; $0.downloadBytes = 30 * gb; $0.freeDiskBytes = 10 * gb; $0.budgetBytes = StorageBudget.noLimit })
        else { Issue.record("expected refusal"); return }
        #expect(r.reason == .disk)
    }

    @Test func readsTheLabsChoiceLikeAndroid() {
        #expect(StorageBudget.limitBytes(choice: nil) == nil)
        #expect(StorageBudget.limitBytes(choice: "auto") == nil)
        #expect(StorageBudget.limitBytes(choice: "none") == StorageBudget.noLimit)
        #expect(StorageBudget.limitBytes(choice: "25") == 25 * gb)
        #expect(StorageBudget.limitBytes(choice: "200") == 200 * gb)
        #expect(StorageBudget.limitBytes(choice: "0") == nil)
        #expect(StorageBudget.limitBytes(choice: "x") == nil)
    }

    @Test func refusesWhenThePhoneLacksFreeSpaceKeepingAMargin() {
        let r = StorageBudget.check(with { $0.freeDiskBytes = 5 * gb })
        guard case .refused(let refused) = r else { Issue.record("expected refusal"); return }
        #expect(refused.reason == .disk)
        #expect(refused.message.contains("the download needs 5 GB and only 5 GB is free"))
        #expect(refused.neededBytes == 5 * gb && refused.freeDiskBytes == 5 * gb)
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
