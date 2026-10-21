import Foundation

/// The answer model the setup wizard recommends, from the phone's RAM (port of `SetupModel.kt`, src/ui-android/setupModel.ts).
///
/// Measured (eval_scores, 2026-10-02): on a POCO F3 (8 GB, reads 7.3 GB) the 1.5B answers at 16-18 tok/s, while 4B-class
/// models ran at ~5 tok/s with 3.4-3.9 GB peak memory. On a POCO X6 Pro (12 GB, reads 10.7 GB) Android closed the
/// backgrounded app holding the 4B. So the 4B is recommended only from 12 GB phones; 8 GB phones get the 1.5B.
public enum SetupModel {
    /// 12 GB phones report about 10.7 GB, 8 GB phones about 7.3 GB.
    public static let recommendDefaultMinRamBytes: Int64 = 10 * 1024 * 1024 * 1024

    public static func recommended(_ models: [CatalogAsset], totalRamBytes: Int64) -> CatalogAsset? {
        let tier: AnswerTier = totalRamBytes >= recommendDefaultMinRamBytes ? .default : .compact
        return models.first { $0.answerTier == tier } ?? models.first
    }

    /// True when the model is bigger than this phone is recommended for: it may be slow or closed in the background.
    /// The 4B (2.5 GB) is heavy under 12 GB, as measured above; that is a file over a quarter of the RAM, which the same rule
    /// applies to the other catalog models (7-8B, ~5 GB: heavy on a 12 GB phone too). Never the compact tier.
    public static func heavyForPhone(_ model: CatalogAsset, totalRamBytes: Int64) -> Bool {
        if model.answerTier == .compact || totalRamBytes <= 0 { return false }
        if model.answerTier == .default { return totalRamBytes < recommendDefaultMinRamBytes }
        return model.sizeBytes > totalRamBytes / 4
    }

    /// The model to download: the user's pick, else one already on the phone, else the recommended one.
    public static func toInstall(_ models: [CatalogAsset], present: Set<String>, totalRamBytes: Int64, chosenId: String? = nil) -> CatalogAsset? {
        models.first { $0.id == chosenId } ?? models.first { present.contains($0.id) } ?? recommended(models, totalRamBytes: totalRamBytes)
    }
}
