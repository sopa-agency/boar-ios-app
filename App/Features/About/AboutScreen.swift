import BoarCore
import SwiftUI

/// About BOAR as a page of sections and rows (android AboutScreen.kt, 555e62ac): the mark, the tagline and the version
/// block at the top (press and hold copies it for a bug report), then what BOAR is, privacy, measuring, the addresses, the
/// plugins on, the knowledge packs, the core team and the credits. Addresses copy on tap or press and hold; nothing opens
/// from here.
struct AboutScreen: View {
    @State private var copied = false
    @State private var copies = 0

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        let plugins = Labs.shared.active.map(\.title)
        GroupedList {
            top(plugins: plugins)

            Section {
                AboutInfoRow("Offline AI research on your \(Platform.deviceNoun). Answers with sources, no signal needed.")
            } header: {
                AboutHeader(title: "What BOAR is", symbol: "info.circle")
            } footer: {
                BoarFooter {
                    Text("Answers are AI-generated from the sources BOAR finds on this \(Platform.deviceNoun). They are not reviewed by clinicians or experts.")
                }
            }

            Section {
                AboutInfoRow("The model lives on your \(Platform.deviceNoun)", "No server receives your questions, so no one holds a switch.")
                AboutInfoRow("One download at setup", "Then airplane mode is fine: BOAR answers from the library on your \(Platform.deviceNoun) and shows the articles it used.")
                AboutInfoRow("The connection", "Only for downloading models or packs, searching Hugging Face and sharing evaluation results, if you turn that on.")
            } header: {
                AboutHeader(title: "Your privacy", symbol: "lock")
            }

            Section {
                AboutInfoRow("Every answer records how it ran", "The model, time to the first word, tokens per second, memory and sources.")
                AboutInfoRow("Measure your own \(Platform.deviceNoun)", "Settings, Advanced, Benchmark (Pro profile).")
                AboutInfoRow("Checked before it loads", "BOAR checks each model against your \(Platform.deviceNoun)'s memory. Downloads stay within a 50 GB storage budget; in Pro you can change it in Experimental.")
            } header: {
                AboutHeader(title: "Measure it yourself", symbol: "speedometer")
            }

            Section {
                AddressRow("boarapp.com", label: String(localized: "Official website"))
                AddressRow("github.com/rferrari/boar-app", label: String(localized: "Source code"), note: "Open source, MIT.")
                AddressRow("x.com/boar_app", label: "X")
                AddressRow("farcaster.xyz/boarapp", label: "Farcaster")
            } header: {
                AboutHeader(title: "Links", symbol: "link")
            } footer: {
                BoarFooter {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Don't trust, verify.")
                            .font(.boar("ui.titleSm").weight(.bold))
                            .foregroundStyle(.boar(.link))
                        Text("News comes only from these addresses. Check the address before you download anything that says it is BOAR.")
                    }
                }
            }

            Section {
                if plugins.isEmpty {
                    AboutInfoRow("None on")
                } else {
                    AboutInfoRow(verbatim: String(localized: "\(plugins.count) on"), plugins.joined(separator: ", "))
                }
            } header: {
                AboutHeader(title: "Plugins on", symbol: "puzzlepiece.extension")
            }

            Section {
                AddressRow("huggingface.co/datasets/r4topunk/boar-packs", label: String(localized: "Packs from R4to's R&D Labs"))
            } header: {
                AboutHeader(title: "Knowledge packs", symbol: "books.vertical")
            }

            Section {
                ForEach(Self.team, id: \.handle) { member in
                    TeamRow(name: member.name, handle: member.handle)
                }
            } header: {
                AboutHeader(title: "Core team, on X", symbol: "person.2")
            }

            Section {
                ForEach(AboutCredits.all, id: \.self) { credit in
                    LabeledContent {
                        Text(verbatim: credit.license)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(.boar(.secondary))
                    } label: {
                        Text(verbatim: credit.name)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(.boar(.primary))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                AboutHeader(title: "Credits", symbol: "heart")
            } footer: {
                BoarFooter {
                    Text("Standing on open work, each under its own license.")
                }
            }

            // Last, as the footer: how the addresses copy (android, Nov 10).
            Section {
            } footer: {
                BoarFooter {
                    Text("Tap or hold an address to copy it. Nothing opens from this page.")
                        .foregroundStyle(.boar(.dim))
                }
            }
        }
        .navigationTitle(AppScreen.about.title)
        .inlineNavigationTitle()
    }

    /// The mark, the tagline, then the version block: version, build and engine. Press and hold copies it with the device and
    /// the plugins on, for a bug report. Only the clipboard.
    private func top(plugins: [String]) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(decorative: "Brand/mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("Your questions.\nYour phone. Your AI.")
                    .font(.boar("ui.title").weight(.bold))
                    .foregroundStyle(.boar(.heading))
                    .multilineTextAlignment(.center)
                versionBlock(plugins: plugins)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    private func versionBlock(plugins: [String]) -> some View {
        let kind = Self.debugBuild ? String(localized: "Development build") : String(localized: "Release build")
        let line = "\(kind) · \(Self.engine)"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "v\(version) (\(build))")
                    .boarText("mono.sm")
                    .foregroundStyle(.boar(.primary))
                Text(verbatim: line)
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.boar(.secondary))
                Text("Press and hold to copy for a bug report.")
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.boar(.dim))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.success))
            } else {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.boar(.dim))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(.rect)
        .onLongPressGesture { copyReport(line: line, plugins: plugins) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Press and hold to copy for a bug report.")) { copyReport(line: line, plugins: plugins) }
    }

    private func copyReport(line: String, plugins: [String]) {
        let device = [DeviceName.current ?? DeviceName.identifier, ProcessInfo.processInfo.operatingSystemVersionString]
            .joined(separator: " · ")
        Platform.copy(AboutReport.text(version: "v\(version) (\(build)) · \(line)", device: device, plugins: plugins))
        withAnimation { copied = true }
        copies += 1
        let mine = copies
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if mine == copies { withAnimation { copied = false } }
        }
    }

    private static var debugBuild: Bool {
        #if DEBUG
        true
        #else
        false
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
