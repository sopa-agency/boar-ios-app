#!/bin/bash
# Exports Android's Boar Avatars themes (ExtraThemes.kt: Tactical Red, Hacker Green, ..., Paper) to
# Fixtures/golden/theme/vault-themes.json, computed by Compose's own Color and lerp (Oklab) on the JVM: the same code
# the Android app runs, so the iOS palettes match it exactly. Then run scripts/export-theme-tokens.py, which writes
# them into Sources/BoarCore/ThemePalettes.swift.
#
#   scripts/export-vault-themes.sh        (refresh .ref first with scripts/sync-reference.sh)
#
# Needs a JDK 17 (brew install openjdk@17) and the Gradle wrapper of the Android clone (../boar-app); Gradle and
# Compose's ui-graphics-desktop (JetBrains, the 1.9 line Android's BOM uses) are downloaded on the first run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="${ANDROID:-$ROOT/../boar-app/android-native}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export THEME_DIR="$ROOT/.ref/android-native/app/src/main/java/team/sopa/boar/ui/theme"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A copy outside the repo: Gradle's build files stay out of it.
cp -R "$ROOT/scripts/vault-themes/." "$WORK/"
cp "$ANDROID/gradlew" "$WORK/"
mkdir -p "$WORK/gradle" && cp -R "$ANDROID/gradle/wrapper" "$WORK/gradle/"
OUT="$ROOT/Fixtures/golden/theme/vault-themes.json"
(cd "$WORK" && ./gradlew -q --no-daemon run) > "$OUT"
echo "wrote ${OUT#$ROOT/}"
