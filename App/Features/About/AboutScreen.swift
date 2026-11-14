import BoarCore
import SwiftUI

/// About BOAR (android AboutScreen.kt / AboutScreen.tsx): what it is, its official addresses, the source, the team, the
/// open work it stands on, and the version and engine.
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

            // Android's thread posts as sections: the official addresses, the open source, the packs, the team and the
            // credits. An address copies on tap or press and hold; nothing opens from here, like Android.
            Section {
                AddressRow("boarapp.com")
                AddressRow("x.com/boar_app")
                AddressRow("farcaster.xyz/boarapp")
            } header: {
                BoarHeader {
                    Text("Official Site")
                }
            } footer: {
                BoarFooter {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("News comes only from these addresses. Check the address before you download anything that says it is BOAR.")
                        Text("Don't trust, verify.")
                            .font(.boar("ui.subtext").weight(.heavy))
                            .foregroundStyle(.boar(.success))
                    }
                }
            }

            Section {
                AddressRow("github.com/sopa-agency/boar-ios-app")
                AddressRow("github.com/rferrari/boar-app")
            } header: {
                BoarHeader {
                    Text("Open Source")
                }
            } footer: {
                BoarFooter {
                    Text("MIT. The code of this app and of the Android app, the model list and the scripts that build the knowledge packs.")
                }
            }

            Section {
                AddressRow("huggingface.co/datasets/r4topunk/boar-packs")
            } header: {
                BoarHeader {
                    Text("Knowledge Packs")
                }
            } footer: {
                BoarFooter {
                    Text("Packs from R4to's R&D Lab.")
                }
            }

            Section {
                ForEach(Self.team, id: \.handle) { member in
                    AddressRow("\(member.name) · @\(member.handle)", copy: "x.com/\(member.handle)")
                }
            } header: {
                BoarHeader {
                    Text("Core Team")
                }
            } footer: {
                BoarFooter {
                    Text("On X. Tap an address to copy it.")
                }
            }

            Section {
                ForEach(AboutCredits.all, id: \.self) { credit in
                    LabeledContent {
                        Text(verbatim: credit.license)
                            .boarText("mono.xs")
                            .foregroundStyle(.boar(.dim))
                    } label: {
                        Text(verbatim: credit.name)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(.boar(.secondary))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                BoarHeader {
                    Text("Credits")
                }
            } footer: {
                BoarFooter {
                    Text("Standing on open work, each under its own license.")
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

    /// BOAR's core team on X, alphabetical by name (android AboutScreen's TEAM).
    private static let team = [
        Member(name: "Bielcx", handle: "bielthegoat"), Member(name: "Jasper", handle: "btcjasper"),
        Member(name: "r4to", handle: "r4topunk"), Member(name: "Sopa", handle: "sopaagency"),
        Member(name: "vaipraonde", handle: "arferrari"), Member(name: "vlad", handle: "sk8ordao"),
    ]

    private struct Member {
        let name: String
        let handle: String
    }
}
