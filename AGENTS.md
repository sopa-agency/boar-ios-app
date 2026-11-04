# boar-ios — native iOS BOAR

TL;DR: SwiftUI app + a Swift port of the android-native Kotlin engine. The Android app is the product and leads; iOS follows it in behaviour, screens and look. The golden fixtures in `Fixtures/golden/` are the parity contract. Apple AI frameworks plug in behind one model seam in `BoarCore`. iOS first; the Mac target comes after the iPhone app is on the App Store.

## Who and where (since 2026-11-04)

- **Owner: Biel** (GitHub `Bielcx`, push; the org account `sopacrew` is admin). r4to (r4topunk) left the project; the rules that named him are gone.
- **Plan and progress:** https://claude.ai/artifact/PxWTkJ3v9zvvY4mNBu6UxN (phases 0–5, one status per step). The page keeps status in its db: collection `status`, doc id = the step id in the page source, body `{s: "todo"|"doing"|"done", at: <ISO date>}`. When a step changes, read the collection, then write it with the `ArtifactData` tool.
- **Android reference:** `rferrari/boar-app`, branch **`main`** (android-native was merged into main; 2.0.0-rc2 on 2026-10-25). Local clone at `../boar-app` with remote `upstream`; Biel can't push there. Run `git -C ../boar-app fetch upstream` before reading it.
- **Where the code lives (since 2026-11-04):** `~/Dev/boar-ios-app` on cx is a real git clone (gh logged in as Bielcx) and the main working copy: the **Boar iOS agent** (OpenClaw, Biel's Telegram topic "Boar IOS") edits, builds and commits there. The Windows PC checkout (`~/Dev/boar-ios-app`) is secondary, for browser work and review; Swift doesn't build on Windows. The two meet through GitHub: push from one, pull on the other, never edit both on the same branch at once.
- **Build host: Mac mini `cx`** (M4, 16 GB, macOS 26.7.1), account `bielcx`, Biel's private account (the team's `eve` account must not see work in progress). SSH by key, home LAN only: `ssh -i ~/.ssh/id_ed25519_cx bielcx@10.0.10.226`. It also runs Biel's OpenClaw gateway (LaunchDaemon `ai.openclaw.gateway`): never stop it, and watch RAM.
- **The loop:** on cx, work in the clone directly. From the PC, `bash scripts/cx.sh '<command>'` runs a command in the cx clone (Homebrew on PATH, `DEVELOPER_DIR` = Xcode 27); it no longer copies files once cx has a git clone, so push first and `git pull` there. Build products, `Vendor/llama.xcframework`, `.build/` and `Local.xcconfig` live only on cx.
- **cx setup status (2026-11-04):** Xcode 27.2 (27B52) active via `xcode-select`, xcodegen 2.46, iOS 27.2 simulator runtime, llama.cpp b11010 fetched; `swift test` green and both targets build. Signing: Biel's free Personal Team `5725USZX2C` in cx's git-ignored `Local.xcconfig`; the Apple Development identity also sits in `boar-build.keychain-db` (password in `~/.config/boar/build-keychain.pw`, made once by `scripts/build-keychain.sh`), first in the search list, so `bash scripts/cx.sh 'bash scripts/device.sh'` builds, signs and installs on his iPhone over SSH with no prompt. `team.sopa.boar.native` belongs to another team, so device builds use `PRODUCT_BUNDLE_IDENTIFIER=team.sopa.boar.biel` until phase 0 picks the final id. The free profile lasts 7 days: renew it with one `-allowProvisioningUpdates` build from an unlocked session. The release llama.xcframework has no simulator slice: `bash scripts/cx.sh 'bash scripts/build-llama-xcframework.sh'` builds it on cx and merges it into `Vendor/` (done 2026-11-04; rerun if `Vendor/` is wiped); the app runs on the iPhone 17 simulator (iOS 27.2). The engine tests read the Android seed assets from `~/Dev/boar-app/assets/{corpus,lexicon}`: on cx that is a real clone of `rferrari/boar-app` (remote `upstream`, since 2026-11-04), so `git -C ~/Dev/boar-app pull` keeps them current. `sudo` and the login keychain need Biel's password: he runs those from his own terminal with `ssh -t`, or on cx's screen.
- Git: line endings are LF (`core.autocrlf false` in this clone; keep it). Commit in small steps, then stop and wait for Biel's OK; open a PR only when he asks.

