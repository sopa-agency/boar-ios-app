import BoarCore
import SwiftUI

/// About BOAR (android AboutScreen.kt / AboutScreen.tsx): what it is, the version and engine, and where the source is.
struct AboutScreen: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        GroupedList {
            Section {
                VStack {
                    Image(decorative: "Brand/mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    Text(verbatim: "BOAR")
                        .font(.boarDisplay(size: 34, relativeTo: .largeTitle))
                        .foregroundStyle(.boar(.heading))
                    Text("Knowledge that travels with you")
                        .font(.boar("ui.titleSm"))
                        .foregroundStyle(.boar(.secondary))
                    #if DEBUG
                    Text("Version \(version) (\(build)) · Development build")
                        .boarText("mono.xs")
                        .foregroundStyle(.boar(.secondary))
                    #else
                    Text("Version \(version) (\(build)) · Release build")
                        .boarText("mono.xs")
                        .foregroundStyle(.boar(.secondary))
                    #endif
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section {
                AboutFeatureRow(title: "Works Offline", symbol: Symbols.offline,
                                text: "Answers come from models and a library on this \(Platform.deviceNoun). No internet needed.")
                AboutFeatureRow(title: "Stays on Your \(Platform.deviceNoun)", symbol: Self.lockSymbol,
                                text: "Your questions, chats and documents never leave it.")
                AboutFeatureRow(title: "Measure It Yourself", symbol: Symbols.benchmark,
                                text: "Turn on Show Technical Details in Settings → Advanced to see timings and run the benchmark.")
            }

            Section {
                Link(destination: Self.sourceURL) {
                    Label {
                        Text(verbatim: "github.com/sopa-agency/boar-ios-app")
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
            } header: {
                BoarHeader {
                    Text("Open Source")
                }
            } footer: {
                BoarFooter {
                    Text("Source code, model lists and the scripts that build the offline library.")
                }
            }

            Section {
                ValueRow(label: "Engine", value: Self.engine)
                ValueRow(label: "Retrieval", value: "SQLite \(sqliteVersion) · FTS5")
            } header: {
                BoarHeader {
                    Text("Engine")
                }
            } footer: {
                BoarFooter {
                    Text("Answers are AI-generated from the sources BOAR finds on this \(Platform.deviceNoun). They are not reviewed by clinicians or experts.")
                }
            }
        }
        .navigationTitle(AppScreen.about.title)
        .inlineNavigationTitle()
    }

    private var sqliteVersion: String { SqliteDatabase.version }

    private static var lockSymbol: AppIcon {
        #if os(macOS)
        "lock.laptopcomputer"
        #else
        "lock.iphone"
        #endif
    }

    /// llama.cpp runs on the CPU on iPhone and on the GPU (Metal) on the Mac.
    private static var engine: String {
        #if os(macOS)
        "llama.cpp b11010 · Metal"
        #else
        "llama.cpp b11010 · CPU"
        #endif
    }

    // A constant, valid URL literal.
    private static let sourceURL = URL(string: "https://github.com/sopa-agency/boar-ios-app") ?? URL.homeDirectory
}
