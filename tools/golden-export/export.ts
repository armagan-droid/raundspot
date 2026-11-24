// One-time source golden export (specs/03 "Kaynak uyumluluğu", AC-3.1).
// Runs inside a checkout of the salon repo at c2fe3fd (run.sh copies it there)
// and writes fixtures/source-golden/: engine cases, their landmark sequences and
// the expression golden. Deterministic: seeded generators only, no clock.
//
// usage: tsx export.ts <out-dir> <rule-pack-dir>

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { EngineEvent, Frame, LandmarkSequence } from "@gymspot/shared";
import {
  ExerciseEngine,
  type ExerciseEngineOptions,
  type ExerciseSetup,
  ExpressionError,
  type LoadedRulePack,
  evaluate,
  loadRulePack,
  parseCheck,
  parseExpression,
  parseReadyPose,
} from "../packages/engine/src/index";
import { evaderSequence, fighterSequence, mirrorFrame, pressSequence, pushupSequence, squatSequence } from "../packages/engine/src/testing/index";

const SOURCE = { repo: "armagan-droid/gymspot", commit: "c2fe3fd" } as const;
const METRICS_EVERY = 10;
const [outDir, packDir] = process.argv.slice(2);
if (!outDir || !packDir) throw new Error("usage: export.ts <out-dir> <rule-pack-dir>");

// ------------------------------------------------------------ cases

interface Case {
  pack: string;
  name: string;
  setup: ExerciseSetup;
  options?: ExerciseEngineOptions;
  cuesEnabled?: { fromT: number; enabled: boolean }[];
  seq: () => LandmarkSequence;
  /** Another case of the same template whose stored sequence this one reuses. */
  sharesSequenceOf?: string;
}

/** 5 decimals, as the Swift snapshots store them; the engine then runs on the stored values. */
const r5 = (x: number) => Math.round(x * 1e5) / 1e5;
function rounded(seq: LandmarkSequence): LandmarkSequence {
  const p = (l: Frame["image"][number]) => ({ x: r5(l.x), y: r5(l.y), z: r5(l.z), visibility: r5(l.visibility) });
  return { ...seq, frames: seq.frames.map((f) => ({ t: f.t, image: f.image.map(p), world: f.world.map(p) })) };
}

/** Every landmark below `visibility` from `fromMs` for `forMs` (tracking loss or poor light). */
function dim(seq: LandmarkSequence, fromMs: number, forMs: number, visibility: number): LandmarkSequence {
  const d = (f: Frame): Frame =>
    f.t < fromMs || f.t >= fromMs + forMs
      ? f
      : { t: f.t, image: f.image.map((l) => ({ ...l, visibility })), world: f.world.map((l) => ({ ...l, visibility })) };
  return { ...seq, frames: seq.frames.map(d) };
}

const mirrored = (seq: LandmarkSequence): LandmarkSequence => ({ ...seq, frames: seq.frames.map(mirrorFrame) });

const FRONT: ExerciseSetup = { view: "front", nearSide: "left" };
const SIDE_L: ExerciseSetup = { view: "side", nearSide: "left" }; // facing right: left side near the camera
const SIDE_R: ExerciseSetup = { view: "side", nearSide: "right" }; // facing left
const AMBIGUOUS: ExerciseSetup = { view: "ambiguous", nearSide: "left" };

const cases: Case[] = [];
const add = (pack: string, name: string, setup: ExerciseSetup, seq: () => LandmarkSequence, extra: Partial<Case> = {}) =>
  cases.push({ pack, name, setup, seq, ...extra });

type Faulty = (() => LandmarkSequence) | { seq: () => LandmarkSequence; setup: ExerciseSetup };

