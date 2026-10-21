#!/bin/bash
# Performance loop on the cabled iPhone (docs/PERF.md). Everything runs on this Mac; outputs go to .build/perf/.
#   scripts/perf.sh build                  Release build, signed with Local.xcconfig's team, installed on the iPhone
#   scripts/perf.sh record NAME [SECS] [--metal]   cold launch under Time Profiler (+ hangs, signposts); waits for unlock
#   scripts/perf.sh report NAME            hangs, BOAR signposts (model.load, answer…), main-thread hot frames in hangs
#   scripts/perf.sh jetsam [YYYY-MM-DD]    memory kills + Boar crashes from the phone (who used the RAM)
#   scripts/perf.sh log                    live device log of BOAR's perf lines (model.load, main.stall, answer…)
#   scripts/perf.sh metrickit              copies MetricKit hang/crash payloads out of the app container
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/.build/perf
DEVICE=${BOAR_DEVICE:?set BOAR_DEVICE to the iPhone UDID (xcrun devicectl list devices)}
BUNDLE=team.sopa.boar.native
mkdir -p "$OUT"

app_path() {
  xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE" --json-output /dev/stdout 2>/dev/null \
    | grep -o '"url" *: *"file://[^"]*Boar.app' | head -1 | sed 's#.*file://##'
}

wait_online() {
  # xctrace lists a locked iPhone as offline: wait until it is unlocked.
  local n=0
  until xcrun xctrace list devices 2>/dev/null | sed '/Devices Offline/,$d' | grep -q "$DEVICE"; do
    [ $n -eq 0 ] && echo "waiting for the iPhone to be unlocked…" >&2
    n=$((n + 1)); [ $n -gt 360 ] && { echo "iPhone stayed locked" >&2; exit 1; }
    sleep 5
  done
}

case "${1:-}" in
build)
  cd "$ROOT"
  command -v xcodegen >/dev/null && xcodegen generate -q
  xcodebuild -project Boar.xcodeproj -scheme Boar -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath .build/DerivedData -allowProvisioningUpdates build -quiet > "$OUT/build.log" 2>&1 \
    || { tail -30 "$OUT/build.log"; exit 1; }
  APP=.build/DerivedData/Build/Products/Release-iphoneos/Boar.app
  codesign --verify --deep --strict "$APP"
  xcrun devicectl device install app --device "$DEVICE" "$APP" | tail -1
  echo "installed $(git rev-parse --short HEAD 2>/dev/null) (Release)"
  ;;
record)
  # Cold launch, suspended before main(); xctrace attaches, then the app resumes. With `xctrace --launch` the
  # os_signpost stream reached the new process only ~4 s in, so launch intervals (services.open, model.load) were lost.
  NAME=${2:?name}; SECS=${3:-60}; ENVARGS=()
  [ "${4:-}" = "--metal" ] && ENVARGS=(--environment-variables '{"BOAR_METAL":"1"}')
  [ -n "$(app_path)" ] || { echo "BOAR is not installed" >&2; exit 1; }
  wait_online
  rm -rf "$OUT/$NAME.trace"
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --start-stopped \
    ${ENVARGS[@]+"${ENVARGS[@]}"} --json-output "$OUT/launch.json" "$BUNDLE" > /dev/null
  PID=$(python3 -c 'import json,sys
def find(o):
    if isinstance(o, dict):
        if "processIdentifier" in o: return o["processIdentifier"]
        o = list(o.values())
    for v in o if isinstance(o, list) else []:
        p = find(v)
        if p: return p
print(find(json.load(open(sys.argv[1]))) or "")' "$OUT/launch.json")
  [ -n "$PID" ] || { echo "no pid in $OUT/launch.json" >&2; exit 1; }
  # The device log is the second witness: every BoarPerf mark also logs a `perf` line with its duration.
  idevicesyslog -u "$DEVICE" -p Boar > "$OUT/$NAME.syslog.txt" 2>/dev/null &
  SL=$!
  # xctrace's view of the device's processes lags a fresh launch by a few seconds: retry the attach.
  for try in 1 2 3 4 5 6 7 8 9 10; do
    xcrun xctrace record --template 'Time Profiler' --device "$DEVICE" --time-limit "${SECS}s" \
      --output "$OUT/$NAME.trace" --attach "$PID" > "$OUT/$NAME.xctrace.log" 2>&1 &
    XT=$!
    n=0
    until grep -q 'Ctrl-C to stop' "$OUT/$NAME.xctrace.log" || ! kill -0 $XT 2>/dev/null; do
      n=$((n + 1)); [ $n -gt 120 ] && { echo "xctrace didn't start" >&2; kill $XT; exit 1; }
      sleep 0.5
    done
    grep -q 'Ctrl-C to stop' "$OUT/$NAME.xctrace.log" && break
    grep -q 'Cannot find process' "$OUT/$NAME.xctrace.log" || { cat "$OUT/$NAME.xctrace.log" >&2; exit 1; }
    sleep 1
  done
  grep -q 'Ctrl-C to stop' "$OUT/$NAME.xctrace.log" || { cat "$OUT/$NAME.xctrace.log" >&2; exit 1; }
  sleep 1
  xcrun devicectl device process resume --device "$DEVICE" --pid "$PID" > /dev/null
  wait $XT || true
  kill $SL 2>/dev/null || true
  tail -2 "$OUT/$NAME.xctrace.log"
  python3 "$ROOT/scripts/perf_report.py" "$OUT/$NAME.trace"
  echo; echo "## Device log (perf lines)"
  grep -E ' ms, footprint|main\.stall|firstToken' "$OUT/$NAME.syslog.txt" | sed 's/^.*<Notice>: /  /' || echo "  (none)"
  ;;
report)
  python3 "$ROOT/scripts/perf_report.py" "$OUT/${2:?name}.trace"
  ;;
jetsam)
  DAY=${2:-$(date +%F)}; D=$OUT/crash-$(date +%H%M%S)
  mkdir -p "$D"
  idevicecrashreport -u "$DEVICE" -k -e -f "$DAY" "$D" > /dev/null
  python3 "$ROOT/scripts/perf_report.py" --jetsam "$D"
  ;;
log)
  idevicesyslog -u "$DEVICE" -p Boar | grep --line-buffered -E ' ms, footprint|main\.stall|firstToken|MetricKit'
  ;;
metrickit)
  D=$OUT/metrickit; mkdir -p "$D"
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "Library/Application Support/BOAR/metrickit" --destination "$D" > /dev/null
  ls -la "$D"
  ;;
*)
  sed -n '2,9p' "$0"; exit 2
  ;;
esac
