import Foundation

/// Which text a failed download shows (android `UserErrors.downloadKey`). The app holds the words; this picks the case, so
/// the mapping is tested with the engine. BOAR's own limit and a full phone are different cases: the phone may have plenty
/// of room when the limit is hit.
public enum DownloadFailure: Equatable, Sendable {
    case noSource
    case offlineBuild
    /// The phone is out of space: the budget check's numbers, or nil for a disk error while writing.
    case disk(StorageBudget.Refused?)
    /// BOAR's storage limit, with no other download running.
    case budget(StorageBudget.Refused)
    /// BOAR's storage limit, counting other downloads that are running.
    case budgetWithDownloads(StorageBudget.Refused)
    case sizeChanged
    case paused
    case checksum
    /// 401/403: the file needs an account (a gated Hugging Face model); retrying won't help.
    case gated
    case server
    /// No route, DNS, a dropped or timed-out connection (Kotlin's bare `IOException`).
    case network
    case generic

    public init(_ error: Error) {
        guard let error = error as? AssetStore.DownloadError else {
            self = error is URLError ? .network : .generic
            return
        }
        switch error {
        case .noSource: self = .noSource
        case .offlineBuild: self = .offlineBuild
        case .storage(_, let refused?) where refused.reason == .budget:
            self = refused.downloadingBytes > 0 ? .budgetWithDownloads(refused) : .budget(refused)
        case .storage(_, let refused): self = .disk(refused)
        case .sizeChanged: self = .sizeChanged
        case .paused: self = .paused
        case .checksum: self = .checksum
        case .http(_, let code) where code == 401 || code == 403: self = .gated
        case .http: self = .server
        case .network: self = .network
        }
    }
}
