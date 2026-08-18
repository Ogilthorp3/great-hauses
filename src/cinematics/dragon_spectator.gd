class_name DragonSpectator
extends Node3D
## DRAGON SPECTATOR + ASHFALL — the dragon SLEEPS on the stone beside the
## board through the whole war, stirs at what happens on it, and WAKES ONCE:
## at checkmate, to deliver the execution — a roar, a swoop over the beaten
## army and a river of fire (ASHFALL).
##
## Presentation only: it never touches game state. Pieces are duck-typed
## Node3D (PieceView works out of the box via its `side` / `piece_type`
## ints; mocks only need the same two fields).
##
## THE WYRM SLEEPS (rebuilt 2026-08-09). It used to hover on a perch above
## the far wall running `Flying_Idle` for the entire match — which is a
## dramatic dead end: a creature that is ALREADY FLYING cannot take flight.
## The arc is now rest -> stir -> wake -> burn:
##
##   REST     coiled ON THE GROUND at `rest_position`, in the east aisle
##            beside the board — clear of the camera's orbit ring (the ring
##            is 2.5-11.5 m out and 1.4-11.2 m up; a couched wyrm at 6.9 m
##            out and 1 m tall is never near it) and clear of the board.
##            `Perch_Idle` at `rest_idle_speed` (0.3) under DragonRig's
##            SLUMBER coil: neck folded forward, chin on the stone, tail
##            curled around the flank, haunches couched, slow breathing
##            swell, throat coals BANKED (`rest_ember_energy`).
##   STIR     a blunder / brilliancy / capture is a sleeping animal being
##            DISTURBED, never a wakening: the coil eases back only to
##            `stir_slumber_floor` (never 0), the head comes up, the coals
##            blink, the breathing quickens, and it settles back. Same rate
##            limit and duel-cam gate as before.
##            A SLEEPING BEAST NEVER SWAPS ITS CLIP (critic blocker,
##            2026-08-09 — see _react for the measurement that earned it).
##   WAKE     checkmate only. Head rises and the coals kindle -> it hauls
##            itself up (`Land_Settle` run BACKWARDS) and unfurls -> it
##            ROARS on the ground (`Roar`) -> only THEN the wings go
##            (`Fast_Flying`) and the bank climbs off the floor into the
##            existing ceremony. The roar lands before the wings by
##            construction: they are separate phases.
##
## Reaction API (integrator connects signals to these; each returns true
## when the reaction actually played):
##   notice_move(world_pos)     call once per ply — feeds the rate limiter
##                              and the idle glance target
##   react_blunder()            a disturbed grumble (asleep: coil + coals)
##   react_brilliant()          a disturbed stir  (asleep: coil + coals)
##   react_capture(square)      a flinch + look at the square
##                              (square: Vector3 world pos, or Vector2i via
##                              the `board` reference)
## The clip names those three carry ('No' / 'Yes' / 'HitReact') are played
## only when the wyrm is NOT asleep — see _react.
## Rate limit: max ONE reaction per `reaction_every_moves` moves (default
## 2), and NEVER while the duel-cam runs (`duel_director.is_active()`).
##
## ASHFALL (awaitable): play_ashfall(losing_side[, winning_house, losers,
##   championship]) — THE CEREMONY (rebuilt 2026-08-08, two tiers):
##
##   MATCH (any checkmate, wall <= 13 s): THE WAKE off the stone (stir ->
##   rise -> roar, ~2.65 s) -> one sweeping Fast_Flying bank that CLIMBS off
##   the floor and laps the hall (inside walls and pillars, above y~3) filmed
##   by a low-angle camera pushing in from below (the awe
##   shot) -> flare to a wing-spread hover above the board center
##   (Flying_Idle at 0.6 reads as a mighty hover), ONE beat of stillness
##   (the inhale) -> the fire sweep over the beaten army with a long ember
##   and drifting-ash tail (particles linger 3-4 s after the breath) -> and,
##   when the ash settles, it flies BACK DOWN to `rest_position`, lands
##   (`Land_Settle`) and re-coils into slumber. Dragon scale swells to ~1.4
##   for the ceremony and returns to 1.15 on the stone.
##   MORTAL-KOMBAT INCINERATION: each warrior the jet touches
##   flashes white-hot, burns down to its charred KayKit skeleton (local
##   cast table below) standing in its exact spot and facing, smolders
##   ~1.2 s under sparse grey wisps, then falls (Death_A via the shared
##   Rig_Medium library when the PieceAssets autoload is present, else a
##   tilt-crumble) and sinks into the stone. Tidegrip's Drowned Legion is
##   already bones — the fire just chars them darker (the intended joke).
##
##   CHAMPIONSHIP (tournament final, wall <= 16 s): the full ceremony,
##   then the dragon banks once more and takes the perch ABOVE THE THRONE
##   (THRONE_PERCH — kept equal to GreatHall.DRAGON_HOVER) with a slow
##   wing-settle at scale 1.6, gentle ember drift over the tableau, and
##   the caption beat "ASHFALL." then "{haus} takes the throne."
##   (strictly sequential — the lines never overlap).
##
##   EMISSIVE MATERIALS ONLY throughout (the hall's 8-omni budget is FULL:
##   this module adds NO Light3D nodes on any path). Click/Esc skips
##   straight to the tier's end state (all losers AND smoldering skeletons
##   removed, camera + Engine.time_scale + WorldEnvironment restored).
##   time_scale hygiene mirrors DuelDirector: restored on normal end, skip,
##   failsafe, and _exit_tree.
##
## THE FIRE is the DRACARYS kit (res://assets/vfx/dracarys.gd) since
## 2026-08-09 — a six-layer torrent (core jet + rolling billows + embers and
## ash that outlive the jet + ground fire + heat shimmer + camera/exposure
## punch) mounted on rig.mouth_node(). It replaced this module's own
## billboard stack, which a critic read as "bare opaque squares… JPEG
## compression blocks, not embers". The kit creates ZERO Light3D nodes; its
## only reach outside its own subtree is a WorldEnvironment exposure/glow
## lift and a camera h_offset/v_offset/fov shake, both recorded on first
## touch and restored unconditionally by cut(), hard_stop(), _exit_tree and
## PREDELETE — there is no success-only restore path. A stuck exposure is a
## shipping bug, so tests/test_cinematics.gd asserts the restore on the
## normal end, on the skip, and on a spectator freed mid-torrent.
##
## Sequence order at checkmate: king death anim (DuelDirector checkmate
## cinematic) -> await play_ashfall(...) -> the existing championship /
## victory flow. See INTEGRATION-dragon.md.

signal ashfall_started
signal ashfall_finished

const DD := preload("res://src/cinematics/duel_director.gd")
const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")
const CaptionScript := preload("res://src/cinematics/cine_caption.gd")
const DracarysScript := preload("res://assets/vfx/dracarys.gd")

const PIECE_KING := 5              # PieceView.Type.KING — kings never burn twice
const CHARCOAL := Color(0.09, 0.085, 0.08)
const EMBER_GLOW := Color(0.9, 0.28, 0.06)

## Championship throne perch — MUST equal GreatHall.DRAGON_HOVER (the hall
## is the authority; test_dragon.gd asserts the two stay in sync).
## Raised 2026-08-09 by 1.15 × champ_scale (1.6) with the rest of the
## origin-moved constants — see DragonRig.BODY_RISE.
const THRONE_PERCH := Vector3(0.0, 4.04, 9.9)

## THE BREATH, in clip time of `Rear_Breathe` (2.25 s, authored inhale →
## held blast → recoil). The ceremony drives this playhead by hand off its
## own wall clock — see DragonRig.play_manual for why no single speed works.
const BREATH_LUNGE_END := 0.92    ## the uncoil lands; the jaws open
const BREATH_HOLD_END := 1.33     ## end of the held blast
const BREATH_CLIP_END := 2.25     ## recoil complete
## Fraction of the breath phase spent lunging; the rest is the held blast
## the fire sweeps under.
const BREATH_LUNGE_FRAC := 0.25

## THE RISE, in clip time of `Land_Settle` (2.50 s, authored flare -> touch-
## down -> wings fold). Played BACKWARDS between these two marks it is the
## opposite motion, which is exactly the one the wake needs: the folded wings
## open and the beast hauls its weight up off the stone. It is deliberately
## NOT run back past ~1.6 s — before that the clip is airborne (measured: the
## feet are 0.6 u off the ground at t 1.15), and a "rise" whose last frames
## have the feet dangling reads as a puppet lifted by a wire, not a beast
## standing up.
const RISE_CLIP_SETTLED := 2.46   ## fully folded, weight down: where rest lives
const RISE_CLIP_UP := 1.62        ## unfurled, still on its feet
## The roar's peak (jaw widest, head highest) sits early in the 1.67 s clip;
## the phase holds through it rather than to the clip's end.
const ROAR_CLIP_LEN := 1.67

## MORTAL-KOMBAT remains cast — the module's OWN local table (PieceAssets
## stays untouched by doctrine). Keyed by duck piece_type; anything not
## listed (queens, tower garrisons, unknowable ducks) rises as a Rogue.
const SKELETON_SCENES := {
	0: preload("res://assets/kaykit-skeletons/Skeleton_Minion.glb"),   # pawn
	2: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # knight
	3: preload("res://assets/kaykit-skeletons/Skeleton_Mage.glb"),     # bishop
	5: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # king (spared, mapping kept whole)
}
const SKELETON_DEFAULT: PackedScene = preload("res://assets/kaykit-skeletons/Skeleton_Rogue.glb")
const SKELETON_HOUSE := "tidegrip"   # the Drowned Legion is already bones

const ASHFALL_LINES: Array[String] = [
	"{wh} leaves nothing for the crows but ash.",
	"What {wh} cannot rule, it burns.",
	"Every banner owes the dragon a debt. {wh} collects.",
	"Kneel or be kindling — so decrees {wh}.",
]

