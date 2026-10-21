#!/usr/bin/env bash
# Rebuild Vendor/llama.xcframework with an iOS *simulator* slice.
#
# Why: the official llama.cpp release XCFramework (scripts/fetch-llama.sh) ships ios-arm64 + macos only, so the app cannot link
# for the iOS simulator. This script builds the `ios-sim` slice from the SAME tag (b11010 = 4bc272fd) with llama.cpp's own
# `build-xcframework.sh ios-sim` on the Mac mini, copies it back, and merges it with the release's ios-arm64 and macOS slices.
#
# Steps (exactly what runs):
#   1. mini: make sure ~/boar/kiln/tmp-llama-xcf has >= 25 GiB free after the build (checked before and after).
#   2. mini: clone llama.cpp at tag b11010 (local clone of ~/boar/spikes/llama-b11010 when present, else GitHub), verify the commit.
#   3. mini: DEVELOPER_DIR=Xcode-27, `bash build-xcframework.sh ios-sim` (cmake -G Xcode, iphonesimulator, arm64+x86_64,
#            Release, Metal embedded, static libs combined into llama.framework, same flags as the official release).
#   4. local: tar the framework + dSYM back, then `xcodebuild -create-xcframework` with
#            [release ios-arm64] + [release macos-arm64_x86_64] + [new ios-arm64_x86_64-simulator].
#   5. mini: delete ~/boar/kiln/tmp-llama-xcf.
#   6. local: replace Vendor/llama.xcframework, write Vendor/llama.xcframework.SHA256 (digest of every file, see below).
#
# usage: bash scripts/build-llama-xcframework.sh          (needs ssh access to a build Mac; set MINI)
# env:   MINI=<ssh-host>  SPIKE_MIRROR=boar/spikes/llama-b11010  KEEP_REMOTE=1 (skip step 5)
set -euo pipefail

TAG=b11010
COMMIT=4bc272fd729bd094c0422e4b8353da8d2fec91f8
MINI="${MINI:?set MINI to the ssh host that builds llama.cpp}"
SPIKE_MIRROR="${SPIKE_MIRROR:-boar/spikes/llama-b11010}"
REMOTE_DIR='boar/kiln/tmp-llama-xcf'
MIN_FREE_GIB=25
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/llama-xcf.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

[ -d "$VENDOR/llama.xcframework/ios-arm64" ] && [ -d "$VENDOR/llama.xcframework/macos-arm64_x86_64" ] \
  || { echo "need the release slices first: bash scripts/fetch-llama.sh" >&2; exit 1; }
if [ -d "$VENDOR/llama.xcframework/ios-arm64_x86_64-simulator" ]; then echo "simulator slice already present"; exit 0; fi

echo "== mini: build ios-sim ($TAG)"
ssh "$MINI" bash -s -- "$TAG" "$COMMIT" "$REMOTE_DIR" "$SPIKE_MIRROR" "$MIN_FREE_GIB" "$DEVELOPER_DIR" "${KEEP_REMOTE:-0}" <<'REMOTE'
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH   # non-login ssh shell: cmake lives in Homebrew
TAG=$1; COMMIT=$2; DIR=$HOME/$3; MIRROR=$HOME/$4; MIN_FREE=$5; export DEVELOPER_DIR=$6; KEEP=$7
free_gib() { df -g / | awk 'NR==2{print $4}'; }
echo "mini free: $(free_gib) GiB"
[ "$(free_gib)" -ge $((MIN_FREE + 2)) ] || { echo "not enough disk on the mini" >&2; exit 1; }
cleanup() { [ "$KEEP" = 1 ] || rm -rf "$DIR"; }
trap cleanup EXIT
rm -rf "$DIR"; mkdir -p "$DIR"; cd "$DIR"
if [ -d "$MIRROR/.git" ]; then
  git clone --quiet --local --no-checkout "$MIRROR" llama.cpp
  git -C llama.cpp checkout --quiet "$COMMIT"
else
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp.git llama.cpp
fi
[ "$(git -C llama.cpp rev-parse HEAD)" = "$COMMIT" ] || { echo "wrong commit" >&2; exit 1; }
cd llama.cpp
bash build-xcframework.sh ios-sim > ../build.log 2>&1 || { tail -50 ../build.log; exit 1; }
tail -3 ../build.log
ls build-ios-sim/framework/llama.framework build-ios-sim/dSYMs
tar -C build-ios-sim -cf ../sim-slice.tar framework/llama.framework dSYMs/llama.dSYM
echo "mini free after build: $(free_gib) GiB"
cp ../sim-slice.tar "$HOME/.llama-sim-slice.tar"
REMOTE

echo "== copy back"
scp -q "$MINI:.llama-sim-slice.tar" "$WORK/sim-slice.tar"
ssh -n "$MINI" 'rm -f ~/.llama-sim-slice.tar'
mkdir -p "$WORK/sim" && tar -C "$WORK/sim" -xf "$WORK/sim-slice.tar"
[ -f "$WORK/sim/framework/llama.framework/llama" ] || { echo "simulator framework missing" >&2; exit 1; }

echo "== merge"
OLD="$VENDOR/llama.xcframework"
NEW="$WORK/llama.xcframework"
xcrun xcodebuild -create-xcframework \
  -framework "$OLD/ios-arm64/llama.framework" -debug-symbols "$OLD/ios-arm64/dSYMs/llama.dSYM" \
  -framework "$OLD/macos-arm64_x86_64/llama.framework" -debug-symbols "$OLD/macos-arm64_x86_64/dSYMs/llama.dSYM" \
  -framework "$WORK/sim/framework/llama.framework" -debug-symbols "$WORK/sim/dSYMs/llama.dSYM" \
  -output "$NEW"
ls "$NEW"
rm -rf "$VENDOR/llama.xcframework" && mv "$NEW" "$VENDOR/llama.xcframework"

# Digest of the whole bundle: sha256 of the sorted per-file sha256 list (symlinks are listed by target).
( cd "$VENDOR/llama.xcframework" && find . \( -type f -o -type l \) | LC_ALL=C sort | while read -r f; do
    if [ -L "$f" ]; then echo "link $f -> $(readlink "$f")"; else echo "$(shasum -a 256 "$f" | cut -d' ' -f1)  $f"; fi
  done ) > "$VENDOR/llama.xcframework.FILES"
SHA="$(shasum -a 256 "$VENDOR/llama.xcframework.FILES" | cut -d' ' -f1)"
echo "$SHA  llama.xcframework (digest of llama.xcframework.FILES; $TAG + ios-sim slice built from $COMMIT)" > "$VENDOR/llama.xcframework.SHA256"
echo "llama.xcframework digest: $SHA"
echo "done. Slices: $(ls "$VENDOR/llama.xcframework" | grep -v Info.plist | tr '\n' ' ')"
