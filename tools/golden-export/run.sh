#!/usr/bin/env bash
# One-time source golden export (specs/03 "Kaynak uyumluluğu", AC-3.1).
# Clones the salon repo at c2fe3fd into a temporary directory, checks that its
# templates are the copies in exercises/source/, runs export.ts twice and
# writes fixtures/source-golden/ only if both runs are byte-identical.
#
# Needs git, Node >= 22 and pnpm (the salon repo's packageManager). Not used by
# CI or the build (specs/02).
#
# usage: tools/golden-export/run.sh [--check]
#   --check  compare a fresh export with the committed fixtures/source-golden/
set -euo pipefail

COMMIT=c2fe3fd
REPO_URL=${GOLDEN_SOURCE_URL:-https://github.com/armagan-droid/gymspot.git}
TSX=tsx@4.23.15
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/fixtures/source-golden"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet "$REPO_URL" "$WORK/gymspot"
git -C "$WORK/gymspot" checkout --quiet "$COMMIT"
echo "source: $(git -C "$WORK/gymspot" log --oneline -1)"

# the golden refers to exercises/source/; it must be the commit's templates (AC-4.2)
for f in "$WORK"/gymspot/exercises/*.json; do
  cmp -s "$f" "$ROOT/exercises/source/$(basename "$f")" || { echo "exercises/source/$(basename "$f") differs from $COMMIT" >&2; exit 1; }
done

(cd "$WORK/gymspot" && pnpm install --frozen-lockfile --silent)
mkdir -p "$WORK/gymspot/golden-export"
cp "$ROOT/tools/golden-export/export.ts" "$WORK/gymspot/golden-export/"

for i in 1 2; do
  (cd "$WORK/gymspot/golden-export" && pnpm dlx --silent "$TSX" export.ts "$WORK/out$i" "$ROOT/exercises/source") 2>"$WORK/summary$i.txt"
done
diff -r "$WORK/out1" "$WORK/out2" >/dev/null || { echo "two runs differ: the export is not deterministic" >&2; exit 1; }
cp "$WORK/summary1.txt" "$WORK/out1/SUMMARY.txt"
(cd "$WORK/out1" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | xargs shasum -a 256 > SHA256SUMS)

if [[ "${1:-}" == "--check" ]]; then
  # superseded.json is added by this project later (specs/03); it is not an export output
  diff -r -x superseded.json "$WORK/out1" "$OUT" && echo "fixtures/source-golden matches a fresh export"
  exit
fi
[[ -e "$OUT" ]] && { echo "$OUT exists: the golden is generated once and never rewritten (specs/03); use --check" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
cp -R "$WORK/out1" "$OUT"
tail -1 "$WORK/summary1.txt"
echo "wrote $OUT (two runs identical)"
