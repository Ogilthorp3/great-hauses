# DRACARYS VFX KIT — API + wiring notes

The fire, **model-independent**. It attaches to any `Node3D` you nominate as
the muzzle, so it works with whichever dragon wins the bake-off — the kit
never touches the model, the rig, or an animation.

Delivered 2026-08-08. Touches **no game code**: everything below is what the
integrator wires up.

---

## Files

| File | What |
|------|------|
| `dracarys.gd` | `DracarysVFX` — the whole kit. All six layers, built in code. |
| `dracarys.tscn` | Optional scene wrapper (see *Installing* — the script alone is enough). |
| `heat_shimmer.gdshader` | LAYER 5 — screen-space refraction. |
| `jet_stem.gdshader` | LAYER 1 — the pressure-taper core. |
| `ground_glow.gdshader` | LAYER 4 — the no-`Light3D` firelight pool. |
| `shock_ring.gdshader` | Ignition / impact shock rings. |
| `dracarys_demo.gd` + `.tscn` | Judging stage + self-checking suite (headless and windowed). |
| `renders/` | Captured frames across the effect's lifetime. |

## Installing

Drop the whole folder anywhere under `res://` (suggested:
`res://src/cinematics/vfx/`). **The kit resolves its four shaders relative to
its own script path**, so no path rewriting is needed — move the folder, it
still works.

```gdscript
const DracarysScript := preload("res://src/cinematics/vfx/dracarys.gd")
var fx: DracarysVFX = DracarysScript.new()
add_child(fx)
```

`dracarys.tscn` is provided for editor use but its `ext_resource` path assumes
the scratch layout (`res://dracarys.gd`). **Prefer the `preload(...).new()`
form above** — it has zero path dependencies. The kit needs no scene.

---

## Minimal wiring (3 lines + the call)

```gdscript
fx.bind_camera(get_viewport().get_camera_3d())   # optional: enables shake
fx.bind_environment($WorldEnvironment)           # optional: enables the lift
fx.floor_y = board.surface_y()                   # where the ground pool sits

await fx.fire(mouth_node, board.square_to_world(target_sq), 2.6)
```

`mouth_node` is any `Node3D` — for the ceremony, the dragon's `Head` bone
attachment (`DragonRig` already exposes one). Pass the node, not a position:
the kit re-reads its global transform every frame, so the torrent follows the
head through the whole animation.

---

## API

### The shot

| Call | Notes |
|------|-------|
| `fire(from, target: Vector3, duration := 2.6) -> void` | **Awaitable.** Returns when the tail has fully died, or immediately after `hard_stop()`. |
| `start(from, target, duration := 2.6) -> void` | Non-blocking form. Use when the ceremony drives its own timeline. |
| `aim(from, target: Vector3) -> void` | Re-point mid-torrent. Safe every frame — this is how you sweep the beam across the losing army. |
| `cut() -> void` | Stop the jet early, **let the tail live** (embers keep flying, ash falls, smoke curls). The graceful stop. |
| `hard_stop() -> void` | **The skip.** Instant clear + full restore. See *Skip safety*. |
| `is_active() -> bool` | |

`from` accepts a `Node3D` (tracked live), a `Transform3D`, or a `Vector3`.

### Signals

| Signal | Fires |
|--------|-------|
| `ignited` | The frame the jet punches out (stem snap + shock ring + punch). |
| `impacted` | The torrent reaches the aim point; ground pool lights. |
| `torrent_cut` | Jet cut; only the tail remains. |
| `finished` | Everything is done — **or immediately on `hard_stop()`**. Exactly once per `fire()`. |

### IMPACT PUNCH (LAYER 6) — reusable on their own

```gdscript
fx.punch_camera(cam, amplitude := 0.15, duration := 0.65,
                frequency := 26.0, fov_kick := 2.6)
fx.punch_exposure(world_env, hold := 2.6, exposure_mul := 1.24,
                  glow_add := 0.40, ambient_add := 0.16, attack := 0.07)
DracarysVFX.make_shake_curve() -> Curve      # static; the envelope itself
fx.restore_camera()                          # idempotent
fx.restore_environment()                     # idempotent
```

`fire()` calls both automatically when `auto_punch` is true (default) and the
camera / environment are bound. Set `auto_punch = false` to drive them from
ceremony code.

**`punch_camera` is animator-safe**: it writes only `h_offset`, `v_offset` and
`fov` — never the camera transform — so a tween driving the camera position
during the bank-and-hover keeps working underneath the shake.

