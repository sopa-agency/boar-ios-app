import BoarAppleAI
import BoarCore
import SwiftUI

/// Settings → Advanced (Pro; android's Advanced tweaks): the answer engine, this iPhone and its storage, the engine tweaks
/// and the benchmark. Answer length moved to the answers, chat memory to the chats, Run Setup Again to Start Over; adaptive
/// routing, staged quotes, free memory and technical details are in Experimental.
struct AdvancedSettingsScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge

    var body: some View {
        @Bindable var model = model
        let apple = model.appleModelAvailability
        BoarForm {
            Section {
                DrillDownPicker(title: "Engine", selection: $model.backendChoice, options: Self.engines(apple: apple.isAvailable)) {
                    SettingsLabel("Engine", symbol: "cpu.fill")
                } current: {
                    Self.engineName(model.backendChoice)
                }
            } header: {
                BoarHeader {
                    Text("Answers")
                }
            } footer: {
                BoarFooter {
                    VStack(alignment: .leading) {
                        Text("Apple Intelligence answers with Apple's built-in model where available; Mac on Your Network sends the writing to llama-server on another Mac.")
                        if !apple.isAvailable {
                            Text(apple.userMessage)
                        }
                    }
                }
            }

            // Without the experimental build there is no Experimental section: Pro's moved rows stay here (android 492e469b).
            if !LabsBuild.experimental {
                Section {
                    SettingsMovedRows(bridge: bridge, profile: .pro)
                } footer: {
                    BoarFooter { SettingsMovedNotes(bridge: bridge) }
                }
            }

            if model.backend == .remote {
                RemoteServerSection(settings: services.settings) {
                    Task { await services.host.unload(); model.chat?.refreshModel() }
                }
            }

            #if !os(macOS)
            // The Mac's Settings window has a Storage tab for it.
            Section {
                NavigationLink {
                    DeviceInfoScreen(services: services)
                } label: {
                    SettingsLabel("\(Platform.deviceNoun) & Storage", symbol: .pack(.settingsHardware))
                }
            }
            #endif

            Section {
                #if os(macOS)
                // The Mac's Settings window shows Engine Tweaks as a tab; the benchmark runs in the main window.
                Button(action: openBenchmark) {
                    SettingsLabel("Open Benchmark", symbol: Symbols.benchmark)
                }
                .buttonStyle(.plain)
                #else
                NavigationLink {
                    EngineTweaksScreen(services: services, bridge: bridge)
                } label: {
                    LabeledContent {
                        Text(bridge.read { $0.engineTweaks.isAuto } ? "Auto" : "Custom")
                    } label: {
                        SettingsLabel("Engine Tweaks", symbol: Symbols.advanced)
                    }
                }
                if let evaluation = model.evaluation {
                    NavigationLink {
                        EvaluationScreen(controller: evaluation, chatBusy: model.chat?.isAnswering ?? false)
                    } label: {
                        SettingsLabel("Benchmark", symbol: Symbols.benchmark)
                    }
                }
                #endif
            } header: {
                BoarHeader {
                    Text("For Developers")
                }
            } footer: {
                BoarFooter {
                    Text("The engine settings and the benchmark. Below Pro, Advanced tweaks pause and your choices are kept.")
                }
            }
        }
        .navigationTitle("Advanced")
        .inlineNavigationTitle()
    }

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow

    private func openBenchmark() {
        model.selection = .screen(.evaluation)
        openWindow(id: "main")
    }
    #endif

    /// The engine choices; Apple Intelligence stays listed but can't be picked where it isn't available.
    private static func engines(apple: Bool) -> [DrillDownOption<ModelBackend>] {
        ModelBackend.allCases.map { DrillDownOption(value: $0, title: engineName($0), disabled: $0 == .apple && !apple) }
    }

    private static func engineName(_ backend: ModelBackend) -> Text {
        switch backend {
        case .llama: Text("Downloaded Model")
        case .apple: Text("Apple Intelligence")
        case .remote: Text("Mac on Your Network")
        }
    }
}