/** The six kinds every template gets (specs/03 "Kapsam"), from template-specific clean and faulty sequences. */
function standard(
  pack: string,
  setup: ExerciseSetup,
  clean: (seed: number) => LandmarkSequence,
  faulty: Faulty[],
  oscillation: () => LandmarkSequence,
) {
  const other = setup.view === "side" ? (setup.nearSide === "left" ? SIDE_R : SIDE_L) : setup;
  add(pack, "clean_seed1", setup, () => clean(1));
  add(pack, "clean_noisy_seed7", setup, () => clean(7));
  // the other side of the body near the camera (side view) or a mirrored picture (front view:
  // a one-sided slip then goes the other way)
  add(pack, "mirrored_seed3", other, () => mirrored(clean(3)));
  faulty.forEach((f, i) =>
    typeof f === "function" ? add(pack, `faulty_${i + 1}`, setup, f) : add(pack, `faulty_${i + 1}`, f.setup, f.seq),
  );
  const first = faulty[0] as () => LandmarkSequence;
  const shared = { sharesSequenceOf: "faulty_1" };
  add(pack, "faulty_1_cues_off_midway", setup, first, { ...shared, cuesEnabled: [{ fromT: 0, enabled: true }, { fromT: 4500, enabled: false }, { fromT: 7000, enabled: true }] });
  add(pack, "faulty_1_no_safety_pause", setup, first, { ...shared, options: { safetyPause: false } });
  add(pack, "faulty_1_ambiguous_view", { ...AMBIGUOUS, nearSide: setup.nearSide }, first, shared);
  add(pack, "oscillation", setup, oscillation);
  add(pack, "tracking_lost", setup, () => dim(clean(5), 3500, 1800, 0.05));
  add(pack, "low_visibility", setup, () => dim(clean(6), 3000, 2500, 0.45));
}

const noisy = (seed: number) => (seed === 1 ? 0.002 : 0.006);
const FPS = 15;

// squat (front + side)
{
  const clean = (seed: number) =>
    squatSequence({ view: "front", fps: FPS, seed, noise: noisy(seed), reps: [{ kneeAngle: 88 }, { kneeAngle: 92 }, { kneeAngle: 85 }] });
  standard(
    "squat",
    FRONT,
    clean,
    [
      () => squatSequence({ view: "front", fps: FPS, seed: 11, noise: 0.003, reps: [{ kneeAngle: 90, valgus: 0.25 }, { kneeAngle: 90, valgus: 0.25 }, { kneeAngle: 90 }] }),
      () => squatSequence({ view: "front", fps: FPS, seed: 12, noise: 0.003, reps: [{ kneeAngle: 120 }, { kneeAngle: 104 }, { kneeAngle: 90 }] }),
      { setup: SIDE_L, seq: () => squatSequence({ view: "side", fps: FPS, seed: 13, noise: 0.003, reps: [{ kneeAngle: 85, torsoLean: 65 }, { kneeAngle: 85, torsoLean: 65 }, { kneeAngle: 85 }] }) },
    ],
    () => squatSequence({ view: "front", fps: 20, seed: 14, noise: 0.006, reps: [{ kneeAngle: 101 }, { kneeAngle: 99 }, { kneeAngle: 150 }, { kneeAngle: 100 }] }),
  );
  add("squat", "side_clean", SIDE_L, () => squatSequence({ view: "side", fps: FPS, seed: 15, noise: 0.003, reps: [{ kneeAngle: 85 }, { kneeAngle: 88 }] }));
}

// push-up (side)
{
  const clean = (seed: number) => pushupSequence({ fps: FPS, seed, noise: noisy(seed), reps: [{ elbowAngle: 80 }, { elbowAngle: 85 }, { elbowAngle: 78 }] });
  standard(
    "pushup",
    SIDE_L,
    clean,
    [
      () => pushupSequence({ fps: FPS, seed: 21, noise: 0.002, reps: [{ elbowAngle: 80, hipOffset: -0.1 }, { elbowAngle: 80, hipOffset: -0.1 }, { elbowAngle: 80 }] }),
      () => pushupSequence({ fps: FPS, seed: 22, noise: 0.002, reps: [{ elbowAngle: 80, hipOffset: 0.12 }, { elbowAngle: 100 }, { elbowAngle: 120 }] }),
      () => pushupSequence({ fps: FPS, seed: 23, noise: 0.002, reps: [{ elbowAngle: 94 }, { elbowAngle: 96 }, { elbowAngle: 80, hipOffset: -0.08 }] }),
    ],
    () => pushupSequence({ fps: 20, seed: 24, noise: 0.006, reps: [{ elbowAngle: 96 }, { elbowAngle: 94 }, { elbowAngle: 140 }] }),
  );
}