`make_shake_curve()` is `static`: reuse the same feel for any other hit
(a wing-beat, the king's death) without instantiating the kit.

### Tunables (`@export`, all optional)

| Property | Default | Effect |
|----------|---------|--------|
| `reach` | `6.0` | Default muzzle→impact distance. Overridden per shot by the actual distance to `target`. Drives jet speed, stem length, shimmer size, pool radius. |
| `intensity` | `1.0` | Global multiplier on every HDR colour. |
| `torrent_spread` | `15.0` | Cone half-angle, degrees. |
| `floor_y` | `0.0` | World Y the ground pool sits on. |
| `heat_shimmer_enabled` | `true` | LAYER 5 toggle — **first thing to drop on a low device tier**. |
| `environment_lift_enabled` | `true` | LAYER 6 environment toggle. |
| `auto_punch` | `true` | Let `fire()` fire the punches itself. |
| `ember_tail` | `4.0` | Seconds embers outlive the jet. |
| `ash_tail` | `4.5` | Seconds of ash drift after that. |

### QA helper

`preview_shimmer(on: bool, from = null, target := Vector3.ZERO)` shows **only**
the refraction layer, no fire. Use it to A/B the effect and to confirm the
screen-texture path is alive on a new device tier before shipping to it.

---

## TIMELINE

Wall-clock seconds from `ignited`. **All internal sequencing is wall clock**
(`Time.get_ticks_usec`), so the kit is immune to the `Engine.time_scale` the
ceremony bends around it.

| t | Beat |
|---|------|
| `0.00` | IGNITION — stem snaps out, blast front, muzzle flash + shock ring, camera shake, exposure kick |
| `0.05` | rolling flame body joins |
| `0.10` | stem reaches full bore |
| `0.32` | dark smoke starts curling off the body |
| `~reach/26` | IMPACT — ground pool lights, splash burst, ground ring, long-lived sparks start |
| `duration` | CUT — jet + stem retract over 0.16 s; environment lift begins its 0.75 s release |
| `+0.45` | ground flame → ground smoke |
| `+0.60` | ashfall starts |
| `+0.90` | jet smoke and spark feed stop |
| `+1.60` | ground smoke stops |
| `+0.35 … +3.55` | ground glow smoulders down |
| `duration + 0.6 + ash_tail*1.5 + 0.4` | `finished` (≈ **10.4 s** at defaults) |

Full default run: `duration 2.6` → `finished` at ≈10.35 s. The demo suite
asserts < 13 s.

---

## HARD CONSTRAINT: no `Light3D`

The hall's 8-omni budget is full (the torches). **This kit creates zero
`Light3D` nodes.** Firelight is sold with:

1. HDR emissive particles (values > 1.0 bloom through the existing glow),
2. an additive **ground-glow quad** lying on the stone — the "light" the fire
   casts on the floor is a mesh, not a lamp,
3. an optional, fully-restored **WorldEnvironment lift**.

`dracarys_demo.gd` asserts the tree-wide `Light3D` count is unchanged across
ignition, torrent, cut, tail, and `hard_stop()`.

### RESTORE CONTRACT (a stuck exposure would be a shipping bug)

Everything the kit changes outside its own subtree is recorded on first touch
and restored by `restore_environment()` / `restore_camera()`. Those are called
unconditionally by:

- the normal end of the sequence,
- `cut()` (release ramp, then a hard restore),
- **`hard_stop()`** (snaps, no ramp),
- `_exit_tree()`,
- `NOTIFICATION_PREDELETE`.

Both are idempotent and safe when nothing was ever changed. **There is no
success-only restore path** — "the effect ended" and "the effect was skipped"
run the same restore code.

Fields saved/restored on the `Environment`: `tonemap_exposure`,
`glow_enabled`, `glow_intensity`, `glow_bloom`, `ambient_light_source`,
`ambient_light_energy`, `ambient_light_color`.
On each shaken `Camera3D`: `h_offset`, `v_offset`, `fov`.

Ambient is only touched when the scene's `ambient_light_source` is already
`COLOR` or `BG` — the kit will not silently switch ambient mode on you.

### Skip safety

`hard_stop()` in one frame: clears every particle buffer, zeroes every shader
`amount` uniform, hides every emitter, cancels all pending callbacks and
fades, restores camera + environment, and emits `finished`. Safe to call at
any time, twice, or when nothing is running.

Wire it to the ceremony's existing click/Esc skip:

```gdscript
func _skip() -> void:
    fx.hard_stop()
```

---

## The six layers

| # | Layer | Implementation |
|---|-------|----------------|
| 1 | **CORE JET** | `jet_stem.gdshader` tapered cone (≈0.30 m bore at the lips → ≈2.2 m across at 52 % of reach, for a 9 m shot) + 340 velocity-streaked particles, spread 3.2°, damped so pressure visibly runs out. Plus a 200-particle one-shot **blast front** on frame one. |
| 2 | **ROLLING BODY** | 820 velocity-aligned particles, spread 15°, turbulent, buoyant — cooling white → yellow → orange → deep red, tongues standing up as they slow. |
| 3 | **EMBERS + ASH** | Jet-riding sparks (3 s) + impact sparks with drag and gravity that outlive the jet ~4 s; then 420 grey ash flakes drifting **down** for `ash_tail`. |
| 4 | **GROUND FIRE** | Impact splash, a pool of upward flame tongues, a shock ring, a smouldering additive glow quad, fading to smoke. |
| 5 | **HEAT SHIMMER** | Two-octave screen-space UV refraction on a camera-facing quad. |
| 6 | **IMPACT PUNCH** | Decaying shake envelope on `h_offset`/`v_offset`/`fov` + exposure/glow/ambient kick with a slow settle. |

---

## Verification

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
P=<...>/dragon-v2/vfx/.godot-check
R=<...>/dragon-v2/vfx/renders

$G --headless --path $P --import                                   # once: builds the class cache
$G --headless --path $P res://dracarys_demo.tscn -- --run          # 19-check suite, exits 0/1
$G --path $P res://dracarys_demo.tscn -- --run --out $R            # 8 frames, side view
$G --path $P res://dracarys_demo.tscn -- --run --angle low --out $R    # hero low angle
$G --path $P res://dracarys_demo.tscn -- --run --no-shimmer --out $R   # LAYER 5 A/B control
$G --path $P res://dracarys_demo.tscn -- --shimmer-proof --out $R      # LAYER 5 evidence
```

The scratch project mirrors the game's renderer exactly (Forward Mobile, 4.7)
and its kit files are **symlinks** to the deliverables one directory up —
there is no copy to drift.

Headless suite (19 checks): no `Light3D` delta, exposure / glow / ambient /
camera restored after a normal run **and** after a mid-torrent `hard_stop()`,
env demonstrably lifted mid-shot (so the restore assertions can't pass
vacuously), all emitters silenced, `hard_stop()` idempotent, run under 13 s.

---

## Traps already paid for (do not "fix" these back)

- **Heat shimmer needs a NEGATIVE `sorting_offset`.** The screen-texture copy
  is taken when the first material sampling it renders. If the shimmer draws
  *after* the flame it samples a copy from before the flame existed and paints
  the bare wall over the torrent — a wall-textured hole punched through the
  fire.
- **`GradientTexture1D.use_hdr = true`** or every colour clamps to 1.0 and
  nothing blooms.
- **`glow_bloom > 0` blooms every pixel** regardless of `glow_hdr_threshold`,
  which turns a dark stone hall into pink paste. Threshold ≥ 1.0, bloom 0.
- **`Color * float` scales alpha too.** Multiplying a gradient stop by
  `intensity` silently destroys the ramp's fade-out; the kit uses `_hot()`,
  which scales RGB and sets alpha explicitly.
- **Velocity-aligned quads that grow big AND slow become drifting petals.**
  Both the body and the blast fade to near-zero alpha well before end of life.
- **Round billboards read as a bag of dots; velocity-aligned elongated quads
  read as flame tongues.** That single choice is most of the look.
- **`visibility_aabb`** is set generously on every emitter — an undersized one
  silently culls the whole torrent when the camera turns.
- **`hard_stop()` hides emitters**, so `start()` must un-hide them. Skipping
  that renders the stem and nothing else.

---

## Known gaps / next pass

- The **demo's back wall and pillars are stand-ins**, not the real hall
  geometry. Values were tuned against dark stone at ~9 m reach; a much
  shorter or much longer shot will want a pass on `intensity`.
- **Not yet profiled on device.** 3 280 particles are allocated across ten
  emitters (peak *live* count is lower), plus one screen-texture pass.
  `heat_shimmer_enabled = false` is the first lever; the flame body's 820 is
  the second. Measured only on an M4 Pro — treat mobile cost as unknown.
- Colour is currently one palette. If houses need tinted fire (green, blue),
  the ramps should move behind a small palette resource.
- The muzzle **flash and shock ring are camera-facing/axis-aligned quads**;
  from directly down the barrel the ring reads as a circle. Fine for the
  ceremony's framing, worth checking if the camera ever ends up head-on.
