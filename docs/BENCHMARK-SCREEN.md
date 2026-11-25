# Benchmark screen: what it runs, measures and exports (decision, 2026-10-16)

TL;DR: the Benchmark screen runs the **public boar-eval bench v0.1** (60 items, the same file the R&D loop and the public boar-bench repo use) instead of only the 17-question "Question set 1". The phone grades what it can grade offline (the deterministic keyword **precheck**, source found, speed, memory), shows it **per category** and **side by side per model** with plain names ("Fast · Qwen2.5-1.5B-Instruct"), and exports **EvalTrace v1** traces that `harness/judge.mjs` and `scorers/score.py` read as they are. The bounty number (judge vs Opus + web) stays a desktop step.

Trigger: r4to on the UI review page, Evaluation card: "precisamos de um evaluation mais completo, com base no rnd e no benchmark geral".

```sh
python3 scripts/build-bench.py ../boar-eval/bench/v0.1/questions.public.jsonl   # regenerates Sources/BoarModels/Resources/bench-v0.1.json
python3 scripts/build-bench.py --golden ../boar-eval/bench/v0.1/questions.public.jsonl ../boar-eval/scorers/vendor/lantern/precheck.py  # Fixtures/bench/precheck-golden.jsonl
swift test --scratch-path .build/eval --filter BoarAnswerTests --skip LabTimingTests
# on the Mac, after Share → Traces for the judge:
node harness/judge.mjs --traces <file>.traces.jsonl --out <file>.judgments.jsonl --bench bench/v0.1 --floor-errored
python3 scorers/score.py --traces <file>.traces.jsonl --judgments <file>.judgments.jsonl --bench bench/v0.1
```

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Question sets: **Quick check** (12 items), **Research bench v0.1** (all 60), **App smoke set** (the 17 old items, set "1") | Quick fits a coffee break on a 4 GB iPhone (12 answers × ~30 s); the full set is the R&D L2 set; the old set stays for Android parity and device requests |
| D2 | Only public dev items: `boar-eval/bench/v0.1/questions.public.jsonl` (sha 568b3ece…, identical to the public boar-bench snapshot). The build script refuses any path with `blind`, `veil`, `v0.2`, `v0.3` or `heldout` | held-out and blind sets are never read or bundled |
| D3 | Not bundled: safety track v0.3 (mixes PT-BR; its veto needs the negation rules), pack self-tests (rubric-only, need the matching packs installed), rubrics and gold answers | English only; nothing the phone cannot grade or does not need |
| D4 | On-device grade = **precheck v2.2**, a byte-faithful Swift port of `scorers/vendor/lantern/precheck.py` (`grade`, `refused`, `norm`), checked against a golden file the Python writes | deterministic, no model; the same statuses the desktop scorer gives (pass / fail-missing / confident-wrong / refused / empty) |
| D5 | 52 of 60 items are precheck items; the 8 others (3 venue-list, 3 first-aid, 2 judge-only) run and export but show "Judged on the computer" | the phone cannot check OSM venues, first-aid rules or rubric quality |
| D6 | **Source found** = retrieval kept an article whose title is one of the item's Wikipedia `reference_sources` (title from the URL). Shown only over items that have one | the R&D retrieval metric (gold source in context) in its offline form |
| D7 | Speed: total p50 / p90, first word p50, decode tok/s median, model load, peak memory. p50 = median; p90 = nearest rank | the Bounty board's latency row; same fields as the trace's `timing` |
| D8 | Labels say what each number is: "Facts checked" carries the caveat that precheck agrees with blind hand labels 88 % of the time and **is not the bounty ratio** | precheck is an upper bound (score.py PRECHECK_CAVEAT); no LLM judge on the phone |
| D9 | Models are named "Fast · Qwen2.5-1.5B-Instruct" (plain name from the catalog copy + the model's own name without quantization) | the review flagged raw catalog names on this screen |
| D10 | Export: **Traces for the judge** = EvalTrace v1 JSONL, one file per model, and per pass when a preset ran several (`adapter: ios-app`, `engine.commit` = app version + build, `engine.arm` = `ios-native`, host = device + iOS). Raw rows JSONL/CSV stay, unchanged columns | judge.mjs and score.py read one system per file; convert_device.py is for the Android "answer" pipeline rows and is not needed |
| D11 | Rows keep every legacy field and add `benchSet`, `check`, `checkWhy`, `sourceHit`, `referenceTitles`, `danger`, `gradingType` | old readers ignore new keys; device requests keep working |
| D12 | Device requests may also name bench v0.1 ids or categories in `queries` (bench items are passed as extra sets) | a connected Mac can run a slice without a new protocol |

## What the screen shows

```
Question Set        [Quick check ▸]      12 questions · bench v0.1 (public dev)
Models to Test      ✓ Fast · Qwen2.5-1.5B-Instruct
                    ✓ Accurate · Qwen3-4B-Instruct-2507
Run                 ▶ Run Benchmark      12 × 2 = 24 answers
Progress            Model 1 of 2 · Question 5 of 12
Summary (per model) Facts checked 7/10 · Wrong 1 · Source found 4/6 · 31 s p50 · 9.8 tok/s
By Category         explanation 2/2 · reasoning 1/2 · …   (one row per category, per model)
Answers             one row per answer; tap → check result, why, timings, sources, the answer
Share               Traces for the judge (per model) · Rows (JSONL) · Rows (CSV)
```

## Presets, scorecard and saved runs (BOAR-56, Android v2.0.0)

Port of Android's bench at v2.0.0 (3619e95a engine, 66ff23c7 page, 91c28f67 log, 06276b77 and 11e7997b vitals,
b13d990e search-only). Engine in `Sources/BoarAnswer/Eval` (`BenchTopics`, `BenchPresets`, `Scorecard`, `SavedRuns`,
`BenchLog`), with Android's BenchPresetsTest, ScorecardTest, SavedRunsTest, SearchOnlyRequestTest, BenchLogTest and
BenchVitalsTest ported. The topic files are Android's `boar-data/topics/*.v1.json` byte for byte, in
`Sources/BoarModels/Topics` (core, vitalik, plugins, problems, howto, research, quick, cards, portuguese, health).

