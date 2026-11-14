/// The Models screen's sort and filter: which answer models show, in what order (port of `ModelOrder.kt`). Pure, so
/// it's unit-tested.
public enum ModelOrder {
    /// smart: active, downloading, on the device by last use, then the rest. lastUsed and added: newest first. The raw
    /// values are Android's, as `AppSettings.modelSort` stores them.
    public enum Sort: String, CaseIterable, Sendable { case smart = "SMART", lastUsed = "LAST_USED", added = "ADDED" }
    /// mine: models added from the Hugging Face search.
    public enum Filter: String, CaseIterable, Sendable { case all = "ALL", onPhone = "ON_PHONE", downloading = "DOWNLOADING", mine = "MINE" }

    /// What the screen knows about each model id; times are epoch ms (missing: never used or not known).
    public struct Facts: Sendable {
        public var active: String?
        public var onPhone: Set<String>
        public var downloading: Set<String>
        public var mine: Set<String>
        public var lastUsed: [String: Int64]
        public var added: [String: Int64]

        public init(active: String? = nil, onPhone: Set<String> = [], downloading: Set<String> = [], mine: Set<String> = [],
                    lastUsed: [String: Int64] = [:], added: [String: Int64] = [:]) {
            self.active = active
            self.onPhone = onPhone
            self.downloading = downloading
            self.mine = mine
            self.lastUsed = lastUsed
            self.added = added
        }
    }

    /// `items` filtered and sorted; ties and models without a time keep their catalog order.
    public static func apply(_ items: [CatalogAsset], sort: Sort, filter: Filter, facts f: Facts) -> [CatalogAsset] {
        let shown = items.filter {
            switch filter {
            case .all: true
            case .onPhone: f.onPhone.contains($0.id)
            case .downloading: f.downloading.contains($0.id)
            case .mine: f.mine.contains($0.id)
            }
        }
        // Keyed by catalog position so equal keys keep their order whatever the sort algorithm does.
        func ordered(_ key: (CatalogAsset) -> (Int, Int64)) -> [CatalogAsset] {
            shown.enumerated().map { (key($0.element), $0.offset, $0.element) }
                .sorted { ($0.0.0, -$0.0.1, $0.1) < ($1.0.0, -$1.0.1, $1.1) }
                .map(\.2)
        }
        switch sort {
        case .smart:
            return ordered { a in
                let group = a.id == f.active ? 0 : f.downloading.contains(a.id) ? 1 : f.onPhone.contains(a.id) ? 2 : 3
                return (group, f.onPhone.contains(a.id) ? f.lastUsed[a.id] ?? 0 : 0)
            }
        case .lastUsed: return ordered { (0, f.lastUsed[$0.id] ?? .min + 1) }
        case .added: return ordered { (0, f.added[$0.id] ?? .min + 1) }
        }
    }
}
