# Plugins on iOS (formerly Boar Labs)

Where each Android lab stands on iOS (2026-11-05), and what the rest would take. Android's labs live in
`app/src/labs/plugins/<id>` (one folder per lab, `plugin.properties` for id, order and status); the iOS labs are
`App/Features/Labs/Plugins/<Name>Lab.swift`, registered in `Labs.registry`, with their logic in the engine
(`Sources/BoarRouting`, `Sources/BoarAnswer/Labs`, `Sources/BoarRAG`) and the Kotlin tests ported next to it.

## Ported

| Lab | Android id | Slot | Engine (iOS) | Tests |
|---|---|---|---|---|
| Press | `printer` | page, answer menu, chat toolbar | `BoarAnswer/Labs/` PressDoc, PressReceipt, PressLayout (+ PictureFit), PressFiles, PressEdit, PressRewrite (marks), DesignerCanvas, `PressPDF` (+ PressPage, PressPaper), `BoarAnswer/Chat/ChatExport` | `PressDocTests`, `PressReceiptTests`, `PressFilesTests`, `PressPDFTests` (PressSelfTest's projects), `PressEditTests`, `ChatExportTests` |
| Vitals | `pulse` | page, tool | `BoarCore/CoreLoad`, thermal state, footprint, `BoarAnswer/Labs/PluginAnswers` | `CoreLoadTests` (Android has none), `PluginAnswersTests` |
| Nomad | `compass` | page, tool | `BoarAnswer/Labs/CompassMath`, `PluginAnswers`, sensor: Core Motion | `CompassMathTests` (Android has none), `PluginAnswersTests` |
| Lunar | `lunar` | page, tool | `BoarAnswer/Labs/MoonPhase`, `PluginAnswers` | `MoonPhaseTests` (Android has none), `PluginAnswersTests` |
| Polyglot | `polyglot` | tool | `BoarRouting/LanguageGate`, detector: NaturalLanguage | `LanguageGateTests` |
| Calculator | `calc` | tool | `BoarRouting/Arithmetic`, `NumGuard`, `CalcShortcut` | `ArithmeticTests`, `NumGuardTests` |
| Distance | `distance` | tool | `BoarRouting/TravelDistance` | `TravelDistanceTests` |
| Facts | `facts` | tool + search stage (two or more countries: the table's dated figures as one more source, `SearchStages`) | `BoarAnswer/Labs/Facts` | `FactsTests`, `FactsCountryContextTests` |
| Guard | `guard` | check | `BoarRouting/VerdictGuard` | `VerdictGuardTests` |
| Cohazard | `cohazard` | tool (first) | `BoarRouting/CoHazard` | `CoHazardTests`, `CoHazardPtEsTests` |
| Cards | `canvas` | answer menu, under the answer's text (`answerExtra`) | `BoarAnswer/Cards` (CardRules, AnswerCard, Visual, VisualContext, CiteMarks) | `CardRulesTests`, `AnswerCardTests`, `AnswerCardPtTests`, `VisualTests`, `VisualContextTests`, `VisualPairingMatrixTests`, `CiteMarksTests`, `CardsPluginTests` |
| Daily Quiz | `dailyQuiz` | page, behind its classified tile | `BoarRAG/DailyQuiz`, `KnowledgeBase.seedArticles`, `BoarCore/KotlinRandom` | `DailyQuizTests`, `KotlinRandomTests` |

All of them together: `LabToolsCombinationTests` and `LabToolsCompoundTests` (Android's, with `Fixtures/labs`).

Sanctuary and Signboard are classified teasers on Android too (no code behind them); iOS shows the same tiles.

Differences from Android, on purpose:

- **Plugins rename and BOAR-53 (2026-11-24, against v2.0.0):** user-facing "Labs" is "Plugins" and no plugin name starts with "Boar" (ids and
  classes keep `Lab`). Every difference below is deliberate:
  - Designer starts off (`LabDefaults.startsOffHere = ["image"]`): Image Playground needs Apple Intelligence, so it isn't on by default.
  - Polyglot is deprecated (`LabDefaults.deprecated`): out of the list, never active.
  - Tiles, the classified teasers, status tags, the easter egg and Daily Quiz are hidden (`PluginsUi`, as Android hides tiles and teasers);
    the list is the only view.
  - Lunar, Nomad and Vitals have no example or Try rows; their "How it works" says they answer in the chat (BOAR-56).
  - Designer has no canvas toolbar, gear or "..." menu. Press is the one `LabPlugin.fullPage` page: no form, the switch in the
    navigation bar beside its gear (Press settings), its "..." menu in the note bar at the bottom.
  - Press's about text and body leave out drawings and the recipes (iOS Designer keeps none); Designer's "How it works" is about Image Playground.
  - A Try row's long press is a context menu (ask, edit in the box, copy).
  - From the header sheet a plugin page opens as a push inside the sheet, with Done instead of Android's close; Press's basket count shows only in
    the sheet row.
  - Selected plugin pages are opened from a plugin answer's picture and name through `AppModel.openPlugin` (a root sheet).
- **No release manifest (decision):** Android's `released.txt` hides plugins that exist in code but aren't released. Every iOS plugin that exists
  ships, and the ones that don't (Big Boar, Wisp, Sanctuary, Signboard) have no code, so iOS needs no manifest; `LabDefaults`'s
  deprecated and start-off sets plus `PluginsUi` are the only gates. Revisit if a plugin lands in code before it's meant to ship.

- **Daily Quiz:** right answers and days played count for Boar Avatars, and the copy says so, as on Android. The draw goes through `KotlinRandom` (Kotlin's
  XorWowRandom, `nextInt`, `shuffle`) so both phones get the same quiz for the same date and library; written from the
  Kotlin stdlib sources, not yet checked against a JVM run (the build host has no Java).
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
- **Press:** the 📎 action sits in the answer's More menu (iOS has no 🧩 sheet); the projects are Android's JSON file at
  `labs/press/projects.json` (the old `labs/basket.json` migrated once), erased with the chats (Erase Chats unless Press
  is kept, Erase All Data, the lock's erase). Files go out through the share sheet (Save to Files included) instead of
  Android's Save as. No drawings: iOS has no Image Gen, so the drawing switches stay hidden,
  as Android hides them when no answer has a drawing. The PDF is Core Text on Android's A4 layout (`PressPDF`, same
  sizes, colors and spacing; Georgia for Android's serif, with Core Text's fallback for Arabic, Chinese and emoji);
  Android's 2.4 s printing animation is left out.
- **Cards (BOAR-54, against v2.0.0):** the row ("Create a card" · what the rules found, or "Nothing to draw here" · "Ask BOAR
  to make one · slower") is in the answer's More menu, with its second line, as Press's (no 🧩 sheet; the "How it works" text
  says More). The model's card runs as the chat's own job (`ChatController.runForLab`) instead of Android's lab hold: a
  question sent meanwhile waits in the chat's queue and starts after it, and Stop ends it (the composer's Stop, ⌘. and
  New Chat treat it as an answer in progress, `ChatController.holdsModel`; the wait line also has a ✕, which Android's
  lacks). It uses only the model the chat
  already has: with none loaded it says "No answer model is loaded" instead of loading one (a model that may not fit asks
  first, in the chat). Not ported: `CardSpec` and `CanvasTest` (dead in v2.0.0), the move of pre-Cards files
  (`files/canvas`, which iOS never had); `cards.v1.json` is a bench topic, ported with Bench in BOAR-56
  (docs/BENCHMARK-SCREEN.md). Press doesn't take the
  card along yet (PressDoc, the PDF's card): that comes with Press in BOAR-55. Answer ids are never reused, so a deleted
  chat's cards need no `eraseAnswers`: their meta goes with the chat.
- **Press redone (BOAR-55, against v2.0.0), part 6.1, the engine:** projects as documents of blocks (`PressDoc`), the old
  basket migrated once into "Field notes" (an unreadable basket stays and is retried, G-3), the receipt, the footer (models,
  "Made offline with BOAR"), the Sources section, own file names scrubbed out of both exports, the validator gate (G-1 to
  G-6, G-9) and the PDF of the block document, with pictures left / center / right and text beside. Deliberate
  differences:
  - Android's `Paper` is `PressPaper`; Android's `PdfCompiler` is `PressPDF`, its `PressPage` lives in the engine (the app
    fills the words and switches, `PressPrefs.page`). Noto Serif and Roboto are Georgia and the system sans; a line's
    height is Core Text's ascent + descent times the spacing, so page breaks can fall a line apart from Android's.
  - The projects JSON is written with sorted keys (BoarCore `JSONValue`), not Kotlin's insertion order; both read either.
  - `PressFiles.copyInto` takes a writer of a temporary URL instead of an `OutputStream`; the photo pixels work in Double,
    Kotlin's in Float. The pack-label regex counts `{1,60}` in code points, Java in UTF-16 units.
  - iOS Designer (Image Playground) keeps no recipe or per-answer illustration, so drawings in a project come only from
    Android-style data (`illustrations` is empty on migration) and the receipt's Drawings line is rare here.
  - Not in 6.1: the page itself (6.2), the rewrite prompts and model work, several projects in the UI and presets (6.3).
    Add to Press goes to the open project and takes the shown card with its ticks. A deleted chat's
    answers leave every project (`LabPlugin.eraseAnswers`, from `ChatController.deleteSession`); the chat limit's prune
    doesn't run it yet, and the prune and delete dialogs don't say Press loses them (`pluginsOn: false`).
  - The Kotlin tests that read Android's screen sources (PressEraseTest, PressDesignerLayoutTest, parts of the gate) have
    no counterpart; the fuzz uses SplitMix64 with seed 7 instead of `java.util.Random(7)`.
- **Press redone, part 6.2, the page:** `PressScreen` draws the open project on white A4 paper (`PressPaperView`) at the PDF's
  sizes scaled to the screen width: the title (renamed on the page), the date, the blocks, the Sources section and the footer,
  with dashed lines where the PDF's pages end (`PressPDF.pageStarts`, the "Show page breaks" setting). Text beside a left or
  right picture is cut with the PDF's own Core Text lines (`PressPDF.splitBeside`), so the paper breaks where the PDF does.
  Tapping a block selects it; the action bar moves it (keeping it in view, `PressLayout.scrollToShow`), opens its text on the
  page, its caption, its place (left → center → right) or removes it, with Undo. The add bar is heading, paragraph, list,
  divider, photo, then answers from a chat; a new block goes after the selected one (else after the bar's last note) and opens
  with its text selected (`PressEdit`). Photos come from `PhotosPicker`, copied upright as a JPEG of at most 1600 px into the
  project's folder (`PressFiles.copyPhoto`). The gear opens Press settings (page breaks, the date, sources, models and their
  speed); the note bar's "..." menu has Save as .pdf / .md, Rename and Delete. Deliberate differences:
  - No drawing button in the add bar: iOS Designer keeps no recipe and its pictures live at container paths, so there is
    nothing stable to point a block at yet.
  - The bar only writes notes, and the pencil edits the text in place. Android's edit sheet (edit myself or ask BOAR) and the
    bar asking BOAR to rewrite a selected block come with the rewrite in 6.3.
  - The menu is a SwiftUI Menu with Save as, Rename and Delete; the project list, New project and All projects come in 6.3.
    Save goes through the share sheet, with no printing animation.
  - Undo of a removed block is a bar above the tools (for `ChatList.undoMs`) instead of a snackbar; the photo file goes 10 s
    after that.
  - Answers added from the page's chat list carry no model or speed, as on Android; the list shows the latest 12 chats.
  - On the paper a line's height is SwiftUI's line spacing over the font's natural height, an approximation of the PDF's
    Core Text lines, so a block can sit a few points off its printed place; the page-break lines come from the PDF itself.
- **Plugin answers (BOAR-56, against v2.0.0):** Lunar, Nomad and Vitals answer their questions in the chat (`PluginAnswers`,
  tool codes `lunar-phase`, `compass-heading`, `vitals-phone`), and a model's answer to a question one of them would have
  taken while it's off says "<name> is off. Turn it on in Plugins ›". Differences: the answers name the device ("This iPhone
  has no compass", "Read on this iPhone just now") where Android says "phone"; "my iPhone" / "this iPad" count as the device
  in Vitals' question; Vitals says the system's heat level ("heat level warm") instead of the battery temperature iOS
  doesn't give, and its "free memory" is what BOAR can still use before iOS closes it (`os_proc_available_memory`; the Mac
  says no memory figure). The tool slot runs synchronously, so the chat reads the compass (up to 900 ms, three readings, as
  Android) and the battery just before the tools run (`PhoneReads.prepare`), only for a question that plugin takes. The
  off line opens the plugin's page (its switch is there) in every profile, where Android's Pro opens the Plugins list.
  Illustrate on these answers waits for Designer. The bench's plugins topic runs them the same way, with the topic's labs
  on whatever the app has on (docs/BENCHMARK-SCREEN.md).
- **Waiting animation (BOAR-56, rc3 bfe69c4b, 50bdf593):** Android draws the boar's trail (or the Matrix rain, a Pro setting)
  on its Close BOAR screen, hoofprints only. iOS has no Close BOAR (an iOS app doesn't quit itself) and no Matrix rain, and
  Designer waits on Image Playground's own progress, so no iOS screen shows a waiting animation and the setting isn't
  offered (it would change nothing). Only the trail's math is ported (`BoarAnswer/Labs/Trail`, `TrailTests`), ready for
  the first iOS wait that needs it.
- **Timing tests:** Kotlin's time limits are for a warm JVM; a Swift debug build with every suite in parallel takes about
  twice as long on the same regexes (`LabCombos.timeFactor`).

Open from the core (item 1 of the 2026-11-04 night): the Labs storage limit (`StorageBudget.userLimit`) and Android's
restart after a crash in a lab (an iOS app can't relaunch itself; the next launch shows what happened instead).

## Not ported: what each would take

### Boar Designer (`image`): possible, large, with a decision first

**Decided 2026-11-12 (Biel):** Image Playground, offered only where Apple Intelligence is on (iOS 18+, iPhone 15 Pro and
later); no in-process engine, as 683 MB for this lab isn't worth it. The rest of this section is the analysis behind it.

**Built 2026-11-12 (`DesignerLab`, ALPHA):** a "What to draw" field and Draw, which opens Apple's
`imagePlaygroundSheet` with the words as the concept and the styles limited to animation, illustration and sketch (never
the cloud provider); the picture comes back as a file and is kept in `designer/` under BOAR's files (Erase All Data
removes it), shown in a gallery with Share and Delete. Needs iOS 18.4 / macOS 15.4 (the style limit) and Apple
Intelligence (`supportsImagePlayground`); elsewhere the page says why. Not ported: Designer's own styles, sizes, seeds,
Regenerate, "From your last chat" and Illustrate. Only the unavailable page has been seen (simulator, iPhone 14 Pro):
the sheet still has to be tried on an iPhone 15 Pro or later, or a Mac with Apple Intelligence.

**Status (2026-11-05):** moved to phase 3. The choice waits for phase 3's memory measurements: the iPhone 14 Pro (6 GB)
lets BOAR use about 3 GB before iOS ends it, and the chat model alone takes about 1 GB.

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

#### Image Playground against what Designer does (2026-11-10, read from the iOS 27.2 SDK)

Input for the decision after phase 3's measurements. What the SDK's `ImagePlayground.swiftinterface` says:

- **The programmatic path is going away.** `ImageCreator` (iOS 18.4+, the only API that draws without showing Apple's
  UI) is **deprecated in iOS 27**: "Use ImagePlaygroundViewController or imagePlaygroundSheet." It still works, but
  building Designer on it means building on something Apple is retiring.
- **What stays is Apple's own sheet** (`imagePlaygroundSheet`, `ImagePlaygroundViewController`, iOS 18.1+): the user
  draws inside Apple's UI from our concepts (text, or text extracted from a longer passage) and an optional source
  image, and gets back a file URL. Our screen would be a launcher plus a gallery, not Designer's own composer.
- **Styles:** animation, illustration, sketch, emoji (Genmoji), `externalProvider` (iOS 26+, ChatGPT in the cloud:
  must be left out, BOAR is offline) and `any` (iOS 27). The app can limit and preselect them
  (`imagePlaygroundGenerationStyle(_:in:)`), not add its own. Designer's 8 prompt styles (engraving, scientific, photo,
  cyber, solarpunk, Y2K, lo-fi, watercolor) can only survive as words in the concept, and the system decides how much
  of them shows.
- **Sizes:** iOS 27 adds `ImagePlaygroundOptions.sizeSpecification` (`.closest(to: CGSize)`), so Designer's 9
  canvases map to the nearest size the system offers; iOS 26.4 adds variety and personalization options, iOS 27 a
  creation strategy (edit existing or generate new).
- **Not offered:** seeds (Designer's "same composition, new words"), a no-style raw prompt, the per-size timings, and
  drawing in the background (`backgroundCreationForbidden`).
- **Devices:** only where Apple Intelligence is on (`ImagePlaygroundViewController.isAvailable`): iPhone 15 Pro and
  later. **The test iPhone 14 Pro and the 4 GB iPhone 13 have none**, so on the phones we test with the lab would
  only show "not available on this iPhone". Android's sd-cli runs on every phone it targets.
- **Gains:** no 683 MB download, no memory fight with the chat model (the system draws out of BOAR's process and
  jetsam budget), Apple's safety filters, nothing to license.

What Designer has that Image Playground can't give: its own styles, sizes and seeds, Regenerate with the same recipe,
Illustrate (the chat model picks the subject and the drawing goes under the answer: with the sheet, the user would
have to confirm in Apple's UI every time), and the same result on every phone.

Reading for the decision: Image Playground is the cheap way to have *a* drawing lab on recent iPhones, but it is not
Designer, and its no-UI API is deprecated. If the lab should behave like Android's, option 2 (stable-diffusion.cpp in
the process, sharing llama.cpp's ggml, chat model unloaded while drawing) is the one that ports it; phase 3's memory
numbers decide whether SDXS (683 MB) fits under the 3 GB jetsam limit with the chat model out.

### Big Boar (`bmoe`): not in the full version

**Decided 2026-11-13 (Biel):** dropped from the full version; the notes below stay for reference.

BigMoeOnEdge runs Qwen3.6-35B-A3B (12.3 GB) by keeping the always-used weights in memory and reading each token's
experts from storage.

- Needs BigMoeOnEdge built as an XCFramework behind the model seam, like `BoarLlama`.
- Mapping a 12 GB file on an iPhone likely needs the extended virtual addressing entitlement (and maybe the increased
  memory limit one); whether a free Personal Team can sign them is unchecked. Speed on the iPhone 14 Pro is unknown.
- Recommendation: leave it for phase 3, after the paid developer account, with a measured run on the cabled iPhone.
- **Decided 2026-11-12 (Biel):** the last item of the full version. Measured on the iPhone once the paid account exists;
  if it doesn't run well, the full version ships without it.

### Boar Wisp (`colibri`): skip, as Android does

Under review on Android: too slow for an assistant (under 1 tok/s) and its engine isn't in the current version. iOS
follows: nothing to port until Android brings it back.