```bash
bash scripts/cx.sh 'bash scripts/fetch-llama.sh && swift test --scratch-path .build/cx'
bash scripts/cx.sh 'xcodegen generate && xcodebuild -project Boar.xcodeproj -scheme Boar -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/DerivedData build'
```

## Build commands (run on cx)

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.2.0.app/Contents/Developer   # always build with Xcode 27 (iOS 27 SDK)
bash scripts/fetch-llama.sh                                              # pinned llama.cpp b11010 XCFramework → Vendor/
swift test --scratch-path .build/<your-name> --filter <Target>Tests      # engine tests on the Mac host
xcodegen generate && xcodebuild -project Boar.xcodeproj -scheme Boar -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/DerivedData build
xcodebuild -project Boar.xcodeproj -scheme BoarMac -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build   # native Mac app (ad-hoc signed, sandboxed)
```

## Layout

| Path | What | Kotlin reference (`.ref/android-native/`) |
|---|---|---|
| `Sources/BoarCore` | shared types, SQLite wrapper (system `SQLite3`), settings, tweaks, units, logging, **the model seam** | `engine/.../engine/{Engine,EngineTweaks,TweakPresets,CpuTopology,CpuVariants}.kt`, `db/`, `settings/` |
| `Sources/BoarRouting` | router, classifier, calculators, profiles, small talk, emergency numbers | `routing/` |
| `Sources/BoarRAG` | retrieval, packs, wiki pack (zstd), compression, document import, seed corpus | `rag/` |
| `Sources/BoarModels` | catalog, asset store, HF query, load guard, setup model, storage budget, text cipher | `models/`, `security/` |
| `Sources/BoarAnswer` | answer pipeline, deep research, follow-up, plan executor, chat store, suggestions, device eval, share results | `answer/`, `chat/`, `eval/` |
| `Sources/BoarLlama` | llama.cpp session over the C API, conforms to the model seam | `Engine.kt`, `cpp/boar_jni.cpp` |
| `Sources/BoarAppleAI` | Apple on-device model (Foundation Models) and iOS 27 extras behind the same seam | — |
| `Sources/BoarRemote` | "Mac on Your Network": llama-server on another computer (OpenAI-compatible streaming) behind the same seam; only generation goes there, search and chats stay on the device | — |
| `App/` | SwiftUI app (XcodeGen `project.yml`): one source tree, two targets, `Boar` (iOS/iPadOS) and `BoarMac` (native macOS, `App/Mac/` holds its plist and entitlements) | `app/src/main/java/.../` |
| `Fixtures/golden/` | golden fixtures copied from android-native at `Fixtures/SOURCE_SHA` | `engine/src/test/` |

`.ref/` is a read-only copy of the Kotlin source (refresh with `scripts/sync-reference.sh`). Never edit it.

## Rules

- **Android leads.** Every Android change on `upstream/main` is either ported or skipped with a written reason. Weekly: `scripts/sync-reference.sh` (now defaults to `upstream/main`), list the android-native commits since `Fixtures/SOURCE_SHA`, port them. On 2026-11-04 the fixtures moved from `f174f35c` (2026-10-15) to `6c52c623` (2.0.0-rc2, 2026-10-25) and every golden suite passes; the engine ports so far are routing, Personal Files retrieval, answer styles and Deep Research's follow-ups. Still open from that range: the app side of Personal Files, Boar Labs, the icon pack and themes, setup's tour, PIN erase, memory release, and the rest of the UI. Some were ported before the hand-over, so compare behaviour, not commit counts.
- **Parity first.** Port behaviour exactly, including string handling, regex semantics, rounding and ordering. Each Kotlin golden test gets a Swift Testing counterpart that reads the same fixture. A failing golden is a bug in the port, never a reason to edit the fixture.
- Tests find fixtures relative to `#filePath` (repo root → `Fixtures/golden`), no SwiftPM resources.
- The engine (`Sources/*`) never imports SwiftUI or UIKit and never imports from `App/`.
- Swift 6 language mode, strict concurrency. Async/await; token streams are `AsyncThrowingStream`; mutable shared state lives in actors. No Combine, no completion handlers in new code.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Logging: `os.Logger(subsystem: "team.sopa.boar", category: <module>)`, no `print`.
- Deployment target iOS 18.0 (2026-10-19, for testers on iOS 18; the Mac target stays 26.0). iOS 26 APIs (Liquid Glass, Foundation Models, SpeechAnalyzer, RecognizeDocumentsRequest, navigationSubtitle, safeAreaBar, close-role buttons) go behind `#available(iOS 26.0, *)` or the shims in `App/Sources/Platform/PlatformModifiers.swift` (`glassOrMaterial`, `prominentGlassButtonStyle`, `bottomBar`, `navigationSubtitleIfAvailable`, `SheetCloseButton`); dictation goes through `Dictation` (unsupported before 26). iOS 27 APIs (Core AI, Spotlight search tool, image prompts, the Foundation Models `LanguageModel` protocol) go behind `if #available(iOS 27, macOS 27, *)`.
- Dependencies: llama.cpp XCFramework and zstd only. No third-party UI or utility packages.

