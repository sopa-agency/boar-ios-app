#!/usr/bin/env bash
# One-time, run by Biel in Terminal on the build host's own screen (asks for the Mac password and an "Allow"):
#   bash ~/Dev/boar-ios-app/scripts/build-keychain.sh
# Creates boar-build.keychain-db holding only the Apple Development identity, its password in
# ~/.config/boar/build-keychain.pw (0600), so scripts/device.sh can sign over SSH without a prompt.
# Whoever controls that macOS account can sign with that (free) certificate; nothing else is exposed.
set -euo pipefail
umask 077
LOGIN=~/Library/Keychains/login.keychain-db
K=~/Library/Keychains/boar-build.keychain-db
F=~/.config/boar/build-keychain.pw
mkdir -p ~/.config/boar
[ -f "$F" ] || openssl rand -hex 24 > "$F"
P=$(cat "$F")
# A keychain left by a half-finished run that no longer opens with the saved password is rebuilt.
if [ -f "$K" ] && ! security unlock-keychain -p "$P" "$K" 2>/dev/null; then security delete-keychain "$K"; fi
[ -f "$K" ] || security create-keychain -p "$P" "$K"
security unlock-keychain -p "$P" "$K"
security set-keychain-settings "$K"   # no auto-lock

curl -fsSLo /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k "$K" /tmp/AppleWWDRCAG3.cer 2>/dev/null || true

# macOS only exports a private key after a GUI confirmation ("Allow"), so run this in Terminal on the build
# host's own screen, not over SSH. The temporary .p12 is deleted right after the import.
P12=$(mktemp -u /tmp/boar-id.XXXXXX).p12
T=$(openssl rand -hex 16)
trap 'rm -f "$P12"' EXIT
security unlock-keychain "$LOGIN"
security export -k "$LOGIN" -t identities -f pkcs12 -P "$T" -o "$P12"
security unlock-keychain -p "$P" "$K"
security import "$P12" -k "$K" -P "$T" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$P" "$K" >/dev/null

# Build keychain first: over SSH the login keychain stays locked and codesign stalls on it (errSecInternalComponent).
security list-keychains -d user -s "$K" "$LOGIN"
security find-identity -v -p codesigning "$K"
echo PRONTO
