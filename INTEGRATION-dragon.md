# DRAGON SPECTATOR + ASHFALL — integration notes

Module delivered 2026-08-08. Per the module boundary it touches **no game
code**: `game.gd` / `game.tscn` / `duel_director.gd` / `piece_view.gd` are
unmodified. Everything below is what the integrator wires up.

## THE VIGIL (2026-08-17) — the wyrm takes the gallery

The fly-in cinematic (`cathedral_cinematic_intro.gd`) now lands the witness
on the cathedral's **Wyrm's Gallery** — the corbelled ledge over the apse
arch at `GreatHall.wyrm_gallery_rest()` = (0, 12.2, 13.55) — and the
spectator keeps its vigil THERE for the whole match, awake: `vigil = true`,
`Perch_Idle` as authored (a standing watch), coals banked at 0.85, head
tracking the play. Bert's reference art (the beast on the ledge above the
throne, coals lit, watching the board) is the composition this serves.

With `vigil` on, the slumber coil stays attached at weight 0 so the
checkmate wake runs the same phase machine — from the ledge it reads as a
crouch-and-DIVE instead of a floor wake, which is a strictly better beat.
Reactions play their full clips (`_react` branches on `is_asleep()`, which
is false at weight 0). The gallery is 9.6 wide precisely so `HitReact`'s
wings (±4.6 at scale 1.65) clear the side balustrades.

`vigil` defaults to **false**: the floor-sleeper contract below and every
`tests/test_dragon.gd` assertion are untouched. The WYRM SLEEPS section
remains the module's own truth; the vigil is an integrator configuration
(game.gd sets it when the hall provides the gallery anchor). One wyrm:
game.gd hides the spectator during the fly-in and reveals it the frame the
cinematic's twin lands on the same stone.

## THE WYRM SLEEPS (2026-08-09) — rest → stir → wake → burn

The spectator no longer hovers on a perch above the far wall. It **sleeps
coiled on the hall floor beside the board** for the whole match and wakes
exactly once, at checkmate. The dramatic fault this fixes: a creature that is
already flying cannot dramatically take flight, so the old ceremony opened at
its own ceiling.

| Beat | What the player sees | Driven by |
|------|----------------------|-----------|
| REST | coiled on the stone at `rest_position` (east aisle, x 6.6): neck folded, chin on the floor, wings mantled, tail curled, throat coals BANKED | `Perch_Idle` at 0.30 under `DragonRig`'s slumber coil |
| STIR | a blunder / brilliancy / capture disturbs it — head lifts, coals blink, it settles back. It **never** fully wakes for a move | `_react` eases the coil to `stir_slumber_floor` (0.42) and back |
| WAKE | head up + coals kindle → hauls itself up (`Land_Settle` **backwards**) → **ROARS on the ground** → only then the wings | ashfall phases `wake` → `roar` → `bank` |
| BURN | the existing ceremony, unchanged: bank, flare, inhale, dracarys, linger | unchanged |
| REST | flies back down to the same stone, lands (`Land_Settle`), re-coils | match tier only; a championship stays awake on the throne |

**Nothing in the integration changed.** `play_ashfall(...)` has the same
signature, the same await, the same signals, the same skip contract, and the
same `time_scale` hygiene. New read-only probes: `is_asleep()`,
`slumber_weight()`, and two new `ashfall_phase()` values, `"wake"` and
`"roar"`.

Wall clock: the default MATCH ceremony measured **12.01 s** (was 10.01 s) —
the wake costs ~2.0 s net, and the budget line moved 12 s → 13 s. The
championship worst case stays inside 16 s.

### ASK: a hall anchor for the resting spot

`rest_position` currently carries its own default because `great_hall.gd`
belongs to another module. It wants the same treatment `spectator_perch()`
got:

```gdscript
# src/env/great_hall.gd
## Where the spectator wyrm sleeps: on the floor in the east aisle, clear of
## the board (±4) and of the feast table at x 9.
func dragon_rest() -> Vector3:
    return Vector3(6.6, FLOOR_Y, 0.6)
```

…and one line in `game.gd`'s `_setup_spectator`, beside the existing perch line:

```gdscript
if hall.has_method("dragon_rest"):
    spectator.rest_position = hall.dragon_rest()
```

Until then the module's default matches those numbers exactly, and
`tests/test_dragon.gd` asserts the spot against the real gameplay camera
(in frame, off the board, and never inside the orbit ring).

## Files

