import BoarAnswer
import SwiftUI

/// Boar Lunar (android labs/plugins/lunar): the moon from the date alone, offline and without location (BoarAnswer
/// `MoonPhase`, Meeus ch. 49): today's phase and lit share, the next full and new moon, and a month of phases. The
/// hemisphere only mirrors the drawing; a waxing moon is lit on the right in the north and on the left in the south.
/// Moonrise and moonset would need the user's location, so they're left out. No slot: the lab is its page.
struct LunarLab: LabPlugin {
    let id = "lunar"
    let order = 60
    let emoji = "🌕"
    let art: String? = "truffle_lunar"
    let status = LabStatus.alpha
    var title: String { String(localized: "Boar Lunar") }
    var body: String { String(localized: "The moon tonight and this month, offline: phase, lit share, the next full and new moon.") }

    func content() -> AnyView { AnyView(LunarSections()) }

    /// Time zones south of the equator: the default hemisphere until the user picks one. The time zone, not the language:
    /// a phone in Brazil set to English (US) said "north" (X6, Oct 16).
    static let southZones = [
        "America/Sao_Paulo", "America/Argentina", "America/Buenos_Aires", "America/Santiago", "America/Montevideo",
        "America/Asuncion", "America/La_Paz", "America/Lima", "America/Bahia", "America/Recife", "America/Fortaleza", "America/Belem",
        "America/Maceio", "America/Cuiaba", "America/Campo_Grande", "America/Porto_Velho", "America/Rio_Branco", "America/Noronha", "America/Araguaina",
        "Australia/", "Pacific/Auckland", "Pacific/Fiji", "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Lusaka",
        "Africa/Windhoek", "Africa/Gaborone", "Indian/Antananarivo", "Indian/Mauritius", "Antarctica/",
    ]

    /// The user's pick (`labs.lunar.south`: "on" / "off"), else the time zone's hemisphere.
    @MainActor static var south: Bool {
        if let pick = AppPaths.defaults.string(forKey: "labs.lunar.south") { return pick == "on" }
        let zone = TimeZone.current.identifier
        return southZones.contains { zone.hasPrefix($0) }
    }

    static func phaseName(_ key: String) -> LocalizedStringResource {
        switch key {
        case "new": "New moon"
        case "waxingCrescent": "Waxing crescent"
        case "firstQuarter": "First quarter"
        case "waxingGibbous": "Waxing gibbous"
        case "full": "Full moon"
        case "waningGibbous": "Waning gibbous"
        case "lastQuarter": "Last quarter"
        default: "Waning crescent"
        }
    }
}

/// The lab's page below the shared header: refreshed every minute. The sections stay direct children of the page's
/// Form (a TimelineView around them made one card of the whole page).
private struct LunarSections: View {
    @State private var south = LunarLab.south
    @State private var monthOffset = 0
    @State private var now = Date.now

    var body: some View {
        let m = MoonPhase.at(now)
        Group {
            Section {
                VStack(spacing: 6) {
                    Text(verbatim: MoonPhase.emoji(m, south: south))
                        .font(.system(size: 96))
                        .accessibilityHidden(true)
                    Text(LunarLab.phaseName(MoonPhase.nameKey(m)))
                        .font(.title2.weight(.semibold))
                    Text("\(Int((m.illumination * 100).rounded()))% lit · day \(m.ageDays.formatted(.number.precision(.fractionLength(1)))) of the cycle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        now = .now
                    }
                }
            }
            Section {
                Fact(label: "Next full moon", value: "🌕 " + Self.dateTime(m.nextFullMs))
                Fact(label: "Next new moon", value: "🌑 " + Self.dateTime(m.nextNewMs))
            }
            Section {
                Picker("Hemisphere", selection: Binding(get: { south }, set: { pick in
                    south = pick
                    AppPaths.defaults.set(pick ? "on" : "off", forKey: "labs.lunar.south")
                })) {
                    Text("Northern hemisphere").tag(false)
                    Text("Southern hemisphere").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section {
                LunarMonth(now: now, offset: monthOffset, south: south) { monthOffset += $0 }
            } footer: {
                Text("Worked out from the date on this \(Platform.deviceNoun), no internet and no location. The hemisphere only changes which side of the moon is lit. Moonrise and moonset need your location, so they are not shown.")
            }
        }
    }

    /// Android's fact card: the label small on top, the date under it.
    private struct Fact: View {
        let label: LocalizedStringResource
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(verbatim: value)
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func dateTime(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

/// A month as a calendar: each day's phase at local noon, today outlined; ‹ › move by a month.
private struct LunarMonth: View {
    let now: Date
    let offset: Int
    let south: Bool
    let move: (Int) -> Void

    var body: some View {
        let cal = Calendar.current
        let shown = cal.date(byAdding: .month, value: offset, to: now) ?? now
        let first = cal.date(from: cal.dateComponents([.year, .month], from: shown)) ?? shown
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let cells: [Int] = Array(repeating: 0, count: lead) + Array(1...days)
        let title = first.formatted(.dateTime.month(.wide).year())
        VStack(spacing: 8) {
            HStack {
                Button("Previous month", systemImage: "chevron.left") { move(-1) }
                    .labelStyle(.iconOnly)
                Text(verbatim: title.prefix(1).uppercased() + title.dropFirst())
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button("Next month", systemImage: "chevron.right") { move(1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells.indices, id: \.self) { i in
                    let d = cells[i]
                    if d == 0 {
                        Color.clear.frame(height: 1)
                    } else {
                        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.date(byAdding: .day, value: d - 1, to: first) ?? first) ?? first
                        let today = cal.isDate(noon, inSameDayAs: now)
                        VStack(spacing: 2) {
                            Text(verbatim: MoonPhase.emoji(MoonPhase.at(noon), south: south)).font(.system(size: 16))
                            Text(verbatim: "\(d)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .overlay {
                            if today { RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 1) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(d): \(String(localized: LunarLab.phaseName(MoonPhase.nameKey(MoonPhase.at(noon)))))"))
                    }
                }
            }
        }
    }
}
