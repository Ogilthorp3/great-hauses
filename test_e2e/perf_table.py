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
          "WORST_ms", "scene_ms_mean", "scene_ms_worst", "gpu_ms",
          "gpu_ms_worst", "rcpu_ms", "drops", "drops50", "objs", "draws",
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
        elif f in ("WORST_ms", "scene_ms_worst", "gpu_ms_worst"):
            out[f] = max(vals)
        else:
            out[f] = sum(vals) / len(vals)
    return out


## DROPS is the headline, not mean_ms. `--disable-vsync` does not defeat
## macOS presentation pacing: an EMPTY scene renders 600 frames in 9.921 s
## (60.5 fps, 16.535 ms/frame) on this machine, so the frame clock in a
## visible window measures the display and nothing else. mean_ms therefore
## sits at ~16.6 whatever the scene contains, and it is printed only so the
## wall stays visible. What survives the wall is a MISSED vsync: `drops` =
## frames >= 25 ms in that second. That is the stutter the player feels, and
## it is the number an optimization has to move.
HDR = (f'{"phase":<20}{"s":>3}{"drops/s":>8}{"WORST":>8}{"mean":>7}{"fps":>6}'
       f'{"rCPU":>7}{"scene":>7}{"draws":>7}{"prims":>10}{"objs":>7}')


def row(name, a):
    fps = 1000.0 / a["mean_ms"] if a["mean_ms"] else 0.0
    return (f'{name:<20}{a["secs"]:>3}{a["drops"]:>8.2f}'
            f'{a["WORST_ms"]:>8.2f}{a["mean_ms"]:>7.2f}{fps:>6.1f}'
            f'{a["rcpu_ms"]:>7.2f}{a["scene_ms_mean"]:>7.3f}'
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
    print(f'{"ablation":<16}{"b_drops":>9}{"a_drops":>9}{"d_drops":>9}'
          f'{"base_ms":>9}{"abl_ms":>9}{"cost_ms":>9}{"b_spread":>10}'
          f'{"d_draws":>9}{"d_prims":>10}')
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
        bdp = med([float(r.get("drops", 0.0)) for r in phases[bk]])
        adp = med([float(r.get("drops", 0.0)) for r in phases[k]])
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
        # The frame clock is pinned to the refresh rate on this machine, so a
        # baseline sitting on 16.67 ms says nothing about cost — but the GPU
        # timer underneath it still does. Flag the wall, rank on dGPU_ms.
        flag = ""
        if abs(b - 16.667) < 0.35:
            flag = "  (mean at the 60Hz wall: read d_drops / d_prims)"
        elif spread > abs(b - a):
            flag = "  <-- cost below its own baseline spread: NOISE"
        print(f'{nm:<16}{bdp:>9.2f}{adp:>9.2f}{bdp - adp:>9.2f}'
              f'{b:>9.2f}{a:>9.2f}{b - a:>9.2f}{spread:>10.2f}'
              f'{int(bdr - adr):>9}{int(bpr - apr):>10}{flag}')


def main():
    for path in sys.argv[1:]:
        env, phases = parse(path)
        print("=" * 118)
        print(path.split("/")[-1])
        if env:
            print(env)
        print(HDR)
        tot_drops = 0.0
        tot_frames = 0.0
        idle_drops = 0.0
        idle_secs = 0
        for k, v in phases.items():
            if k.startswith("BASE-") or k.startswith("ABL-") or k == "warm":
                continue
            print(row(k, agg(v)))
            for r in v:
                tot_drops += float(r.get("drops", 0.0))
                tot_frames += float(r.get("frames", 0.0))
                if k.startswith("idle"):
                    idle_drops += float(r.get("drops", 0.0))
                    idle_secs += 1
        if tot_frames:
            print(f'  TOTAL dropped frames {int(tot_drops)} / {int(tot_frames)} '
                  f'({100.0 * tot_drops / tot_frames:.2f}%)   '
                  f'IDLE drops/s {idle_drops / max(idle_secs, 1):.2f}')
        ablation_table(phases)


if __name__ == "__main__":
    main()
