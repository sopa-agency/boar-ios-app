#!/bin/bash
# UI audit capture: builds the app (DEBUG), installs it on the "BOAR Audit iPhone 13" simulator and saves one light and one
# dark screenshot per screen, each launched straight onto the screen with -uiDemo -uiScreen (no taps, no model).
#
#   [MODES=dark] [UI_LANG=pt] [THEME=campfire] scripts/ui-capture.sh <out-dir> [--no-build] [--only name,name] [--wait seconds]
#   VAULT='<json>' [ICON=<id>] scripts/ui-capture.sh ...   Boarverse on, that Boar Avatars state, that avatar equipped
#
# THEME shows the app in that theme (-uiTheme, this run only); a theme other than System looks the same in both modes,
# so it is captured once (light) unless MODES says otherwise.
#
# Output: <out-dir>/<screen>-light.png and -dark.png. DerivedData: the shared .build/DerivedData.
# The simulator keeps existing afterwards (shut down), so reruns reuse it.
set -u
export DEVELOPER_DIR=/Applications/Xcode-27.2.0.app/Contents/Developer
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: ui-capture.sh <out-dir> [--no-build] [--only a,b] [--wait N]}"; shift
BUILD=1; ONLY=""; WAIT=9
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --only) ONLY="$2"; shift ;;
    --wait) WAIT="$2"; shift ;;
  esac
  shift
done
NAME="BOAR Audit iPhone 13"
BUNDLE="team.sopa.boar.native"
DD="$ROOT/.build/DerivedData"
APP="$DD/Build/Products/Debug-iphonesimulator/Boar.app"

UDID=$(xcrun simctl list devices | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$UDID" ]; then
  # The newest plain iOS runtime installed (iOS 27.2 on the build host since 2026-11-04).
  RUNTIME=$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*$' | tail -1)
  for TYPE in "iPhone 13" "iPhone 17"; do
    UDID=$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME" 2>/dev/null) && break
  done
fi
[ -n "$UDID" ] || { echo "no simulator"; exit 1; }
echo "simulator $UDID"

if [ "$BUILD" = 1 ]; then
  (cd "$ROOT" && xcodegen generate >/dev/null && \
   xcodebuild -project Boar.xcodeproj -scheme Boar -destination "platform=iOS Simulator,id=$UDID" \
     -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3) || exit 1
fi
[ -d "$APP" ] || { echo "no build at $APP"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --operatorName "" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || exit 1
mkdir -p "$OUT"

# name|screen|scroll (scroll: points from the top, or "end"; empty = none)
SCREENS="
setup|setup|
setup-model|setup-model|
setup-knowledge|setup-knowledge|
setup-install|setup-install|
setup-index|setup-index|
setup-guide-look|setup-guide-look|
setup-guide-files|setup-guide-files|
setup-guide-answers|setup-guide-answers|
setup-guide-ask|setup-guide-ask|
setup-guide-first|setup-guide-first|
setup-guide-pin|setup-guide-pin|
setup-guide-privacy|setup-guide-privacy|
setup-guide-labs|setup-guide-labs|
setup-guide-ready|setup-guide-ready|
chat-empty|chat-empty|
chat-load-crash|chat-load-crash|
chat-error|chat-error|
chat-no-model|chat-no-model|
chat|chat|
chat-top|chat-top|0
chat-streaming|chat-streaming|
chat-retrieving|chat-retrieving|
chat-research|chat-research|
sidebar|sidebar|
citation-sheet|citation-sheet|
receipt|receipt|
tone-sheet|tone-sheet|
models|models|
model-detail|model-detail|
models-downloading|models-downloading|480
models-browse|models-browse|
documents|documents|
settings|settings|
settings-2|settings|650
settings-3|settings|end
settings-advanced|settings-advanced|
settings-advanced-2|settings-advanced|end
device-info|device-info|
settings-engine|settings-engine|
settings-engine-2|settings-engine|end
evaluation|evaluation|
about|about|
about-2|about|end
lock|lock|
labs|labs|
labs-2|labs|end
lab-image|lab-image|
avatars|avatars|
avatars-2|avatars|end
tour-welcome|tour-welcome|
tour-theme|tour-theme|
tour-styles|tour-styles|
tour-deep|tour-deep|
tour-sources|tour-sources|
tour-knowledge|tour-knowledge|
tour-models|tour-models|
tour-adaptive|tour-adaptive|
tour-lock|tour-lock|
tour-labs|tour-labs|
tour-end|tour-end|
"

if [ -n "${THEME:-}" ] && [ "$THEME" != system ]; then MODES="${MODES:-light}"; fi
for MODE in ${MODES:-light dark}; do
  xcrun simctl ui "$UDID" appearance "$MODE" >/dev/null
  # Switching the appearance can drop the status bar override: set it again for every mode.
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --operatorName "" >/dev/null 2>&1
  echo "$SCREENS" | while IFS='|' read -r FILE SCREEN SCROLL; do
    [ -n "$FILE" ] || continue
    if [ -n "$ONLY" ] && ! echo ",$ONLY," | grep -q ",$FILE,"; then continue; fi
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
    case "${UI_LANG:-en}" in pt) LOCALE=pt_BR ;; *) LOCALE=en_US ;; esac
    ARGS=(-uiDemo -uiScreen "$SCREEN" -AppleLanguages "(${UI_LANG:-en})" -AppleLocale "$LOCALE")
    [ -n "$SCROLL" ] && ARGS+=(-uiScroll "$SCROLL")
    # A lab's page shows its content only switched on (-uiDemo starts every lab off); Designer with pictures to show.
    case "$SCREEN" in lab-*) ARGS+=("-labs.enabled.${SCREEN#lab-}" YES) ;; esac
    [ "$SCREEN" = lab-image ] && ARGS+=(-uiDesigner YES)
    [ -n "${THEME:-}" ] && ARGS+=(-uiTheme "$THEME")
    [ -n "${VAULT:-}" ] && ARGS+=(-uiBoarverse YES -uiVault "$VAULT")
    [ -n "${ICON:-}" ] && ARGS+=(-uiIcon "$ICON")
    xcrun simctl launch "$UDID" "$BUNDLE" "${ARGS[@]}" >/dev/null
    EXTRA=0; [ -n "$SCROLL" ] && EXTRA=4
    sleep $((WAIT + EXTRA))
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$FILE-$MODE.png" >/dev/null 2>&1 && echo "$FILE-$MODE"
  done
done

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1
xcrun simctl ui "$UDID" appearance light >/dev/null
xcrun simctl shutdown "$UDID" >/dev/null 2>&1
echo "done: $OUT (simulator $UDID shut down)"