## THE RESTING PLACE — where the wyrm sleeps, on the hall floor beside the
## board. Chosen against the real gameplay camera (pivot (0,0.4,0), yaw PI,
## pitch -0.85, fov 50, 16:9), not by eye on a preview render:
##   * the EAST aisle, x 6.6 — outside the board (±4) and inside the feast
##     table at x 9; it lands 18% across the frame and dead level with the
##     board's middle, i.e. LOOMING beside it and not covering one square;
##   * the camera's orbit ring never gets near it: the tightest zoom step that
##     can reach the wyrm's radius at all still puts the eye 3.5 m up, and at
##     the default 11.5/-0.85 the eye is 9 m up (test_dragon.gd solves this
##     rather than sampling it);
##   * yaw -0.3PI turns the head toward the board's east flank AND puts the
##     beast BROADSIDE to the camera. That last one is not decoration: at the
##     first yaw tried (-3PI/4) the camera looked down the wyrm's spine and
##     the whole animal read as a folded umbrella; in profile the neck, the
##     mantled wing and the curled tail are three separate readable shapes.
##     Checked on the rendered boot frame, not reasoned about.
##
## IT DOES NOT OVERLAP THE TABLE — the second half of the sprawl blocker
## (2026-08-09), and it is a FALSIFIED hypothesis rather than a fix. The east
## feast table stands at x 8.35..9.65 (GreatHall._build_tables, measured). The
## coiled sleeper's furthest bone reaches x 7.34 at rest and x 7.81 at the stir
## floor — 1.01 m and 0.54 m of daylight. Nothing was moved: the furniture was
## never the problem, the reaction CLIP was (see _react), and it reached x 8.74.
## tests/test_dragon.gd::_test_rest_clears_the_table keeps the daylight honest,
## so a later re-tune of the pose cannot walk the wyrm into the benches again.
## No hall anchor exists for this yet (GreatHall is another module's file) —
## see INTEGRATION-dragon.md for the `GreatHall.dragon_rest()` request.
@export var rest_position := Vector3(6.6, -0.3, 0.6)   ## y = GreatHall.FLOOR_Y
@export var rest_yaw := -PI * 0.30
@export var rest_idle_speed := 0.30    ## Perch_Idle, slowed under the coil
@export var rest_ember_energy := 0.40  ## the throat coals, BANKED
@export var wake_ember_energy := 2.60  ## …and kindled (emissive only)
## THE VIGIL (2026-08-17): the wyrm keeps watch AWAKE on a high perch instead
## of sleeping on the hall floor — the fly-in cinematic lands it on the
## cathedral's Wyrm's Gallery and it watches the fight from up there (Bert's
## reference art: the beast on the ledge above the throne, coals lit). With
## vigil on: no slumber coil, Perch_Idle as authored (a standing watch),
## reactions play their full clips (`_react` already branches on is_asleep),
## and at checkmate the wake becomes a crouch-and-dive off the ledge.
## Default OFF: every floor-sleeper contract and test is untouched.
@export var vigil := false
@export var vigil_idle_speed := 0.5
@export var vigil_ember_energy := 0.85
## A stir NEVER uncoils past this. RAISED 0.42 -> 0.62 (2026-08-09) with the
## deeper coil: the fold now travels ~220 deg of neck, so 0.42 of it left the
## beast half-way between coiled and standing — wings tented flat on the stone
## and the neck part-extended, which `showcase/07` and `08` both photographed
## and which reads exactly like the sprawl the new pose exists to kill. At
## 0.62 the body stays folded (wings mantled, tail curled) and it is the HEAD
## that lifts, which is what a disturbed sleeper actually does.
@export var stir_slumber_floor := 0.62

## Airborne anchor above the far wall. Nothing perches here any more — it is
## kept because the integrator feeds it from GreatHall.spectator_perch() (the
## e2e asserts the two agree) and the breath phase uses it as the fixed
## reference for which side of the beaten army the wyrm hovers on, which is
## what keeps the ceremony's framing identical to the one that was tuned.
## Root y carries the +1.15 × rig_scale lift the ground-origin serpent-wyrm
## needs (DragonRig.BODY_RISE).
@export var perch_position := Vector3(0.0, 6.0225, 11.2)   ## matches GreatHall.spectator_perch()
@export var perch_yaw := PI            ## face the board (-Z)
@export var dragon_scale := 1.65        ## impressive, majestic wyrm beside the board
@export var idle_speed := 0.55         ## slow Flying_Idle loop in the air
@export var bob_amplitude := 0.14
@export var bob_speed := 0.8           ## rad/s of the bob sine
@export var reaction_every_moves := 2  ## max 1 reaction per N moves
@export var glance_min_gap := 6.0      ## idle head-turn cadence (wall sec)
@export var glance_max_gap := 10.0

# CEREMONY wall-clock timings (exported so tests can shrink them).
@export var ash_stir_wall := 0.55      ## the head comes off the stone
@export var ash_rise_wall := 0.9       ## Land_Settle backwards: it stands up
@export var ash_roar_wall := 1.2       ## THE ROAR — on the ground, before the wings
@export var ash_ramp_wall := 0.25      ## slow-mo dip in (rides the stir)
@export var ash_bank_wall := 2.0       ## takeoff climb + one lap of the hall
@export var ash_flare_wall := 0.7      ## bank -> wing-spread hover, board center
@export var ash_inhale_wall := 0.6     ## ONE beat of stillness — the inhale
@export var ash_swoop_wall := 1.3      ## championship: the crown-bank to the throne
@export var ash_breath_wall := 2.8     ## the fire sweep across the army
@export var ash_linger_wall := 1.6     ## jet cut; embers/ash drift, bones fall
@export var ash_return_wall := 1.1     ## match: down to the stone and land
@export var ash_settle_wall := 1.4     ## championship: slow wing-settle on the throne
@export var ash_flash_wall := 0.12     ## ignition flash before the skeleton swap
@export var ash_smolder_wall := 1.2    ## smoldering beat between swap and collapse
@export var ash_collapse_wall := 0.8   ## Death_A is retimed to fit this window
@export var ash_char_wall := 0.4       ## tint -> charcoal (Tidegrip char-in-place)
@export var ash_crumble_wall := 0.45   ## final sink into the stone, then freed
@export var ash_hover_height := 1.85    ## elevated hover height for bigger dragon wings
@export var ash_hover_backoff := 4.1   ## distance from the losers' centroid
@export var ashfall_slow_scale := 0.55
@export var ceremony_scale := 2.25      ## the wyrm swells with massive presence for the ceremony
@export var champ_scale := 2.55         ## …and majestic roost upon the throne
@export var bank_radius := 6.8         ## inside the ±12 walls and 10.6-radius pillars
@export var bank_height := 5.11        ## bank floor root y for giant dragon
@export var failsafe_wall_sec := 20.0   ## > the championship worst case (15.9)
@export var keep_skeletons := true      ## Terminator 2: charred skeletons remain on the board

## Integrator references (both duck-typed, both optional):
## anything with is_active() gates reactions off the duel-cam;
## anything with square_to_world(Vector2i) converts board squares.
var duel_director: Node = null
var board: Node = null

var rig: DragonRig = null
var caption: CineCaption = null

var _reacting := false
var _moves_since_reaction := 99        # first reaction is always allowed
var _last_move_pos := Vector3.INF
var _glance_in := 4.0
var _gaze_id := 0
var _look: LookAtModifier3D = null
var _gaze_target: Node3D = null

## THE SLEEPER. `_slumber` is DragonRig's coil modifier; its `weight` is the
## whole rest/stir/wake state in one number (1 = coiled asleep, 0 = the clip
## as authored). `_slumber_id` cancels an in-flight ramp the way `_gaze_id`
## cancels a glance — a stir that lands mid-settle must not fight it.
var _slumber = null                    # DragonRig.Slumber
var _perch: Node = null                # DragonRig.PerchSway (vigil only)
var _slumber_id := 0
var _ember := 0.0                      # current throat-coal energy

## World points the ceremony caption must never cover (the throne, the
## crowned king on the dais). The integrator fills this; the ceremony adds
## the burning army itself while the jet is up. See CineCaption.
var ceremony_avoid: Array = []

var _ash_active := false
var _ash_skip := false
var _ash_seq := 0
## THE CEREMONY'S OWN CLOCK, EXPOSED. The ashfall runs on wall time while the
## engine clock is bent to 0.55 — so any test that sleeps `n` seconds after
## the dip actually sleeps n/0.55 and lands somewhere else entirely. That is
## exactly how the torrent shipped for a day with NO FRAME OF IT ANYWHERE:
## the dragon-live scenario's post-dip await put 02_mid_ashfall at ~2.8 s,
## the tail of the BANK, while the jet does not ignite until ~4.85 s (critic
## defect P1, 2026-08-09). Instruments must wait on STATE, not on a stopwatch
## they do not own — these two probes are that state.
var _ash_phase := ""      # "" | launch | bank | flare | inhale | breath | linger | return | crown
var _jet_lit := false     # the jet itself is burning (not the ember tail)
var _prev_time_scale := 1.0
var _ash_losers: Array = []
var _fx: Node3D = null                 # DracarysVFX — the torrent (lazily built)
var _remains: Array = []               # live skeleton entries: {node, anim, smoke, mats}
var _drift: GPUParticles3D = null      # championship tableau ember drift
var _champ_mode := false
var _end_pos := Vector3.ZERO           # tier-aware ceremony end pose
var _end_yaw := PI
var _end_scale := 1.15
var _end_idle_speed := 0.55
var _end_clip := "Perch_Idle"
var _end_slumber := 1.0                # match: re-coils; championship: awake

var _cine_cam: Camera3D = null         # the ceremony camera (windowed only)
var _cam_prev: Camera3D = null
var _cam_live := false
var _cam_tick := 0
var _cam_pos := Vector3.ZERO           # smoothed dolly position
var _cam_look := Vector3.ZERO          # smoothed look point (fast — never loses the wyrm)


