#!/usr/bin/env bash
# Build, sign and install the iOS app on a device, from cx. Run through cx.sh:
#   bash scripts/cx.sh 'bash scripts/device.sh'            (DEVICE from ~/.config/boar/local.env)
# Needs scripts/build-keychain.sh once. Env: DEVICE (UDID), BUNDLE_ID (personal-team id until phase 0 picks the final one).
# ponytail: no -allowProvisioningUpdates (the Xcode account lives in the locked login keychain); the free-team
# profile lasts 7 days, renew it with one build from an unlocked session (Xcode, or ssh -t + unlock-keychain).
set -euo pipefail
[ -f ~/.config/boar/local.env ] && . ~/.config/boar/local.env
DEVICE="${DEVICE:?set DEVICE=<udid> in ~/.config/boar/local.env}"
BUNDLE_ID="${BUNDLE_ID:-team.sopa.boar.biel}"
K=~/Library/Keychains/boar-build.keychain-db
security unlock-keychain -p "$(cat ~/.config/boar/build-keychain.pw)" "$K"
xcodegen generate --quiet
# The same identity also sits in the (locked) login keychain; point codesign at the build one.
xcodebuild -project Boar.xcodeproj -scheme Boar -destination "id=$DEVICE" -derivedDataPath .build/DerivedData \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" OTHER_CODE_SIGN_FLAGS="--keychain $K" build -quiet
xcrun devicectl device install app --device "$DEVICE" .build/DerivedData/Build/Products/Debug-iphoneos/Boar.app
