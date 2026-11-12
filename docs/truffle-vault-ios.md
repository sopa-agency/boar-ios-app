# Boar Avatars (the Truffle Vault) on iOS

Study and plan, 2026-11-10, against `rferrari/boar-app` at `Fixtures/SOURCE_SHA`. Step 1 (the engine) is merged; step 2
(counting) is built, see [Step 2 as built](#step-2-as-built-counting-2026-11-11); nothing shows on screen yet. The UI
says **Boar Avatars**, and the switch that turns them on says **Boarverse**; the Android code still says vault and truffle,
and so does this plan when it names code.

## What Android has

| Piece | Android file | Size |
|---|---|---|
| Rules: facts → which avatars unlock | `engine/.../vault/Vault.kt` | 185 lines, pure Kotlin |
| Rule tests | `engine/src/test/.../vault/VaultTest.kt` | 11 tests |
| Counting on the phone, storage, "new avatar" events, equip | `app/.../appearance/TruffleVault.kt` | 167 lines |
| Grid, avatar picker, theme picker, toast, entry row | `app/.../ui/appearance/VaultScreen.kt` | 184 lines |
| Extra themes (Tactical Red, Hacker Green, Stealth Mono, Nomad Moss, Quantum Cyan, Solarpunk Gold, Paper) | `app/.../ui/theme/ExtraThemes.kt` | 82 lines |
| Launcher icon switch (activity aliases) | `appearance/IconSwitcher.kt`, `src/launcherIcons/` | 43 lines + 40 adaptive icons |
| Art: id → avatar drawable + alias, generated | `appearance/TruffleArt.kt`, `art/icons/truffles.json`, `art/icons/hires/` (512 px webp) | 40 boars, 2.3 MB hi-res |
| Copy | `strings_native.xml` (`native_vault_*`, `native_rule_*`, `native_truffle_*`), EN + PT | 102 strings each |

**40 avatars, 43 rules.** Each avatar has one rule (`Vault.RULES`, ordered like `truffles.json`); 3 rules
(`CHATS_100`, `EVAL_SHARED`, `EXPORT`) are defined but no avatar uses them today.
`tactical` is `ALWAYS` (a fresh install has it, and it is never announced). `fomo_unicorn` is `ALL_OTHERS`: decided in
`apply`, it unlocks in the same pass as the last other avatar.

**Facts** (all counted on the phone, never sent): answers, sourced answers, offline answers, answers between 02:00 and
03:59, Deep Research runs, evaluation runs and shares, chats, documents, exports, packs, Hugging Face models, best tok/s,
voice used, asked in Portuguese, PIN on, theme changed, Advanced tweaks changed, source build, de-Googled phone, Daily
Quiz right answers and days, days used, days opened in airplane mode. Day lists are ISO dates, distinct, sorted, at
most 64; a streak counts days in a row ending today or yesterday.

**Stored** in `settings.json` under `truffleVault` (`{facts, unlocked: {id: epochMs}, themes: {id: epochMs}}`, unknown
keys ignored, junk → empty state) and `iconId` (the equipped boar, null = BOAR's own). The Boarverse switch is a
separate preference (`vault/experimental.on`), off by default.

**Flags.** `EXPERIMENTAL_FEATURES` (build): shows the Boarverse switch at the bottom of Advanced tweaks, next to Boar
Labs. `SWITCH_SHOWN` (code, true since Oct 24). `TRUFFLE_LAUNCHER_ICONS` (build, **off** by default): the equipped boar
also becomes the launcher icon. With Boarverse off, facts are still counted, so turning it on later finds avatars
waiting; but no toast, no picker, BOAR's own avatar, and only the open themes.

**Where it shows when on:** Settings → Display (avatar row under the theme chips, extra themes in the chips, "N more
themes are unlocked by Labs and avatars"), Settings → Boar Avatars section (the way into the grid), the grid (unlocked
in color with name and date or "Equipped", locked as a near-black silhouette with "?" and the rule's clue), a toast
"New avatar unlocked: X" with Equip, and the equipped boar in place of the mascot: chat header, empty chat, each answer,
drawer header.

**Themes.** Tactical Red opens with Boarverse on; Paper with the `snow` avatar; the other five are granted by labs
(`grantTheme`; on Android only the benchmark activity grants them all today). Each extra is Moonlight with an accent and a
surface mixed by Compose's `lerp`, which mixes in Oklab. Paper is written out whole.

## What carries over 1:1

- **The rules engine** (`Vault`, `Facts`, `Rule`, `RULES`, `State`, `apply`, `Days`, `isNight`) as Swift in
  `Sources/BoarCore/Vault.swift`: no platform code in it. Dates as `yyyy-MM-dd` strings with a Gregorian calendar in the
  phone's time zone (what `LocalDate.now()` gives). Same JSON (`settings.json` → `truffleVault`, `iconId`), so the shape
  matches what Android stores and the iOS app's `KeyValueStore` already speaks.
- **All 40 avatars and their order, names and clues** (EN + PT from `strings_native.xml`, into `Localizable.xcstrings`).
- **The screens**: grid, picker, theme chips, toast, entry row, Boarverse switch in Advanced → Experimental (iOS already
  has `LabsBuild.experimental` and the Labs switch there).
- **Most counters** have an iOS twin already: answers/sourced/Deep Research (chat), evaluations and share
  (`EvalShareMenu`), documents and export (`ExportedFile`, Press), packs, Hugging Face models (`HfBrowser`), tok/s,
  voice (`VoiceInputController`), Portuguese (the routing's language), theme and tweaks changes, Daily Quiz
  (`DailyQuizLab` exists; it would start counting `quizRight`/`quizDays` and its copy would get Android's "Right answers
  unlock Boar Avatars." back), days used.

## What changes on iOS

- **Launcher icon:** `UIApplication.setAlternateIconName` instead of activity aliases. iOS shows its own "You have
  changed the icon" alert and only allows it in the foreground, so the switch happens at Equip, not when the app leaves
  the screen. 40 alternate icon sets (1024 px, built from `art/icons/hires/<id>.webp` on `ic_bg_<id>` from
  `truffle_colors.xml`, like Android's adaptive icon) listed in `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` only when
  the flag is on; off (Android's default), the boars stay inside the app and the icons aren't shipped. The Mac app can
  only change the Dock icon while running (`NSApp.applicationIconImage`): leave it out there.
- **PIN → app lock.** `pinOn` is iOS's lock (`AppLock`, Face ID / passcode); the clue says "Lock BOAR" instead of
  "with a PIN" (same change the tour made).
- **Airplane mode:** iOS has no API for it. Closest honest signal: opened with no network at all
  (`NWPath.status == .unsatisfied`, which `SystemStatus` already watches). Four avatars use it (nomad, ice, snow,
  tactical_ii); their clues will say "no network" instead of "airplane mode". **Decided 2026-11-11 (Biel):** a day
  counts in `airplaneDays` when BOAR is opened with no network at all; the clue wording comes with the UI.
- **Source build** (`hacker`): Android checks the APK isn't signed with BOAR's release key. iOS: the build isn't from the
  App Store or TestFlight (`AppTransaction.shared` → `environment == .xcode`, or a debug build). Same meaning: built it
  yourself. **Decided 2026-11-11 (Biel):** a DEBUG build, or `AppTransaction.shared` reporting `.xcode`; asked once per
  launch in the background, and an error (offline, no receipt) counts nothing. On the Mac, a build with no App Store
  receipt isn't asked (asking may open the App Store's sign-in).
- **Speed** (`quantum` FAST_15, `volcanic` FAST_8): Android only has on-device engines. iOS's "Mac on your network"
  engine would count the Mac's speed, so a remote answer gives no speed; Apple's model runs on the device and counts.
- **Erase All Data** (Android's "clear app data") empties the vault and the Boarverse switch; Reset settings keeps them.
- **De-Googled** (`stealth`): no iOS equivalent (every iPhone is "de-Googled"). Options: (a) unlock it on every iPhone
  at first open, like `tactical`; (b) keep it locked forever on iOS (the unicorn would then be unreachable); (c) a
  different iOS rule (e.g. Lockdown Mode, which has no public API either). **Recommendation: (a)**, with an iOS clue,
  and tell Android so the decision is shared. **Decided 2026-11-11 (Biel): (a).** Every iPhone and Mac counts as
  de-Googled (`degoogled = true` at every open), so `stealth` unlocks at the first open like `tactical` (but, unlike
  `tactical`, it is announced). Android still to be told.
- **Offline answers:** "no validated internet" on Android → `NWPath.status != .satisfied` on iOS (what the chat's
  ONLINE pill already uses).
- **Picture of a locked avatar:** Android's color matrix → SwiftUI `.colorMultiply(.black)` + a near-black tint, or a
  silhouette pre-rendered by the import script. Same look either way; to be checked against an Android capture.
- **Toast:** iOS has no Android-style toast in the app yet; a small banner at the top (like the chat's other banners)
  with an Equip button, announced to VoiceOver.

## Proving parity (the golden part)

The build host has no JVM, so Android can't be run here to dump expected states (same limit as the Daily Quiz's
`KotlinRandom`). Instead:

1. **Port `VaultTest.kt` test for test** (`Tests/BoarCoreTests/VaultTests.swift`), the way the labs' Kotlin tests were.
2. **Roster check:** copy `art/icons/truffles.json` into `Fixtures/vault/` (via `sync-reference.sh`) and assert
   `Vault.rules` keys equal its ids in order, as Android does.
3. **Rule table check:** a small script (`scripts/check-vault-rules.py`) reads `.ref/.../vault/Vault.kt` and asserts that
   every `Rule(...)` threshold and every `"id" to Rule.X` pair matches the Swift file. Re-run after each
   `sync-reference.sh`, so a rule changed on Android fails here.
4. **JSON compatibility:** decode a state written by Android (the test's own JSON strings plus one with unknown keys).
5. **Theme colors:** Compose's Oklab `lerp` ported and checked against values computed by Android (any machine with a JDK
   can run one unit test that prints the six derived palettes into a fixture). Until then the extra themes stay out.

## Plan and estimate

Each step is one branch/PR, behind the Boarverse switch (off by default) so main never shows half of it.

1. **Engine + tests** (steps 1–4 above): ~2 h. No UI. *(Tonight's item 5, if time allows.)*
2. **Counting**: `TruffleVault` service in `BoarServices`, `onOpen` at launch and on foreground, `answered` after each
   answer, and the ~12 one-line `record { }` calls (theme, tweaks, documents, export, eval run/share, HF model, voice,
   quiz). ~3 h, plus a debug `-uiVault <state>` to seed states for captures and the XCUITest. The engine's `fresh`
   includes `tactical`; like Android (`TruffleVault.kt`), the service drops `ALWAYS` avatars before announcing.
3. **Art import**: extend `import-icon-pack.py` (or a new `import-truffles.py`) for 40 avatar imagesets from the hi-res
   webp (HEIC/PNG), and the silhouettes. ~1 h. Adds ~2–3 MB.
4. **UI**: Boarverse switch, grid, avatar picker, toast, equipped boar in `Mascot` (chat header, empty chat, answers,
   sidebar). Captures EN/PT, light/dark, iPhone 13 and 17; XCUITest for switch → grid → equip. ~4 h.
5. **Extra themes**: Oklab lerp, the six derived palettes + Paper, `ThemeChoice` listing them only while Boarverse is on
   and the avatar/grant is there. Needs that fixture first. ~2 h.
6. **Launcher icons** (flag off, like Android): 40 alternate icon sets, build setting, `setAlternateIconName`. ~2 h, and
   checked on the iPhone.

About **two nights** of work in total, plus Biel's two decisions (airplane mode, de-Googled; both made 2026-11-11) before step 2 and the theme
fixture before step 5.

## Step 2 as built (counting, 2026-11-11)

`App/Sources/Services/TruffleVault.swift` (main actor, `@Observable`, owned by `BoarServices`) stores
`Vault.toJson(state)` under `truffleVault` as a JSON object (`AppSettings.truffleVault`, Android's shape). `record`
applies `Vault.apply` with today and now in ms, saves only on a change, and queues new avatars for the message while
Boarverse is on, dropping `ALWAYS` (Android line 59). Boarverse is stored in the app's defaults as
`vault.experimental.on` (Android: prefs "vault", `experimental.on`), off, with no switch yet. The fact updates are pure
(`Vault.Counting` in BoarCore, tested in `VaultCountingTests`); the network, clock, lock, files and App Store are read in
the app. DEBUG `-uiVault <json>` stores a state before the vault opens (`DebugLaunch`).

| iOS | Android |
|---|---|
| `AppModel.checkVault` (launch, `didBecomeActive`, leaving Models) → `onOpen` | `BoarServices.checkVault`, `MainActivity` start and leaving "models" |
| `AppLock.enable` → `pinOn` | `MainActivity` PIN setup `onDone` → `checkVault` |
| `ChatController.answer` after the answer is saved → `answered` | `ChatViewModel` after `upsertMessage` |
| `AppModel.setTheme` (Settings → Display and the tour's theme card) → `themeChanged` | `SettingsScreen` (2 places), `MainActivity` tour |
| `EngineTweaksScreen.save`, non-Auto → `tweaksChanged` | `SettingsScreen` TweaksSection `save` |
| `DocumentsController.run` after an import → `documents += files` | `DocumentsViewModel.import` |
| `DocumentsController.exportFile` → `exports += 1` | `DocumentsViewModel.exportIntent` |
| `EvaluationController.start`, a screen run that wasn't stopped → `evalRuns += 1` | `EvaluationViewModel.run` |
| `ModelsController.hfAdd` → `hfModels = max(…, discovered)` | `ModelsViewModel.hfAdd` |
| `VoiceInputController` (dictation that heard words) → `voice` | `VoiceInput.onResults` |
| `DailyQuizLab` pick → `quizRight`, `quizDays` (the quiz's day) | `DailyQuizLab` (labs plugin) |

Offline answers: no satisfied path, what the ONLINE badge shows. Night: `Vault.isNight(hour:)` with the local hour.
A no-network day: the path status at open is `.unsatisfied` (at launch it waits up to 2 s for the monitor's first report).

Differences and what's left out, on purpose:

- **`evalShares` is never counted:** Android uploads a run to BOAR's results service (`ResultsSharing`) and counts a
  successful upload; iOS only exports files through the share sheet, which is not that. `EVAL_SHARED` has no avatar.
- **Setup's file import** (`SetupViewModel`, documents): iOS setup has no files page; documents come only from Knowledge.
- **Bench requests** (debug builds' `Documents/eval/requests`) don't count evaluation runs, as Android's `BenchActivity`
  doesn't. Its `grantTheme` waits for the extra themes (step 5).
- **Also on return to the foreground:** iOS checks the vault whenever BOAR becomes active, Android only at start and
  after Models or PIN setup. It saves only on a change, so a return the same day writes nothing.
- **Exports** count when the share sheet asks for the file (iOS makes it lazily), not when the sheet opens.
- **Dictation** counts when words were heard, also when sending cuts the dictation short (Android's recognizer ends by
  itself and reports `onResults`).
- The Daily Quiz's "Right answers unlock Boar Avatars." copy, the clues, `equip`, the launcher icon and the toast come
  with the UI (step 4).

## Questions for Android

- `CHATS_100`, `EVAL_SHARED` and `EXPORT` have no avatar; port them anyway (cheap) so the rule table stays identical.
- The unicorn needs `stealth` and `hacker`, which most Android users never get (not de-Googled, not built from source):
  the legendary is effectively for builders only. Fine on Android; on iOS, `stealth` decides whether anyone can get it.