func _ready() -> void:
	rig = DragonRigScript.spawn(self, "SpectatorDragon", Vector3.ZERO, 0.0, dragon_scale)
	position = rest_position
	rotation.y = rest_yaw
	# THE COIL. Built before the first clip so no frame of the match ever
	# shows the beast standing to attention. (A vigil keeps the modifier at
	# weight 0 — attached but dormant, so the checkmate wake path stays one
	# code path for both postures.)
	_slumber = rig.attach_slumber(DragonRigScript.slumber_default(), 0.05, 0.55)
	_set_slumber(0.0 if vigil else 1.0)
	# A VIGIL IS STILL A LIVING ANIMAL. Perch_Idle welds the legs (two keys
	# per leg bone against the torso's ninety-seven), so a watching wyrm sat
	# with its feet nailed down. The coiled sleeper does not want this — its
	# legs are couched under it by the slumber pose — so it is vigil-only.
	if vigil:
		_perch = rig.attach_perch_sway()
	rig.play_loop("Perch_Idle", vigil_idle_speed if vigil else rest_idle_speed)
	if rig.anim != null:   # desync from the championship dragon's flap
		rig.anim.seek(randf() * rig.clip_length("Perch_Idle"))
	_set_ember(vigil_ember_energy if vigil else rest_ember_energy)
	caption = CaptionScript.new()
	caption.name = "AshfallCaption"
	add_child(caption)
	_cine_cam = Camera3D.new()
	_cine_cam.name = "CeremonyCam"
	_cine_cam.top_level = true   # ignores the perch/bank motion of this node
	_cine_cam.current = false
	add_child(_cine_cam)
	_end_pos = rest_position
	_end_yaw = rest_yaw
	_end_scale = dragon_scale
	_end_idle_speed = vigil_idle_speed if vigil else rest_idle_speed
	_end_clip = "Perch_Idle"
	_end_slumber = 0.0 if vigil else 1.0
	_build_gaze()
	_glance_in = randf_range(glance_min_gap, glance_max_gap)


func _process(delta: float) -> void:
	# THE COUCH. The coil folds the legs, which lifts the toe claws 0.32
	# rig-local units — so the rig node sinks by exactly that much times its
	# scale and the claws stay ON the stone instead of hovering over it. It
	# tracks `weight`, so standing up during the wake also physically raises
	# the body. Runs before the ceremony early-out: the wake needs it.
	if rig != null and is_instance_valid(rig):
		rig.position.y = -DragonRigScript.SLUMBER_ROOT_DROP \
			* rig.scale.x * _slumber_weight()
	if _ash_active:
		# Keep the ceremony caption sliding clear of what it is filming.
		if caption != null and is_instance_valid(caption):
			caption.avoid_points = _caption_avoid()
		return
	if _champ_mode:
		# After a championship the roost IS the throne perch — still airborne,
		# so it keeps the gentle bob (wall clock: the perch ignores slow-mo).
		var t := float(Time.get_ticks_msec()) / 1000.0
		position = THRONE_PERCH \
			+ Vector3.UP * (sin(t * bob_speed * TAU * 0.5) * bob_amplitude)
	else:
		# A sleeping animal on stone does not bob. Its breathing lives in the
		# clip and in the coil's own swell — putting a hover sine on a beast
		# that is lying down is precisely the tell that it is not.
		position = rest_position
	# Occasional head turn toward the last-moved piece. Asleep this is a
	# half-glance — one eye cracked at the board, not a look.
	_glance_in -= clampf(delta / maxf(Engine.time_scale, 0.05), 0.0, 0.1)
	if _glance_in <= 0.0:
		_glance_in = randf_range(glance_min_gap, glance_max_gap)
		if _last_move_pos.is_finite() and not _reacting and not _duel_cam_active():
			_gaze_pulse(_last_move_pos, 0.4 if is_asleep() else 0.75, 1.4)


# ── spectator API ──────────────────────────────────────────────────────────


## Feed one ply: advances the reaction rate limiter and retargets the idle
## glance. `world_pos` — where the moved piece landed (Vector3 or Vector2i).
func notice_move(world_pos: Variant = null) -> void:
	_moves_since_reaction = mini(_moves_since_reaction + 1, 99)
	var p := _to_world(world_pos)
	if p.is_finite():
		_last_move_pos = p
		_glance_in = minf(_glance_in, randf_range(1.5, 3.5))


## Undo support: a take-back removes plies notice_move already counted —
## wind the reaction rate limiter back so the wyrm's patience stays honest.
func rewind_moves(n: int) -> void:
	_moves_since_reaction = maxi(_moves_since_reaction - n, 0)


func can_react() -> bool:
	return not _ash_active and not _reacting \
		and _moves_since_reaction >= reaction_every_moves \
		and not _duel_cam_active() \
		and rig != null and rig.anim != null


func react_blunder() -> bool:
	return _react("No", 0.45, Vector3.INF)


func react_brilliant() -> bool:
	return _react("Yes", 0.45, Vector3.INF)


func react_capture(square: Variant = null) -> bool:
	return _react("HitReact", 0.7, _to_world(square))


## THE STIR — a sleeping beast disturbed, never woken. The coil eases back
## only as far as `stir_slumber_floor` (the head lifts, the shoulders come
## off the stone, the tail stays curled), the throat coals blink, the
## breathing quickens, and then it settles back down. The floor is the
## contract: NOTHING that happens on the board — not a queen taken, not a
## mate threat — fully wakes it. Only checkmate does.
##
## ── A SLEEPING BEAST NEVER SWAPS ITS CLIP (critic blocker, 2026-08-09) ────
## Until now the stir also PLAYED a reaction clip — `HitReact` / `Yes` / `No`
## — over the coil. Those clips are authored for a beast that is standing up:
## they throw the wings out. The coil cannot put back what a full-body clip
## spreads, because the coil's own wing terms are 12 deg and 22 deg (see
## DragonRig.SLUMBER_WING1/2) while the clip moves them through a right
## angle. Measured on the live rig, world x of the wing/tail bones at rest
## position, coil at the stir floor (0.62):
##
##   Perch_Idle  coil 1.00   x-span 1.10   max x 7.34   ← the coiled sleeper
##   Perch_Idle  coil 0.62   x-span 2.16   max x 7.81   ← head up, wings in
##   HitReact    coil 0.62   x-span 3.19   max x 8.74   ← the right wing OUT
##   Yes / No    coil 0.62   x-span 2.49   max x 8.06   ← wings up in the air
##
## The east feast table stands at x 8.35..9.65 (GreatHall._build_tables), so
## `HitReact` did not merely unfold the wyrm — it drove a wing membrane 0.4 m
## THROUGH the furniture, which is exactly what duel/04_post_duel and
## showcase/07-08 photographed. Both defects, one cause: a capture is the last
## thing that happens before the post-duel frame is taken, so the frame caught
## the flinch every time.
##
## So a stir is now the coil, the coals and the breath, and nothing else:
## `Perch_Idle` keeps running (quickened by `stir_idle_rush` — what a disturbed
## sleeper actually changes is the RATE of its breathing), the head lifts
## because the coil eases, and the silhouette stays a folded animal in every
## frame. Awake — after a championship, on the throne — the clips are still
## the right instrument and still play.
@export var stir_hold_wall := 1.05    ## how long a coil-only stir holds
@export var stir_idle_rush := 2.4     ## x rest_idle_speed while disturbed


func _react(clip: String, speed: float, look_pos: Vector3) -> bool:
	if not can_react():
		return false
	var asleep := is_asleep()
	_moves_since_reaction = 0
	_reacting = true
	if look_pos.is_finite():
		_last_move_pos = look_pos
		_gaze_pulse(look_pos, 0.9, 0.8)
	if not vigil:
		_slumber_ramp(stir_slumber_floor, 0.35)
	_ember_blink()
	var dur := stir_hold_wall
	if asleep:
		# The breath quickens; the pose does not change hands.
		rig.play_loop("Perch_Idle", rest_idle_speed * stir_idle_rush, 0.25)
	else:
		dur = maxf(rig.play_once(clip, speed), 0.1)
	var runner := func() -> void:
		await _wall_sleep(dur)
		if is_instance_valid(self) and is_inside_tree():
			_reacting = false
			if not _ash_active:
				rig.play_loop("Perch_Idle",
					vigil_idle_speed if vigil else rest_idle_speed, 0.5)
				if not vigil:
					_slumber_ramp(1.0, 1.1)   # …and settles back
	runner.call()
	return true


## True while the wyrm is coiled on the stone (its whole-match state). False
## from the instant the wake begins and, after a championship, for good.
func is_asleep() -> bool:
	return not _ash_active and not _champ_mode and _slumber_weight() > 0.05


## The coil's blend, 1 = fully asleep. THE probe for "did a capture wake it?"
func slumber_weight() -> float:
	return _slumber_weight()


func _slumber_weight() -> float:
	return float(_slumber.weight) if _slumber != null else 0.0


func _set_slumber(w: float) -> void:
	_slumber_id += 1   # any in-flight ramp loses
	if _slumber != null:
		_slumber.weight = clampf(w, 0.0, 1.0)


## Cross-fade the coil to `to` over `dur` wall seconds. Fire-and-forget; a
## later ramp (or a hard _set_slumber) cancels this one via _slumber_id.
func _slumber_ramp(to: float, dur: float) -> void:
	if _slumber == null:
		return
	_slumber_id += 1
	var my_id := _slumber_id
	var from: float = _slumber.weight
	var runner := func() -> void:
		var t0 := Time.get_ticks_msec()
		while _slumber_id == my_id and is_instance_valid(self) and _slumber != null:
			var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
			_slumber.weight = lerpf(from, to, _ease_cubic(u))
			if u >= 1.0:
				return
			var tree := get_tree()
			if tree == null:
				return
			await tree.process_frame
	runner.call()


func _set_ember(v: float) -> void:
	_ember = v
	if rig != null and is_instance_valid(rig):
		rig.set_ember_energy(v)


## One slow blink of the banked coals: a dim, then back. The wyrm's eye
## sockets are authored as holes (`dragon_void`), so the coals ARE its eye —
## and they are emission, never a Light3D (the hall's 8 omnis are all torches).
func _ember_blink() -> void:
	var base := _ember
	var runner := func() -> void:
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(self) and not _ash_active:
			var u := clampf(float(Time.get_ticks_msec() - t0) / 900.0, 0.0, 1.0)
			_set_ember(base * (1.0 + 0.9 * sin(u * PI)))
			if u >= 1.0:
				_set_ember(base)
				return
			var tree := get_tree()
			if tree == null:
				return
			await tree.process_frame
	runner.call()


