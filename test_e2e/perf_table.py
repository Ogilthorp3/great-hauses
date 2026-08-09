#!/usr/bin/env python3
"""perf_table.py — turn run_perf.sh logs into a table, and fail on a regression.

READ THIS BEFORE QUOTING ANY NUMBER OUT OF THESE LOGS
=====================================================

A SECOND GODOT PROCESS ON THIS GPU INVALIDATES EVERY MILLISECOND BELOW.
Not "adds noise" — invalidates. Measured on this machine, same binary, same
scene, same window, one variable:

    owner's live game RUNNING     this game reads ~60 fps / 16.67 ms
    owner's live game SUSPENDED   this game reads 232-339 fps / 3-4 ms

Two agents in one day read the first number as a game defect and reported a
slow game. It was the neighbour. Every run therefore prints a PERF COTENANT
block, and this table refuses to print a headline without it.

WHAT THE PREVIOUS VERSION OF THIS FILE BELIEVED, AND WHY IT WAS WRONG
--------------------------------------------------------------------
It asserted a "60 Hz macOS presentation wall": that `--disable-vsync` cannot
defeat macOS presentation pacing, that mean_ms therefore sits at ~16.6 ms
whatever the scene holds, and that milliseconds are consequently meaningless
here. Its evidence was one empty-scene run that read 16.535 ms/frame.

That evidence was a co-tenant, not a wall. The same harness has since logged
this game at 232-339 fps at 1080p and at 6K with the neighbour suspended, and
the empty scene is measured on every run now (mode `noise`) instead of being
quoted from memory. There is no wall. There is a neighbour.

The belief did real damage: because ms were declared meaningless, a geometry
A/B was run under PERF_LOAD supersampling — which multiplies FILL while
leaving draw calls, primitives and shadow submission untouched — and the
5.12 ms it produced was a fill number wearing a geometry label. That mode is
retired. To read a geometry change, read `prims` and `draws`.

HOW TO READ THE TABLE
---------------------
  drops/s   frames >= 25 ms per second. The stutter a player feels. Compare
            against the noise floor (mode `noise`), which is NOT zero: the
            harness itself drops ~0.1-0.2 % of frames on an empty scene.
  WORST     the worst single frame in the phase. This is the match-load
            stall's home; a mean will never show it.
  mean/fps  honest wall-clock frame time. Real, and comparable ONLY between
            runs whose PERF COTENANT blocks match.
  draws     draw calls. Deterministic — identical across runs, contention
  prims     primitives. Deterministic. THESE ARE THE GEOMETRY RANKING, and
            the only numbers here a busy GPU cannot move.

Usage:
  perf_table.py <log> [<log> ...]           print the tables
  perf_table.py --gate <log> [<log> ...]    print, then exit 1 on a breach
"""
import re
import sys
from collections import OrderedDict

FIELDS = ("frames", "min_ms", "p5_ms", "mean_ms", "median_ms", "p95_ms",
          "WORST_ms", "scene_ms_mean", "scene_ms_worst", "gpu_ms",
          "gpu_ms_worst", "rcpu_ms", "drops", "drops50", "objs", "draws",
          "prims", "vram_mb", "nodes")

# ── THE THRESHOLDS ─────────────────────────────────────────────────────────
# A harness that only prints cannot fail, and a check that cannot fail is not
# a gate. These are set from measured behaviour with a margin, NOT from
# aspiration — every one of them passes on the current build and would have
# caught the regression it is named for.
#
# They are deliberately split: the deterministic counters are hard ceilings
# (a busy GPU cannot move a draw call), while the frame-timing ceilings are
# only enforced on a QUIET run, because a co-tenant makes them meaningless.
GATE = {
    # Geometry. The sun's cascade regression (4 PSSM splits over 100 m) put
    # these at 855 draws / 1.02 M prims; one split over 30 m brought them to
    # 853 / 454 k. A ceiling here catches a cascade being restored, a shadow
    # caster being added to the hall, or a piece gaining surfaces.
    "draws_max": 900,
    "prims_max": 520_000,
    # Stutter, steady state only (idle / settle / hover phases). The empty
    # scene drops ~0.1 frames per second all by itself, so 2.0 is a real
    # ceiling and not a rounding of zero.
    "drops_per_sec_max": 2.0,
    # The match-load stall, WARM (loads 2..N in one process). Measured at
    # 164-193 ms on this build. The first load of a process is excluded and
    # gated separately: it additionally pays ~347 ms of one-time asset
    # construction that loads 2..N do not, and folding the two together would
    # either let a warm regression hide under the cold ceiling or make every
    # run red.
    "load_worst_ms_max": 320.0,
    # The match-load stall, COLD (the first load in a process). Measured at
    # 543-550 ms. Deliberately loose: this is the number to WATCH, not to
    # police, until the Hall-of-Banners preload lands.
    "load_cold_worst_ms_max": 800.0,
}
STEADY_PHASES = ("idle", "settle", "hover")


