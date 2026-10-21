#!/usr/bin/env bash
# Fetch the official llama.cpp XCFramework pinned to the same commit as android-native (b11010 = 4bc272fd).
set -euo pipefail
TAG=b11010
SHA256=1afd7b5f1bc67bc0967878dc80f33435175e4f0b0a80b5b3a2abdc63ea55b9a3
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor"
[ -d "$DEST/llama.xcframework" ] && { echo "llama.xcframework present"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/llama.zip" "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-xcframework.zip"
echo "$SHA256  $TMP/llama.zip" | shasum -a 256 -c -
mkdir -p "$DEST"; unzip -q "$TMP/llama.zip" -d "$TMP/x"
mv "$(find "$TMP/x" -maxdepth 3 -name 'llama.xcframework' -type d | head -1)" "$DEST/"
echo "$TAG" > "$DEST/llama.xcframework.TAG"
echo "llama.xcframework $TAG installed"