func _duel_cam_active() -> bool:
	return duel_director != null and is_instance_valid(duel_director) \
		and duel_director.has_method("is_active") and duel_director.is_active()


func _to_world(square: Variant) -> Vector3:
	if square is Vector3:
		return square
	if square is Vector2i and board != null and is_instance_valid(board) \
			and board.has_method("square_to_world"):
		var local: Vector3 = board.square_to_world(square)
		if board is Node3D:
			return (board as Node3D).to_global(local)
		return local
	return Vector3.INF


func is_ashfall_active() -> bool:
	return _ash_active


## Which beat of the ceremony is on screen right now (see _ash_phase). "" when
## no ceremony is running. THE instrument hook: an e2e that wants the torrent
## waits for this, never for a wall-clock guess.
func ashfall_phase() -> String:
	return _ash_phase


## True only while the JET is burning — the beat a fire photograph must be
## taken in. Goes false the instant the ceremony cuts the jet, while
## is_fire_tail_alive() is still true for the embers/ash that outlive it.
func is_jet_burning() -> bool:
	return _jet_lit and _fx != null and is_instance_valid(_fx) and _fx.is_active()


## True while ANY of the fire lives — jet, embers, drifting ash, ground smoke.
func is_fire_tail_alive() -> bool:
	return _fx != null and is_instance_valid(_fx) and _fx.is_active()


## The points the ceremony caption must clear this frame: whatever the
## integrator handed us, plus the army currently being burned.
func _caption_avoid() -> Array:
	var pts: Array = ceremony_avoid.duplicate()
	if _ash_phase == "breath" or _ash_phase == "linger":
		var c := _losers_centroid()
		if c.is_finite():
			pts.append(c + Vector3.UP * 0.8)
	return pts


## Remove the spectator (e.g. before the championship tableau summons its
## own throne dragon). Restores presentation via _exit_tree.
func dismiss() -> void:
	queue_free()


# ── ASHFALL ────────────────────────────────────────────────────────────────