// shoulder press (front + side)
{
  const clean = (seed: number) => pressSequence({ view: "front", fps: FPS, seed, noise: noisy(seed), reps: [{ elbowAngle: 175 }, { elbowAngle: 172 }, { elbowAngle: 176 }] });
  standard(
    "shoulder_press",
    FRONT,
    clean,
    [
      () => pressSequence({ view: "front", fps: FPS, seed: 31, noise: 0.002, reps: [{ elbowAngle: 175, elbowAngleRight: 140 }, { elbowAngle: 175, elbowAngleRight: 140 }, { elbowAngle: 175 }] }),
      { setup: SIDE_L, seq: () => pressSequence({ view: "side", fps: FPS, seed: 32, noise: 0.002, reps: [{ elbowAngle: 175, torsoLean: 20 }, { elbowAngle: 175, torsoLean: 20 }, { elbowAngle: 175 }] }) },
      () => pressSequence({ view: "front", fps: FPS, seed: 33, noise: 0.002, reps: [{ elbowAngle: 150 }, { elbowAngle: 158 }, { elbowAngle: 175 }] }),
    ],
    () => pressSequence({ view: "front", fps: 20, seed: 34, noise: 0.006, reps: [{ elbowAngle: 161 }, { elbowAngle: 159 }, { elbowAngle: 120 }] }),
  );
}

// head movement (front)
const slipTo = (slip: number) => ({ slip, durationMs: 700 });
const neck = { slip: 8, neckTilt: 60, durationMs: 700 };
for (const [pack, dir] of [["slip", 1], ["slip_left", 1], ["slip_right", -1]] as const) {
  const s = (deg: number) => slipTo(dir * deg);
  const clean = (seed: number) =>
    evaderSequence({ exerciseId: pack, fps: FPS, seed, noise: noisy(seed), reps: pack === "slip" ? [s(25), s(-25), s(25)] : [s(25), s(27), s(24)] });
  standard(
    pack,
    FRONT,
    clean,
    [
      () => evaderSequence({ exerciseId: pack, fps: FPS, seed: 41, noise: 0.002, reps: [{ ...neck, slip: dir * 8, neckTilt: dir * 60 }, { ...neck, slip: dir * 8, neckTilt: dir * 60 }, s(25)] }),
      () => evaderSequence({ exerciseId: pack, fps: FPS, seed: 42, noise: 0.002, dropSide: "right", reps: [{ ...s(25), guardDrop: 1, durationMs: 1200 }, s(25), { ...s(25), guardDrop: 1, durationMs: 1200 }] }),
      () => evaderSequence({ exerciseId: pack, fps: FPS, seed: 43, noise: 0.002, reps: [s(15), s(25), { kneeAngle: 110, torsoLean: 25, durationMs: 900 }] }),
    ],
    () => evaderSequence({ exerciseId: pack, fps: 20, seed: 44, noise: 0.008, reps: [s(19), s(18), s(20), s(8)] }),
  );
}
{
  const deep = { kneeAngle: 110, torsoLean: 25, durationMs: 900 };
  const clean = (seed: number) => evaderSequence({ exerciseId: "duck", fps: FPS, seed, noise: noisy(seed), reps: [deep, { ...deep, kneeAngle: 105 }, deep] });
  standard(
    "duck",
    FRONT,
    clean,
    [
      () => evaderSequence({ exerciseId: "duck", fps: FPS, seed: 51, noise: 0.002, reps: [{ ...deep, guardDrop: 1, durationMs: 1400 }, { ...deep, guardDrop: 1, durationMs: 1400 }, deep] }),
      () => evaderSequence({ exerciseId: "duck", fps: FPS, seed: 52, noise: 0.002, dropSide: "left", reps: [{ kneeAngle: 125, torsoLean: 15, durationMs: 900 }, { ...deep, guardDrop: 1, durationMs: 1400 }, slipTo(30)] }),
      () => evaderSequence({ exerciseId: "duck", fps: FPS, seed: 53, noise: 0.002, reps: [{ ...deep, durationMs: 200 }, deep, { ...deep, durationMs: 3500 }] }),
    ],
    () => evaderSequence({ exerciseId: "duck", fps: 20, seed: 54, noise: 0.008, reps: [{ kneeAngle: 118, torsoLean: 20, durationMs: 900 }, { kneeAngle: 120, torsoLean: 18, durationMs: 900 }, deep] }),
  );
}