| File | What |
|------|------|
| `src/cinematics/dragon_rig.gd` | `DragonRig` — shared dragon.glb controller (loader + emissive lift + clip helpers + Head-bone mouth mount). `GreatHall.summon_champion_dragon()` now delegates here; **never duplicate the loader again**. |
| `src/cinematics/dragon_spectator.gd` | `DragonSpectator` — the perched watcher + reactions + `play_ashfall()`. |
| `src/cinematics/cine_caption.gd` | `CineCaption` — the cinematics caption style as a reusable layer (kept in lock-step with DuelDirector's private copy; this file is canonical if they drift). |
| `src/cinematics/ashfall_test.gd` + `scenes/cinematics/ashfall_test.tscn` | Standalone self-checking stage (headless + windowed). |
| `tests/test_dragon.gd` | Headless suite: rate limit, duel-cam gate, time_scale restore on completion/skip/free, loser cleanup, duck-scan, no-Light3D assert. |
| `src/env/great_hall.gd` | Additions only: `spectator_perch()` anchor; `summon_champion_dragon()` refactored onto `DragonRig` (same behavior/API, e2e showcase asserts unchanged). |

## Wiring (all in `game.gd`, ~10 lines)

### 1. Spawn the spectator (in `_ready`, after `duel_director` exists)

```gdscript
const DragonSpectatorScript := preload("res://src/cinematics/dragon_spectator.gd")
var spectator: DragonSpectator

spectator = DragonSpectatorScript.new()
spectator.name = "DragonSpectator"
add_child(spectator)
spectator.duel_director = duel_director   # reactions gate on is_active()
spectator.board = board                   # lets react_capture take Vector2i squares
var hall: GreatHall = get_node_or_null("GreatHall")
if hall != null:
    spectator.perch_position = hall.spectator_perch()
```

The perch (default `(0, 4.7, 11.2)`, yaw PI) sits above the far wall: out of
the default orbit frame (pitch -0.85), visible the moment the player orbits
upward. Slow `Flying_Idle` + bob + occasional head glance at the last-moved
piece (LookAtModifier3D on the `Head` bone).

### 2. Feed it moves (end of `_execute_ply`, after `_animate_move`)

```gdscript
spectator.notice_move(board.square_to_world(sq_of(move.to_square)))
```

This drives BOTH the rate limiter and the idle glance target. Without it the
dragon still idles, but reactions stay locked after the first one.

### 3. Reactions — connect YOUR signals to these methods

Each returns `true` only when the reaction actually played. They
self-enforce the contract: **max 1 reaction per 2 `notice_move` plies, and
never while `duel_director.is_active()`** — callers just fire.

| Call | Clip | Suggested source signal |
|------|------|------------------------|
| `spectator.react_capture(sq_of(move.captured_square))` | HitReact flinch + head snaps to the square | in `_animate_move`'s capture branch, right after `duel_director.play_duel(...)` returns (accepts `Vector2i` via `spectator.board`, or a `Vector3`) |
| `spectator.react_blunder()` | 'No' head-shake | `oracle.oracle_stumbled` (`func(_r): spectator.react_blunder()`), or your eval-drop detector |
| `spectator.react_brilliant()` | 'Yes' nod | counsel HEEDS / mate-found / promotion — integrator's judgment |

### 4. ASHFALL — chain at checkmate, BEFORE the existing victory flow

In `_end_sequence`, after the checkmate cinematic (king death) returns:

```gdscript
await duel_director.play_checkmate(king_view, winner_key,
    func(): await king_view.die())
# ── ASHFALL: the execution — king death → ashfall → victory flow ──
var loser_pieces: Array = []
for sq in views:
    var pv: PieceView = views[sq]
    if is_instance_valid(pv) and pv.side == loser:
        loser_pieces.append(pv)
await spectator.play_ashfall(loser,
    duel_director.resolve_house_name(winner_key), loser_pieces)
for sq in views.keys():           # ashfall freed those views
    if not is_instance_valid(views[sq]):
        views.erase(sq)
```

- `loser` is the same `PieceView.House` value `_end_sequence` already
  computes. Passing `loser_pieces` explicitly is preferred; with an empty
  array the module duck-scans the tree for `side == losing_side`
  (kings excluded — his death already played).
- Ordering caveat: `play_checkmate` fires `victory_panel_requested` during
  its hold, i.e. before ASHFALL. Acceptable as-is; for the strict
  king-death → ASHFALL → panel order, don't show the panel from that signal
  — call `_show_match_end(...)` yourself after `await play_ashfall(...)`.
- The board is already non-interactive here (`game_over == true`), and the
  module owns click/Esc while active: **click = skip to end state** (all
  losers removed, `Engine.time_scale == 1.0` — restored on normal end,
  skip, failsafe overrun, and `_exit_tree`, same hygiene as DuelDirector).
- Duration ≤ 6 s wall clock (defaults sum ≈ 5.3 s; the suite asserts it).
- Signals the module EMITS (optional to observe): `ashfall_started`,
  `ashfall_finished`.

### 5. Championship interplay

`start_championship_tableau()` summons its own throne dragon
(`hall.summon_champion_dragon()`, now DragonRig-backed, unchanged
behavior). To avoid two dragons in the throne frame, call
`spectator.dismiss()` before starting the tableau.

## Constraints honored (and asserted by `tests/test_dragon.gd`)

- **NO `Light3D` on any module path** — the hall's 8-omni budget is full.
  Fire is GPUParticles3D with emissive/unshaded materials only (additive
  flame core + ember sparks, alpha smoke). The suite counts tree-wide
  `Light3D` before/after every path and fails on any delta.
- Charred pieces get **duplicated** materials — the shared
  `PieceAssets.tinted_material` cache is never contaminated.
- All cinematic timing is wall-clock (immune to the time_scale it bends).
- Headless-safe end to end; headless boot stays clean.

## Verification commands

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
P=~/Projects/godot-lab/great-houses-chess
$G --headless --path $P -s res://tests/test_dragon.gd            # unit suite
$G --headless --path $P res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test
$G --path $P res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test  # visual + screenshot
# mid-fire frame lands at test_e2e/artifacts/module-previews/ashfall.png
```
