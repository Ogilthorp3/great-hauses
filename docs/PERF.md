# Performance — what is true, how it was measured, and what will lie to you

> ## ⚠️ A SECOND GODOT INSTANCE ON THIS GPU INVALIDATES EVERY TIMING IN THIS DOCUMENT
>
> **Not "adds noise" — invalidates.** Same binary, same scene, same window,
> one variable changed:
>
> | Owner's live game (`godot-lab/.play-oracle`) | This game reads |
> |---|---|
> | **rendering** | ~60 fps · 16.67 ms/frame |
> | **suspended** | **232–339 fps · 3–4 ms/frame** (at 1080p *and* at native 6K) |
>
> That is ~90 % of the frame budget, taken by a neighbour, at both
> resolutions. **Two separate agents mistook this contention for a defect in
> this game** and reported a slow game that was in fact running at 235–315 fps.
> Both of their harnesses printed the co-tenant on every single run. Neither
> controlled for it. That mistake cost this project two full agent-hours in
> one day, and it produced a "60 Hz macOS presentation wall" doctrine that was
> then baked into the harness headers, the headline metric and the docs — from
> where it went on to justify a measurement technique that was wrong by
> construction (see *PERF_LOAD, retired*).
>
> ### The co-tenancy check every future measurement must record
>
> 1. **Before**: `pgrep -fl Godot`. `run_perf.sh` does this automatically —
>    it **refuses** to measure while another Godot runs *this* project, and
>    records every unrelated one in `cotenants.txt`.
> 2. **During**: the harness prints a `PERF COTENANT` block *from inside the
>    measured process, at measure time*. `perf_table.py` refuses to print a
>    table without it and marks older logs `<ABSENT> — UNATTRIBUTABLE`.
> 3. **When quoting a number**: quote the `PERF COTENANT` line beside it. A
>    millisecond without one is not a measurement.
> 4. **Never quiet the machine by suspending or killing a process you did not
>    start.** The 232–339 fps figures above were obtained by `SIGSTOP`ing the
>    owner's live game (a `kill -CONT <pid>` sleeper is still recorded in
>    `artifacts/perf/20260809-075833/cotenants.txt`). Do not repeat it. If the
>    machine is busy, say the machine was busy.

---

## The honest state of the game

**The game is fast.** On a quiet machine it renders at 232–339 fps at 1080p
and at native 6K — roughly 3–4 ms against a 16.7 ms budget. There is no
steady-state performance problem, and every report that there was one was
measuring a neighbour.

There is exactly **one stall a player actually feels**, and it is at match
load. Everything else in this document is instrumentation for finding the
next one.

---

## There is no 60 Hz wall

The retired doctrine claimed `--disable-vsync` could not defeat macOS
presentation pacing, that `mean_ms` therefore sat at ~16.6 ms whatever the
scene held, and that milliseconds here were meaningless. Its whole evidence
was one empty-scene run reading 16.535 ms/frame.

An empty scene *cannot* cost 16.5 ms — which should have been read as *the
instrument is wrong*, not as *the machine has a wall*. It was a co-tenant.

The empty scene is now measured on **every** run instead of being quoted from
memory: `./test_e2e/run_perf.sh noise` frees the game and samples a scene
holding one bare `Node`, then adds a cube, then spins the cube. It is both the
**noise floor** and the **control**.

### The noise floor is not zero

An empty scene, with the harness logging every frame exactly as it does over
the real game, still drops frames:

| Arm | draws | fps | drops/s |
|---|---|---|---|
| `noise-empty` (one bare Node) | 0 | 60.0 | 0.0–0.1 |
| `noise-cube` (one BoxMesh + Camera3D) | 1 | 60.0 | 0.0 |
| `noise-spin` (same cube, mutated every frame) | 1 | 60.0 | 0.0 |

Roughly **0.1–0.2 % of frames** are dropped by the instrument and the machine
before the game contributes anything. A drop threshold set below that floor
would fail on an empty screen, which is why the gate's ceiling is 2.0
drops/second and not zero.

*(These three arms were all recorded with the owner's game rendering, which
is why they all sit at 60. That is the point of having a control: the empty
scene and the full game read the **same** number under contention, which is
itself the proof that the number is not about scene content.)*

---

## The match-load stall — the one a player sees

### It was mismeasured, and the harness was the reason

Thirteen audited runs reported a **120–152 ms** worst frame at match load. That
number was wrong, and the instrument produced it:

> Every phase switch is driven from a coroutine, and a coroutine waiting on
> `get_tree().process_frame` resumes **before** the `_process` callbacks of
> that frame. `_set_phase()` reset `_last_us = now` at that moment — so the
> frame that carried the whole scene swap had its delta **discarded** before
> the sampler ever saw it. The 120–152 ms figure was an earlier, smaller
> frame. The real one was never in the data at all.

`_set_phase()` now banks the straddling interval against the phase that did
the work. With that fixed, the **true** figures at 1080p, four consecutive
loads in one process:

