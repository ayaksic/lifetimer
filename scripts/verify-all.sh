#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "[1/9] Security and private-data history scan"
node scripts/security-check.mjs --history

echo "[2/9] Contracts, manifest, schemes, versions, and entitlements"
node scripts/check-contracts.mjs

echo "[3/9] Swift package and native CloudKit adapter tests"
TZ=America/New_York swift test

echo "[4/9] Shared Swift/JavaScript fixture parity"
TZ=America/New_York node Tests/WebParity/web-parity.test.cjs

echo "[5/9] Web CloudKit adapter tests (fake database; no live account)"
node Tests/WebParity/cloudkit-settings.test.cjs

echo "[6/9] Web artifact assembly and generated build identity"
node scripts/build-web.mjs

derived_root="$repo_root/.build/verification-derived-data"

echo "[7/9] iPhone and iOS widget/Live Activity simulator builds"
xcodebuild -quiet \
  -project "Apps/iOS/Life Timer.xcodeproj" \
  -scheme "Life Timer" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived_root/ios-app" \
  CODE_SIGNING_ALLOWED=NO \
  build
test -f "$derived_root/ios-app/Build/Products/Debug-iphonesimulator/Life Timer.app/LifeTimerBuildInfo.plist"
plutil -lint "$derived_root/ios-app/Build/Products/Debug-iphonesimulator/Life Timer.app/LifeTimerBuildInfo.plist" >/dev/null
xcodebuild -quiet \
  -project "Apps/iOS/Life Timer.xcodeproj" \
  -scheme "Life Timer WidgetsExtension" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived_root/ios-widget" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[8/9] Watch app simulator build"
xcodebuild -quiet \
  -project "Apps/watchOS/lifetimer.xcodeproj" \
  -scheme "lifetimer Watch App" \
  -configuration Debug \
  -sdk watchsimulator \
  -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$derived_root/watch-app" \
  CODE_SIGNING_ALLOWED=NO \
  build
test -f "$derived_root/watch-app/Build/Products/Debug-watchsimulator/lifetimer Watch App.app/LifeTimerBuildInfo.plist"
plutil -lint "$derived_root/watch-app/Build/Products/Debug-watchsimulator/lifetimer Watch App.app/LifeTimerBuildInfo.plist" >/dev/null

echo "[9/9] Watch complication simulator build"
xcodebuild -quiet \
  -project "Apps/watchOS/lifetimer.xcodeproj" \
  -scheme "lifetimer Complication" \
  -configuration Debug \
  -sdk watchsimulator \
  -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$derived_root/watch-complication" \
  CODE_SIGNING_ALLOWED=NO \
  build

git diff --check
echo "Life Timer repository verification passed. No deploy, install, signing, or live CloudKit operation was performed."