// fighting techniques (side)
const fast = { durationMs: 600 };
const fighter = (pack: string, seed: number, noise: number, reps: object[], extra: object = {}) =>
  fighterSequence({ exerciseId: pack, fps: FPS, seed, noise, reps: reps as never, ...extra });
for (const [pack, kick, lean] of [
  ["teep", { hipFlex: 90, kneeAngle: 170, torsoLean: 15 }, 45],
  ["mae_geri", { hipFlex: 95, kneeAngle: 175 }, 35],
  ["knee_strike", { hipFlex: 105, kneeAngle: 50 }, 45],
] as const) {
  const k = { ...kick, ...fast };
  standard(
    pack,
    SIDE_L,
    (seed) => fighter(pack, seed, noisy(seed), [k, k, k]),
    [
      () => fighter(pack, 61, 0.002, [{ ...k, torsoLean: lean }, { ...k, torsoLean: lean }, k]),
      () => fighter(pack, 62, 0.002, [{ ...k, guardDrop: 1, durationMs: 1200 }, k, { ...k, guardDrop: 1, durationMs: 1200 }]),
      () => fighter(pack, 63, 0.002, [{ ...k, hipFlex: kick.hipFlex - 25 }, { ...k, durationMs: 150 }, k], { kickSide: "left" }),
    ],
    () => fighter(pack, 64, 0.008, [{ ...k, hipFlex: kick.hipFlex - 8 }, { ...k, hipFlex: kick.hipFlex - 6 }, k], { fps: 20 }),
  );
}
{
  const p = { punchElbow: 175, durationMs: 400 };
  standard(
    "straight_punch",
    SIDE_L,
    (seed) => fighter("straight_punch", seed, noisy(seed), [p, p, p, p]),
    [
      () => fighter("straight_punch", 71, 0.002, [{ ...p, torsoLean: 25 }, { ...p, torsoLean: 25 }, p]),
      () => fighter("straight_punch", 72, 0.002, [{ ...p, guardDrop: 1, durationMs: 900 }, p, { ...p, guardDrop: 1, durationMs: 900 }]),
      () => fighter("straight_punch", 73, 0.002, [{ punchElbow: 110, durationMs: 400 }, p, { guardDrop: 1, punchElbow: 35 }], { punchSide: "left" }),
    ],
    () => fighter("straight_punch", 74, 0.008, [{ punchElbow: 128, durationMs: 400 }, { punchElbow: 132, durationMs: 400 }, p], { fps: 20 }),
  );
}

// ------------------------------------------------------------ run

/** Smoothed metric values as the engine hands them to the rep counter, and the counter's state. */
function run(loaded: LoadedRulePack, seq: LandmarkSequence, c: Case) {
  const engine = new ExerciseEngine(loaded, c.setup, c.options);
  const internals = engine as unknown as {
    computer: { order: readonly string[] };
    counter: { state: string; push: (t: number, v: Record<string, number>) => unknown };
  };
  const order = internals.computer.order;
  let lastValues: Record<string, number> = {};
  const push = internals.counter.push.bind(internals.counter);
  internals.counter.push = (t, v) => {
    lastValues = v;
    return push(t, v);
  };
  const switches = [...(c.cuesEnabled ?? [])].sort((a, b) => a.fromT - b.fromT);
  const events: Record<string, unknown>[] = [];
  const values: { frame: number; values: Record<string, number | null> }[] = [];
  const repStates: string[] = [];
  seq.frames.forEach((frame, i) => {
    while (switches.length > 0 && frame.t >= switches[0]!.fromT) engine.setCuesEnabled(switches.shift()!.enabled);
    for (const e of engine.push(frame) as EngineEvent[]) events.push({ frame: i, t: frame.t, ...e });
    if (i % METRICS_EVERY === 0) {
      const row: Record<string, number | null> = {};
      for (const name of order) {
        const v = lastValues[name];
        row[name] = typeof v === "number" && !Number.isNaN(v) ? v : null;
      }
      values.push({ frame: i, values: row });
    }
    repStates.push(internals.counter.state);
  });
  return { events, metrics: { every: METRICS_EVERY, values }, repStates };
}

