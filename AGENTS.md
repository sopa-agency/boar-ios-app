# boar-ios — native iOS BOAR

TL;DR: SwiftUI app + a Swift port of the android-native Kotlin engine. The Kotlin engine is the reference; the golden fixtures in `Fixtures/golden/` are the parity contract. Apple AI frameworks plug in behind one model seam in `BoarCore`.

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer   # always build with Xcode 27 (iOS 27 SDK)
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

- **Parity first.** Port behaviour exactly, including string handling, regex semantics, rounding and ordering. Each Kotlin golden test gets a Swift Testing counterpart that reads the same fixture. A failing golden is a bug in the port, never a reason to edit the fixture.
- Tests find fixtures relative to `#filePath` (repo root → `Fixtures/golden`), no SwiftPM resources.
- The engine (`Sources/*`) never imports SwiftUI or UIKit and never imports from `App/`.
- Swift 6 language mode, strict concurrency. Async/await; token streams are `AsyncThrowingStream`; mutable shared state lives in actors. No Combine, no completion handlers in new code.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Logging: `os.Logger(subsystem: "team.sopa.boar", category: <module>)`, no `print`.
- Deployment target iOS 18.0 (2026-10-19, for testers on iOS 18; the Mac target stays 26.0). iOS 26 APIs (Liquid Glass, Foundation Models, SpeechAnalyzer, RecognizeDocumentsRequest, navigationSubtitle, safeAreaBar, close-role buttons) go behind `#available(iOS 26.0, *)` or the shims in `App/Sources/Platform/PlatformModifiers.swift` (`glassOrMaterial`, `prominentGlassButtonStyle`, `bottomBar`, `navigationSubtitleIfAvailable`, `SheetCloseButton`); dictation goes through `Dictation` (unsupported before 26). iOS 27 APIs (Core AI, Spotlight search tool, image prompts, the Foundation Models `LanguageModel` protocol) go behind `if #available(iOS 27, macOS 27, *)`.
- Dependencies: llama.cpp XCFramework and zstd only. No third-party UI or utility packages.

## App conventions (Apple patterns)

**Stock Apple UI, no brand design system** (r4to, 2026-10-15): system font with semantic text styles, semantic system colors plus one AccentColor tint, standard List/Form/toolbar/sheet components. Never port the Android Campfire/Moonlight tokens, the Baloo 2/Lexend fonts, glows, gradients or hand-made cards and capsules. The mascot appears only in About and the app icon.

Any work in `App/` follows the `swiftui-pro` skill (Paul Hudson, MIT, installed in the workspace's `.claude/skills/swiftui-pro`), with our iOS 26.0 deployment target: its iOS 27-only advice goes behind `#available`.

- SwiftUI + Observation: `@Observable` models injected with `.environment`, `@State` for view-owned state, `@Bindable` for bindings. No `ObservableObject`.
- Navigation: `NavigationSplitView` (sessions sidebar → chat), `NavigationStack` inside; sheets for setup/settings flows; `Form` for settings; `ContentUnavailableView` for empty states; `ShareLink`; `.fileImporter` and `PhotosPicker` for documents.
- Standard system components so Liquid Glass applies; no custom navigation chrome. SF Symbols, Dynamic Type, VoiceOver labels, light and dark.
- Strings in a String Catalog (`Localizable.xcstrings`), English source.
- Security: PIN lock becomes LocalAuthentication (Face ID / passcode); secrets in the Keychain; CryptoKit for the text cipher.
- Downloads: background `URLSession`; models live in Application Support, excluded from backup.
- Voice: SpeechAnalyzer / SpeechTranscriber on device. OCR: Vision document recognition. Siri: App Intents + App Shortcuts ("Ask BOAR").
- Bundle id `team.sopa.boar.native` (coexists with the Expo build on the test iPhone). Signing team comes from the git-ignored `Local.xcconfig`.

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
- On the serving Mac: `scripts/serve-remote.sh <model.gguf> [port] [api-key]` (binds 0.0.0.0, `--jinja`). Do not start it on the research Mac mini without r4to's OK: it competes with the running arms.
- Tests: `swift test --filter BoarRemoteTests` (pure); `BOAR_REMOTE_URL=http://127.0.0.1:8199 swift test --filter RemoteSmokeTests` against a real server. DEBUG launch arg `-uiRemote <address>` selects the engine and checks the connection on launch.

## Devices

- Test iPhone: iPhone 13 (iPhone14,5), iOS 26.6, 4 GB RAM, no Apple Intelligence → llama.cpp path with the 1.5B model.
- No iOS 27 simulator runtime is installed, but the iOS 26.1 runtime is, and the app (deployment target 26.0) runs there: `xcodebuild ... -destination 'platform=iOS Simulator,id=<udid>'`, then `xcrun simctl install/launch`. Core AI and Vision's `OCRTool` overlay are not in the Simulator SDK, so that code sits behind `#if canImport(CoreAI)` / `#if !targetEnvironment(simulator)`. Models for a simulator run: APFS-clone (`cp -c`) the GGUFs from `../shared-models` into the app container's `Library/Application Support/BOAR/models/` under the catalog filenames.
- **Performance:** measure Release builds on the cabled iPhone with `scripts/perf.sh` (docs/PERF.md). llama.cpp runs on the CPU on iPhone/iPad: runtime Metal shader compilation thrashed the 4 GB iPhone 13 (`BOAR_METAL=1` to experiment). Build, sign and install on this MacBook; never on the Mac mini (it runs the research jobs).
- The MacBook has little free disk: one shared DerivedData under `.build/`, delete stale scratch paths when done.
