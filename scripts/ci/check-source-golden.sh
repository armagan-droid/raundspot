#!/usr/bin/env bash
# AC-3.7: the source golden is never changed or deleted (specs/03). Every file
# listed in SHA256SUMS must be there unchanged, the list itself is pinned, and
# the only file that may be added is superseded.json.
set -euo pipefail
export LC_ALL=C

MANIFEST_SHA256=2c7486aa2c1d8df357a476901edf8ce35f7affce6bcb3e623617904ae641ceba
cd "$(dirname "$0")/../../fixtures/source-golden"

sum() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

[[ "$(sum SHA256SUMS | cut -d' ' -f1)" == "$MANIFEST_SHA256" ]] || { echo "fixtures/source-golden/SHA256SUMS changed" >&2; exit 1; }
sum -c --quiet SHA256SUMS

extra=$(comm -13 <(cut -d' ' -f3- SHA256SUMS | sort) \
  <(find . -type f ! -name SHA256SUMS ! -name superseded.json | sed 's|^\./||' | sort))
[[ -z "$extra" ]] || { echo "files added to fixtures/source-golden (only superseded.json may be):" >&2; echo "$extra" >&2; exit 1; }
echo "source golden unchanged ($(wc -l < SHA256SUMS | tr -d ' ') files)"