## App conventions (Apple patterns)

**Android's look, Apple's pieces** (Biel, 2026-11-04; replaces r4to's "stock Apple UI, no brand"). Someone holding both phones sees the same app; an iPhone user still gets iPhone behaviour.

- **Same as Android:** screens and their order, flows, copy (EN and PT), the Boar icon pack, the mascot where Android shows it, the themes and their tokens (`ui/theme/ThemeTokens.kt`, `Theme.kt`, `ExtraThemes.kt` in `.ref/android-native/app/...`), the BOAR fonts (`res/font`), accents and glyphs. Compare each screen with an Android capture side by side before calling it done.
- **Apple's pieces:** navigation and back gestures, sheets, lists and forms, keyboard and text input, menus, the share sheet, file and photo pickers, Face ID, haptics, Dynamic Type, VoiceOver, and Liquid Glass where the system applies it. Never draw Android chrome (Material top bars, FABs, snackbars, ripples) on iOS.
- Theme tokens live in one place (asset catalog colors or a `Theme` type) and are used by name; no literal colors in views. Light and dark both work.
- Where Android has no icon, use an SF Symbol at the same weight.

- SwiftUI + Observation: `@Observable` models injected with `.environment`, `@State` for view-owned state, `@Bindable` for bindings. No `ObservableObject`.
- Navigation: `NavigationSplitView` (sessions sidebar → chat), `NavigationStack` inside; sheets for setup/settings flows; `Form` for settings; `ContentUnavailableView` for empty states; `ShareLink`; `.fileImporter` and `PhotosPicker` for documents.
- Standard system components so Liquid Glass applies; no custom navigation chrome. SF Symbols, Dynamic Type, VoiceOver labels, light and dark.
- Strings in a String Catalog (`Localizable.xcstrings`), English source, **Portuguese required**: the build is English only today; Android's PT is in `res/values-pt/strings*.xml`. The language follows the system.
- Security: PIN lock becomes LocalAuthentication (Face ID / passcode); secrets in the Keychain; CryptoKit for the text cipher.
- Downloads: background `URLSession`; models live in Application Support, excluded from backup.
- Voice: SpeechAnalyzer / SpeechTranscriber on device. OCR: Vision document recognition. Siri: App Intents + App Shortcuts ("Ask BOAR").
- Bundle id `team.sopa.boar.native` for now (it coexisted with the old Expo build). The final id is a phase-0 decision and can't change after the first App Store Connect upload. The signing team comes from the git-ignored `Local.xcconfig` (r4to's copy didn't come with the repo; Biel's is made in phase 1).

## Mac app