```
Preset              By hand | Fast | Medium | Complete      Topic [Plugins and calculators ▸]
                    Models: Qwen3-1.7B · Expected: about 3 min for 21 answers (from the F3's medians)
Vitals / Log        while a run goes, on top: heat, battery, memory; the log newest line first, "● last line 12 s ago"
Scorecard           plugins 18/20 passed ↑ up · was 15/20 · 0 to read · 1 skipped (plugin off)
                    qwen3-1.7b-q4km · succinct: first word, whole answer, peak memory
Saved Runs (n)      newest first: date, level · topic · answers · BOAR version · "from a computer"; tap opens, Delete asks
```

- **Levels:** Fast = Succinct on the 1.7B (or the only answer model); Medium = Succinct on the 1.7B and the 4B; Complete =
  Succinct and Detailed on both, plus Deep Research for the research topic. Each pass answers in its style with the
  chat's rules (short-answer reasons, `autoMaxTokens`, small talk at Succinct's length, the small-model prompts).
- **Plugins:** a topic's labs answer and check (the plugins topic), else the ones switched on in the app; an instant
  answer is the row (`reasonCodes: ["answer:<tool>"]`, `tool`), as in the chat. Nomad and Vitals read the device first.
- **Rows** add `style`, `level`, `topic`, `topicVersion`, `labsOn`, `tool`, `fileSources`, `path` (`deep`,
  `search-only`) and `subQuestions`; the CSV has Android's new columns, then iOS's bench-check columns.
- **Files:** `Documents/eval/<runId>.jsonl` as before, plus `<runId>.meta.json` (written as the run goes; a run the app
  closed on shows as interrupted) and `<runId>.scorecard.txt` (against the last finished run of the same level and
  topics). Old runs without a meta are listed from their rows.
- **Device requests** take `"preset": "fast-plugins"` or `"level"` + `"topics"`, and `"searchOnly": true` (the sources
  with similarity, score, match and kind; no answer). The status file says `preset` and `scorecardPath`.

Differences from Android, on purpose:

- No separate bench activity (BenchActivity, adb-only): the log and the vitals card sit on top of the Benchmark screen
  while a run goes. The saved run's `source` is `"request"` (a connected computer), not `"adb"`.
- Vitals read what iOS gives: the thermal state (no battery temperature), battery, BOAR's footprint and what it can
  still use, the core count. No per-core clocks; the heat is the thermal state, with its peak during the run.
- By hand keeps iOS's question sets (Quick check, Research bench v0.1, App smoke set); the topic picker shows with a
  level only (Android's by hand also takes a topic's questions).
- No BenchModels (Android's bench-only Qwen3-0.6B pushed over USB), and no request fields for outside questions,
  engines, retrieval mode, answer style or labs (`questions`, `engine(s)`, `retrieval`, `style`, `labs`): the iOS
  runner keeps the legacy fixed-model pipeline and the app's or the topic's plugins. No Staged rows either.
- The bench screens are in English and Portuguese (Android's bench activity is English only).

## Not in scope (next iterations)

- The judge itself (desktop, Opus or a cross-family judge; see XFAM).
- Safety veto on device (port `safety_check.py` + rules v0.3).
- Pack self-tests with the matching packs installed (retrieval hit of `in_pack_facts`).
- The engine commit inside the app (a build-time Info.plist key would need a project.yml change).

UNKNOWN: precheck's ICU regex vs Python `re` could differ on exotic Unicode; the golden file covers every bench term, not arbitrary answers.
