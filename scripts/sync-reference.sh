#!/usr/bin/env bash
# Refresh the read-only Kotlin reference (.ref/) and the golden fixtures from boar-app's android-native at a ref.
# Usage: scripts/sync-reference.sh [git-ref]   (default upstream/main). Writes Fixtures/SOURCE_SHA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP="$ROOT/../boar-app"; REF="${1:-upstream/main}"
SHA="$(git -C "$APP" rev-parse "$REF")"
# Boar Avatars' roster (VaultTests checks Vault.rules against it, as Android's VaultTest does). Read first, so a ref
# without it stops the script before anything is replaced.
ROSTER="$(git -C "$APP" show "$SHA:android-native/art/icons/truffles.json")"
rm -rf "$ROOT/.ref" "$ROOT/Fixtures/golden"; mkdir -p "$ROOT/.ref" "$ROOT/Fixtures"
git -C "$APP" -c core.autocrlf=false archive "$SHA" android-native/engine/src/test/resources/golden | tar -x -C "$ROOT/.ref"
mv "$ROOT/.ref/android-native/engine/src/test/resources/golden" "$ROOT/Fixtures/golden"
git -C "$APP" -c core.autocrlf=false archive "$SHA" android-native/engine/src/main/java android-native/engine/src/test/java android-native/app/src/main \
  android-native/engine/src/main/cpp/boar_jni.cpp android-native/engine/src/main/cpp/boar_sqlite.cpp android-native/engine/src/main/cpp/CMakeLists.txt | tar -x -C "$ROOT/.ref"
rm -rf "$ROOT/.ref/android-native/engine/src/test/resources"
mkdir -p "$ROOT/Fixtures/vault"
printf '%s\n' "$ROSTER" > "$ROOT/Fixtures/vault/truffles.json"
# The theme golden isn't one of Android's: it's exported from the Kotlin theme just extracted (the rm above took it).
python3 "$ROOT/scripts/export-theme-tokens.py"
echo "$SHA" > "$ROOT/Fixtures/SOURCE_SHA"; echo "synced $REF = $SHA"
