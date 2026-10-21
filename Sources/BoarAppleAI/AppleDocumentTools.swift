import BoarCore
import CoreSpotlight
import Foundation
import FoundationModels
import Vision

/// iOS 27: a Foundation Models session that can search the user's own documents.
///
/// Two system tools come with the iOS 27 SDK as cross-import overlays:
/// - `SpotlightSearchTool` (`_CoreSpotlight_FoundationModels`): the model issues Spotlight queries over the app's Core Spotlight
///   index (chat sessions donated by `SessionSpotlightIndexer`, imported documents) and, when `fileScopes` is non-empty, over
///   files in those folders;
/// - `OCRTool` (`_Vision_FoundationModels`): the model reads text out of images it is given.
///
/// Everything runs on device. Use `makeSession` for direct Foundation Models use (SwiftUI, App Intents) or `makeModel` for the
/// BOAR pipeline (it conforms to the model seam).
@available(iOS 27, macOS 27, visionOS 27, *)
public enum AppleDocumentTools {
    public static let defaultInstructions = """
        You are BOAR, an offline research assistant. Answer questions about the user's own documents and past conversations. \
        Use the search tool to find relevant items before answering, and the OCR tool to read text in images. \
        Quote the document titles you used. If nothing relevant is found, say so plainly instead of guessing.
        """

    /// The Spotlight search tool over the app's own index, plus files under `fileScopes`.
    public static func spotlightTool(fileScopes: [URL] = [], maximumResultCount: Int? = 20) -> SpotlightSearchTool {
        var spotlight = CoreSpotlightSource(searchableIndexDelegate: nil, fetchAttributes: [])
        spotlight.maximumResultCount = maximumResultCount
        var sources: [SearchSource] = [.coreSpotlight(spotlight)]
        if !fileScopes.isEmpty {
            var files = FileSource()
            files.scopes = fileScopes
            files.maximumResultCount = maximumResultCount
            sources.append(.files(files))
        }
        return SpotlightSearchTool(configuration: SpotlightSearchTool.Configuration(
            sources: sources, guide: .focused(.documents), maximumResponseSize: nil))
    }

    #if !targetEnvironment(simulator)
    /// Vision's OCR tool (`_Vision_FoundationModels` ships in the device SDKs only, not the iOS Simulator SDK).
    public static func ocrTool() -> OCRTool { OCRTool() }
    #endif

    /// The tool list `makeSession` / `makeModel` use.
    public static func tools(fileScopes: [URL] = [], includeOCR: Bool = true) -> [any Tool] {
        var tools: [any Tool] = [spotlightTool(fileScopes: fileScopes)]
        #if !targetEnvironment(simulator)
        if includeOCR { tools.append(ocrTool()) }
        #endif
        return tools
    }

    /// A ready Foundation Models session with the document tools.
    public static func makeSession(
        instructions: String = defaultInstructions, fileScopes: [URL] = [], includeOCR: Bool = true,
        model: SystemLanguageModel = .default
    ) -> LanguageModelSession {
        LanguageModelSession(model: model, tools: tools(fileScopes: fileScopes, includeOCR: includeOCR), instructions: instructions)
    }

    /// The same tools behind the BOAR model seam: send `[system(defaultInstructions), user(question)]`.
    public static func makeModel(fileScopes: [URL] = [], includeOCR: Bool = true, model: SystemLanguageModel = .default) -> AppleSystemModel {
        AppleSystemModel(model: model, tools: tools(fileScopes: fileScopes, includeOCR: includeOCR), name: "Apple on-device model + documents")
    }
}