const write = (path: string, text: string) => {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, text);
};

const packs = new Map<string, LoadedRulePack>();
const summary: string[] = [];
for (const c of cases) {
  let loaded = packs.get(c.pack);
  if (!loaded) {
    loaded = loadRulePack(JSON.parse(readFileSync(join(packDir, `${c.pack}.json`), "utf8")));
    packs.set(c.pack, loaded);
  }
  const sequence = `sequences/${c.pack}/${c.sharesSequenceOf ?? c.name}.json`;
  const seq = rounded(c.seq());
  const expected = run(loaded, seq, c);
  const golden = {
    goldenVersion: 1,
    source: SOURCE,
    rulePack: loaded.pack.id,
    rulePackVersion: loaded.pack.version,
    setup: c.setup,
    options: { safetyPause: c.options?.safetyPause ?? true },
    cuesEnabled: c.cuesEnabled ?? [],
    sequence,
    expected,
  };
  if (!c.sharesSequenceOf) write(join(outDir, sequence), JSON.stringify(seq) + "\n");
  write(join(outDir, `${c.pack}.${c.name}.json`), JSON.stringify(golden, null, 1) + "\n");
  const kinds = expected.events.map((e) => (e.type === "REP_COMPLETED" ? `${e.outcome}${(e.faults as string[]).length ? `[${e.faults}]` : ""}` : e.type === "FAULT_DETECTED" || e.type === "SAFETY_PAUSE" ? `${e.type}:${e.faultId}` : e.type)).filter((k) => k !== "REP_STARTED");
  summary.push(`${c.pack}.${c.name}: ${kinds.join(" ")}`);
}

// ------------------------------------------------------------ expression golden