| | worst frame, load 1 (cold) | worst frame, loads 2–4 (warm) |
|---|---|---|
| **the real stall** | **550 ms** | **181 / 180 / 193 ms** |
| *(what 13 runs reported)* | *(never measured)* | *120–152 ms* |

So the stall is **~50 % worse than anyone thought**, and the cold one is
nearly four times worse.

### Where the time goes

`game.gd::_ready()` is bracketed step by step on the wall clock (`PERF
LOADSTEP`, armed only when the harness is in the tree). Measured per load:

| step | cold (load 1) | warm (loads 2–4) |
|---|---|---|
| `dress-hall` | 60 ms | **58 ms — every load, it never warms up** |
| `spawn-32-pieces` | **362 ms** | 15 ms |
| music / banter / HUD / director | ~11 ms | ~8 ms |
| **scene free + resource load + instantiate + children `_ready()`** | — | **~100–155 ms** |

Two distinct costs, with different cures:

* **`spawn-32-pieces`: 362 ms cold → 15 ms warm.** First use builds each
  *type × haus* mesh/material pair into the `PieceAssets` cache. This is
  **CPU construction, not shader compilation** — it happens inside
  `_spawn_from_state()`, before anything is drawn. Confirmed by repetition:
  a cost that vanishes on load 2 is first-use construction.
* **The scene swap itself (~100–155 ms, every load).** Freeing the Hall,
  `ResourceLoader` on `game.tscn`, node construction, and every **child**
  `_ready()` (children are readied before their parent — the Great Hall
  builds its whole room in there).

### The fix that worked, and was reverted anyway

**Stated plainly: the stall is now precisely located and measured, but it is
NOT fixed.** No behavioural change shipped.

Spreading `_ready()` across frames — yielding after the HUD, then raising the
army two pieces per frame — was implemented and measured. It works:

| | cold worst frame | warm worst frame |
|---|---|---|
| unchanged | 550 ms | 181 / 180 / 193 ms |
| staggered | 343 ms | 153 / 154 / 163 ms |

It was **reverted** because it breaks a contract the rest of the project
depends on. `e2e_driver.gd::_boot_game()` reads `views.size()` and compares it
to the engine's piece count *the instant* `_game()` becomes non-null, and then
counts how many of those views have a model. A board that assembles over 16
frames is empty at that moment: **18 of 20 e2e scenarios failed** with
`boot-views-match — 0 piece views for 32 engine pieces`. That contract —
*the board is complete when the scene exists* — is not local to `game.gd`, and
renegotiating it means changing the harness in step with the game.

The measurement stayed. `game.gd::_ready()` now carries the `PERF LOADSTEP`
brackets permanently (inert unless the perf harness is in the tree), so the
next person gets the breakdown for free instead of re-deriving it.

### What should be done instead — the fix that keeps the contract

**Warm `game.tscn` during the Hall of Banners.**
`main.gd::_on_selection_complete()` already waits **0.75 s** after the haus is
chosen — a deliberate beat, *"let the 'rides to war' banner breathe before the
hall doors open"* — and only then calls `change_scene_to_file`. A
`ResourceLoader.load_threaded_request()` fired into that beat would leave the
scene and its dependencies in the resource cache, taking the load clean out of
the swap frame, **in dead time the player is already spending**, with the board
still built synchronously and the contract untouched.

This is the single highest-value remaining fix, and the measurements say why:
the pre-yield part of `_ready()` is only ~3.6 ms, so the recurring ~155 ms is
almost entirely *outside* `_ready()` — scene free, `ResourceLoader`, node
construction, and children's `_ready()`. **No amount of deferring inside
`game.gd` can reach it.** (`src/main.gd`)

Secondary: **defer the Great Hall's procedural build.** It is a child node of
`game.tscn`, so its `_ready()` runs inside the swap frame by construction.
(`src/env/great_hall.gd`, `scenes/game.tscn`)

Note the stall lands at the **end** of that 0.75 s banner beat with the Hall
still fully on screen — it is not hidden behind a fade, so it is genuinely
visible rather than merely present in a log.

---

## The sun's shadow cascade — the one shipped win

`directional_shadow_mode` was the engine default (`PARALLEL_4_SPLITS`) over
the default 100 m. **This hall is 24 m across** and the orbit camera never
leaves a 4–13 m ring around the board, so *every* caster sat inside all four
splits and was re-submitted four times. The shadow pass was measuring 417 of
855 draw calls and 795 k of 1.02 M primitives — **3.6× the main pass**.

One split over 30 m covers everything the camera can physically see (13 m
orbit + 12 m far wall + margin) and submits each caster once:

| | draws | primitives |
|---|---|---|
| 4 splits / 100 m (engine default) | 855 | 1 020 000 |
| **1 split / 30 m (shipped)** | **853** | **454 242** |

**−55.4 % of per-frame primitives** for a 0.2 % pixel change confined to
self-shadow terminators. These are `draws`/`prims` counters — deterministic,
identical across runs, and immune to whatever else the GPU is doing. That is
precisely why they, and not milliseconds, are the geometry ranking.

