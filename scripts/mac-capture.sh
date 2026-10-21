#!/bin/bash
# Mac UI capture: launches the DEBUG Mac build in the background (no focus change) with -uiDemo -uiScreen <name>, and
# captures only its window with screencapture -l (works behind other windows).
#
#   [EXTRA="-uiRemote 127.0.0.1:8199"] scripts/mac-capture.sh <out-dir> screen[,screen...] [light|dark]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: mac-capture.sh <out-dir> screens [light|dark]}"; SCREENS="${2:?screens}"; MODE="${3:-light}"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/BOAR.app"
TMP="$HOME/Library/Containers/team.sopa.boar.native/Data/tmp"
# -uiDemo keeps its files in Application Support/BOAR-demo and its settings in the team.sopa.boar.native.demo suite, so
# the real models, chats and preferences in the container are never touched.
trap 'pkill -f "BOAR.app/Contents/MacOS/BOAR -uiDemo" 2>/dev/null' EXIT
mkdir -p "$OUT"
for S in ${SCREENS//,/ }; do
  pkill -f "BOAR.app/Contents/MacOS/BOAR -uiDemo" 2>/dev/null; sleep 1
  rm -f "$TMP/ui-window.txt"
  open -g -n "$APP" --args -uiDemo -uiScreen "$S" -uiSnapshot 7 -AppleLanguages "(en)" ${EXTRA:-} -uiAppearance "$MODE"
  for i in $(seq 1 40); do [ -s "$TMP/ui-window.txt" ] && break; sleep 0.5; done
  ID=$(cat "$TMP/ui-window.txt" 2>/dev/null)
  [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/mac-$S-$MODE.png" && echo "mac-$S-$MODE"
  sleep 1
done
