# Privacy policy: what changes for iPhone and Mac (draft)

> **Draft for review, not a policy.** BOAR has one privacy policy, `PRIVACY.md` in `rferrari/boar-app`
> (version 0.9.1, 20 October 2026). It says it will cover the iPhone version before one is released. This file lists
> what that policy has to say differently or add for the iOS and Mac apps, checked against this repo's code on
> 2026-11-06, so the policy's owners can merge it there. The App Store also needs the policy's public URL.

## Already true on iOS, same words as Android

- No account, no advertising, no analytics or crash reporting. `App/Resources/PrivacyInfo.xcprivacy` declares no
  tracking and no collected data.
- Questions, answers, conversations, documents, the knowledge base and settings stay on the device (section 1),
  except what goes to a server the user sets up (item 7 below).
- The internet is used only when the user starts it: model and pack downloads from Hugging Face or GitHub, and
  Hugging Face search (sections 2.1, 2.2). iOS adds two: Apple's speech model download (item 3) and the user's own
  server (item 7).
- **Share results** is not in the iOS app: `Sources/BoarAnswer/Eval/ShareResults.swift` is ported, but no screen
  calls it and the app has no Supabase settings. Section 2.3 applies as "current iOS builds don't include it".
- No location permission.

## Different on iOS: the policy needs these words

1. **Scope (intro).** "BOAR for iPhone and iPad (iOS 18 or later) and BOAR for Mac (macOS 26 or later)", next to the
   Android app.
2. **Deleting data (section 1).** The button is **Erase All Data**, at the end of Settings
   (`SettingsRecoverySection.swift`): models, knowledge packs, documents, chats and settings, including the network
   server's address and API key, and setup starts over. It also removes BOAR's items from Spotlight (`DataPurge.swift`).
   Uninstalling deletes the app's files and settings, but **not the network server's API key**: iOS keeps Keychain
   items after an app is deleted (`RemoteConfig.swift`, service `team.sopa.boar.remote`). Erase All Data before
   uninstalling removes it.
3. **Voice input (section 2.4).** iOS uses Apple's on-device speech recognition (SpeechAnalyzer, iOS 26 or later).
   It asks for the microphone permission. The first time, iOS downloads its English speech model from Apple
   (`AssetInventory`); after that, recognition runs on the device and the audio isn't sent anywhere. Before iOS 26
   there is no microphone button.
4. **Apple Intelligence (new).** On devices with Apple Intelligence, the user can pick Apple's built-in model. It
   runs on the device through Apple's Foundation Models framework, and BOAR sends nothing to Apple. Apple's own
   terms for Apple Intelligence apply.
5. **Spotlight and Siri (new).** Each chat's title and its summary are added to the device's Spotlight index so
   system search can find them (`AskBoarIntent.swift`, `SessionSpotlightIndexer`). The summary is written by BOAR
   from the chat's questions and answers. They stay on the device, and they are removed when a lock is turned on and when the user erases the data
   (`AppModel.reloadSessions`). "Ask BOAR" works through Siri and Shortcuts (App
   Intents). When the user speaks to Siri, Apple's Siri processing applies before the question reaches BOAR.
6. **Photos (new).** Photos of pages are picked with the system photo picker (`PhotosPicker`), which gives BOAR only
   the photos the user selects, without library access: the app declares no photo library permission or
   entitlement. The text in them is read on the device (Vision).
7. **Another computer (new, iOS and Mac).** In Settings → Advanced, the user can point BOAR at a llama.cpp server,
   meant for a computer on their own network (for example a Mac mini). When that is on, **the whole prompt is sent to
   that server** to write the answer: the question, the passages BOAR found, the chat's summary and its recent
   questions and answers, and the Personal Files note (`RagPure.assemblePrompt`). The library, documents and stored
   chats stay on the device. The address can be `http://` only for a local network host (`NSAllowsLocalNetworking`);
   that traffic is not encrypted. It can also be an `https://` server anywhere on the internet
   (`RemoteServer.parse`), which then receives the same prompt. An optional API key is sent with each request. It asks
   for the local network permission. It is off until the user sets it up.
8. **Lock (section 9).** iOS uses Face ID or the device passcode (LocalAuthentication). With the lock on, chats are
   sealed with AES-256-GCM in the same format as Android (`Sources/BoarModels/TextCipher.swift`), and their titles
   leave Spotlight.
9. **Backup (section 9).** On iPhone and iPad, as on Android, the chats, imported documents, knowledge base, models
   and packs are kept out of iCloud and computer backups (`AppPaths.swift`, the whole BOAR folder; evaluation runs in
   `EvalRunner`). Decided on 2026-11-06. **On the Mac**, chats and documents stay in Time Machine, the user's own
   backup, so a failed disk doesn't lose them; only the downloads (models, packs, partial files) and the evaluation
   runs are excluded. With the lock on, the chats in that copy are sealed with a key kept in this Mac's Keychain only,
   so that copy can't be opened on another Mac (nor, likely, after the disk is replaced). **Not yet excluded: the settings** (theme, model choice, Labs state and the network
   server's address), which live in the app's standard preferences file and still go into backups; the server's
   API key does not (Keychain, this device only).

## Terms of Use

`TERMS.md` (0.9.1) is platform-neutral. Two points for the App Store:

- The note that "current Android builds don't include result sharing" should say the same for iOS and Mac.
- App Store apps use Apple's standard license agreement (EULA) unless the developer gives App Store Connect a custom
  one, which then has to include Apple's minimum terms. Using Apple's standard EULA next to BOAR's terms is the
  simpler choice; the project decides.

## Not covered here

The website, legal bases, processors, retention, rights, children and contact (sections 3 to 8 and 10 to 11) don't
change for iOS while **Share results** stays out of the app.