const METRICS = ["knee_angle_avg", "torso_lean", "knee_valgus_l", "knee_valgus_r", "hip_offset", "constructor"];
type Form = "expression" | "check" | "readyPose";
const values: Record<string, number | null>[] = [
  {},
  { torso_lean: 11, hip_offset: -0.06, knee_angle_avg: 165, knee_valgus_l: 0.05, knee_valgus_r: 0.2 },
  { torso_lean: 10, hip_offset: 0, knee_angle_avg: 100, knee_valgus_l: 0.2, knee_valgus_r: 0.05 },
  { torso_lean: 0, hip_offset: 0.1 },
  { torso_lean: 2, knee_valgus_l: 0.5 },
  { torso_lean: null, hip_offset: 1.5, knee_angle_avg: -0 },
  { torso_lean: -3.5, hip_offset: -1e-9, knee_angle_avg: 170, knee_valgus_l: null, knee_valgus_r: 0.16, constructor: 1 },
];
const sources: [Form, string][] = [
  ...[
    "knee_angle_avg > 160",
    "hip_offset < -0.06",
    "torso_lean > 10",
    "torso_lean >= 10",
    "torso_lean < 10",
    "torso_lean <= 10",
    "torso_lean > 1 or torso_lean > 2 and torso_lean > 3",
    "not torso_lean > 1 and torso_lean > 2",
    "(torso_lean > 1 or torso_lean > 2) and torso_lean > 3",
    "torso_lean > 1 and hip_offset > 1",
    "torso_lean > 1 or hip_offset > 1",
    "not torso_lean > 1",
    "not not torso_lean > 1",
    "abs(hip_offset) > 0.05",
    "max(knee_valgus_l, knee_valgus_r) > 0.15",
    "min(knee_valgus_l, knee_valgus_r) > 0.1",
    "avg(knee_valgus_l, knee_valgus_r) > 0.1",
    "avg(min(torso_lean, 3), 4) < 5",
    "max(knee_valgus_l, knee_valgus_r, hip_offset, 0.12) >= 0.15",
    "abs(-1) > hip_offset",
    "0.5 < knee_valgus_r",
    "  torso_lean>=1and(not torso_lean<2)",
    "knee_valgus_l > 0.15 or knee_valgus_r > 0.15",
    "constructor > 0",
    "torso_lean > .5",
    "torso_lean > 5.",
    "torso_lean > 1e3",
    "torso_lean > -0",
    // errors
    "",
    "torso_lean",
    "torso_lean >",
    "> 1",
    "torso_lean > 1 >",
    "torso_lean < 1 < 2",
    "(torso_lean > 1",
    "torso_lean > 1)",
    "torso_lean > 1 and",
    "abs() > 1",
    "abs(torso_lean, hip_offset) > 1",
    "avg(torso_lean,) > 1",
    "min(torso_lean) > 1",
    "1.5.2 > 1",
    "- 1 > torso_lean",
    "torso_lean > 1 & 2",
    "hip_angle > 1",
    "sqrt(torso_lean) > 1",
    "knee_angle_avg > 165 for 1500ms",
    'eval("1")',
    "eval(1) > 0",
    "Function('return 1')() > 0",
    "process.exit(1)",
    "torso_lean > 1; process.exit(1)",
    "__proto__ > 0",
    "torso_lean.constructor > 0",
    "torso_lean['x'] > 0",
    "`x` > 0",
    '"1" > 0',
    "torso_lean == 1",
    "torso_lean = 1",
    "torso_lean != 1",
    "!(torso_lean > 1)",
    "torso_lean > 1 && torso_lean < 2",
    "() => 1",
    "TORSO_LEAN > 1",
    "torso_lean > 1 and or hip_offset > 1",
    "not > 1",
    "and > 1",
    "torso_lean > abs",
    "torso_lean ≥ 1",
    "torso_lean > 1 ğ",
  ].map((s): [Form, string] => ["expression", s]),
  ...[
    "at_turn: knee_angle_avg > 100",
    "during_rep: torso_lean > 1",
    "at_start: torso_lean > 1",
    "during_rep: knee_valgus_l > 0.15 or knee_valgus_r > 0.15",
    "at_phase_bottom: torso_lean > 1",
    "torso_lean > 1",
    "at_turn torso_lean > 1",
    "at_turn:",
    ": torso_lean > 1",
    "at_turn: torso_lean > 1 for 100ms",
  ].map((s): [Form, string] => ["check", s]),
  ...[
    "knee_angle_avg > 165 for 1500ms",
    "torso_lean < 10 and hip_offset > -0.3 for 1000ms",
    "knee_angle_avg > 165",
    "knee_angle_avg > 165 for 1.5ms",
    "knee_angle_avg > 165 for 1500",
    "knee_angle_avg > 165 for -5ms",
    "knee_angle_avg > 165 for 0ms",
    "knee_angle_avg > 165 for 1500 ms",
    "knee_angle_avg > 165 for 1500ms and torso_lean > 1",
    "knee_angle_avg > 165 for ms",
  ].map((s): [Form, string] => ["readyPose", s]),
];

const metricSet = new Set(METRICS);
const expressions = sources.flatMap(([form, src]) =>
  [true, false].map((restricted) => {
    const options = restricted ? { metrics: metricSet } : {};
    const entry: Record<string, unknown> = { form, src, metrics: restricted ? METRICS : null };
    try {
      const parsed =
        form === "check" ? parseCheck(src, options) : form === "readyPose" ? parseReadyPose(src, options) : { expr: parseExpression(src, options) };
      if ("position" in parsed) entry.position = parsed.position;
      if ("durationMs" in parsed) entry.durationMs = parsed.durationMs;
      entry.results = values.map((v) => {
        const input: Record<string, number> = {};
        for (const [k, x] of Object.entries(v)) input[k] = x === null ? NaN : x;
        const truth = evaluate(parsed.expr, input);
        return { values: v, truth: truth === undefined ? "unknown" : truth };
      });
    } catch (e) {
      if (!(e instanceof ExpressionError)) throw e;
      entry.error = { reason: e.reason, column: e.column };
    }
    return entry;
  }),
);
write(join(outDir, "expressions.json"), JSON.stringify({ goldenVersion: 1, source: SOURCE, nullMeans: "NaN", expressions }, null, 1) + "\n");

process.stderr.write(summary.join("\n") + `\n${cases.length} engine cases, ${expressions.length} expression entries\n`);
