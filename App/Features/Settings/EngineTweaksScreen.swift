import BoarCore
import SwiftUI

/// Advanced tweaks (android SettingsScreen.kt TweaksSection): every engine knob, Auto by default. A change unloads the
/// model, which reloads with it on the next answer.
///
/// iOS: the CPU build picker, the core set and "keep threads on those cores" are left out. One llama.cpp build ships
/// with the app, and Darwin has no thread affinity, so those settings would have no effect here.
struct EngineTweaksScreen: View {
    let services: BoarServices
    let bridge: SettingsBridge

    /// The single knobs stay folded under the preset unless asked for (or already customized).
    @State private var showsEverySetting = false

    private var tweaks: EngineTweaks { bridge.read { $0.engineTweaks } }

    private func save(_ next: EngineTweaks) {
        services.settings.engineTweaks = next
        bridge.touch()
        let host = services.host
        Task { await host.unload() }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<EngineTweaks, T>) -> Binding<T> {
        Binding(get: { tweaks[keyPath: keyPath] }, set: { v in var t = tweaks; t[keyPath: keyPath] = v; save(t) })
    }

    private func autoLabel(_ value: some CustomStringConvertible) -> Text { Text("Auto (\(value.description))") }

    /// Fastest, picked for the first time: its heat and battery warning first (android `runPresetWarned`).
    @State private var warningRun = false

    private func choose(_ p: TweakPreset, _ tw: EngineTweaks) {
        if p == .run && !services.settings.runPresetWarned { warningRun = true } else { save(p.applyTo(tw)) }
    }

    /// The warning, with a line for a phone under 8 GB, where large models may run out of memory.
    private var runWarning: String {
        let base = String(localized: "Fastest answers. The \(Platform.deviceNoun) gets warmer and uses more battery, and answers have no time limit (use Stop). Best while charging.")
        guard services.totalRamBytes < 8 * 1_000_000_000 else { return base }
        return base + "\n\n" + String(localized: "This \(Platform.deviceNoun) has less than 8 GB of RAM: large models may run out of memory.")
    }