## THE CEREMONY (awaitable; see the header for the full shape). Call AFTER
## the losing king's death cinematic released and BEFORE the victory /
## championship flow. `losers` may be passed explicitly (the integrator's
## own view list); when empty the tree is duck-scanned for Node3D with
## side == losing_side. `winning_house` is the display name used in the
## captions. `championship` selects the throne-perch tier (call-compatible:
## the game's existing 3-arg call plays the match tier).
func play_ashfall(losing_side: int, winning_house: String = "",
		losers: Array = [], championship: bool = false) -> void:
	if _ash_active or not is_inside_tree():
		return
	# Never overlap the duel-cam: wait (bounded) for it to release.
	var wait0 := Time.get_ticks_msec()
	while _duel_cam_active() and Time.get_ticks_msec() - wait0 < 3000:
		await get_tree().process_frame
	_ash_seq += 1
	var seq := _ash_seq
	_ash_active = true
	_ash_skip = false
	_champ_mode = championship
	_prev_time_scale = Engine.time_scale
	_end_pos = THRONE_PERCH if championship else rest_position
	_end_yaw = PI if championship else rest_yaw
	_end_scale = champ_scale if championship else dragon_scale
	_end_idle_speed = 0.45 if championship else rest_idle_speed
	_end_clip = "Flying_Idle" if championship else "Perch_Idle"
	_end_slumber = 0.0 if championship else 1.0
	_ash_losers = []
	for p in (losers if not losers.is_empty() else _collect_losers(losing_side)):
		if is_instance_valid(p) and p is Node3D and not p.is_queued_for_deletion():
			_ash_losers.append(p)
	_ash_phase = "wake"
	_jet_lit = false
	ashfall_started.emit()
	_arm_failsafe(seq)
	_gaze_off()
	_cam_take()   # windowed only: the ceremony camera (no-op headless)

	# ── I. THE WAKE ───────────────────────────────────────────────────────
	# The one moment the whole match has been building to, and the reason the
	# wyrm spends the match on the floor: it has somewhere to go. Three beats,
	# in this order, ON THE GROUND. The roar lands BEFORE the wings by
	# construction — they are separate phases and the wings do not move until
	# the bank.
	#
	# I.a THE STIR — the head comes up off the stone and the coals kindle.
	# The slow-mo dip rides this beat instead of costing its own (detached:
	# _wall_lerp bails on seq/skip, so a click here still snaps cleanly).
	_ts_ramp(seq, ashfall_slow_scale, ash_ramp_wall)
	var wake_pos := position
	var stir := func(u: float) -> void:
		_set_slumber(1.0 - _ease_cubic(u))
		_set_ember(lerpf(rest_ember_energy, wake_ember_energy, u))
		# THE WAKE DOLLY drops to the floor and pushes in over the three
		# beats. Every mark stands in the NEAR AISLE (z <= -4.9, past the
		# board's near rank) — the same scar the bank's dolly carries: a
		# ceremony camera that stands ON the board shoots every frame from
		# inside somebody's helmet.
		_cam_track(Vector3(0.9, 1.75, -7.2), _body_pos())
	rig.play_loop("Perch_Idle", 0.85, 0.35)
	await _wall_lerp(seq, stir, 0.0, 1.0, ash_stir_wall)
	if _ash_seq != seq or _ash_skip:
		return
	# I.b THE RISE — `Land_Settle` run BACKWARDS: folded wings open, the
	# weight comes up off the haunches. Driven by hand (see DragonRig.
	# play_manual) because no playback speed plays a clip in reverse.
	var rising := rig.play_manual("Land_Settle")
	var rise := func(u: float) -> void:
		if rising:
			rig.seek_clip(lerpf(RISE_CLIP_SETTLED, RISE_CLIP_UP, _ease_cubic(u)))
		position = wake_pos + Vector3.UP * (0.12 * u)
		_cam_track(Vector3(1.7, 1.45, -6.1), _body_pos())
	await _wall_lerp(seq, rise, 0.0, 1.0, ash_rise_wall)
	if _ash_seq != seq or _ash_skip:
		return
	# I.c THE ROAR — head up, jaw wide, still standing on the hall floor.
	# This is where the caption's mark lands: the sound, then the flight.
	_ash_phase = "roar"
	rig.play_once("Roar", 1.0, 0.25)
	caption.show_line("ASHFALL.")
	var roar_pos := position
	var roar := func(u: float) -> void:
		position = roar_pos + Vector3.UP * (0.10 * sin(u * PI))
		_cam_track(Vector3(2.6, 1.15, -4.9), _body_pos() + Vector3.UP * 0.95)
	await _wall_lerp(seq, roar, 0.0, 1.0, ash_roar_wall)
	if _ash_seq != seq or _ash_skip:
		return
	rig.play_loop("Fast_Flying", 1.15)   # NOW the wings — hard beats off the floor
	_scale_ramp(seq, ceremony_scale, ash_bank_wall + ash_flare_wall)   # swells, never pops

	# ── II. THE BANK — the takeoff climb straight into one sweeping pass
	# around the hall, filmed from below: the low-angle camera pushes in as
	# the wyrm thunders overhead.
	_ash_phase = "bank"
	var start_pos := position
	var th0 := atan2(start_pos.x, start_pos.z)
	var prev_p := start_pos
	var beats_eased := false
	var t0 := Time.get_ticks_msec()
	while true:
		if _ash_seq != seq or _ash_skip:
			return   # skip() already snapped to the end state
		var u := clampf(float(Time.get_ticks_msec() - t0) / (ash_bank_wall * 1000.0), 0.0, 1.0)
		var e := _ease_cubic(u)
		var th := th0 - e * TAU   # one full clockwise lap of the hall
		var r := lerpf(bank_radius, 5.2, e)
		var h := lerpf(bank_height + 1.0, bank_height, e)
		var target := Vector3(sin(th) * r, h, cos(th) * r)
		# The smooth climb: the takeoff blends over the first third of the lap
		var p := start_pos.lerp(target, _ease_cubic(clampf(u / 0.35, 0.0, 1.0)))
		var v := p - prev_p
		prev_p = p
		position = p
		if v.length() > 0.001:
			rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 0.35)
		rotation.z = -0.32 * sin(u * PI)   # smooth banking lean into the turn
		if not beats_eased and u >= 0.4:
			beats_eased = true   # off the floor: hard beats settle into cruise
			rig.play_loop("Fast_Flying", 0.8, 0.5)
		# The awe shot: a low camera pulled back from the board — the wyrm
		# wheels across the hall as a winged SILHOUETTE (this asset's
		# majesty lives in its wingspan at distance, never in close-ups).
		# It must stand in the AISLE, not on the board: at z -4.5 the dolly
		# sat a single tile from the near rank and every ashfall frame was
		# shot from inside somebody's helmet (found by eye, 2026-08-09).
		#
		# RAISED AND TILTED DOWN 2026-08-09. At (0, 1.35, -9.0) aimed square at
		# the body, the dolly looked so steeply UP that every sightline behind
		# the wyrm left the room: `04_mid_ashfall` shipped a dragon on pure
		# black, the one frame a critic called broken. The hall now has a roof
		# (GreatHall._build_roof), and this mark keeps it in shot — back to the
		# near wall, up to head height of a standing man, and the look point
		# dropped BELOW the wyrm so the banner wall and the board ride the
		# bottom of the frame instead of falling out of it.
		_cam_track(Vector3(0.0, 2.4, -10.4), _body_pos() - Vector3.UP * 1.4)
		if u >= 1.0:
			break
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame

	# ── III. THE FLARE — wing-spread hover above the board center ──
	_ash_phase = "flare"
	rig.play_loop("Flying_Idle", 0.6, 0.5)   # slow flap: the mighty hover
	var hover_center := Vector3(0.0, 3.11, 0.0)   # 1.50 + 1.15×1.4 (root moved)
	var f0_pos := position
	var f0_yaw := rotation.y
	var f0_roll := rotation.z
	var flare := func(u: float) -> void:
		position = f0_pos.lerp(hover_center, u) + Vector3.UP * sin(u * PI) * 0.5
		rotation.y = lerp_angle(f0_yaw, PI, u)
		rotation.z = lerpf(f0_roll, 0.0, u)
		_cam_track(Vector3(0.0, 1.55, -9.6), _body_pos())
	await _wall_lerp(seq, flare, 0.0, 1.0, ash_flare_wall)
	if _ash_seq != seq or _ash_skip:
		return

	# ── IV. THE INHALE — one beat of stillness before the judgment ──
	_ash_phase = "inhale"
	_ensure_fx()   # build the torrent now, off-screen, not on the ignition frame
	var inhale := func(u: float) -> void:
		position = hover_center + Vector3.UP * (0.18 * u)
		_cam_track(Vector3(0.0, 1.7, -9.2), _body_pos())
	await _wall_lerp(seq, inhale, 0.0, 1.0, ash_inhale_wall)
	if _ash_seq != seq or _ash_skip:
		return

	# ── V. THE BREATH — the fire sweep across the beaten army; every
	# warrior the jet touches burns down to a smoldering skeleton ──
	_ash_phase = "breath"
	var focus := _losers_centroid()
	var away := perch_position - focus
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var breath_hover := Vector3(focus.x, ash_hover_height, focus.z) + away * ash_hover_backoff
	# `Rear_Breathe` is driven BY HAND: the lunge is played fast, then the
	# held-blast pose is crawled through for the whole fire sweep (see
	# DragonRig.play_manual). The jet ignites the frame the jaws reach the
	# hold and cuts when the sweep ends — the beat the asset was authored for.
	var manual := rig.play_manual("Rear_Breathe")
	if not manual:
		rig.play_once("Headbutt", 1.4, 0.2)   # ancient rigs without the clip
	var order := _sweep_order(breath_hover)
	var burned := {}
	var line := _kill_line(winning_house)
	var line_shown := false
	var lit := false
	var jet_side := (focus - breath_hover).cross(Vector3.UP)
	jet_side = jet_side.normalized() if jet_side.length() > 0.01 else Vector3.RIGHT
	var inhale_pos := position
	var bt0 := Time.get_ticks_msec()
	while _ash_seq == seq and not _ash_skip:
		var u := clampf(float(Time.get_ticks_msec() - bt0) / (ash_breath_wall * 1000.0), 0.0, 1.0)
		position = inhale_pos.lerp(breath_hover, clampf(u / 0.2, 0.0, 1.0))
		if manual:
			rig.seek_clip(_breath_clip_time(u))
		# The blast: fire only while the jaws are open on the held pose.
		var blasting := u >= BREATH_LUNGE_FRAC
		var b := clampf((u - BREATH_LUNGE_FRAC) / maxf(1.0 - BREATH_LUNGE_FRAC, 0.001), 0.0, 1.0)
		var aim := _sweep_aim(order, b, focus)
		_aim_breath(aim, breath_hover)
		if blasting and not lit:
			lit = true
			_fire_start(aim)
		elif blasting:
			_fire_aim(aim)
		# Ignite each survivor as the jet passes its slot in the sweep.
		var slot := (int(floor(b * order.size() - 0.0001)) if blasting else -1) \
			if order.size() > 0 else -1
		for i in range(0, slot + 1):
			if not burned.has(i):
				burned[i] = true
				_incinerate(order[i], seq)
		if not line_shown and u >= 0.55:
			line_shown = true
			caption.show_line(line)
		# Both subjects in one frame: the wyrm rearing and the army it is
		# burning. Raised and pulled back 2026-08-09 — at UP*1.8 the dolly
		# stood among the pieces and the head that the jet leaves was off
		# the top of every blast frame.
		_cam_track(focus + jet_side * 6.4 + Vector3.UP * 3.4
			- (focus - breath_hover).normalized() * 2.6,
			focus.lerp(_body_pos() + Vector3.UP * 1.5, 0.62))
		if u >= 1.0:
			break
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
	if _ash_seq != seq or _ash_skip:
		return   # skip() already snapped to the end state
	for i in order.size():   # anything the sweep math missed still burns
		if not burned.has(i):
			burned[i] = true
			_incinerate(order[i], seq)

	# ── VI. THE LINGER — the jet cuts; embers and drifting ash hang in
	# the torchlight while the last of the burned fall. The wyrm departs
	# only when the field is bones and ash (bounded).
	# cut() is the GRACEFUL stop: the jet retracts over 0.16 s while the
	# embers, ash, ground fire and smoke live on for seconds — the lingering
	# tail this phase exists to show. hard_stop() would kill them too.
	_ash_phase = "linger"
	_fire_cut()
	_gaze_off()   # the head comes back off the aim point with the jet
	var recoil_wall := minf(ash_linger_wall * 0.45, 0.65)
	if not manual:
		rig.play_loop("Flying_Idle", 0.6, 0.4)
	var lt0 := Time.get_ticks_msec()
	while _ash_seq == seq and not _ash_skip:
		var el := float(Time.get_ticks_msec() - lt0) / 1000.0
		# The recoil out of the blast, then back to the hover loop.
		if manual:
			if el < recoil_wall:
				rig.seek_clip(lerpf(BREATH_HOLD_END, BREATH_CLIP_END,
					clampf(el / maxf(recoil_wall, 0.001), 0.0, 1.0)))
			else:
				manual = false
				rig.play_loop("Flying_Idle", 0.6, 0.4)
		if el >= ash_linger_wall and (_field_resolved() or el >= ash_linger_wall + 2.2):
			break
		_cam_track(focus + jet_side * 4.4 + Vector3.UP * 2.2
			- (focus - breath_hover).normalized() * 1.4,
			focus + Vector3.UP * 0.7)
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
	if _ash_seq != seq or _ash_skip:
		return

	if not championship:
		# ── VII. THE RETURN — down to the stone it slept on, and LAND.
		# Size and clock restored on the way. `Land_Settle` is played forward
		# here (the wake ran it backwards) from 40% of the descent, so the
		# flare and touchdown land under the beast as it arrives; _ash_finish
		# then blends Perch_Idle in and the coil ramps back over 1.2 s.
		_ash_phase = "return"
		rig.play_loop("Fast_Flying", 1.0, 0.3)
		_scale_ramp(seq, dragon_scale, ash_return_wall)
		var from := position
		var from_yaw := rotation.y
		var touched := {"v": false}
		var back := func(u: float) -> void:
			position = from.lerp(rest_position, _ease_cubic(u)) \
				+ Vector3.UP * sin(u * PI) * 0.8
			rotation.y = lerp_angle(from_yaw, rest_yaw, u)
			rotation.z = lerpf(rotation.z, 0.0, 0.15)
			if not touched["v"] and u >= 0.4:
				touched["v"] = true
				rig.play_once("Land_Settle", 1.5, 0.35)
			_cam_home(u)
		await _wall_lerp(seq, back, 0.0, 1.0, ash_return_wall)
	else:
		# ── VII. THE CROWNING — one more bank, then the throne perch ──
		_ash_phase = "crown"
		rig.play_loop("Fast_Flying", 1.0, 0.3)
		_scale_ramp(seq, champ_scale, ash_swoop_wall + ash_settle_wall * 0.5)
		var c0 := position
		var c_hold := {"prev": c0}
		var champ_arc := func(u: float) -> void:
			var mid := Vector3(5.8, bank_height + 0.4, 4.4)   # wide over the east aisle
			var p := _bezier3(c0, mid, THRONE_PERCH + Vector3.UP * 0.7, u)
			var v: Vector3 = p - c_hold["prev"]
			c_hold["prev"] = p
			position = p
			if v.length() > 0.001:
				rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 0.4)
			rotation.z = -0.3 * sin(u * PI)
			_cam_track(Vector3(2.0, 1.15, 3.4), THRONE_PERCH + Vector3.UP * 1.7)
		await _wall_lerp(seq, champ_arc, 0.0, 1.0, ash_swoop_wall)
		if _ash_seq != seq or _ash_skip:
			return
		# The slow wing-settle onto the perch above the Throne of Blades,
		# with the caption beat: the ceremony's mark, then the crown —
		# strictly sequential, the two lines never overlap.
		rig.play_loop("Flying_Idle", 0.45, 0.9)
		caption.show_line("ASHFALL.")
		var s0 := position
		var s0_yaw := rotation.y
		var s0_roll := rotation.z
		var settle := func(u: float) -> void:
			position = s0.lerp(THRONE_PERCH, u)
			rotation.y = lerp_angle(s0_yaw, PI, u)
			rotation.z = lerpf(s0_roll, 0.0, u)
			_cam_track(Vector3(2.0, 1.15, 3.4), THRONE_PERCH + Vector3.UP * 1.7)
		await _wall_lerp(seq, settle, 0.0, 1.0, ash_settle_wall)
		if _ash_seq != seq or _ash_skip:
			return
		_ensure_drift()   # gentle embers over the tableau
		await _wall_wait_seq(seq, 0.4)
		if _ash_seq != seq or _ash_skip:
			return
		caption.show_line("%s takes the throne." % (
			winning_house if not winning_house.is_empty() else "The champion"))
		await _wall_wait_seq(seq, 1.3)
	_ash_finish(seq)


## Snap the ceremony to its tier's end state: all losers AND smoldering
## skeletons removed, camera + clock restored, dragon on the wall perch
## (match) or the throne perch (championship). Wired to click/Esc.
func skip() -> void:
	if not _ash_active or _ash_skip:
		return
	_ash_skip = true
	_ash_finish(_ash_seq)


## Live skeleton count on the ash field (test probe).
func remains_count() -> int:
	var n := 0
	for entry in _remains:
		if is_instance_valid(entry.get("node")):
			n += 1
	return n


