import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A file made when the share sheet asks for it (a collection's JSON, an evaluation's JSONL or CSV): nothing is
/// written until the user picks a destination.
struct ExportedFile: Transferable {
    let filename: String
    let contents: @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            let dir = FileManager.default.temporaryDirectory.appending(path: "exports/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: file.filename)
            try await file.contents().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }
    }
}