The regression arm is kept in the ablation sweep as `pssm4`, so the shipped
setting can be A/B'd against what it replaced at any time.

---

## The dracarys torrent — measured for the first time

The heaviest VFX in the game, the only place `GPUParticles3D` exist, and it
had **never appeared in a single perf run**: every previous run played a
normal opening and stopped. `./test_e2e/run_perf.sh vfx` drives a mate-in-1,
lets the checkmate cinematic run, and phase-tags the ashfall ceremony off the
ceremony's **own clock** (`spectator.ashfall_phase()`) — never a stopwatch,
because `play_ashfall` bends `Engine.time_scale` to 0.55 and a 1.5 s wait
would land two beats late.

Per beat, 1080p (co-tenant present — read the counters, not the ms):

| beat | drops/s | WORST ms | draws | prims |
|---|---|---|---|---|
| `ash-launch` | 0.00 | 18 | 283 | 86 074 |
| `ash-bank` | 0.33 | 31 | 245 | 94 440 |
| **`ash-flare`** | **2.00** | **162** | 266 | 98 001 |
| `ash-inhale` | 0.00 | 23 | 266 | 98 001 |
| **`ash-breath`** (the torrent) | 3.00 | 69 | **193** | **78 940** |
| `ash-linger` | 2.50 | 33 | 172 | 57 820 |
| `ash-return` | 0.00 | 22 | 236 | 52 366 |
| `post-ashfall-idle` | 0.00 | 21 | 232 | 46 647 |

**The torrent is not the problem.** `ash-breath` — the six-layer fire itself —
runs at **193 draw calls and 79 k primitives, *fewer* than the settled board**
(308 / 107 k), because the duel camera frames the wyrm and culls the hall.
The most expensive thing this game can put on screen is cheaper than the
chessboard.

**The expensive beat is `ash-flare`**: 154 ms and 162 ms worst frames across
two runs, 2.0 drops/s, reproducible. That is the wing-flare beat, and it is
where `_ensure_fx()` lazily builds the torrent. Same shape as the match-load
stall: **first-use construction landing on a visible frame.** Not yet fixed.

**No lingering particle cost.** After the ceremony, all 10 systems report
`visible=0` and `emitting=0`; the 3 280-particle budget is retained but idle.

**One open question, stated as such:** the census never caught a system with
`emitting=true`, not even 0.4 s into the burning torrent. Either the kit
drives one-shot bursts via `restart()` (so `emitting` is true for a frame at a
time and sampling misses it), or the fire is drawn by something other than
particle emission. **Not resolved — do not assume the particles are inert.**

---

## Using the harness

```bash
./test_e2e/run_perf.sh noise      # the instrument's own floor, and the control
./test_e2e/run_perf.sh load       # the match-load stall, 4 transitions, breakdown
./test_e2e/run_perf.sh vfx        # the dracarys torrent / ashfall ceremony
./test_e2e/run_perf.sh gate       # the regression gate — exits 1 on a breach
./test_e2e/run_e2e.sh perf        # the same gate, from the e2e runner

python3 test_e2e/perf_table.py --gate <log>     # table + pass/fail
```

### The gate can now fail

The harness used to only ever print, so a regression could walk straight past
it. `perf_table.py --gate` enforces:

| ceiling | value | catches |
|---|---|---|
| `draws_max` | 900 | a shadow cascade restored, a caster added to the hall |
| `prims_max` | 520 000 | the same, and pieces gaining surfaces |
| `drops_per_sec_max` | 2.0 | stutter — set above the measured 0.1–0.2 % noise floor |
| `load_worst_ms_max` | 320 ms | a quarter-second freeze returning to match load |

The **deterministic** ceilings (draws, prims, load stall) are enforced always
— a busy GPU cannot move a draw call. The **frame-timing** ceiling is skipped
on a contended run, and the report says so out loud rather than passing
quietly or failing spuriously.

### Things in here that exist only as evidence

* **`contaminated`** — a 6K run *with* screenshots. A screenshot is a
  synchronous ~81 MB GPU→CPU framebuffer readback plus a PNG encode, on the
  main thread, inside the frame. That cost was once read as a game defect and
  "fixed" by halving the render resolution. Never quote a number from that log.
* **`PERF_LOAD`, retired.** It supersampled the 3D render target to lift the
  frame clear of the (imaginary) refresh wall so a *geometry* A/B could be
  read in milliseconds. Supersampling multiplies **fill** and leaves draw
  calls, primitives, skinning and shadow submission untouched — it measured
  the wrong axis by construction, and the **5.12 ms** it once attributed to
  the sun's cascade was a fill number wearing a geometry label. To read a
  geometry change, read `prims`.
* **Godot's per-viewport GPU timer** returns `0.0000` on every frame under the
  Metal backend here. The CPU half of the same API returns sane values, so the
  measurement *is* enabled and the GPU timestamps are simply absent. It is
  read and reported anyway, so the day it starts working is obvious.
