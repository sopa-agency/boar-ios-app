# Boar Labs on iOS

Where each Android lab stands on iOS (2026-11-05), and what the rest would take. Android's labs live in
`app/src/labs/plugins/<id>` (one folder per lab, `plugin.properties` for id, order and status); the iOS labs are
`App/Features/Labs/Plugins/<Name>Lab.swift`, registered in `Labs.registry`, with their logic in the engine
(`Sources/BoarRouting`, `Sources/BoarAnswer/Labs`, `Sources/BoarRAG`) and the Kotlin tests ported next to it.

## Ported

| Lab | Android id | Slot | Engine (iOS) | Tests |
|---|---|---|---|---|
| Boar Vitals | `pulse` | page | `BoarCore/CoreLoad`, thermal state, footprint | `CoreLoadTests` (Android has none) |
| Boar Nomad | `compass` | page | `BoarAnswer/Labs/CompassMath`, sensor: Core Motion | `CompassMathTests` (Android has none) |
| Boar Lunar | `lunar` | page | `BoarAnswer/Labs/MoonPhase` | `MoonPhaseTests` (Android has none) |
| Boar Polyglot | `polyglot` | tool | `BoarRouting/LanguageGate`, detector: NaturalLanguage | `LanguageGateTests` |
| Boar Calculator | `calc` | tool | `BoarRouting/Arithmetic`, `NumGuard`, `CalcShortcut` | `ArithmeticTests`, `NumGuardTests` |
| Boar Distance | `distance` | tool | `BoarRouting/TravelDistance` | `TravelDistanceTests` |
| Boar Facts | `facts` | tool | `BoarAnswer/Labs/Facts` | `FactsTests` |
| Boar Guard | `guard` | check | `BoarRouting/VerdictGuard` | `VerdictGuardTests` |
| Boar Cohazard | `cohazard` | tool (first) | `BoarRouting/CoHazard` | `CoHazardTests`, `CoHazardPtEsTests` |
| Daily Quiz | `dailyQuiz` | page, behind its classified tile | `BoarRAG/DailyQuiz`, `KnowledgeBase.seedArticles`, `BoarCore/KotlinRandom` | `DailyQuizTests`, `KotlinRandomTests` |

All of them together: `LabToolsCombinationTests` and `LabToolsCompoundTests` (Android's, with `Fixtures/labs`).

Sanctuary and Signboard are classified teasers on Android too (no code behind them); iOS shows the same tiles.

Differences from Android, on purpose:

- **Daily Quiz:** Android's right answers unlock Boar Avatars (engine `vault/Vault.kt`). The iOS app has no Vault yet, so
  the quiz counts nothing and its copy doesn't promise avatars. The draw goes through `KotlinRandom` (Kotlin's
  XorWowRandom, `nextInt`, `shuffle`) so both phones get the same quiz for the same date and library; written from the
  Kotlin stdlib sources, not yet checked against a JVM run (cx has no Java).
- **Polyglot:** the note leaves out Android's "without the phone's detector (Android 10+)" sentence: NaturalLanguage is
  always there.
- **Nomad:** Core Motion device motion in the `.xMagneticNorthZVertical` frame (fused, no permission prompt) instead of
  Android's rotation vector, so there is no raw accelerometer + magnetometer fallback. The figure-8 hint follows the
  magnetometer's calibration accuracy and shows until the first report, like Android. The simulator and the Mac have no
  magnetometer and show the "no magnetometer" text; the needle itself is still to be checked on the iPhone.
- **Vitals:** iOS gives apps neither the battery temperature, nor the cores' clocks, nor the other apps' memory. The heat
  card shows the thermal state (`ProcessInfo.thermalState`, Android's four labels) and its last two minutes as a step line;
  the cores card shows each core's load from Mach's tick counters (`host_processor_info`); memory is BOAR's footprint
  against what iOS lets it use (`os_proc_available_memory`; the Mac against its RAM), as on the device screen. The chip
  card keeps engine (llama.cpp · Metal/CPU, Apple Intelligence or llama-server), CPU features, battery and device.
- **Timing tests:** Kotlin's time limits are for a warm JVM; a Swift debug build with every suite in parallel takes about
  twice as long on the same regexes (`LabCombos.timeFactor`).

Open from the core (item 1 of the 2026-11-04 night): the Labs storage limit (`StorageBudget.userLimit`) and Android's
restart after a crash in a lab (an iOS app can't relaunch itself; the next launch shows what happened instead).

## Not ported: what each would take

### Boar Press (`printer`): feasible, medium to large

A basket of answers from any chat ("＋ Basket"), reordered and edited, compiled to an A4 PDF or Markdown.

- All of it has Apple pieces: a basket action in the answer menu, a `List` with edit mode for ordering, PDF through
  `UIGraphicsPDFRenderer` (iOS) or `ImageRenderer` (both), sharing through `ShareLink` and `.fileExporter`.
- About 900 lines of Kotlin, most of it UI. Each entry's optional drawing comes from Designer: without it, entries keep
  their own illustration or none.
- Recommendation: the next lab to port; it doesn't depend on anything iOS lacks.

### Boar Designer (`image`): possible, large, with a decision first

Android runs stable-diffusion.cpp's `sd-cli` with SDXS-512 (one step) as its own process, so its ggml can't clash with
the chat engine's and an out-of-memory kill takes only the image down.

- iOS apps can't start a child process, so the Android design doesn't carry over. Three ways:
  1. **Image Playground** (`ImageCreator`, iOS 18.4+): the system's own generator, no download. Only on Apple
     Intelligence iPhones (not the 4 GB ones), and only its styles (animation, illustration, sketch).
  2. **stable-diffusion.cpp in the app's process:** it bundles its own ggml, which clashes with llama.cpp's symbols;
     it would have to be built against the same ggml as llama.cpp b11010 (or with renamed symbols), and the chat model
     unloaded while drawing to stay under the memory limit.
  3. **Core ML** (Apple's `ml-stable-diffusion`): SD 1.5/2.1/SDXL convert, SDXS has no ready Core ML port.
- Recommendation: start with Image Playground where it exists (small, no model to ship) and decide on 2 or 3 with Biel.

### Big Boar (`bmoe`): study only, large

BigMoeOnEdge runs Qwen3.6-35B-A3B (12.3 GB) by keeping the always-used weights in memory and reading each token's
experts from storage.

- Needs BigMoeOnEdge built as an XCFramework behind the model seam, like `BoarLlama`.
- Mapping a 12 GB file on an iPhone likely needs the extended virtual addressing entitlement (and maybe the increased
  memory limit one); whether a free Personal Team can sign them is unchecked. Speed on the iPhone 14 Pro is unknown.
- Recommendation: leave it for phase 3, after the paid developer account, with a measured run on the cabled iPhone.

### Boar Wisp (`colibri`): skip, as Android does

Under review on Android: too slow for an assistant (under 1 tok/s) and its engine isn't in the current version. iOS
follows: nothing to port until Android brings it back.
