# BOAR Guide

## What BOAR is
BOAR is an AI research assistant that runs entirely on your phone. It answers from a library stored on the phone and lists the sources it used under the answer, so you can check them. Once it is set up, it works without internet, and your questions never leave the phone. BOAR is the app's name; the wild boar is only its mascot.

## Working offline
BOAR uses the internet only to download what it needs: during setup (the answer model, the search model and a knowledge pack), and later only if you choose to download another model or pack, or search Hugging Face for models. After that, everything runs on the phone, and airplane mode is fine. The ONLINE / OFFLINE pill next to "BOAR" at the top of the chat shows whether the phone has a connection; BOAR answers the same either way.

## Setting up BOAR
The first launch asks two things: your language (then Get started) and the answer model (one is recommended for your phone's memory). Tap Continue: when there is room, BOAR downloads the Encyclopedia knowledge package straight away. Only when space is short does it ask you to choose between Encyclopedia and Essential, and it says what the bigger one adds (about 164 MB, 50,000 more Wikipedia articles; the models are the same). While it downloads, a short guide walks you through: Make it yours, Your own files, How BOAR answers, How to ask, Your first question, a PIN, Notifications and Privacy and memory. Every page has Not now, and every choice can be changed later. If the downloads stop moving, tap Restart downloads; if the phone went offline, tap Try again once it is back. If you close BOAR before setup finishes, setup starts again from the first step with your choices kept, and the download continues where it stopped. When everything is in, tap Open BOAR. You can run setup again from Settings → Start over → Run setup again.

## Asking questions
Type a question at the bottom of the chat and tap send. Ask in English or Portuguese. Clear, specific questions work best: name the thing you mean ("How do I treat a minor burn?", "When was the Eiffel Tower built?"). An empty chat suggests Research Topics to try. While BOAR works, a line under the question says what it is doing (searching, reasoning, writing) and for how long. Tap stop to end the answer early; what was written and the sources found so far stay. Start a new chat with + at the top of the chat or New Research Session in the menu. Press and hold one of your own messages to put it back in the box.

## Answer styles
The style button left of where you type picks how BOAR answers (also in Settings → How BOAR answers, from the Explorer profile):
- Succinct & Direct: short replies.
- Thorough & Detailed: full explanations. This is the default.
- Local Files: answers only from your own files.
The style applies to the next questions until you change it. Health and seed-phrase questions always get a short answer, with a note under it, and greetings get a short reply. Settings → How BOAR answers also sets Max output tokens, the longest an answer can be; if an answer stops at that limit, it offers to allow more and redo it.

## Deep Research
Deep Research is for big questions. Turn it on with the 🔬 button at the top of the chat, in the style button's sheet, or in Settings → How BOAR answers (Deep Research Mode). BOAR splits the question into 2 or 3 smaller ones, searches the library for each, then writes one longer answer with sources. While it is on, the box says "Deep Research question…". It is slower than a normal answer, a few minutes on the smaller model. It works with Succinct & Direct and Thorough & Detailed; with Local Files, BOAR answers normally.

## Local Files
Local Files lets BOAR answer from your own documents: notes, PDFs and spreadsheets (.txt, .md, .csv, .json, and .pdf with selectable text; scanned and password-protected PDFs can't be read, and very large files are refused). In the menu, open Knowledge → Local Files and tap Pick Files & Import, or add files during setup. Files go into collections, each with its own switch: only switched-on collections are searched. Tap Ask about them, or pick the Local Files style, and ask: about one file by name, or for a summary of all your files. If your files don't hold the answer, BOAR says "I couldn't find this in your Local Files." instead of guessing. Your files stay on the phone.

## Knowledge packs
Knowledge packs are the libraries BOAR searches, stored on the phone. The Wikipedia Vital Articles pack holds more than 50,000 articles (about 164 MB). Manage them in the menu → Knowledge → BOAR Knowledge: see what is installed, Download or Remove a pack. A pack is downloaded once; after that it works offline.

## Sources under an answer
Under each answer that used the library, Retrieved sources lists them, numbered, with how well each one matched: articles from the library, or "Your documents" with Local Files. Tap a source to see the passage. "Read the whole article ›" opens the full article or file, offline, with the part BOAR used marked. Quick replies such as greetings and the plugins' instant answers have no sources. In the Pro profile, Settings → Advanced tweaks → Sources layout can put the sources above the answer instead: one row per article with the sentence that answers best, the question's words in bold; tap a row or a [n] in the answer to read the passage.

## Under an answer
Each finished answer shows how long it took and how fast it was written. Below it: ▲ and ▼ to rate it, ⧉ to copy it, 💭 to see the model's reasoning when it has some, and 🧩 for the actions of the plugins you have switched on. Under the latest answer, Keep going offers the next step: Continue after a Succinct answer (BOAR goes on from it), Research this after a Detailed one (the same question with Deep Research).

## Models
The answer model writes the answers. Setup recommends one for your phone's memory: Qwen3 4B (about 2.5 GB) on phones with 12 GB of memory, Qwen3 1.7B (about 1.1 GB) on smaller phones. On 12 GB phones, LFM2.5 8B is marked as the fast pick. Open Model Catalog in the menu: see what is installed, Select & Use another model, Download one, or Remove one you don't need. A colored badge shows how well each model fits the phone's memory. If BOAR's search model is missing, a warning at the top of the Model Catalog says so. Bigger models answer better but more slowly and need more memory. The name of the model answering shows under "BOAR" at the top of the chat.

## Finding more models
Discover GGUF models, in the Model Catalog and in setup, searches Hugging Face for more models. It needs internet only while it searches and downloads, and your search words go to Hugging Face. These models are not vetted by BOAR. Models that need a Hugging Face account can't be downloaded by BOAR. If a model may not fit the phone's memory, BOAR warns before loading it and offers Load anyway or Pick another model.

## PIN lock
A PIN (4 to 8 digits) locks BOAR and protects your chats. Set it in Settings → PIN lock (Set a PIN, Change PIN, Remove PIN), or during setup. With a PIN on, BOAR asks for it when you open the app and again after a minute in the background, your chats are stored encrypted with a key that only your PIN can open, and BOAR's screen is blank in recent apps, screenshots and screen recordings. After several wrong tries, BOAR makes you wait before trying again, longer each time.

## Forgot the PIN
If you forget your PIN, tap "Forgot the PIN?" on the PIN screen. Without the PIN, your chats can't be opened, not even by us, so BOAR offers to erase them, together with your Local Files and what the plugins made, and then removes the PIN. Tap Erase chats and files before the countdown ends to confirm; otherwise nothing is erased. Models and knowledge packs stay. If the erase can't finish, the PIN stays on so you can try again.

## Notifications
While BOAR writes an answer, it shows a "BOAR is answering…" notification; tap it to come back. Android asks your permission once, during setup or in the chat. Without it, answers still keep going when you switch apps; you just won't see that BOAR is working. Turn it on later with Allow notifications or in Android's settings for BOAR.

## Look and text size
Settings → Display & theme changes the theme and the text size (Compact, Standard, Large). From the Explorer profile it also has the screen rotation (Auto, Portrait, Landscape; Portrait by default) and Haptic feedback (off by default). Show speed while answering (off by default, every profile) shows the tokens per second at the top of the chat while BOAR writes. Moonlight (the default) and Campfire are always available; more themes open as you use BOAR with Boarverse on.

## Boarverse and Boar Avatars
Boarverse is an optional, playful layer, off by default: Settings → Experimental → Boarverse (from the Explorer profile). With it on, using BOAR unlocks Boar Avatars, characters you can use as BOAR's picture in the chat and the menu. Some avatars also bring new themes. When you unlock one, BOAR says "New avatar unlocked". See yours and pick one in Settings → Boar Avatars. Everything is counted on the phone and never leaves it. Turning Boarverse off brings back BOAR's own picture; your avatars stay waiting.

Answers come in steps (Staged answers, built in): the quotes from the sources first, then a short answer, the details and a check of the numbers. Stop when you have enough. In Pro, Settings → Advanced tweaks → Staged quotes turns it off.

## Plugins
Plugins is a set of experiments. In the Pro profile, open Plugins in the menu, or Settings → Experimental → Open Plugins: one row per plugin with what it does, its status and a switch to turn it on or off right there. Tap a plugin for its page and its own settings; Show as tiles shows them as a grid. The tested plugins start on (Vitals, Designer, Press, Calculator, Distance, Facts, Cohazard, Cards); the rest start off. A plugin that is on works in every profile. In every profile, each plugin's page has its own on/off switch at the top, and the plugin button at the top of the chat lists the plugins you used last and, under OFF, the ones you switched off from their pages, so you can turn them back on. Cohazard, the carbon monoxide safety card, can be switched off only in Pro, after BOAR asks. Each plugin shows its status: LIVE, BETA (tested on phones), ALPHA (early) or UNDER REVIEW (visible but parked). Some tiles are CLASSIFIED: in testing, with no release date. Some plugins answer instantly without the model, and then the answer offers "Ask BOAR instead". Plugins with actions add them to 🧩 under answers. The Plugins settings also pick the waiting animation: Boar trail or Matrix rain.

## The plugins
- Vitals: watch the phone work: heat, each core's clock, memory and the chip.
- Calculator: exact answers to everyday calculations (battery, fuel, hiking, currency, water, temperature, durations), instantly. Plain sums and percentages still go to the model.
- Facts: one fact about a country, city, mountain, river, landmark or award, from a Wikidata table.
- Cohazard: a fixed carbon monoxide safety answer for running fuel-burning devices indoors.
- Distance: how far apart two cities are, and how long to walk, cycle or drive it, as an estimate.
- Polyglot: says so at once when you ask in a language BOAR doesn't speak yet.
- Designer: draws an illustration from a few words, offline. It downloads its drawing model (683 MB) the first time.
- Press: collect answers into a basket and compile them into a PDF or a Markdown file.
- Canvas: from 🧩 under an answer, Create a card: the model picks a bar, line or pie chart, a table, steps, a comparison or key facts, from the answer, earlier answers in the chat and the answer's sources, and BOAR draws it. Every number must be in one of those; anything that isn't is left out and listed. Switch the same data between bars, line, pie and table, copy it, or open it full screen. Under the card, Make it interactive builds a small interactive page from the answer; it takes longer.
- Nomad: a compass from the phone's sensors, offline, no location needed.
- Lunar: the moon tonight and this month: phase, lit share, next full and new moon.
- Guard: fixes a yes/no or winner that the model's own figures or dates contradict.

## Settings
Settings starts with Profile, then the sections your profile shows, folded: How BOAR answers, Chats & history, Display & theme, Boar Avatars (with Boarverse on), Language and voice, PIN lock, This phone (with Show technical details on), Advanced tweaks, Experimental, and Start over. Models and Knowledge are in the menu (Model Catalog, Knowledge). Advanced tweaks (Pro) holds presets for speed, battery and heat, Free memory when I leave BOAR and how soon, Sources layout, and Show technical details, which adds memory and storage bars in the menu and the This phone section.

## Profiles
Settings → Profile picks how much Settings shows. Starter: language, look, PIN and starting over. Explorer adds how BOAR answers, chats and history, voice, Boarverse, rotation and haptics. Pro adds Advanced tweaks, technical details and Plugins. Below Pro, Advanced tweaks and technical details go back to Auto; your choices return when you pick Pro again. A new install starts on Starter; after an update BOAR picks the profile that shows everything you had changed, and says so once.

## Chats and history
Your chats are kept on the phone and listed under Recent sessions in the menu. Settings → Chats & history (from the Explorer profile) sets how many chats BOAR keeps, whether it names them by itself, whether it summarizes long chats in the background, whether deleting a chat asks first, and clears the history. Delete a single chat from the menu. While BOAR is answering, stop the answer to switch chats. With a PIN on, chats are stored encrypted.

## Voice input
Tap the microphone inside the box where you type to speak a question. BOAR uses the phone's own on-device speech recognition, in the app's language (with System, your phone's); a phone without that language's speech pack listens in its own. On a phone without on-device recognition, the microphone doesn't show. Turn voice input on or off in Settings → Language and voice (from the Explorer profile).

## Language
BOAR's screens come in English and Portuguese: pick System, English or Português in Settings → Language and voice. You can ask in either language; for a Portuguese question, BOAR also searches the English library.

## Privacy
BOAR runs on the phone: questions, answers, files and chats stay there. It contacts the internet only to download models and packs you choose, and to send your search words to Hugging Face when you use Discover GGUF models. It never sends your questions anywhere.

## Close BOAR
Close BOAR, in the menu, frees the memory the model uses and closes the app; if an answer is still being written, it asks first. By default, BOAR also frees the model as soon as you leave the app and no answer is running, so other apps have room: Settings → Advanced tweaks → Free memory when I leave BOAR.

## Starting over
Settings → Start over has: Run setup again, See the tour, Reset settings, and Erase everything. Reset settings puts the theme, answer style, Deep Research, Advanced tweaks and display options back to their defaults and opens setup; models, packs, chats, PIN and language stay. Erase everything deletes models, packs, your files, all chats, settings and the PIN, closes BOAR, and the next launch starts setup; it can't be undone.

## About BOAR
Tap the BOAR mark at the top of the menu for About BOAR: the version, the project's links and the credits.

## When something goes wrong
- An answer is slow: try Succinct & Direct, a lower Max output tokens, a smaller model in the Model Catalog, or turn Deep Research off.
- A model failed to load: tap Try again with less memory, or pick another model; a model too big for the phone's memory can fail.
- An answer was cut off because BOAR closed: it says Interrupted; tap Try again.
- The download stopped in setup: tap Restart downloads, or Try again once the phone is online.
