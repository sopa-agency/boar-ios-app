import BoarAppleAI
import BoarCore
import SwiftUI

/// Settings → Advanced: answer length, chat memory, the answer engine, this iPhone, and setup again. The tools for people
/// who want to look under the hood (adaptive routing, engine tweaks, benchmark) appear with Show Technical Details on.
struct AdvancedSettingsScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge
    @State private var labs = Labs.shared

    var body: some View {
        @Bindable var model = model
        let personalityId = bridge.read { $0.personalityId }
        let deep = bridge.read { $0.deepResearchMode }
        let summarize = bridge.read { $0.autoSummarize }
        let turns = bridge.read { $0.historyTurnThreshold }
        let technical = bridge.read { $0.showLiveStats }
        let apple = model.appleModelAvailability
        BoarForm {
            Section {
                Picker(selection: bridge.binding({ AnswerLength(tokens: $0.maxTokensChoice) }, { $0.maxTokensChoice = $1.tokens })) {
                    ForEach(AnswerLength.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel("Answer Length", symbol: "text.alignleft")
                }
                .pickerStyle(.menu)
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
                        Text("Auto fits the answer style (up to \(AppSettings.autoMaxTokens(personalityId: personalityId, deepResearch: deep)) tokens now). Apple Intelligence answers with Apple's built-in model where available; Mac on Your Network sends the writing to llama-server on another Mac.")
                        if !apple.isAvailable {
                            Text(apple.userMessage)
                        }
                    }
                }
            }

            if model.backend == .remote {
                RemoteServerSection(settings: services.settings) {
                    Task { await services.host.unload(); model.chat?.refreshModel() }
                }
            }

            Section {
                Toggle(isOn: bridge.binding({ $0.autoSummarize }, { $0.autoSummarize = $1 })) {
                    SettingsLabel("Summarize Older Turns", symbol: "text.append")
                }
                Stepper(value: bridge.binding({ $0.historyTurnThreshold }, { $0.historyTurnThreshold = $1 }), in: 2...12, step: 2) {
                    Text("Keep \(turns) Recent Turns")
                        .monospacedDigit()
                }
                .disabled(!summarize)
            } header: {
                BoarHeader {
                    Text("Chat Memory")
                }
            } footer: {
                BoarFooter {
                    Text("Long chats keep their context: older turns are condensed and the most recent ones stay word for word.")
                }
            }

            Section {
                #if !os(macOS)
                // The Mac's Settings window has a Storage tab for it.
                NavigationLink {
                    DeviceInfoScreen(services: services)
                } label: {
                    SettingsLabel("\(Platform.deviceNoun) & Storage", symbol: .pack(.settingsHardware))
                }
                #endif
                Button(action: model.reopenSetup) {
                    SettingsLabel("Run Setup Again", symbol: Symbols.retry)
                        .foregroundStyle(.boar(.link))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            } footer: {
                BoarFooter {
                    Text("Run Setup Again checks your models and library.")
                }
            }

            Section {
                Toggle(isOn: bridge.binding({ $0.showLiveStats }, { $0.showLiveStats = $1 })) {
                    SettingsLabel("Show Technical Details", symbol: "chevron.left.forwardslash.chevron.right")
                }
                if technical {
                    Toggle(isOn: bridge.binding({ $0.adaptiveRoutingEnabled }, { $0.adaptiveRoutingEnabled = $1 })) {
                        SettingsLabel("Adaptive Routing", symbol: "arrow.triangle.branch")
                    }
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
                }
            } header: {
                BoarHeader {
                    Text("For Developers")
                }
            } footer: {
                BoarFooter {
                    Text(technical
                         ? "Timings and speed show under each answer. Adaptive Routing picks the best installed model for each question."
                         : "Shows timings under each answer, plus the engine settings and the benchmark.")
                }
            }

            // At the very bottom, the switch builders find (android LabHooks.SettingsRow).
            if LabsBuild.experimental {
                Section {
                    Toggle(isOn: Binding(get: { labs.labsOn }, set: { labs.labsOn = $0 })) {
                        SettingsLabel("Boar Labs", symbol: Symbols.labs)
                    }
                } footer: {
                    BoarFooter {
                        Text("Unfinished experiments in the menu and under answers. They may be slow, rough or change without notice.")
                    }
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
