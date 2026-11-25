# Profiles, Settings and About on iOS (BOAR-52)

Android v2.0.0 leads. This is what the iOS port of its profiles, shorter Settings, About, Boar Avatars in Display & theme and
the removed Tour does differently, and what the Plugins work (BOAR-53) must finish.

## What is ported

- **Profiles** Starter (id `simple`), Explorer, Pro: `UserProfile`, `SettingsPart`, `LabDefaults` and `AppSettings.settleProfile`
  in `BoarCore`, with the Kotlin tests ported (`UserProfileTests`). Pro's settings read as their defaults below Pro and keep
  what is stored. An install from before profiles gets its profile once, from what it changed, and a one-time toast.
- **Settings** (`App/Features/Settings`): pills in the header (44 pt targets, selected trait), toasts for a pick (2.8 s), what
  pauses going down (4.5 s) and the update note (7 s); Models and Knowledge are only in the menu; Chats hold the summarize
  rows and Clear Chat History; Display & theme holds the Boar Avatar strip (`AvatarStrip`, last box "All ›"); Experimental
  holds adaptive routing, Boarverse, staged quotes, free memory (and after how long), technical details and the Boar Labs row;
  Start Over holds Run Setup Again, Reset and Erase; About is the last row. The embedding-missing warning is in the Models list.
- **About** as sections and rows, the hold-to-copy version block (`AboutReport`), credits with Amandita for the BOAR FAQ.
- **Tour removed**: the screens, strings, the debug hooks and its entry points; Setup's guide is the onboarding.
- Portuguese: Starter is "Iniciante"; Boar is never "Javali" (avatar names are "Boar ...").

## Deliberate differences

- **No language, text size or orientation setting**: iOS sets the language per app in the system Settings (the app follows it:
  English or Portuguese; Language & Voice carries a note saying so), Dynamic Type replaces the text size, and the app rotates
  with the system. `SettingsPart.language`, `.textSize` and `.orientation` stay in the table (and their tests) without a row.
- **No folding sections**: Settings is one list, so "back from a page keeps the scroll and the open sections" (7ab2fa6c) is what
  the navigation stack already does. There are no open sections to remember.
- **No unreadable settings file**: the iOS stores never report one, so Android's `loadFailed` / unsaved-profile case is not ported.
- **No Telemetry row**: iOS has no telemetry part; `SettingsPart.telemetry` is in the table only.
- **Haptics default to on** (Android: off), so on the Explorer check "changed" means off. The row shows from Explorer, on iPhone only.
- **Engine** (Downloaded model, Apple Intelligence, Mac on Your Network) and **Engine Tweaks / Benchmark / iPhone & Storage** are in
  Advanced, which is Pro's. The Mac's Settings window has the same split as tabs (Experimental, Advanced, Storage and Engine appear
  with their parts).
- **Confirm chat delete** ("Ask Before Deleting a Chat") stays in Chats: Android removed it on Nov 12 in a slice outside BOAR-52.
- **No Close BOAR or power icon in the menu**: an iOS app can't close itself.
- **About**: Android's Engine line is in the version block (llama.cpp build and CPU/Metal), and the AI-answers disclaimer stays
  as the footer of What BOAR is. The iOS source repository is no longer listed (Android v2.0.0's list is the five addresses).
  The bug report says `Device:` with the model and the system version (Android: model and Android API).
- **The longer note** of Experimental says "in Boar Labs" where Android says "in Plugins" and "Some start on".
- **Guide .md files** are not touched here: PR #61 carries the v2.0.0 guide text.

- **Screenshots come from the Mac build** (`shots/b52-*.png`, not committed): the llama.xcframework has no iOS simulator slice
  (`scripts/build-llama-xcframework.sh` needs 25 GiB free) and the build host has no display session, so `screencapture` fails.
  `-uiSnapshot` now also writes the window frame (toolbar included) as `ui-window.png` through `cacheDisplay`, and
  `-uiProfile <simple|explorer|pro>` / `-uiProfileNote YES` open Settings as a profile or with the update toast (DEBUG).
  Glass materials (the toast's background) don't render in that capture.

## What BOAR-53 finished (2026-11-24)

- Plugins everywhere: the Experimental note, the sidebar item, the setup guide's page and About say Plugins. The Experimental note is
  "Extra tools in the menu and under answers. Each one can be switched on or off. Some start on; switch on the others you want in Plugins.
  If one misbehaves, ..."; an "Open Plugins" link sits under it in every profile.
- Default-on list and toast: `LabDefaults.switchOf` with a stored tri-state; the update toast appends "These plugins are now on: ..." with
  `Labs.turnedOnByUpdate`.
- Pro's share is only the master switch and the storage limit in Experimental. The plugins list, the header icon and sheet and every plugin
  page and switch are in every profile, as at v2.0.0 (`LabDefaults.managementShown` is unused there). A plugin that is on keeps working.
- Cohazard asks before going off in every profile, from the list, its page and setup.
- About's "Plugins on" list is `Labs.shared.active`, which excludes deprecated plugins (Polyglot).
- Not done: "plugin settings pause below Pro" in the going-down toast: Android doesn't use it at v2.0.0 either.
