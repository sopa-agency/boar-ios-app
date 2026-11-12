# Performance on the iPhone

TL;DR: build Release, record a cold launch over the cable with Time Profiler, read hangs + BOAR signposts + memory, and check jetsam reports when the whole phone slows down. Debug builds (`-Onone`) are not representative: always measure Release.

```bash
bash scripts/perf.sh build              # Release, signed on this Mac, installed on the cabled iPhone
bash scripts/perf.sh record cold1 75    # cold launch under Time Profiler; waits until the iPhone is unlocked
bash scripts/perf.sh report cold1       # hangs, model.load / answer / main.stall marks, CPU per thread, hot frames
bash scripts/perf.sh jetsam             # today's memory kills + BOAR crashes (who held the RAM)
bash scripts/perf.sh log                # live device log of BOAR's perf lines while you use the app
bash scripts/perf.sh metrickit          # MetricKit hang/crash payloads saved by the app
open .build/perf/cold1.trace            # the same trace in Instruments (Hangs, Points of Interest lanes)
```

Set the iPhone's Auto-Lock to Never while profiling: a locked iPhone is "offline" for `xctrace` and `devicectl`.

To measure a Release build installed another way (under another bundle ID, such as `team.sopa.boar.biel`), skip `build` and set `BOAR_BUNDLE` to that bundle ID for `record` and `metrickit`. `scripts/device.sh` builds Debug: its hang and time numbers don't count as Release.

## What the app reports

| Signal | Where | Meaning |
|---|---|---|
| `services.open`, `model.load`, `embedder.load`, `answer` intervals | Points of Interest lane; log category `perf` | duration plus memory footprint before → after and headroom (`os_proc_available_memory`) |
| `answer.firstToken` event | same | time to first token inside the `answer` interval |
| `main.stall` event | same | the main thread didn't answer a ping for > 250 ms (`PerfMonitor` watchdog, always on) |
| MetricKit JSON | `Library/Application Support/BOAR/metrickit/` | hang, crash and CPU diagnostics, delivered on the next launch |

Instruments' own Hangs lane flags main-thread hangs ≥ 250 ms (microhang) and ≥ 500 ms (hang). A hang with no CPU samples on the main thread means it was blocked (file I/O, a lock) or the system starved it: check `jetsam`.

## Known causes (keep this list current)

- **Metal shader compile (2026-10-16).** This llama.cpp build compiles ggml's Metal source at run time: up to three `MTLCompilerService` processes of ~470 MB each on the 4 GB iPhone 13. The system thrashed (dozens of daemons killed, ~30 MB free, the whole UI frozen) and the embedder crashed in `ggml_metal_library_get_pipeline`. iPhone and iPad now run llama.cpp on the CPU (`LlamaSession.metalEnabled`; `BOAR_METAL=1` turns Metal back on for experiments, `perf.sh record NAME SECS --metal`). Metal on iOS waits for a precompiled metallib.
- **Synchronous file checks on the main thread (fixed 2026-10-16).** `AssetStore.status` (stat, integrity.json) and the free-space query (`volumeAvailableCapacityForImportantUsage` waits on the system's CacheDelete service, off-CPU, so Time Profiler shows few samples for a long wait) ran on the main actor at launch through `SetupFlow.refreshPlans()`, `SetupFlow.ready` and `ModelsController.refresh()`: two ~0.4 s microhangs on the iPhone 13. They now go through `services.background { }`; keep new disk or free-space reads there too. The model preload also waits 600 ms after the chat appears: loading next to the first render left a 291 ms microhang. After both: 0 hangs in two cold launches (cold3, cold4), `model.load` 1.4–1.5 s.
- **Signposts missing from launch traces (fixed 2026-10-16).** With `xctrace record --launch` the os_signpost stream reached the new process only ~4 s after launch, so `services.open` and `model.load` never showed (later events did). `perf.sh record` now launches the app suspended (`devicectl … --start-stopped`), attaches xctrace, then resumes it. `perf_report.py` flags an End whose Begin is missing.

## Measurements

- **Memory peak, iPhone 14 Pro (2026-11-12).** Release, Qwen3 1.7B, three answers: peak footprint 554 MB (chat model ~390 MB, embedder ~5 MB), ~2.5 GB of headroom left, no jetsam. Answers took 15–19 s, `model.load` 1.9 s. On a 4 GB iPhone the per-app limit is around 2 GB, so this should fit; confirm on one.
- **Launch stalls, same day (open).** The first launch right after install showed two ~0.4 s `main.stall` events; a later cold launch under Time Profiler showed none (`model.load` 0.9 s). Likely the first-launch system work after install; repeat two or three cold launches to close it.

## References

- WWDC26 session 268, "Profile, fix, and verify: Improve app responsiveness with Instruments": Swift Executors instrument, System Trace inspector for low-CPU hangs, Top Functions mode.
- On the command line, `xctrace record --template 'Time Profiler'` records hangs, signposts and CPU samples in one pass. Avoid adding the SwiftUI instrument to the same recording on iOS 26 devices: it can leave every lane empty (Apple Developer Forums thread 810782).