func _ash_finish(seq: int) -> void:
	if not _ash_active or seq != _ash_seq:
		return
	_ash_active = false
	_ash_phase = ""
	Engine.time_scale = _prev_time_scale
	_fire_stop()   # THE SKIP: clears every particle AND restores env + camera
	_gaze_off()
	if caption != null:
		caption.avoid_points = []
		caption.hide_line()
	for p in _ash_losers:   # end state: every loser gone, skipped or not
		if is_instance_valid(p) and p is Node3D:
			p.queue_free()
	_ash_losers.clear()
	if not keep_skeletons or _ash_skip:
		for entry in _remains:   # clean smoldering skeletons on skip or non-persistent mode
			var n = entry.get("node")
			if is_instance_valid(n):
				n.queue_free()
		_remains.clear()
	_cam_release()
	# Tier-aware end pose: a match ends back ASLEEP on the stone at 1.15;
	# a championship ends awake on the throne perch at 1.6 with the ember
	# drift on — it has just crowned a house, it does not go back to bed.
	position = _end_pos
	rotation = Vector3(0.0, _end_yaw, 0.0)
	if rig != null:
		rig.scale = Vector3.ONE * _end_scale
		rig.play_loop(_end_clip, _end_idle_speed, 0.3)
	if _end_slumber > 0.0 and not _ash_skip:
		_set_slumber(0.0)          # start from awake…
		_slumber_ramp(_end_slumber, 1.2)   # …and re-coil, visibly
	else:
		_set_slumber(_end_slumber)   # the skip is a snap, by contract
	_set_ember(rest_ember_energy if _end_slumber > 0.0 else wake_ember_energy)
	if _champ_mode:
		_ensure_drift()
	ashfall_finished.emit()


## Clean up any persistent charred skeletons from the battlefield.
func clear_remains() -> void:
	for entry in _remains:
		var n = entry.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_remains.clear()


func _exit_tree() -> void:
	## Finally-style guarantee: a freed spectator never strands a slowed
	## clock, a stolen viewport or a lifted exposure (the DuelDirector
	## hygiene rule, extended to the dracarys environment lift).
	if _ash_active:
		_ash_active = false
		_ash_phase = ""
		Engine.time_scale = _prev_time_scale
		# The integrator's chrome/verdict hold is reference-counted off this
		# signal: a spectator freed mid-ceremony must still balance the books,
		# or the HUD stays faded and the victory card never opens.
		ashfall_finished.emit()
	_fire_stop()
	for entry in _remains:   # remains live outside this subtree — free them
		var n = entry.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_remains.clear()
	_cam_release()


func _input(event: InputEvent) -> void:
	if not _ash_active:
		return
	var wants_skip := false
	if event is InputEventMouseButton and event.pressed:
		wants_skip = true
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		wants_skip = true
	if wants_skip:
		skip()
		get_viewport().set_input_as_handled()


func _arm_failsafe(seq: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(failsafe_wall_sec, true, false, true)
	t.timeout.connect(func() -> void:
		if is_instance_valid(self) and _ash_seq == seq and _ash_active and not _ash_skip:
			push_warning("DragonSpectator failsafe: ashfall overran — snapping to end state")
			skip())


func _set_ts(v: float) -> void:
	Engine.time_scale = v


## The cinematic slow-mo dip, DETACHED so it can ride the wake's first beat
## instead of costing the budget a phase of its own. Same seq/skip discipline
## as every other _wall_lerp: a click during the dip returns without writing,
## and _ash_finish has already restored the clock by then.
func _ts_ramp(seq: int, to: float, dur: float) -> void:
	var from := Engine.time_scale
	var runner := func() -> void:
		await _wall_lerp(seq, _set_ts, from, to, dur)
	runner.call()


# ── ashfall internals ──────────────────────────────────────────────────────


func _collect_losers(losing_side: int) -> Array:
	## Duck-scan: every Node3D with `side` == losing_side and an int
	## `piece_type` that is not the king (he fell to the checkmate
	## cinematic already).
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	for n in tree.root.find_children("*", "Node3D", true, false):
		if n.is_queued_for_deletion():
			continue
		var s: Variant = n.get("side")
		var pt: Variant = n.get("piece_type")
		if typeof(s) == TYPE_INT and typeof(pt) == TYPE_INT \
				and int(s) == losing_side and int(pt) != PIECE_KING:
			out.append(n)
	return out


func _losers_centroid() -> Vector3:
	if _ash_losers.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n := 0
	for p in _ash_losers:
		if is_instance_valid(p) and p is Node3D:
			sum += (p as Node3D).global_position
			n += 1
	return sum / maxf(1.0, float(n))


func _sweep_order(hover: Vector3) -> Array:
	## Losers sorted by bearing from the hover point — one continuous arc
	## of fire instead of a random spray.
	var order: Array = []
	for p in _ash_losers:
		if is_instance_valid(p) and p is Node3D:
			order.append(p)
	order.sort_custom(func(a, b) -> bool:
		var pa: Vector3 = a.global_position - hover
		var pb: Vector3 = b.global_position - hover
		return atan2(pa.x, pa.z) < atan2(pb.x, pb.z))
	return order


func _sweep_aim(order: Array, u: float, fallback: Vector3) -> Vector3:
	var pts: Array = []
	for p in order:
		if is_instance_valid(p) and p is Node3D:
			pts.append((p as Node3D).global_position)
	if pts.is_empty():
		return fallback
	if pts.size() == 1:
		return pts[0]
	var f: float = u * float(pts.size() - 1)
	var i := clampi(int(floor(f)), 0, pts.size() - 2)
	return (pts[i] as Vector3).lerp(pts[i + 1], f - float(i))


## Wall-clock progress through the breath phase (0..1) -> `Rear_Breathe`
## playhead in seconds. Two segments:
##   u < BREATH_LUNGE_FRAC : clip 0.00 -> 0.92, the cock-back and uncoil,
##                           played FASTER than authored so the lunge snaps
##   u >= BREATH_LUNGE_FRAC: clip 0.92 -> 1.33, THE HELD BLAST, crawled
##                           through so the open-jawed pose covers the whole
##                           fire sweep instead of 0.41 s of it
## The recoil (1.33 -> 2.25) is played out by the linger phase.
static func _breath_clip_time(u: float) -> float:
	if u < BREATH_LUNGE_FRAC:
		return BREATH_LUNGE_END * clampf(u / BREATH_LUNGE_FRAC, 0.0, 1.0)
	var b := clampf((u - BREATH_LUNGE_FRAC) / maxf(1.0 - BREATH_LUNGE_FRAC, 0.001), 0.0, 1.0)
	return lerpf(BREATH_LUNGE_END, BREATH_HOLD_END, b)


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z)   # native forward is +Z


## Turn the whole beast onto the aim point and crank the HEAD after it, so
## the torrent leaves a snout that is actually pointing at what it burns.
##
## The mouth node's own basis is deliberately NOT overwritten any more: the
## dracarys kit aims from the muzzle's ORIGIN to the world target itself, and
## writing a basis onto a BoneAttachment3D child only fights the animation
## that owns the head bone. The LookAtModifier3D already on the Head bone is
## the right instrument — it is limited, eased, and blends with the clip.
func _aim_breath(aim: Vector3, hover: Vector3) -> void:
	rotation.y = _yaw_toward(hover, aim)
	if _look != null and is_instance_valid(_look) and _gaze_target != null:
		_gaze_target.global_position = aim
		_look.influence = 0.85


# ── MORTAL-KOMBAT INCINERATION ─────────────────────────────────────────────
# When the jet touches a warrior: ignition flash -> the flesh burns off and
# a charred KayKit skeleton stands in the same spot and facing -> ~1.2 s
# smoldering beat under sparse grey wisps -> Death_A collapse (shared
# Rig_Medium library via the PieceAssets autoload; tilt-crumble when it is
# not around) -> the bones sink into the stone. Tidegrip's Drowned Legion
# is already bones — the fire just chars them a shade darker.
# Emissive materials only; every path is cleaned by _ash_finish on skip.


func _incinerate(piece: Node3D, seq: int) -> void:
	if not is_instance_valid(piece):
		return
	var runner := func() -> void:
		# 1) Ignition flash: every surface spikes white-hot (emissive only).
		var mats := _override_mats(piece)
		var flash := func(f: float) -> void:
			if not is_instance_valid(piece):
				return
			for e in mats:
				var m: StandardMaterial3D = e[0]
				m.emission_enabled = true
				m.emission = Color(1.0, 0.88, 0.52) * (0.4 + 2.8 * f)
		await _wall_lerp(seq, flash, 0.0, 1.0, ash_flash_wall)
		if _ash_seq != seq or _ash_skip or not is_instance_valid(piece):
			return
		if _is_already_bones(piece):
			await _char_in_place(piece, mats, seq)
			return
		# 2) The swap: same position, same yaw — the warrior is gone, his
		# charred skeleton still stands where he stood.
		var entry := _spawn_remains(piece)
		piece.queue_free()   # consumed by the fire
		if entry.is_empty():
			return
		# 3) The smolder: a beat of stillness under thin grey wisps.
		await _wall_wait_seq(seq, ash_smolder_wall)
		if _ash_seq != seq or _ash_skip:
			return
		# 4) The collapse — and into the stone as ash.
		await _collapse_remains(entry, seq)
	runner.call()


## Duplicate every surface material on `node` (the shared PieceAssets cache
## is never contaminated). Returns [[mat, original_albedo], ...].
func _override_mats(node: Node3D) -> Array:
	var mats: Array = []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override.duplicate()
			mi.material_override = m
			mats.append([m, m.albedo_color])
			continue
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m2: StandardMaterial3D = src.duplicate()
				mi.set_surface_override_material(s, m2)
				mats.append([m2, m2.albedo_color])
	return mats


## Already a skeleton? The Drowned Legion (house_id "tidegrip") — or any
## model visibly built from the skeleton cast.
func _is_already_bones(piece: Node3D) -> bool:
	if str(piece.get("house_id")) == SKELETON_HOUSE:
		return true
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("Skeleton_"):
			return true
	return false


