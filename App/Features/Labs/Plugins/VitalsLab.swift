import BoarCore
import BoarLlama
import BoarModels
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Boar Vitals (android labs/plugins/pulse `DevicePulseLab.kt`): what the device feels while BOAR works, once a second.
/// Android reads the battery temperature, each core's clock and the other apps' memory; iOS gives apps none of those, so
/// here the heat is the system's thermal state (with the last two minutes as a line), each core shows its load (Mach tick
/// counters, BoarCore `CoreLoad`), and memory is BOAR's footprint against what iOS lets it use. The chip card keeps
/// Android's lines: engine, CPU features, battery, device.
struct VitalsLab: LabPlugin {
    let id = "pulse"
    let order = 10
    let emoji = "🌡️"
    let art: String? = "truffle_synthetic"
    let status = LabStatus.live
    var title: String { String(localized: "Boar Vitals") }
    var body: String { String(localized: "Watch your \(Platform.deviceNoun) work: heat, every core's load, memory and the chip BOAR runs on.") }

    func content() -> AnyView { AnyView(VitalsSections()) }
}

private struct VitalsSample {
    var thermal: ProcessInfo.ThermalState
    var coreLoad: [Double?]
    var footprint: Int64
    /// What BOAR can still allocate before iOS ends it; nil on the Mac.
    var available: Int64?
    var batteryPct: Int?
    var charging: Bool
}

