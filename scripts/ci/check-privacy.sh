#!/usr/bin/env bash
# specs/10 privacy checks on the sources (Linux CI):
# - AC-10.5: every required-reason API category used in App/ or a package's
#   Sources/ is declared in App/Resources/PrivacyInfo.xcprivacy; no tracking.
# - AC-10.2: no third-party dependency: no remote Swift package in the
#   project or in any Package.swift (local path packages only).
# - AC-10.1 (static side): no networking API or web address in the code.
set -euo pipefail
cd "$(dirname "$0")/../.."
manifest=App/Resources/PrivacyInfo.xcprivacy
fail=0
err() { echo "privacy: $*" >&2; fail=1; }

[[ -f "$manifest" ]] || { echo "privacy: $manifest is missing" >&2; exit 1; }
grep -A1 "<key>NSPrivacyTracking</key>" "$manifest" | grep -q "<false/>" || err "NSPrivacyTracking must be false"

sources=$(find App Packages/*/Sources -name '*.swift' -not -path '*/SoloEngineTesting/*')
uses() { grep -lE "$1" $sources 2>/dev/null | head -1; }
check() {  # category, pattern
  local file
  file=$(uses "$2") || true
  if [[ -n "$file" ]] && ! grep -q "<string>NSPrivacyAccessedAPICategory$1</string>" "$manifest"; then
    err "$file uses a $1 API; declare NSPrivacyAccessedAPICategory$1 with its reason"
  fi
}
check UserDefaults 'UserDefaults|@AppStorage|@SceneStorage'
check FileTimestamp 'creationDate|modificationDate|contentModificationDate|attributesOfItem|getattrlist|[^a-zA-Z]stat\('
check SystemBootTime 'systemUptime|mach_absolute_time|mach_continuous_time'
check DiskSpace 'volumeAvailableCapacity|systemFreeSize|statfs'
check ActiveKeyboards 'activeInputModes'

grep -q XCRemoteSwiftPackageReference GymSpotSolo.xcodeproj/project.pbxproj && err "the Xcode project has a remote Swift package (specs/10)"
for p in Packages/*/Package.swift; do
  grep -qE '\.package\(\s*(name:[^)]*)?url:' "$p" && err "$p depends on a remote package (specs/10)"
done

net=$(grep -nE 'URLSession|NWConnection|NWPathMonitor|NSURLConnection|CFNetwork|"https?://' $sources || true)
[[ -z "$net" ]] || err "networking in the code (specs/10 rule 2):"$'\n'"$net"

[[ $fail == 0 ]] && echo "privacy checks passed"
exit $fail
