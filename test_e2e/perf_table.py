#!/usr/bin/env python3
"""perf_table.py — turn run_perf.sh logs into the before-table.

Reads `PERF phase=...` lines and aggregates them per phase. Two tables:

  perf logs    one row per phase, in the order the run played them
  ablate logs  one row per ablation, each compared against the MEAN OF THE
               TWO BASELINES THAT BRACKET IT — a cost is only credited when
               the baselines either side of it agree, because on this machine
               the baseline itself wanders (a live game and a 6K compositor
               share the GPU).

The headline column is p5_ms, not mean_ms. Interference can only ever ADD
time to a frame, so the fastest frames are the uncontended ones: p5 measures
the game, the mean measures the machine. WORST_ms stays in the table because
it is what the player actually feels.

Usage:  perf_table.py <log> [<log> ...]
"""
import re
import sys
from collections import OrderedDict

FIELDS = ("frames", "min_ms", "p5_ms", "mean_ms", "median_ms", "p95_ms",
          "WORST_ms", "scene_ms_mean", "scene_ms_worst", "objs", "draws",
          "prims", "vram_mb", "nodes")


def parse(path):
    phases = OrderedDict()
    env = ""
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("PERF ENV"):
            env = line.strip()
            continue
        if not line.startswith("PERF phase="):
            continue
        kv = dict(re.findall(r"(\w+)=([-\w.]+)", line))
        ph = kv.get("phase", "?")
        if not ph:
            continue
        phases.setdefault(ph, []).append(kv)
    return env, phases


def agg(rows):
    out = {"secs": len(rows)}
    for f in FIELDS:
        vals = [float(r[f]) for r in rows if f in r]
        if not vals:
            out[f] = 0.0
            continue
        # min/p5 aggregate as a MINIMUM across seconds (the cleanest frame in
        # the phase); everything else as a mean, WORST as a maximum.
        if f in ("min_ms", "p5_ms"):
            out[f] = min(vals)
        elif f in ("WORST_ms", "scene_ms_worst"):
            out[f] = max(vals)
        else:
            out[f] = sum(vals) / len(vals)
    return out


HDR = (f'{"phase":<20}{"s":>3}{"fps@p5":>8}{"min":>7}{"p5":>7}{"mean":>7}'
       f'{"p95":>7}{"WORST":>8}{"scene":>7}{"draws":>7}{"prims":>10}{"objs":>7}')


def row(name, a):
    fps = 1000.0 / a["p5_ms"] if a["p5_ms"] else 0.0
    return (f'{name:<20}{a["secs"]:>3}{fps:>8.1f}{a["min_ms"]:>7.2f}'
            f'{a["p5_ms"]:>7.2f}{a["mean_ms"]:>7.2f}{a["p95_ms"]:>7.2f}'
            f'{a["WORST_ms"]:>8.2f}{a["scene_ms_mean"]:>7.3f}'
            f'{int(a["draws"]):>7}{int(a["prims"]):>10}{int(a["objs"]):>7}')


def med(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return 0.0
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def ablation_table(phases):
    abls = [k for k in phases if k.startswith("ABL-")]
    if not abls:
        return
    print()
    print("ABLATION — interleaved A/B, medians of 1-second samples taken seconds apart")
    print("  cost_ms = median(ablated frame ms) subtracted from median(baseline frame ms);")
    print("  spread = baseline max-min across its own samples — a cost smaller than")
    print("  its own baseline spread is NOISE, not a finding.")
    print(f'{"ablation":<16}{"base_ms":>9}{"abl_ms":>9}{"cost_ms":>9}{"cost_%":>8}'
          f'{"b_spread":>10}{"base_fps":>10}{"abl_fps":>9}{"d_draws":>9}'
          f'{"d_prims":>10}{"b_scene":>9}{"a_scene":>9}')
    for k in abls:
        nm = k[4:]
        bk = "BASE-" + nm
        if bk not in phases:
            continue
        bms = [float(r["mean_ms"]) for r in phases[bk]]
        ams = [float(r["mean_ms"]) for r in phases[k]]
        bfps = [float(r["fps"]) for r in phases[bk]]
        afps = [float(r["fps"]) for r in phases[k]]
        bdr = med([float(r["draws"]) for r in phases[bk]])
        adr = med([float(r["draws"]) for r in phases[k]])
        bpr = med([float(r["prims"]) for r in phases[bk]])
        apr = med([float(r["prims"]) for r in phases[k]])
        bsc = med([float(r["scene_ms_mean"]) for r in phases[bk]])
        asc = med([float(r["scene_ms_mean"]) for r in phases[k]])
        b, a = med(bms), med(ams)
        spread = max(bms) - min(bms) if bms else 0.0
        pct = 100.0 * (b - a) / b if b else 0.0
        # THE 60 Hz CEILING. A screen-sized window on macOS gets its
        # presentation hard-synced to the display no matter what
        # --disable-vsync says; every frame then measures 16.66-16.67 ms
        # whatever is in it. In the 6K sweep, hiding all 32 pieces (-660 draw
        # calls, -970 k primitives) moved the number by 0.00 ms — that is not
        # "the pieces are free", that is the clock being a wall. Any row whose
        # BASELINE sits on the ceiling carries no information about cost.
        flag = ""
        if abs(b - 16.667) < 0.35:
            flag = "  <-- BASELINE AT 60Hz CEILING: no information"
        elif abs(a - 16.667) < 0.35:
            flag = "  <-- ablated arm hit the ceiling: cost is a LOWER bound"
        print(f'{nm:<16}{b:>9.2f}{a:>9.2f}{b - a:>9.2f}{pct:>8.1f}{spread:>10.2f}'
              f'{med(bfps):>10.1f}{med(afps):>9.1f}{int(bdr - adr):>9}'
              f'{int(bpr - apr):>10}{bsc:>9.3f}{asc:>9.3f}{flag}')


def main():
    for path in sys.argv[1:]:
        env, phases = parse(path)
        print("=" * 118)
        print(path.split("/")[-1])
        if env:
            print(env)
        print(HDR)
        for k, v in phases.items():
            if k.startswith("BASE-") or k.startswith("ABL-") or k == "warm":
                continue
            print(row(k, agg(v)))
        ablation_table(phases)


if __name__ == "__main__":
    main()