    var body: some View {
        let tw = tweaks
        let auto = EngineTweaks().resolve(services.topology, totalRamBytes: services.totalRamBytes).params
        let resolved = tw.resolve(services.topology, totalRamBytes: services.totalRamBytes)
        let n = services.topology.cores.count
        let preset = TweakPreset.of(tw)
        BoarForm {
            Section {
                Picker(selection: Binding(get: { preset }, set: { p in if let p { choose(p, tw) } })) {
                    ForEach(TweakPreset.allCases, id: \.self) { p in
                        Label(Self.presetName(p), systemImage: p.symbol).tag(Optional(p))
                    }
                    if preset == nil { Label("Custom", systemImage: "slider.horizontal.3").tag(TweakPreset?.none) }
                } label: {
                    Text("Preset")
                } currentValueLabel: {
                    Text(preset.map(Self.presetName) ?? String(localized: "Custom"))
                }
                .drillDownPickerStyle()
            } footer: {
                BoarFooter {
                    Text(preset.map(Self.presetNote) ?? String(localized: "Custom: your own settings below. Pick a preset to start over from it."))
                }
            }

            if preset != nil {
                Section {
                    Toggle("Show Every Setting", isOn: $showsEverySetting)
                } footer: {
                    BoarFooter {
                        Text("Threads, memory, loading and answer limits, one by one. The preset is enough for most people.")
                    }
                }
            }

            if showsEverySetting || preset == nil {
                Section {
                    Picker("Threads", selection: binding(\.threads)) {
                        autoLabel(auto.threads).tag(Int?.none)
                        ForEach(1...max(n, 1), id: \.self) { Text(verbatim: "\($0)").tag(Optional($0)) }
                    }
                    Picker("Prompt Threads", selection: binding(\.threadsBatch)) {
                        autoLabel(auto.threadsBatch).tag(Int?.none)
                        ForEach(1...max(n, 1), id: \.self) { Text(verbatim: "\($0)").tag(Optional($0)) }
                    }
                } header: {
                    Text("CPU")
                } footer: {
                    BoarFooter {
                        Text("More threads than performance cores is usually slower. On iPhone, answers run on the CPU.")
                    }
                }

                Section {
                    Picker("Context Size", selection: binding(\.contextTokens)) {
                        autoLabel(auto.nCtx).tag(Int?.none)
                        ForEach([2048, 3072, 4096, 8192, 16384], id: \.self) { Text(verbatim: "\($0)").tag(Optional($0)) }
                    }
                    Picker("Prompt Batch", selection: binding(\.batch)) {
                        autoLabel(auto.nBatch).tag(Int?.none)
                        ForEach([128, 256, 512, 1024, 2048], id: \.self) { Text(verbatim: "\($0)").tag(Optional($0)) }
                    }
                    Picker("Micro-Batch", selection: binding(\.microBatch)) {
                        autoLabel(auto.nUbatch).tag(Int?.none)
                        ForEach([64, 128, 256, 512], id: \.self) { Text(verbatim: "\($0)").tag(Optional($0)) }
                    }
                    Picker("KV Cache", selection: binding(\.kvCache)) {
                        autoLabel(auto.typeK.rawValue).tag(KvType?.none)
                        ForEach(KvType.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Flash Attention", selection: binding(\.flashAttention)) {
                        Text("Auto").tag(FlashAttn.auto)
                        Text("On").tag(FlashAttn.on)
                        Text("Off").tag(FlashAttn.off)
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    BoarFooter {
                        Text("Q8_0 and Q4_0 use less memory for the KV cache; on some phones Q8_0 with flash attention generates slower.")
                    }
                }

                Section {
                    Picker("Weights", selection: binding(\.loadMode)) {
                        Text("Auto (Mapped)").tag(LoadMode?.none)
                        Text("Mapped + Locked").tag(Optional(LoadMode.mmapMlock))
                        Text("In Memory").tag(Optional(LoadMode.readAll))
                    }
                    Picker("Repacking", selection: binding(\.weightRepack)) {
                        Text("Auto (On)").tag(Bool?.none)
                        Text("On").tag(Optional(true))
                        Text("Off").tag(Optional(false))
                    }
                    Picker("Stream Experts", selection: binding(\.lazyExperts)) {
                        Text("Auto (Off)").tag(LazyMode?.none)
                        Text("Auto").tag(Optional(LazyMode.auto))
                        Text("On").tag(Optional(LazyMode.on))
                    }
                } header: {
                    Text("Loading")
                } footer: {
                    BoarFooter {
                        Text("Auto maps the model from storage. Repacking reads prompts about 2× faster. After a load that ran out of memory, the next one keeps the weights mapped.")
                    }
                }

                Section {
                    Picker("Thinking", selection: binding(\.thinking)) {
                        Text("Auto (Off)").tag(Bool?.none)
                        Text("On").tag(Optional(true))
                        Text("Off").tag(Optional(false))
                    }
                    Picker("Time Limit", selection: binding(\.stageTimeoutSeconds)) {
                        let autoMinutes = Int((Double(EngineTweaks.autoStageTimeoutMs(nPredict: services.settings.maxTokens)) / 60_000).rounded())
                        Text("Auto (\(autoMinutes) min)").tag(Int?.none)
                        ForEach([2, 5, 10, 20], id: \.self) { m in Text("\(m) min").tag(Optional(m * 60)) }
                        Text("No Limit").tag(Optional(0))
                    }
                } header: {
                    Text("Answers")
                } footer: {
                    BoarFooter {
                        Text("Thinking lets a reasoning model think before it answers; Auto keeps it off so the answer isn't cut short. The Auto time limit grows with the answer length; an answer that hits it keeps what it wrote.")
                    }
                }
            }

            Section {
                Button("Reset All to Auto", systemImage: "arrow.uturn.backward") { save(EngineTweaks()) }
                    .disabled(tw.isAuto)
            } footer: {
                BoarFooter {
                    VStack(alignment: .leading) {
                        if !resolved.notes.isEmpty {
                            Text("Adjusted for this \(Platform.deviceNoun): \(resolved.notes.joined(separator: "; ")).")
                        }
                        Text("Auto is what we measured best on real phones; anything you set wins. Changes apply from the next answer.")
                    }
                }
            }
        }
        .navigationTitle("Engine Tweaks")
        .inlineNavigationTitle()
        .alert(Self.presetName(.run), isPresented: $warningRun) {
            Button("Run") {
                services.settings.runPresetWarned = true
                save(TweakPreset.run.applyTo(tweaks))
            }
            Button("Keep Auto", role: .cancel) {}
        } message: {
            Text(runWarning)
        }
    }

    static func presetName(_ p: TweakPreset) -> String {
        switch p {
        case .run: String(localized: "Fastest")
        case .path: String(localized: "Auto (Recommended)")
        case .forage: String(localized: "Battery Saver")
        case .cool: String(localized: "Cool Down")
        }
    }

    static func presetNote(_ p: TweakPreset) -> String {
        switch p {
        case .run: String(localized: "The fastest answers, with more heat and battery use.")
        case .path: String(localized: "What we measured best on real phones. Balanced.")
        case .forage: String(localized: "Cooler and easier on the battery. Slower answers.")
        case .cool: String(localized: "For a hot \(Platform.deviceNoun). The slowest answers.")
        }
    }
}
