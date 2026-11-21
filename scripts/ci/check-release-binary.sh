#!/usr/bin/env bash
# AC-2.3: the App Store binary (GymSpotSolo, Release) contains no SoloRecording
# symbols. Control: the Beta binary (GymSpotSoloBeta, Beta) does, so the check
# cannot pass vacuously.
# AC-2.5: neither Info.plist declares NSMicrophoneUsageDescription.
#
# usage: scripts/ci/check-release-binary.sh <derived-data-dir>
set -euo pipefail

DD="${1:?usage: $0 <derived-data-dir>}"
build() {
  xcodebuild build -project GymSpotSolo.xcodeproj -scheme "$1" -configuration "$2" \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO -quiet
}

build GymSpotSolo Release
build GymSpotSoloBeta Beta

RELEASE_APP="$DD/Build/Products/Release-iphonesimulator/GymSpotSolo.app"
BETA_APP="$DD/Build/Products/Beta-iphonesimulator/GymSpotSoloBeta.app"

count_symbols() { (nm -a "$1" 2>/dev/null || true) | grep -c 'SoloRecording' || true; }

release_count=$(count_symbols "$RELEASE_APP/GymSpotSolo")
beta_count=$(count_symbols "$BETA_APP/GymSpotSoloBeta")
echo "SoloRecording symbols: Release=$release_count Beta=$beta_count"

status=0
if [ "$release_count" -ne 0 ]; then
  echo "FAIL AC-2.3: Release binary contains SoloRecording symbols"; status=1
fi
if [ "$beta_count" -eq 0 ]; then
  echo "FAIL control: Beta binary has no SoloRecording symbols (check would be vacuous)"; status=1
fi
for app in "$RELEASE_APP" "$BETA_APP"; do
  if /usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$app/Info.plist" >/dev/null 2>&1; then
    echo "FAIL AC-2.5: $(basename "$app") declares NSMicrophoneUsageDescription"; status=1
  fi
done
[ "$status" -eq 0 ] && echo "OK: AC-2.3, AC-2.5"
exit "$status"