private struct VitalsSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var now: VitalsSample?
    /// The thermal level (0 nominal … 3 critical) of the last `history` seconds.
    @State private var levels: [Int] = []
    @State private var ticks: [CoreLoad.Ticks] = []
    private static let history = 120
    private static let keyFeatures: Set<String> = ["asimddp", "asimdhp", "i8mm", "sve", "sve2", "sme", "bf16"]

    var body: some View {
        Group {
            if let s = now {
                Section {
                    Text(VitalsSections.thermalLabel(s.thermal))
                        .font(.boar("ui.headline"))
                        .foregroundStyle(Color(palette[keyPath: VitalsSections.thermalColor(s.thermal)]))
                    ThermalSpark(levels: levels, history: VitalsSections.history)
                        .frame(height: 56)
                        .accessibilityHidden(true)
                    Text("last \(levels.count) s · hottest: \(VitalsSections.thermalLabel(VitalsSections.state(levels.max() ?? 0)))")
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.dim))
                } header: {
                    Text("Heat")
                } footer: {
                    BoarFooter {
                        Text("\(Platform.systemName) doesn't give apps the battery temperature: this is its own heat level, the one that makes it slow the \(Platform.deviceNoun) down.")
                    }
                }
                Section {
                    ForEach(Array(s.coreLoad.enumerated()), id: \.offset) { i, load in
                        VitalsMeter(label: "cpu\(i)", value: load.map { "\(Int(($0 * 100).rounded())) %" } ?? "—",
                                    fraction: load ?? 0, tint: \.cyan400)
                    }
                } header: {
                    Text("Cores")
                } footer: {
                    BoarFooter {
                        Text("How busy each core is. \(Platform.systemName) doesn't give apps the clock speed.")
                    }
                }
                Section {
                    let ram = DeviceMemory.totalBytes
                    if let available = s.available {
                        VitalsMeter(label: "BOAR", value: VitalsSections.bytes(s.footprint),
                                    fraction: Double(s.footprint) / Double(max(s.footprint + available, 1)), tint: \.textAccentEmerald)
                        VitalsLine(label: String(localized: "limit"),
                                   value: String(localized: "\(VitalsSections.bytes(available)) more before \(Platform.systemName) closes it"))
                    } else {
                        VitalsMeter(label: "BOAR", value: VitalsSections.bytes(s.footprint),
                                    fraction: Double(s.footprint) / Double(max(ram, 1)), tint: \.textAccentEmerald)
                    }
                    VitalsLine(label: Platform.deviceNoun, value: VitalsSections.bytes(ram))
                } header: {
                    Text("Memory")
                }
                Section {
                    VitalsLine(label: String(localized: "engine"), value: engine)
                    VitalsLine(label: String(localized: "features"),
                               value: CpuVariants.readFeatures().filter { VitalsSections.keyFeatures.contains($0) }.sorted().joined(separator: " ").nonEmpty ?? "—")
                    VitalsLine(label: String(localized: "battery"), value: (s.batteryPct.map { "\($0)%" } ?? "—") + (s.charging ? " ⚡" : ""))
                    VitalsLine(label: String(localized: "device"), value: VitalsSections.device)
                } header: {
                    Text("Chip")
                } footer: {
                    BoarFooter {
                        Text("Leave this open, ask BOAR something, then come back to see what it cost.")
                    }
                }
            } else {
                // Something on screen before the first sample: an empty Group in a Form never runs its .task.
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .task {
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            #endif
            ticks = CoreLoad.read()
            // The first sample at once; the cores' load needs a second snapshot.
            let first = VitalsSections.read(load: ticks.map { _ in nil })
            now = first
            levels = [VitalsSections.level(first.thermal)]
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let next = CoreLoad.read()
                let s = VitalsSections.read(load: CoreLoad.load(before: ticks, after: next))
                ticks = next
                now = s
                levels = Array((levels + [VitalsSections.level(s.thermal)]).suffix(VitalsSections.history))
            }
        }
    }

    private var engine: String {
        switch model.backend {
        case .llama: "llama.cpp · " + (LlamaSession.metalEnabled ? "Metal" : "CPU")
        case .apple: "Apple Intelligence"
        case .remote: String(localized: "llama-server on your network")
        }
    }

    private static func read(load: [Double?]) -> VitalsSample {
        var pct: Int?
        var charging = false
        #if os(iOS)
        let d = UIDevice.current
        if d.batteryLevel >= 0 { pct = Int((d.batteryLevel * 100).rounded()) }
        charging = d.batteryState == .charging || d.batteryState == .full
        #endif
        return VitalsSample(thermal: ProcessInfo.processInfo.thermalState, coreLoad: load, footprint: AppMemory.footprintBytes(),
                            available: DeviceMemory.availableBytes, batteryPct: pct, charging: charging)
    }

    static func level(_ s: ProcessInfo.ThermalState) -> Int {
        switch s {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        default: 3
        }
    }

    static func state(_ level: Int) -> ProcessInfo.ThermalState {
        [.nominal, .fair, .serious, .critical][min(max(level, 0), 3)]
    }

    /// Android's four thermal labels, with the system's name in place of "Android".
    static func thermalLabel(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: String(localized: "cool")
        case .fair: String(localized: "warm")
        case .serious: String(localized: "hot: \(Platform.systemName) may slow it down")
        default: String(localized: "too hot: \(Platform.systemName) is slowing it down")
        }
    }

    /// Android's heat colors (DevicePulseLab.kt heatColor): emerald while cool, amber while warm, crimson500 from the
    /// moment the system may slow the device down (serious and critical alike, as Android's top band).
    static func thermalColor(_ s: ProcessInfo.ThermalState) -> KeyPath<BoarPalette, ARGB> {
        switch s {
        case .nominal: \.textAccentEmerald
        case .fair: \.amber400
        default: \.crimson500
        }
    }

    /// As the device screen shows memory (Android: GB with one decimal, which reads "0.0 GB" for a demo run).
    static func bytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .memory)) }

    /// "Apple iPhone 13 · iPhone14,5" (android "MANUFACTURER MODEL · SoC"); the Mac: its model id and chip.
    static var device: String {
        #if os(macOS)
        return ["Apple", sysctlString("hw.model"), sysctlString("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: " · ")
        #else
        var info = utsname()
        uname(&info)
        let uname = withUnsafeBytes(of: &info.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        let machine: String = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? uname
        if let name = DeviceName.current { return "Apple \(name) · \(machine)" }
        return "Apple \(machine)"
        #endif
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A label, a bar and its value (android `Meter`).
private struct VitalsMeter: View {
    let label: String
    let value: String
    let fraction: Double
    let tint: KeyPath<BoarPalette, ARGB>
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: label).font(.boar("mono.xs")).foregroundStyle(.boar(.muted)).frame(width: 52, alignment: .leading)
            // Android's Meter: a 6 pt bar on the theme's track (track(0.4)), not the system's gray one.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Color.black.opacity(palette.trackAlpha(0.4))
                    Color(palette[keyPath: tint])
                        .frame(width: g.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            .clipShape(.rect(cornerRadius: 3))
            Text(verbatim: value).font(.boar("mono.xs")).monospacedDigit().foregroundStyle(.boar(.secondary)).frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A label and its value (android `Line`).
private struct VitalsLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label).font(.boar("mono.xs")).foregroundStyle(.boar(.muted)).frame(width: 72, alignment: .leading)
            Text(verbatim: value).font(.boar("mono.xs")).foregroundStyle(.boar(.secondary))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The thermal level over the last `history` seconds, as a step line on a fixed 0…3 scale (android `Spark`, which scales
/// to the temperatures it has).
private struct ThermalSpark: View {
    let levels: [Int]
    let history: Int
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { ctx, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height))
            base.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.stroke(base, with: .style(BoarStyle(role: .border)), lineWidth: 1)
            guard levels.count >= 2 else { return }
            func y(_ l: Int) -> CGFloat { size.height - 2 - (size.height - 4) * CGFloat(l) / 3 }
            var line = Path()
            for (i, l) in levels.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(history - 1)
                if i == 0 { line.move(to: CGPoint(x: x, y: y(l))) } else {
                    line.addLine(to: CGPoint(x: x, y: y(levels[i - 1])))
                    line.addLine(to: CGPoint(x: x, y: y(l)))
                }
            }
            // Android's Spark: emerald400, 3 px.
            ctx.stroke(line, with: .color(Color(palette.emerald400)), lineWidth: 3 / displayScale)
        }
    }
}
