# App Store listing and App Store Connect answers (draft)

> **Draft for review.** Everything App Store Connect will ask for BOAR on iPhone, iPad and Mac, prepared before the
> paid Apple account exists (phase 3), so the submission is copy and paste on launch day. Checked against this repo's
> code on 2026-11-11. English first; the Portuguese listing waits (PT is backlog). No brand book or claims playbook is
> published for BOAR yet: the copy only repeats what the README already claims and can be measured.

## App information

- **Name** (30 characters max): `BOAR: Offline AI` (16). "BOAR" alone is likely taken or too short to be found.
- **Subtitle** (30 max): `Answers with no signal` (22). Alternative: `Private AI with its sources` (27).
- **Bundle ID:** not final (phase 0: `team.sopa.boar.native` today, `team.sopa.boar` recommended). It can't change
  after the first upload.
- **Primary category:** Reference (matches `LSApplicationCategoryType` in `project.yml`). **Secondary:** Productivity.
- **Platforms:** iPhone and iPad (`TARGETED_DEVICE_FAMILY` 1,2, iOS 18 or later) and Mac (macOS 26 or later) as one
  universal purchase if the Mac app ships with the same bundle ID (phase 5 decides).
- **Price:** free, no in-app purchases.
- **Privacy policy URL:** needed before submitting. BOAR's policy is `PRIVACY.md` in `rferrari/boar-app`, which doesn't
  cover iOS yet (`docs/legal/PRIVACY-ios.md` lists what it must add). Apple wants a public web page, not a GitHub file
  view: a page on boarapp.com once the policy covers iOS.
- **Support URL:** required. `https://github.com/sopa-agency/boar-ios-app/issues` works; a boarapp.com page is better.

## App Privacy (the "nutrition label")

Answer: **Data Not Collected.** Apple counts data as collected when it leaves the device and the developer or a
partner can keep it. BOAR sends nothing to SOPA or anyone else on its own:

- No account, no analytics, no crash reporting, no ads (`PrivacyInfo.xcprivacy` declares no tracking and no collected
  data).
- Downloads (models and packs from Hugging Face or GitHub) only fetch files. The Hugging Face model search sends the
  words typed in it to Hugging Face, which BOAR doesn't keep or link to anyone: still not collection by the developer.
- **Mac on Your Network** (Settings → Advanced → Engine) sends the whole prompt to a server the user sets up. That server is the
  user's, not the developer's or a partner's, so it isn't collection; say so in the review notes.
- Voice input and Apple Intelligence run on the device.

Revisit this answer if anything starts sending data: Android's evaluation upload (`ShareResults.swift`, ported but
unused on iOS; the Benchmark's "Share Results" menu only exports a file through the share sheet), crash reporting, or
any analytics.

## Age rating

Expected **4+** (Apple's questionnaire, all "None"/"No"), except two answers to check against Apple's form on the day:

- The new AI questions (generated content / chatbot): answer that BOAR is a general-purpose assistant whose answers
  come from a small on-device model, and that it can be wrong. If the form asks for unrestricted generation of
  mature content, the honest answer is that an open model can produce anything a user asks for: this may push the
  rating to 13+ or higher (Apple's ages since 2025: 4+, 9+, 13+, 16+, 18+). Decide with the team; Android's Play rating is the reference.
- Unrestricted web access: **No** (no browser; Hugging Face search lists model files only).

## Export compliance

`ITSAppUsesNonExemptEncryption = false` in `project.yml` for both apps: BOAR uses only Apple's encryption (CryptoKit's
AES-GCM for locked chats, HTTPS for downloads), which Apple treats as exempt. Nothing to upload.

## Listing copy

**Promotional text** (170 max, can change without a new version):

> Airplane mode on, BOAR still answers. A small AI and a library on your phone: no account, no server, and every
> answer shows the articles it came from.

**Description** (4,000 max):

> BOAR is a small AI and a library that live on your iPhone. Download a model and the knowledge you want once; after
> that, it answers in a tunnel, on a flight or in a mountain hut, with no signal at all.
>
> ANSWERS YOU CAN CHECK
> Small models make mistakes, so BOAR answers from a library and lists the articles it used. Tap a citation to read
> the exact passage.
>
> NOTHING LEAVES YOUR PHONE
> No account, no analytics, no tracking. Your questions are answered on the device, unless you choose to have your own
> Mac write the answers. Lock your chats with Face ID.
>
> YOUR OWN LIBRARY
> Import your own documents and photos of pages, and ask about them. Pick the answer style you like, from short and
> direct to thorough.
>
> MEASURED, NOT HYPED
> Every answer keeps a receipt: the model, the time to the first word and the speed.
>
> MORE
> • Choose another model, or find one on Hugging Face.
> • Boar Labs: optional experiments such as a calculator and Boar Press, which turns answers into a PDF.
> • Siri and Shortcuts: "Ask BOAR".
> • Light and dark themes.
>
> The library is made of Wikipedia articles (CC BY-SA 4.0). BOAR is open source (MIT).

Before submitting, check every feature named above is in the build being sent (Labs list, Siri, photo import), and
replace nothing with a number that wasn't measured on a device.

**Keywords** (100 max, commas, no spaces after them, no app names or trademarks):

`offline,ai,private,local,assistant,chat,no internet,airplane,library,encyclopedia,sources,llm` (93)

**What's New:** App Store Connect doesn't ask for it on the first version.

## Review notes (App Review Information)

- No sign-in: the app has no account.
- First launch: setup downloads a language model and a knowledge pack (hundreds of MB to a few GB, chosen by the
  user). This is data the app reads, not code: llama.cpp runs the model, nothing is executed from the download
  (guideline 2.5.2).
- After setup, turn on airplane mode: chat, search and sources keep working.
- Settings → Advanced → Engine → Mac on Your Network is off by default and only talks to a server the user enters.
- A short screen recording of setup and an offline answer goes with the submission (phase 4).

## Screenshots

Required sets (Apple scales the rest down):

- iPhone 6.9" (1320 × 2868 portrait), up to 10.
- iPad 13" (2064 × 2752 portrait), since the app runs on iPad.
- Mac (2880 × 1800 or 1440 × 900) if the Mac app is submitted.

Proposed six, from `scripts/ui-capture.sh` in demo mode, light and dark: setup ("Knowledge that travels with you"),
an answer with its sources, a source opened, the library, an answer receipt, the app lock. Captions in the image are
optional; plain captures match the README. Captures need a real model's answer, not the demo's "No Answer Model".
