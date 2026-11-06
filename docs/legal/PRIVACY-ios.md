# Privacy policy: what changes for iPhone and Mac (draft)

> **Draft for review, not a policy.** BOAR has one privacy policy, `PRIVACY.md` in `rferrari/boar-app`
> (version 0.9.1, 20 October 2026). It says it will cover the iPhone version before one is released. This file lists
> what that policy has to say differently or add for the iOS and Mac apps, checked against this repo's code on
> 2026-11-06, so the policy's owners can merge it there. The App Store also needs the policy's public URL.

## Already true on iOS, same words as Android

- No account, no advertising, no analytics or crash reporting. `App/Resources/PrivacyInfo.xcprivacy` declares no
  tracking and no collected data.
- Questions, answers, conversations, documents, the knowledge base and settings stay on the device (section 1).
- The internet is used only when the user starts it: model and pack downloads from Hugging Face or GitHub, and
  Hugging Face search (sections 2.1, 2.2).
- **Share results** is not in the iOS app: `Sources/BoarAnswer/Eval/ShareResults.swift` is ported, but no screen
  calls it and the app has no Supabase settings. Section 2.3 applies as "current iOS builds don't include it".
- No location permission.

## Different on iOS: the policy needs these words

1. **Scope (intro).** "BOAR for iPhone and iPad (iOS 18 or later) and BOAR for Mac (macOS 26 or later)", next to the
   Android app.
2. **Deleting data (section 1).** The button is **Erase All Data**, at the end of Settings
   (`SettingsRecoverySection.swift`): models, knowledge packs, documents and chats, and setup starts over. It also
   removes BOAR's items from Spotlight (`DataPurge.swift`). Uninstalling deletes everything, as on Android.
3. **Voice input (section 2.4).** iOS uses Apple's on-device speech recognition (SpeechAnalyzer, iOS 26 or later).
   It asks for the microphone and speech recognition permissions. Before iOS 26 there is no microphone button.
4. **Apple Intelligence (new).** On devices with Apple Intelligence, the user can pick Apple's built-in model. It
   runs on the device through Apple's Foundation Models framework, and BOAR sends nothing to Apple. Apple's own
   terms for Apple Intelligence apply.
5. **Spotlight and Siri (new).** Chat titles are added to the device's Spotlight index so system search can find
   them. They stay on the device, and they are removed when a lock is turned on and when the user erases the data
   (`AppModel.reloadSessions`, `SessionSpotlightIndexer`). "Ask BOAR" works through Siri and Shortcuts (App
   Intents). When the user speaks to Siri, Apple's Siri processing applies before the question reaches BOAR.
6. **Photos (new).** Photos of pages are picked with the system photo picker (`PhotosPicker`), which gives BOAR only
   the photos the user selects, without library access. The text in them is read on the device (Vision).
7. **Another computer on your network (new, iOS and Mac).** In Settings → Advanced, the user can point BOAR at a
   llama.cpp server on their own network (for example a Mac mini). When that is on, **the prompt (the question and
   the passages BOAR found) is sent to that computer** to write the answer. The library and chats stay on the
   device. The connection is plain HTTP on the local network (`NSAllowsLocalNetworking`), with an optional API key.
   It asks for the local network permission. It is off until the user sets it up.
8. **Lock (section 9).** iOS uses Face ID or the device passcode (LocalAuthentication). With the lock on, chats are
   sealed with AES-256-GCM in the same format as Android (`Sources/BoarModels/TextCipher.swift`), and their titles
   leave Spotlight.
9. **Backup (section 9): differs today.** Android excludes BOAR's data from cloud backup and device transfer. On
   iOS only models, knowledge packs and partial downloads are excluded (`AppPaths.swift`). **The chats database,
   imported documents and settings are included in iCloud and computer backups.** Either the app excludes them
   too, to match Android, or the policy says so for iOS. This is a decision for the project, not for this draft.

## Terms of Use

`TERMS.md` (0.9.1) is platform-neutral. Two points for the App Store:

- The note that "current Android builds don't include result sharing" should say the same for iOS and Mac.
- App Store apps use Apple's standard license agreement (EULA) unless the developer gives App Store Connect a custom
  one, which then has to include Apple's minimum terms. Using Apple's standard EULA next to BOAR's terms is the
  simpler choice; the project decides.

## Not covered here

The website, legal bases, processors, retention, rights, children and contact (sections 3 to 8 and 10 to 11) don't
change for iOS while **Share results** stays out of the app.