## The pre-2026-08-08 char: tint -> charcoal, smolder wisps, tilt-crumble.
## Kept for the already-bones cast (the joke: they just char darker).
func _char_in_place(piece: Node3D, mats: Array, seq: int) -> void:
	var smoke := _smolder_wisps(piece, _mesh_height(piece))
	var charred := func(f: float) -> void:
		if not is_instance_valid(piece):
			return
		for e in mats:
			var m: StandardMaterial3D = e[0]
			m.albedo_color = (e[1] as Color).lerp(CHARCOAL, f)
			m.emission_enabled = true
			m.emission = EMBER_GLOW * (1.0 - f)   # the glow cools as it chars
	await _wall_lerp(seq, charred, 0.0, 1.0, ash_char_wall)
	if _ash_seq != seq or _ash_skip or not is_instance_valid(piece):
		return
	await _wall_wait_seq(seq, ash_smolder_wall * 0.6)
	if is_instance_valid(smoke):
		smoke.emitting = false
	if _ash_seq != seq or _ash_skip or not is_instance_valid(piece):
		return
	var p0 := piece.position
	var tilt := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.35, 0.35))
	var r0 := piece.rotation
	var crumble := func(f: float) -> void:
		if not is_instance_valid(piece):
			return
		piece.rotation = r0 + tilt * f
		piece.position = p0 + Vector3.DOWN * (1.15 * f * f)
		piece.scale = Vector3.ONE * (1.0 - 0.2 * f)
	await _wall_lerp(seq, crumble, 0.0, 1.0, ash_crumble_wall)
	if is_instance_valid(piece):
		piece.queue_free()


## Stand the charred skeleton where the warrior stood. Returns the remains
## entry ({node, anim, smoke, mats}) — registered in _remains so skip and
## teardown can always clean the field.
func _spawn_remains(piece: Node3D) -> Dictionary:
	var parent := piece.get_parent()
	if parent == null or not is_instance_valid(parent):
		return {}
	var victim_h := _mesh_height(piece)
	var pt = piece.get("piece_type")
	var packed: PackedScene = SKELETON_SCENES.get(
		int(pt) if typeof(pt) == TYPE_INT else -1, SKELETON_DEFAULT)
	var shell := Node3D.new()
	shell.name = "AshRemains"
	parent.add_child(shell)
	shell.global_position = piece.global_position
	shell.rotation.y = piece.global_rotation.y   # same facing as the fallen
	var model := packed.instantiate()
	model.name = "Bones"
	shell.add_child(model)
	var raw_h := _mesh_height(model)
	model.scale = Vector3.ONE * (victim_h / maxf(raw_h, 0.01))
	# Zelda-Grade Scorched Bone Material: Realistic calcified ashen bone with subtle soot and faint dying ember warmth
	var mats := _override_mats(model)
	for e in mats:
		var m: StandardMaterial3D = e[0]
		m.albedo_color = Color(0.22, 0.20, 0.19)   # realistic weathered bone & charcoal ivory
		m.roughness = 0.92
		m.metallic = 0.0
		m.emission_enabled = true
		m.emission = Color(0.95, 0.45, 0.12) * 0.18    # delicate, realistic dying ember warmth
	# The shared Rig_Medium library (PieceAssets autoload) animates the
	# bones; without it (headless unit tests) they stand in rest pose and
	# fall via the crumble fallback.
	var ap := _attach_shared_anims(model)
	if ap != null and ap.has_animation("Idle_A"):
		ap.play("Idle_A")
		ap.speed_scale = 0.4   # dazed, smoldering
	var smoke := _smolder_wisps(shell, victim_h)
	var entry := {"node": shell, "anim": ap, "smoke": smoke, "mats": mats}
	_remains.append(entry)
	return entry


func _collapse_remains(entry: Dictionary, seq: int) -> void:
	var shell: Node3D = entry["node"]
	if not is_instance_valid(shell):
		_remains.erase(entry)
		return
	var ap: AnimationPlayer = entry.get("anim")
	if ap != null and is_instance_valid(ap) and ap.has_animation("Death_A"):
		var clip_len: float = ap.get_animation("Death_A").length
		ap.speed_scale = clip_len / maxf(ash_collapse_wall, 0.05)   # fits the budget
		ap.play("Death_A", 0.1)
		await _wall_wait_seq(seq, ash_collapse_wall)
	else:
		var r0 := shell.rotation
		var tilt := Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.4, 0.4))
		var fall := func(f: float) -> void:
			if is_instance_valid(shell):
				shell.rotation = r0 + tilt * f
		await _wall_lerp(seq, fall, 0.0, 1.0, ash_collapse_wall)
	if _ash_seq != seq or _ash_skip:
		return   # _ash_finish sweeps the field

	if keep_skeletons:
		# Zelda-Grade Realistic Bone: Subtle, faint warm ember trace in the bone fissures
		for e in entry["mats"]:
			var m: StandardMaterial3D = e[0]
			m.emission = Color(0.85, 0.35, 0.08) * 0.04   # subtle, grounded, zero neon glow
		return

	var smoke = entry.get("smoke")
	if is_instance_valid(smoke):
		smoke.emitting = false
	if not is_instance_valid(shell):
		_remains.erase(entry)
		return
	var p0 := shell.position
	var sink := func(f: float) -> void:
		if not is_instance_valid(shell):
			return
		shell.position = p0 + Vector3.DOWN * (0.9 * f * f)
		shell.scale = Vector3.ONE * (1.0 - 0.25 * f)
		for e in entry["mats"]:
			var m: StandardMaterial3D = e[0]
			m.emission = EMBER_GLOW * 0.35 * (1.0 - f)   # the last embers die
	await _wall_lerp(seq, sink, 0.0, 1.0, ash_crumble_wall)
	if _ash_seq != seq or _ash_skip:
		return
	if is_instance_valid(shell):
		shell.queue_free()
	_remains.erase(entry)