- `BoarMac` builds the same `App/` sources natively for macOS 26. iOS-only SwiftUI and UIKit calls go through `App/Sources/Platform/` (`.inlineNavigationTitle()`, `.groupedListStyle()`, `.drillDownPickerStyle()`, `.compactSectionSpacing()`, `.alwaysVisible`, `.leadingBar`, `Color.baseBackground`, `Platform.copy`, `Platform.keepAwake`, `Platform.deviceNoun`); new screens use those instead of the iOS-only API so both targets keep compiling. Copy says "this \(Platform.deviceNoun)", never "this iPhone".
- Mac layout patterns (HIG: use the large window, fewer nested levels, less modality): one main `Window` (Window → BOAR, ⌘0) plus a `Settings` scene (⌘,: General / Privacy / Advanced / Storage / Engine tabs, no navigation pushes inside it) and an About window from the app menu. Menu commands live in `App/Sources/Platform/BoarCommands.swift` (New Chat ⌘N, Import Documents ⌘⇧I, Find Chats ⌘F, Chat menu: Stop ⌘., Answer Style, Deep Research ⇧⌘R, Rename, Delete ⌘⌫; View: Chat/Documents/Models ⌘1–3); they reach views through `AppModel.sidebarRequest` / `importRequest` / `citationRequest`.
- Library screens are list + details side by side (`MasterDetail`, Mac only): Models, Documents, Hugging Face. Sources open in the chat's trailing `.inspector`, not a sheet. Screens of sections use `GroupedList` (grouped form on the Mac) and `.readableWidth()`; any sheet gets `.macSheetSize()`, or a List in it collapses to nothing.
- Selectable answer text hands citation links (`boar-source://<n>/<answer id>`) to the system on the Mac: the Mac target registers the scheme and `onOpenURL` routes it back to the inspector. Keep `.textSelection` on the answers.
- Sandboxed (network client, user-selected files, microphone, photos); data lives in `~/Library/Containers/team.sopa.boar.native`. A DEBUG `-uiDemo` run keeps its files in `Application Support/BOAR-demo` and its settings in the `team.sopa.boar.native.demo` defaults suite, so it never touches the real models, chats or preferences; still never run it unsandboxed. DEBUG `-uiImport <file>` imports a file on launch (tests the import path without the system file panel).
- llama.cpp uses Metal on the Mac by default (`BOAR_METAL=0` turns it off).
- UI capture without stealing focus: `scripts/mac-capture.sh <out> chat,models [light|dark]` (launches a second, demo instance in the background with `-uiDemo -uiScreen … -uiSnapshot 7 -uiAppearance <mode>` at 1240×800, or `EXTRA="-uiSize 1040x600"`), captures only its window with `screencapture -l`, and quits only demo instances). The Settings and About windows are separate scenes: capture them live.

## Mac on Your Network (remote engine)

- Settings → Advanced → Engine → "Mac on Your Network": an address (`mac-mini.local:8080`) and an optional API key (Keychain). Retrieval, the library and chats stay on the device; generation streams from llama-server.
- On the serving Mac: `scripts/serve-remote.sh <model.gguf> [port] [api-key]` (binds 0.0.0.0, `--jinja`). cx can serve it on the LAN for tests: always set an API key, and stop it afterwards (RAM is shared with OpenClaw).
- Tests: `swift test --filter BoarRemoteTests` (pure); `BOAR_REMOTE_URL=http://127.0.0.1:8199 swift test --filter RemoteSmokeTests` against a real server. DEBUG launch arg `-uiRemote <address>` selects the engine and checks the connection on launch.

## Devices

- Test iPhone: Biel's iPhone 14 Pro (6 GB, iOS 18.5, UDID `00008120-000609021463C01E`, the `device.sh` default), paired with cx on 2026-11-04. r4to tested on an iPhone 13 with 4 GB RAM; 4 GB phones stay the target to protect (llama.cpp path with the 1.5B model, no Apple Intelligence).
- Pair the iPhone with cx over USB once; after that `xcrun devicectl` installs over the home Wi-Fi. cx has no screen: a dummy HDMI plug makes Screen Sharing usable when Instruments or an Xcode dialog needs a display.
- Simulator: install an iOS 26.x runtime on cx; the app runs there: `xcodebuild ... -destination 'platform=iOS Simulator,id=<udid>'`, then `xcrun simctl install/launch`. Core AI and Vision's `OCRTool` overlay are not in the Simulator SDK, so that code sits behind `#if canImport(CoreAI)` / `#if !targetEnvironment(simulator)`. Models for a simulator run: APFS-clone (`cp -c`) the GGUFs from `~/shared-models` on cx (empty for now; r4to's copy didn't come with the repo) into the app container's `Library/Application Support/BOAR/models/` under the catalog filenames.
- **Performance:** measure Release builds on the cabled iPhone with `scripts/perf.sh` (docs/PERF.md). llama.cpp runs on the CPU on iPhone/iPad: runtime Metal shader compilation thrashed the 4 GB iPhone 13 (`BOAR_METAL=1` to experiment). Build, sign and install from cx.
- cx disk: ~94 GB free before Xcode. One shared DerivedData under `.build/`; delete stale scratch paths when done.
