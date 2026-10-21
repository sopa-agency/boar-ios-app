// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BoarEngine",
    platforms: [.iOS("18.0"), .macOS("26.0")],
    products: [
        .library(name: "BoarCore", targets: ["BoarCore"]),
        .library(name: "BoarRouting", targets: ["BoarRouting"]),
        .library(name: "BoarRAG", targets: ["BoarRAG"]),
        .library(name: "BoarModels", targets: ["BoarModels"]),
        .library(name: "BoarAnswer", targets: ["BoarAnswer"]),
        .library(name: "BoarLlama", targets: ["BoarLlama"]),
        .library(name: "BoarAppleAI", targets: ["BoarAppleAI"]),
        .library(name: "BoarRemote", targets: ["BoarRemote"]),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
    ],
    targets: [
        .target(name: "BoarCore"),
        .target(name: "BoarRouting", dependencies: ["BoarCore"]),
        .target(name: "BoarRAG", dependencies: ["BoarCore", .product(name: "libzstd", package: "zstd")]),
        .target(name: "BoarModels", dependencies: ["BoarCore"], resources: [.process("Resources")]),
        .target(name: "BoarAnswer", dependencies: ["BoarCore", "BoarRouting", "BoarRAG", "BoarModels"]),
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
        .target(name: "BoarLlama", dependencies: ["BoarCore", "llama"]),
        .target(name: "BoarAppleAI", dependencies: ["BoarCore"]),
        .target(name: "BoarRemote", dependencies: ["BoarCore"]),
        .testTarget(name: "BoarCoreTests", dependencies: ["BoarCore"]),
        .testTarget(name: "BoarRoutingTests", dependencies: ["BoarRouting"]),
        .testTarget(name: "BoarRAGTests", dependencies: ["BoarRAG"]),
        .testTarget(name: "BoarModelsTests", dependencies: ["BoarModels"]),
        .testTarget(name: "BoarAnswerTests", dependencies: ["BoarAnswer"]),
        .testTarget(name: "BoarLlamaTests", dependencies: ["BoarLlama"]),
        .testTarget(name: "BoarAppleAITests", dependencies: ["BoarAppleAI"]),
        .testTarget(name: "BoarRemoteTests", dependencies: ["BoarRemote"]),
    ],
    swiftLanguageModes: [.v6]
)