def parse(path):
    phases = OrderedDict()
    env = ""
    cotenants = []
    hitches = []
    loadsteps = []
    particles = []
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("PERF ENV"):
            env = line.strip()
            continue
        if line.startswith("PERF COTENANT"):
            cotenants.append(line.strip())
            continue
        if line.startswith("PERF HITCH"):
            hitches.append(dict(re.findall(r"(\w+)=([-\w.]+)", line)))
            continue
        if line.startswith("PERF LOADSTEP"):
            loadsteps.append(dict(re.findall(r"(\w+)=([-\w.]+)", line)))
            continue
        if line.startswith("PERF PARTICLES"):
            particles.append(line.strip())
            continue
        if not line.startswith("PERF phase="):
            continue
        kv = dict(re.findall(r"(\w+)=([-\w.]+)", line))
        ph = kv.get("phase", "?")
        if not ph:
            continue
        phases.setdefault(ph, []).append(kv)
    return env, phases, cotenants, hitches, loadsteps, particles


def agg(rows):
    out = {"secs": len(rows)}
    for f in FIELDS:
        vals = [float(r[f]) for r in rows if f in r]
        if not vals:
            out[f] = 0.0
            continue
        if f in ("min_ms", "p5_ms"):
            out[f] = min(vals)
        elif f in ("WORST_ms", "scene_ms_worst", "gpu_ms_worst"):
            out[f] = max(vals)
        else:
            out[f] = sum(vals) / len(vals)
    return out


HDR = (f'{"phase":<20}{"s":>3}{"drops/s":>8}{"WORST":>9}{"mean":>7}{"fps":>7}'
       f'{"rCPU":>7}{"scene":>7}{"draws":>7}{"prims":>10}{"objs":>7}')