## Sparse grey smoke wisps rising off smoldering bones. Emissive-free MIX
## billboards — never a light.
func _smolder_wisps(parent: Node3D, height: float) -> GPUParticles3D:
	var smoke := DragonRigScript.spawn_emitter(parent, "SmolderWisps", {
		"amount": 12, "lifetime": 1.7, "size": 0.22,
		"velocity": Vector2(0.5, 1.1), "spread": 16.0,
		"direction": Vector3(0.0, 1.0, 0.0),
		"gravity": Vector3(0.0, 0.7, 0.0), "grow": 1.8,
		"ramp": [
			[0.0, Color(0.16, 0.15, 0.14, 0.0)],
			[0.3, Color(0.18, 0.17, 0.16, 0.2)],
			[1.0, Color(0.07, 0.07, 0.07, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	})
	smoke.position = Vector3.UP * (height * 0.55)
	smoke.emitting = true
	return smoke


## The shared Rig_Medium animation library, duck-fetched off the
## PieceAssets autoload (never referenced by name — headless -s test runs
## have no autoloads, and this module must still compile and run there).
func _attach_shared_anims(model: Node) -> AnimationPlayer:
	var pa := get_node_or_null("/root/PieceAssets")
	if pa == null or not pa.has_method("shared_anims"):
		return null
	var lib: AnimationLibrary = pa.shared_anims()
	if lib == null:
		return null
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	model.add_child(ap)   # root_node ".." = the skeleton scene root
	ap.add_animation_library("", lib)
	return ap


## Combined world-space height of every MeshInstance3D under `node` — used
## to match the skeleton's stature to the warrior it replaces.
func _mesh_height(node: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	if lo > hi:
		return 0.9
	return maxf(hi - lo, 0.05)


func _field_resolved() -> bool:
	for p in _ash_losers:
		if is_instance_valid(p):
			return false
	return keep_skeletons or _remains.is_empty()


# ── THE FIRE — the DRACARYS kit (res://assets/vfx/dracarys.gd) ─────────────
# Six layers: core jet, rolling billows, embers + ash that outlive the jet,
# ground fire, heat shimmer, impact punch. It creates NO Light3D — firelight
# is HDR emissive particles plus an additive glow quad lying on the stone.
# The only state it touches outside its own subtree is the WorldEnvironment
# exposure/glow lift and the camera shake offsets, and BOTH are restored
# unconditionally by cut(), hard_stop(), _exit_tree and PREDELETE.
#
# Built lazily on the inhale beat: this module is instanced by every unit
# test and every match, and only a checkmate ever needs 3 280 particles.


## Build (once) and bind the torrent. Safe to call repeatedly.
func _ensure_fx() -> void:
	if _fx != null and is_instance_valid(_fx):
		_bind_fx()
		return
	if rig == null or rig.mouth_node() == null:
		return
	_fx = DracarysScript.new()
	_fx.name = "Dracarys"
	# ── TUNE BEFORE add_child. THE KIT BUILDS ITSELF IN _ready() ──
	# Everything below is baked into shader uniforms, gradients and particle
	# materials by Dracarys._build(), and _build() runs from its _ready() —
	# i.e. the instant this node enters the tree. Every one of these
	# assignments used to sit BELOW add_child(), so the whole tuning pass
	# (including an `intensity` trimmed "by measurement") had never once
	# reached the fire: it burned at the kit's stock 1.0 in a small dark hall.
	# Which is exactly why nobody caught it — see _ash_phase for the other
	# half of that story: no frame of the fire had ever been taken either.
	#
	# Board scale, not the demo stage: the losing army is ~8x2 tiles, so the
	# sweep wants ~4 tiles of reach, not the kit's 9 m default (its README
	# §7 hand-over asks for exactly this re-tune).
	_fx.reach = 4.2
	_fx.torrent_spread = 9.0
	_fx.ember_tail = 3.2
	_fx.ash_tail = 3.0
	# The kit's stock HDR values were tuned against a stand-in stage at 9 m;
	# fired six units across a small dark hall they bloom the stone walls
	# white — measured on the first frame ever taken of the real thing: 7.9%
	# of the whole picture at v >= 0.98, the banners and the white wyrm itself
	# gone to paper. The fire keeps a hot clipped CORE (flame should); the
	# room it burns in stays a dark stone hall.
	_fx.intensity = 0.40
	# The punches are driven here rather than by auto_punch so the hall gets
	# a KICK, not a new exposure setting: the stock 1.24× exposure + 0.40
	# glow lifted the whole room a full stop.
	_fx.auto_punch = false
	# Parented to the spectator, which never scales (the RIG scales) — the
	# kit drives its muzzle by GLOBAL transform, so position/rotation of this
	# node are compensated but a parent scale would not be.
	add_child(_fx)
	_bind_fx()


## (Re)bind the live camera, the hall's WorldEnvironment and the floor the
## ground pool lies on. Cheap; done at every ignition because the ceremony
## camera is taken and released around it.
func _bind_fx() -> void:
	if _fx == null or not is_instance_valid(_fx):
		return
	var cam: Camera3D = _cine_cam if _cam_live else null
	if cam == null:
		var vp := get_viewport()
		cam = vp.get_camera_3d() if vp != null else null
	_fx.bind_camera(cam)
	_fx.bind_environment(_world_env())
	_fx.floor_y = _fire_floor_y()


func _world_env() -> WorldEnvironment:
	var tree := get_tree()
	if tree == null:
		return null
	var found := tree.root.find_children("*", "WorldEnvironment", true, false)
	return found[0] as WorldEnvironment if not found.is_empty() else null


## Where the ground pool lies: the board's top face when the integrator gave
## us a board, otherwise the burning army's own footing.
func _fire_floor_y() -> float:
	if board != null and is_instance_valid(board) and board.has_method("square_to_world"):
		var local: Vector3 = board.square_to_world(Vector2i(0, 0))
		return (board as Node3D).to_global(local).y if board is Node3D else local.y
	var lo := INF
	for p in _ash_losers:
		if is_instance_valid(p) and p is Node3D:
			lo = minf(lo, (p as Node3D).global_position.y)
	return 0.0 if lo == INF else lo


func _fire_start(aim: Vector3) -> void:
	_ensure_fx()
	if _fx == null or not is_instance_valid(_fx):
		return
	_bind_fx()
	var mouth := rig.mouth_node()
	if mouth == null:
		return
	# `duration` is the jet's own length; the ceremony cuts it by hand at the
	# end of the sweep, so ask for a hair more than the sweep can take.
	_fx.start(mouth, aim, ash_breath_wall + 1.0)
	_jet_lit = true
	# LAYER 6, hand-driven (auto_punch is off — see _ensure_fx). The camera
	# shake writes only h_offset/v_offset/fov, so the ceremony dolly keeps
	# working underneath it; both punches record-and-restore.
	var cam: Camera3D = _cine_cam if _cam_live else null
	if cam == null:
		var vp := get_viewport()
		cam = vp.get_camera_3d() if vp != null else null
	if cam != null:
		_fx.punch_camera(cam, 0.09, 0.55, 24.0, 1.7)
	var we := _world_env()
	if we != null:
		# A KICK, not a new exposure setting (see _ensure_fx): the hall lifts a
		# hair on ignition and comes straight back down.
		_fx.punch_exposure(we, ash_breath_wall, 1.02, 0.045, 0.05, 0.07)


func _fire_aim(aim: Vector3) -> void:
	if _fx == null or not is_instance_valid(_fx) or not _fx.is_active():
		return
	var mouth := rig.mouth_node()
	if mouth != null:
		_fx.aim(mouth, aim)   # sweeping the beam across the army


## The graceful stop: the jet retracts, the tail lives on.
func _fire_cut() -> void:
	_jet_lit = false
	if _fx != null and is_instance_valid(_fx) and _fx.is_active():
		_fx.cut()


## THE SKIP: instant clear + full camera/environment restore. Idempotent, and
## safe when nothing ever fired.
func _fire_stop() -> void:
	_jet_lit = false
	if _fx != null and is_instance_valid(_fx):
		_fx.hard_stop()


## Championship tableau: a gentle ember drift over the throne. Created
## once, parented to the rig (dismissed with the spectator). Emissive
## billboards only.
func _ensure_drift() -> void:
	if _drift != null and is_instance_valid(_drift):
		_drift.emitting = true
		return
	if rig == null:
		return
	_drift = DragonRigScript.spawn_emitter(rig, "TableauEmberDrift", {
		"amount": 26, "lifetime": 3.2, "size": 0.06,
		"velocity": Vector2(0.2, 0.7), "spread": 70.0,
		"direction": Vector3(0.0, -1.0, 0.0),
		"gravity": Vector3(0.0, -0.35, 0.0), "grow": 0.8,
		"emission_radius": 1.7,
		"ramp": [
			[0.0, Color(1.0, 0.7, 0.3, 0.0)],
			[0.2, Color(1.0, 0.55, 0.15, 0.9)],
			[1.0, Color(0.5, 0.12, 0.03, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 2.2,
	})
	# Rig-local, so it rides the ground-origin root: just over the back.
	_drift.position = Vector3.UP * (DragonRigScript.BODY_RISE + 1.10)
	_drift.emitting = true


# ── ceremony camera (windowed only; headless runs skip every _cam_*) ───────


func _cam_take() -> bool:
	if _cam_live:
		return true
	var vp := get_viewport()
	if vp == null:
		return false
	var prev := vp.get_camera_3d()
	if prev == null or prev == _cine_cam:
		return false
	_cam_prev = prev
	_cine_cam.fov = 56.0
	_cine_cam.global_transform = prev.global_transform
	_cam_pos = prev.global_position
	_cam_look = prev.global_position - prev.global_transform.basis.z * 6.0
	_cine_cam.current = true
	_cam_live = true
	_cam_tick = Time.get_ticks_msec()
	return true


## Smooth pursuit: the dolly POSITION eases slowly (one continuous move
## across phase hand-offs) while the LOOK POINT tracks fast — the camera
## may trail the wyrm's sweep by a few degrees, never lose it.
func _cam_track(pos: Vector3, look: Vector3) -> void:
	if not _cam_live:
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _cam_tick) / 1000.0, 0.0, 0.1)
	_cam_tick = now
	_cam_pos = _cam_pos.lerp(pos, 1.0 - exp(-6.0 * dt))
	_cam_look = _cam_look.lerp(look, 1.0 - exp(-16.0 * dt))
	var dir := _cam_look - _cam_pos
	if dir.length() < 0.05:
		return
	_cine_cam.global_transform = Transform3D(
		Basis.looking_at(dir, Vector3.UP), _cam_pos)


## Ease home toward the gameplay camera during the return (u 0..1).
func _cam_home(u: float) -> void:
	if not _cam_live or not is_instance_valid(_cam_prev):
		return
	_cine_cam.global_transform = _cine_cam.global_transform.interpolate_with(
		_cam_prev.global_transform, clampf(u * u, 0.0, 1.0))


func _cam_release() -> void:
	if not _cam_live:
		return
	if is_instance_valid(_cam_prev):
		_cam_prev.current = true
	_cine_cam.current = false
	_cam_live = false
	_cam_prev = null


# ── ceremony misc ──────────────────────────────────────────────────────────


## Where the beast's body reads on screen. The serpent-wyrm's armature root
## sits ON THE GROUND between its feet; the torso/chest mass centre is
## DragonRig.BODY_RISE (0.95, measured) above it, scaled. (Was 2.1 — the old
## Quaternius rig hung its mesh around a mid-air root. Every ceremony height
## moved with this constant; see DragonRig's header for the conversion.)
func _body_pos() -> Vector3:
	var s := rig.scale.x if rig != null else 1.0
	return global_position + Vector3.UP * (DragonRigScript.BODY_RISE * s)


## Concurrent scale swell — a tween, never a pop.
func _scale_ramp(seq: int, to: float, dur: float) -> void:
	if rig == null:
		return
	var from := rig.scale.x
	var runner := func() -> void:
		var setter := func(v: float) -> void:
			if rig != null and is_instance_valid(rig):
				rig.scale = Vector3.ONE * v
		await _wall_lerp(seq, setter, from, to, dur)
	runner.call()


func _wall_wait_seq(seq: int, sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _ash_seq != seq or _ash_skip:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


static func _bezier3(a: Vector3, m: Vector3, b: Vector3, u: float) -> Vector3:
	var q0 := a.lerp(m, u)
	var q1 := m.lerp(b, u)
	return q0.lerp(q1, u)


# ── head gaze (LookAtModifier3D on the Head bone) ──────────────────────────


func _build_gaze() -> void:
	if rig.skeleton == null:
		return
	_gaze_target = Node3D.new()
	_gaze_target.name = "GazeTarget"
	add_child(_gaze_target)
	_look = LookAtModifier3D.new()
	_look.name = "HeadGaze"
	_look.bone_name = DragonRigScript.HEAD_BONE
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y   # bone runs to Head_end
	_look.primary_rotation_axis = Vector3.AXIS_Z   # binding types this Vector3.Axis
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = PI * 0.75
	_look.secondary_limit_angle = PI * 0.5
	_look.duration = 0.35
	_look.transition_type = Tween.TRANS_SINE
	_look.ease_type = Tween.EASE_IN_OUT
	_look.influence = 0.0
	rig.skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_gaze_target)


## One glance: ramp the head toward `pos`, hold, release. Fire-and-forget.
func _gaze_pulse(pos: Vector3, strength: float, hold: float) -> void:
	if _look == null:
		return
	_gaze_id += 1
	var my_id := _gaze_id
	_gaze_target.global_position = pos
	var runner := func() -> void:
		await _gaze_ramp(my_id, _look.influence, strength, 0.4)
		await _wall_sleep(hold)
		if _gaze_id == my_id:
			await _gaze_ramp(my_id, _look.influence, 0.0, 0.6)
	runner.call()


func _gaze_off() -> void:
	_gaze_id += 1
	if _look != null:
		_look.influence = 0.0


func _gaze_ramp(my_id: int, from: float, to: float, dur: float) -> void:
	var t0 := Time.get_ticks_msec()
	while _gaze_id == my_id and is_instance_valid(_look):
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		_look.influence = lerpf(from, to, u)
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


# ── wall-clock plumbing (immune to Engine.time_scale) ──────────────────────


static func _ease_cubic(u: float) -> float:
	if u < 0.5:
		return 4.0 * u * u * u
	return 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0


func _wall_lerp(seq: int, setter: Callable, from: float, to: float, dur: float) -> void:
	if dur <= 0.0:
		if _ash_seq == seq and not _ash_skip:
			setter.call(to)
		return
	var t0 := Time.get_ticks_msec()
	while true:
		if _ash_seq != seq or _ash_skip:
			return
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		setter.call(lerpf(from, to, _ease_cubic(u)))
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _wall_sleep(sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _kill_line(winning_house: String) -> String:
	var wh := winning_house if not winning_house.is_empty() else "The winning haus"
	return DD.format_line(ASHFALL_LINES.pick_random(), {"wh": wh})
