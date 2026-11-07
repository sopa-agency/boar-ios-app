import BoarAnswer
import SwiftUI
#if os(iOS)
import CoreMotion
#endif

/// Boar Nomad (android labs/plugins/compass): a compass from the device's own sensors, offline. Android reads its fused
/// rotation vector; here Core Motion's device motion in the magnetic-north frame gives the heading, with no permission
/// prompt and no location. It points to magnetic north: true north needs the local declination, which needs the user's
/// location, and BOAR doesn't ask for it. A low magnetometer calibration shows the figure-8 hint. The Mac has no
/// magnetometer: the page says so. The arithmetic is BoarAnswer `CompassMath`.
struct CompassLab: LabPlugin {
    let id = "compass"
    let order = 50
    let emoji = "🧭"
    let art: String? = "truffle_nomad"
    let status = LabStatus.alpha
    var title: String { String(localized: "Boar Nomad") }
    var body: String { String(localized: "A compass from the \(Platform.deviceNoun)'s own sensors, offline, no location needed.") }

    func content() -> AnyView { AnyView(CompassSections()) }

    static func direction(_ key: String) -> LocalizedStringResource {
        switch key {
        case "n": LocalizedStringResource("labs.compass.dir.n", defaultValue: "N", comment: "Compass: north")
        case "ne": LocalizedStringResource("labs.compass.dir.ne", defaultValue: "NE", comment: "Compass: northeast")
        case "e": LocalizedStringResource("labs.compass.dir.e", defaultValue: "E", comment: "Compass: east")
        case "se": LocalizedStringResource("labs.compass.dir.se", defaultValue: "SE", comment: "Compass: southeast")
        case "s": LocalizedStringResource("labs.compass.dir.s", defaultValue: "S", comment: "Compass: south")
        case "sw": LocalizedStringResource("labs.compass.dir.sw", defaultValue: "SW", comment: "Compass: southwest")
        case "w": LocalizedStringResource("labs.compass.dir.w", defaultValue: "W", comment: "Compass: west")
        default: LocalizedStringResource("labs.compass.dir.nw", defaultValue: "NW", comment: "Compass: northwest")
        }
    }
}

/// The heading from Core Motion, smoothed (CompassMath), while the page is on screen.
@MainActor
@Observable
private final class CompassReader {
    private(set) var heading = 0.0
    private(set) var seen = false
    /// Starts low, like Android's SENSOR_STATUS_UNRELIABLE: the figure-8 hint shows until the magnetometer reports.
    private(set) var lowAccuracy = true
    #if os(iOS)
    private let motion = CMMotionManager()
    #endif

    var available: Bool {
        #if os(iOS)
        motion.isDeviceMotionAvailable && CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
        #else
        false
        #endif
    }

    func start() {
        #if os(iOS)
        guard available, !motion.isDeviceMotionActive else { return }
        // About Android's SENSOR_DELAY_UI.
        motion.deviceMotionUpdateInterval = 1.0 / 16
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] m, _ in
            guard let m, m.heading >= 0 else { return }
            let reading = m.heading.truncatingRemainder(dividingBy: 360)
            let accuracy = m.magneticField.accuracy
            let low = accuracy == .uncalibrated || accuracy == .low
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.heading = CompassMath.follow(self.heading, reading: reading, first: !self.seen)
                self.seen = true
                self.lowAccuracy = low
            }
        }
        #endif
    }

    func stop() {
        #if os(iOS)
        motion.stopDeviceMotionUpdates()
        #endif
    }
}

private struct CompassSections: View {
    @State private var reader = CompassReader()
    @State private var shownDeg = 0
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if !reader.available {
                Section {
                    Text("This \(Platform.deviceNoun) has no magnetometer, so it can't show a compass.").foregroundStyle(.boar(.muted))
                }
            } else {
                Section {
                    VStack(spacing: 8) {
                        if reader.seen {
                            Text("\(shownDeg)° \(Text(CompassLab.direction(CompassMath.cardinal(shownDeg))))")
                                .font(.boar("ui.headline").monospacedDigit())
                        } else {
                            Text(verbatim: "—").font(.boar("ui.headline"))
                        }
                        CompassRose(heading: reader.heading)
                            .frame(maxWidth: 320)
                            .aspectRatio(1, contentMode: .fit)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                if reader.lowAccuracy {
                    Section {
                        Label("Low accuracy: move the \(Platform.deviceNoun) in a figure 8 a few times, away from metal and magnets.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.boar(.warning))
                            .listRowBackground(Color(palette.amberBgSubtle))
                    }
                }
            }
            Section {
            } footer: {
                BoarFooter {
                    Text("Points to magnetic north, worked out on this \(Platform.deviceNoun) with no internet. True north differs by a few degrees depending on where you are; it would need your location, which BOAR doesn't ask for. Hold the \(Platform.deviceNoun) flat.")
                }
            }
        }
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
        .onChange(of: reader.heading) { _, h in shownDeg = CompassMath.shown(h, previous: shownDeg) }
    }
}

/// The dial turns so its N points to magnetic north; the marker at the top is where the device points.
private struct CompassRose: View {
    let heading: Double

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + 2, y: c.y - r + 2, width: 2 * r - 4, height: 2 * r - 4)),
                       with: .style(BoarStyle(role: .border)), lineWidth: 1.5)
            var dial = ctx
            dial.translateBy(x: c.x, y: c.y)
            dial.rotate(by: .degrees(-heading))
            for i in 0..<72 {
                let a = Angle.degrees(Double(i) * 5 - 90).radians
                let len: CGFloat = i % 18 == 0 ? 0.16 : i % 6 == 0 ? 0.10 : 0.05
                let outer = CGPoint(x: (r - 6) * cos(a), y: (r - 6) * sin(a))
                let inner = CGPoint(x: (r - 6 - r * len) * cos(a), y: (r - 6 - r * len) * sin(a))
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                dial.stroke(tick, with: .style(BoarStyle(role: i == 0 ? .danger : .muted)), lineWidth: i % 18 == 0 ? 2.5 : 1)
            }
            // The needle: crimson to the north, plain to the south.
            var north = Path()
            north.move(to: CGPoint(x: 0, y: -r * 0.62))
            north.addLine(to: CGPoint(x: -r * 0.07, y: 0))
            north.addLine(to: CGPoint(x: r * 0.07, y: 0))
            north.closeSubpath()
            var south = Path()
            south.move(to: CGPoint(x: 0, y: r * 0.62))
            south.addLine(to: CGPoint(x: -r * 0.07, y: 0))
            south.addLine(to: CGPoint(x: r * 0.07, y: 0))
            south.closeSubpath()
            dial.fill(north, with: .style(BoarStyle(role: .danger)))
            dial.fill(south, with: .style(BoarStyle(role: .muted)))
            // Where the device points.
            var top = Path()
            top.move(to: CGPoint(x: c.x, y: 0))
            top.addLine(to: CGPoint(x: c.x - r * 0.06, y: r * 0.1))
            top.addLine(to: CGPoint(x: c.x + r * 0.06, y: r * 0.1))
            top.closeSubpath()
            ctx.fill(top, with: .style(BoarStyle(role: .success)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.04, y: c.y - r * 0.04, width: r * 0.08, height: r * 0.08)), with: .style(BoarStyle(role: .success)))
        }
    }
}
