import BoarCore
import Foundation
import Testing

/// Parity with Android's theme (Fixtures/golden/theme/theme-tokens.json, exported from ThemeTokens.kt and
/// ExtraThemes.kt by scripts/export-theme-tokens.py).
struct ThemeTokensTests {
    nonisolated(unsafe) static let fixture: [String: Any] = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/golden/theme/theme-tokens.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }()

    static var themes: [[String: Any]] { fixture["themes"] as? [[String: Any]] ?? [] }

    /// Boar Avatars' themes as Compose computes them on the JVM (scripts/export-vault-themes.sh).
    nonisolated(unsafe) static let vaultThemes: [[String: Any]] = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/golden/theme/vault-themes.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return obj
    }()

    @Test func everyPaletteMatchesKotlin() throws {
        #expect(Self.themes.count == 3)
        #expect(Self.vaultThemes.map { $0["id"] as? String } == ThemeTokens.vault.map(\.id))
        for theme in Self.themes + Self.vaultThemes {
            let id = try #require(theme["id"] as? String)
            let palette = try #require(ThemeTokens.all.first { $0.id == id }, "missing palette \(id)")
            #expect(palette.name == theme["name"] as? String)
            #expect(palette.icon == theme["icon"] as? String)
            #expect(palette.light == theme["light"] as? Bool)
            let colors = try #require(theme["colors"] as? [String: String])
            let tokens = palette.tokens
            #expect(tokens.count == 59, "\(id) has \(tokens.count) tokens")
            #expect(Set(tokens.map(\.name)) == Set(colors.keys), "\(id) token names differ")
            for (name, color) in tokens {
                #expect(color.description == colors[name], "\(id).\(name): \(color) vs \(colors[name] ?? "nil")")
            }
        }
    }

    @Test func defaultAndLookup() {
        #expect(ThemeTokens.defaultId == Self.fixture["defaultId"] as? String)
        #expect(ThemeTokens.byId(nil).id == "moonlight")
        #expect(ThemeTokens.byId("campfire").id == "campfire")
        #expect(ThemeTokens.byId("paper").light)
        #expect(ThemeTokens.byId("no-such-theme").id == "moonlight")
        #expect(ThemeTokens.open.map(\.id) == ["campfire", "moonlight"])
    }

    @Test func themeChoice() {
        // Unset and "system" follow the device; Android's ids round-trip.
        #expect(ThemeChoice(storedId: nil) == .system)
        #expect(ThemeChoice(storedId: "system") == .system)
        #expect(ThemeChoice.system.storedId == "system")
        for id in ["campfire", "moonlight", "paper"] {
            #expect(ThemeChoice(storedId: id) == .theme(id))
            #expect(ThemeChoice(storedId: id).storedId == id)
        }
        // Older iOS builds stored the appearance.
        #expect(ThemeChoice(storedId: "light") == .theme("paper"))
        #expect(ThemeChoice(storedId: "dark") == .theme("moonlight"))
        // A Vault theme keeps its id; one this app has no palette for falls back to Moonlight, like Android's lookup.
        #expect(ThemeChoice(storedId: "tactical_red") == .theme("tactical_red"))
        #expect(ThemeChoice(storedId: "neon_pink") == .theme("moonlight"))
        // "system" is unknown to Android, which falls back to its default.
        #expect(ThemeTokens.byId(ThemeChoice.system.storedId).id == ThemeTokens.defaultId)

        #expect(ThemeChoice.system.palette(dark: true).id == "moonlight")
        #expect(ThemeChoice.system.palette(dark: false).id == "paper")
        #expect(ThemeChoice.theme("campfire").palette(dark: false).id == "campfire")

        #expect(ThemeChoice.choices(current: .system) == [.system, .theme("campfire"), .theme("moonlight")])
        #expect(ThemeChoice.choices(current: .theme("campfire")).count == 3)
        #expect(ThemeChoice.choices(current: .theme("paper")).last == .theme("paper"))
    }

    /// Android's ThemePicker filter and MainActivity's guard.
    @Test func boarAvatarsThemes() {
        let none = Vault.State()
        #expect(ThemeTokens.available(boarverse: false, state: none).map(\.id) == ["campfire", "moonlight"])
        // Boarverse on: Tactical Red comes with it.
        #expect(ThemeTokens.available(boarverse: true, state: none).map(\.id) == ["campfire", "moonlight", "tactical_red"])
        // Snow brings Paper; a Lab's grant brings its theme. Off, neither shows.
        let some = Vault.State(unlocked: ["snow": 1], themes: ["hacker_green": 2])
        #expect(ThemeTokens.available(boarverse: true, state: some).map(\.id)
                == ["campfire", "moonlight", "tactical_red", "hacker_green", "paper"])
        #expect(ThemeTokens.available(boarverse: false, state: some).count == 2)
        // Shown only while Boarverse is on, back to Moonlight otherwise; Paper and the open ones always.
        #expect(ThemeChoice.theme("tactical_red").shown(boarverse: true) == .theme("tactical_red"))
        #expect(ThemeChoice.theme("tactical_red").shown(boarverse: false) == .theme("moonlight"))
        #expect(ThemeChoice.theme("paper").shown(boarverse: false) == .theme("paper"))
        #expect(ThemeChoice.theme("campfire").shown(boarverse: false) == .theme("campfire"))
        #expect(ThemeChoice.system.shown(boarverse: false) == .system)
        #expect(ThemeTokens.all.count - ThemeTokens.available(boarverse: true, state: none).count == 6)
    }

    @Test func spacingAndRadii() throws {
        let spacing = try #require(Self.fixture["spacing"] as? [String: Int])
        let ours: [String: Double] = ["xxs": Spacing.xxs, "xs": Spacing.xs, "sm": Spacing.sm, "md": Spacing.md,
                                      "base": Spacing.base, "lg": Spacing.lg, "xl": Spacing.xl, "xxl": Spacing.xxl,
                                      "xxxl": Spacing.xxxl]
        #expect(spacing.mapValues(Double.init) == ours)
        let radii = try #require(Self.fixture["radii"] as? [String: Int])
        let ourRadii: [String: Double] = ["xs": Radii.xs, "sm": Radii.sm, "md": Radii.md, "lg": Radii.lg,
                                          "xl": Radii.xl, "xxl": Radii.xxl, "full": Radii.full]
        #expect(radii.mapValues(Double.init) == ourRadii)
    }

    @Test func typeScalesMatchKotlin() throws {
        let type = try #require(Self.fixture["type"] as? [String: [String: [String: Any]]])
        #expect(Set(type.keys) == Set(TypeTokens.scales))
        for scale in TypeTokens.scales {
            let expected = try #require(type[scale])
            let ours = TypeTokens.specs(scale)
            #expect(Set(ours.keys) == Set(expected.keys), "\(scale) style names differ")
            for (name, e) in expected {
                let spec = try #require(ours[name])
                #expect(spec.family == e["family"] as? String, "\(scale) \(name) family")
                #expect(spec.size == (e["size"] as? NSNumber)?.floatValue, "\(scale) \(name) size")
                #expect(spec.lineHeight == (e["lineHeight"] as? NSNumber)?.floatValue, "\(scale) \(name) line")
                #expect(spec.weight == e["weight"] as? Int, "\(scale) \(name) weight")
                #expect(spec.letterSpacing == (e["letterSpacing"] as? NSNumber)?.floatValue, "\(scale) \(name) tracking")
            }
        }
    }

    @Test func brandFaces() {
        #expect(BrandType.familyFor("code", weight: 400) == (.monospace, false))
        #expect(BrandType.familyFor("display", weight: 700) == (.baloo700, false))
        #expect(BrandType.familyFor("display", weight: 900) == (.baloo800, false))
        #expect(BrandType.familyFor("sans-serif", weight: 800) == (.baloo800, false))
        #expect(BrandType.familyFor("monospace", weight: 400) == (.lexend400, true))
        #expect(BrandType.familyFor("monospace", weight: 600) == (.lexend600, true))
        #expect(BrandType.familyFor("sans-serif", weight: 500) == (.lexend500, false))
        #expect(BrandType.familyFor(nil, weight: 700) == (.lexend700, false))
    }

    @Test func scaledSizes() {
        #expect(BrandType.scaledSize(9.25) == 12)
        #expect(BrandType.scaledSize(11) == 12)
        #expect(BrandType.scaledSize(11.5) == 16)
        #expect(BrandType.scaledSize(12) == 13)
        #expect(BrandType.scaledSize(13) == 14)
        #expect(BrandType.scaledSize(15) == 16)
        #expect(BrandType.scaledSize(16) == 16)
        #expect(BrandType.scaledSize(24) == 24)
    }

    /// Worked by hand from Theme.kt's brandStyle (Float math, Math.round).
    @Test func resolvedStyles() throws {
        let body = try #require(BrandType.style("ui.body", scale: "standard"))
        #expect(body.size == 16 && body.lineHeight == 24 && body.face == .lexend400 && !body.tabular)
        let monoMd = try #require(BrandType.style("mono.md", scale: "compact"))
        #expect(monoMd.size == 14 && monoMd.lineHeight == 19 && monoMd.face == .lexend600 && monoMd.tabular)
        let headline = try #require(BrandType.style("ui.headline", scale: "large"))
        #expect(headline.size == 32 && headline.lineHeight == 40 && headline.face == .baloo800 && headline.letterSpacing == -0.3)
        let title = try #require(BrandType.style("ui.title", scale: nil))
        #expect(title.size == 16 && title.lineHeight == 22 && title.face == .baloo700)
        let micro = try #require(BrandType.style("ui.micro", scale: "large"))
        #expect(micro.size == 19 && micro.lineHeight == 25)   // 11.5 → 16 × 1.2 = 19.2; 15 × 19 / 11.5 = 24.8
        #expect(BrandType.style("ui.nope", scale: nil) == nil)
    }
}