def row(name, a):
    fps = 1000.0 / a["mean_ms"] if a["mean_ms"] else 0.0
    return (f'{name:<20}{a["secs"]:>3}{a["drops"]:>8.2f}'
            f'{a["WORST_ms"]:>9.2f}{a["mean_ms"]:>7.2f}{fps:>7.1f}'
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
    print("  Rank on d_prims / d_draws: they are deterministic and a co-tenant")
    print("  cannot move them. cost_ms is real but only trustworthy when the run")
    print("  was quiet AND the cost exceeds the baseline's own spread.")
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
        bdr = med([float(r["draws"]) for r in phases[bk]])
        adr = med([float(r["draws"]) for r in phases[k]])
        bpr = med([float(r["prims"]) for r in phases[bk]])
        apr = med([float(r["prims"]) for r in phases[k]])
        bdp = med([float(r.get("drops", 0.0)) for r in phases[bk]])
        adp = med([float(r.get("drops", 0.0)) for r in phases[k]])
        b, a = med(bms), med(ams)
        spread = max(bms) - min(bms) if bms else 0.0
        flag = ""
        if spread > abs(b - a):
            flag = "  <-- cost below its own baseline spread: NOISE"
        print(f'{nm:<16}{bdp:>9.2f}{adp:>9.2f}{bdp - adp:>9.2f}'
              f'{b:>9.2f}{a:>9.2f}{b - a:>9.2f}{spread:>10.2f}'
              f'{int(bdr - adr):>9}{int(bpr - apr):>10}{flag}')


def load_table(loadsteps, hitches):
    """The match-load breakdown — the one stall a player of this game sees."""
    if not loadsteps:
        return
    print()
    print("MATCH LOAD — inside game.gd::_ready(), wall clock, per iteration")
    iters = []
    cur = None
    for s in loadsteps:
        if s.get("step") == "init->enter_tree":
            cur = OrderedDict()
            iters.append(cur)
        if cur is not None:
            cur[s.get("step", "?")] = float(s.get("ms", 0.0))
    if not iters:
        return
    steps = list(iters[0].keys())
    print(f'{"step":<34}' + "".join(f'{"iter%d" % (i + 1):>10}' for i in range(len(iters))))
    for st in steps:
        print(f'{st:<34}' + "".join(f'{it.get(st, 0.0):>10.2f}' for it in iters))
    print(f'{"TOTAL _ready + children":<34}'
          + "".join(f'{sum(it.values()):>10.2f}' for it in iters))
    worst = [h for h in hitches if h.get("phase", "").startswith("match-load")]
    if worst:
        print("  worst frames in match-load: "
              + ", ".join("%.0f ms" % float(h["ms"]) for h in worst))
        print("  (iteration 1 pays first-use asset construction; 2..N do not —")
        print("   a cost that vanishes after the first load is construction, not")
        print("   rendering, and it happens before any draw)")


def gate(path, phases, cotenants, hitches):
    """Return a list of breach strings. Empty means the run is green."""
    breaches = []
    quiet = True
    for c in cotenants:
        m = re.match(r"PERF COTENANT count=(\d+)", c)
        if m and int(m.group(1)) > 0:
            quiet = False
    for name, rows in phases.items():
        if name.startswith(("BASE-", "ABL-")) or name == "warm":
            continue
        a = agg(rows)
        if a["draws"] > GATE["draws_max"]:
            breaches.append("%s: %d draw calls > ceiling %d"
                            % (name, int(a["draws"]), GATE["draws_max"]))
        if a["prims"] > GATE["prims_max"]:
            breaches.append("%s: %d primitives > ceiling %d"
                            % (name, int(a["prims"]), GATE["prims_max"]))
        if name.startswith(STEADY_PHASES):
            if not quiet:
                continue          # a co-tenant makes frame timing meaningless
            if a["drops"] > GATE["drops_per_sec_max"]:
                breaches.append("%s: %.2f drops/s > ceiling %.2f"
                                % (name, a["drops"], GATE["drops_per_sec_max"]))
    # COLD vs WARM. `load` mode tags its transitions match-load-1..N; every
    # other mode loads the match exactly once and tags it plain `match-load`,
    # which is therefore ALWAYS the cold one. Treating that bare phase as
    # warm is how a 543 ms first load once tripped the warm ceiling.
    cold, warm = [], []
    for h in hitches:
        ph = h.get("phase", "")
        m = re.match(r"match-load(?:-(\d+))?$", ph)
        if not m:
            continue
        n = int(m.group(1)) if m.group(1) else 1
        (warm if n >= 2 else cold).append(float(h["ms"]))
    if warm and max(warm) > GATE["load_worst_ms_max"]:
        breaches.append("match load (warm): %.0f ms worst frame > ceiling %.0f"
                        % (max(warm), GATE["load_worst_ms_max"]))
    if cold and max(cold) > GATE["load_cold_worst_ms_max"]:
        breaches.append("match load (cold, first of process): %.0f ms worst "
                        "frame > ceiling %.0f"
                        % (max(cold), GATE["load_cold_worst_ms_max"]))
    if not quiet:
        breaches.append("NOT A QUIET RUN — frame-timing gates were SKIPPED "
                        "(a second Godot was rendering; see PERF COTENANT)")
    return breaches


def main():
    args = [a for a in sys.argv[1:] if a != "--gate"]
    gating = "--gate" in sys.argv[1:]
    rc = 0
    for path in args:
        env, phases, cotenants, hitches, loadsteps, particles = parse(path)
        print("=" * 118)
        print(path.split("/")[-1])
        if env:
            print(env)
        # THE CO-TENANCY LINE IS NOT OPTIONAL. It is printed before the table
        # so it cannot be scrolled past, and it is printed even when empty so
        # that "nobody checked" and "nobody was there" never look alike.
        if cotenants:
            for c in cotenants:
                print(c)
        else:
            print("PERF COTENANT <ABSENT> — this log predates co-tenancy "
                  "recording; its milliseconds are UNATTRIBUTABLE")
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
                if k.startswith("idle") or k.startswith("noise"):
                    idle_drops += float(r.get("drops", 0.0))
                    idle_secs += 1
        if tot_frames:
            print(f'  TOTAL dropped frames {int(tot_drops)} / {int(tot_frames)} '
                  f'({100.0 * tot_drops / tot_frames:.2f}%)   '
                  f'IDLE drops/s {idle_drops / max(idle_secs, 1):.2f}')
        for p in particles:
            print("  " + p)
        load_table(loadsteps, hitches)
        ablation_table(phases)
        if gating:
            breaches = gate(path, phases, cotenants, hitches)
            # A skipped timing gate is a WARNING, not a failure: refusing to
            # measure beside a co-tenant is the correct behaviour, and making
            # it red would train people to ignore red.
            hard = [b for b in breaches if not b.startswith("NOT A QUIET RUN")]
            soft = [b for b in breaches if b.startswith("NOT A QUIET RUN")]
            print()
            if hard:
                print("GATE: FAIL")
                for b in hard:
                    print("  - " + b)
                rc = 1
            else:
                print("GATE: PASS (deterministic ceilings held)")
            for b in soft:
                print("  ! " + b)
    sys.exit(rc)


if __name__ == "__main__":
    main()
