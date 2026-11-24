# golden-export

One-time export of the source golden (`specs/03` "Kaynak uyumluluğu", AC-3.1). It ran once, on 2026-11-24. Its output, `fixtures/source-golden/`, is never rewritten. Node and this script are not part of CI or the build (`specs/02`).

```sh
tools/golden-export/run.sh --check   # a fresh export equals the committed files
```

`run.sh` does the following:
1. Clones the salon repo into a temporary directory and checks out `c2fe3fd`.
2. Checks that the clone's `exercises/*.json` are byte-equal to `exercises/source/`.
3. Runs `pnpm install --frozen-lockfile`, then runs `export.ts` twice with `tsx` (pinned in `run.sh`).
4. Accepts the result only if both runs give the same bytes, then writes `SHA256SUMS`.

Without `--check` it refuses to write over an existing `fixtures/source-golden/`.

The script needs git, Node ≥ 22 and pnpm 12 (the salon repo's `packageManager`). It does not install them anywhere permanent; a Node in a temporary directory on `PATH` is enough.

`export.ts` loads the source engine through relative imports, because `run.sh` copies it into the clone. It uses the clone's `@gymspot/engine/testing` generators. The engine's internals (`computer.order`, `counter`) are read only to record the smoothed metric values and rep states.
