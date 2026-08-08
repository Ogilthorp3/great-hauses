class_name DragonSpectator
extends Node3D
## DRAGON SPECTATOR + ASHFALL — the dragon watches the whole war from a
## perch above the far wall, reacts to the play, and delivers the checkmate
## execution: a swoop over the beaten army and a river of fire (ASHFALL).
##
## Presentation only: it never touches game state. Pieces are duck-typed
## Node3D (PieceView works out of the box via its `side` / `piece_type`
## ints; mocks only need the same two fields).
##
## Perch: slow Flying_Idle + gentle bob above the far wall — out of the
## default camera's frame (orbit pitch -0.85), in view when the player
## orbits upward. Occasional head glance (LookAtModifier3D on the Head
## bone) toward the last-moved piece.
##
## Reaction API (integrator connects signals to these; each returns true
## when the reaction actually played):
##   notice_move(world_pos)     call once per ply — feeds the rate limiter
##                              and the idle glance target
##   react_blunder()            'No' head-shake
##   react_brilliant()          'Yes' nod
##   react_capture(square)      'HitReact' flinch + look at the square
##                              (square: Vector3 world pos, or Vector2i via
##                              the `board` reference)
## Rate limit: max ONE reaction per `reaction_every_moves` moves (default
## 2), and NEVER while the duel-cam runs (`duel_director.is_active()`).
##
## ASHFALL (awaitable): play_ashfall(losing_side[, winning_house, losers,
##   championship]) — THE CEREMONY (rebuilt 2026-08-08, two tiers):
##
##   MATCH (any checkmate, wall <= 12 s): launch from the perch -> one
##   sweeping Fast_Flying bank around the hall (inside walls and pillars,
##   above y~3) filmed by a low-angle camera pushing in from below (the awe
##   shot) -> flare to a wing-spread hover above the board center
##   (Flying_Idle at 0.6 reads as a mighty hover), ONE beat of stillness
##   (the inhale) -> the fire sweep over the beaten army with a long ember
##   and drifting-ash tail (particles linger 3-4 s after the breath).
##   Dragon scale swells to ~1.4 for the ceremony and returns to the perch
##   at 1.15. MORTAL-KOMBAT INCINERATION: each warrior the jet touches
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
##   the caption beat "ASHFALL." then "{house} takes the throne."
##   (strictly sequential — the lines never overlap).
##
##   EMISSIVE MATERIALS ONLY throughout (the hall's 8-omni budget is FULL:
##   this module adds NO Light3D nodes on any path). Click/Esc skips
##   straight to the tier's end state (all losers AND smoldering skeletons
##   removed, camera + Engine.time_scale restored). time_scale hygiene
##   mirrors DuelDirector: restored on normal end, skip, failsafe, and
##   _exit_tree.
##
## Sequence order at checkmate: king death anim (DuelDirector checkmate
## cinematic) -> await play_ashfall(...) -> the existing championship /
## victory flow. See INTEGRATION-dragon.md.

signal ashfall_started
signal ashfall_finished

const DD := preload("res://src/cinematics/duel_director.gd")
const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")
const CaptionScript := preload("res://src/cinematics/cine_caption.gd")

const PIECE_KING := 5              # PieceView.Type.KING — kings never burn twice
const CHARCOAL := Color(0.09, 0.085, 0.08)
const EMBER_GLOW := Color(0.9, 0.28, 0.06)

## Championship throne perch — MUST equal GreatHall.DRAGON_HOVER (the hall
## is the authority; test_dragon.gd asserts the two stay in sync).
const THRONE_PERCH := Vector3(0.0, 2.2, 9.9)

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

## Perch pose (world space of this node's parent). Defaults match
## GreatHall.spectator_perch() with the board at the origin.
@export var perch_position := Vector3(0.0, 4.7, 11.2)
@export var perch_yaw := PI            ## face the board (-Z)
@export var dragon_scale := 1.15
@export var idle_speed := 0.55         ## slow Flying_Idle loop at the perch
@export var bob_amplitude := 0.14
@export var bob_speed := 0.8           ## rad/s of the bob sine
@export var reaction_every_moves := 2  ## max 1 reaction per N moves
@export var glance_min_gap := 6.0      ## idle head-turn cadence (wall sec)
@export var glance_max_gap := 10.0

# CEREMONY wall-clock timings (exported so tests can shrink them).
# MATCH budget: ramp .25 + bank 2.6 + flare .7 + inhale .6 + breath 2.8
#   + linger 1.6 + return .9 ≈ 9.5 s (last remains resolve inside the
#   linger's bounded wait) <= 12 s.
# CHAMPIONSHIP: match minus return, plus crown-bank 1.3 + settle 1.4
#   + caption beats ~1.7 ≈ 12.3 s <= 16 s.
@export var ash_ramp_wall := 0.25      ## slow-mo dip in
@export var ash_bank_wall := 2.6       ## one sweeping bank around the hall
@export var ash_flare_wall := 0.7      ## bank -> wing-spread hover, board center
@export var ash_inhale_wall := 0.6     ## ONE beat of stillness — the inhale
@export var ash_swoop_wall := 1.3      ## championship: the crown-bank to the throne
@export var ash_breath_wall := 2.8     ## the fire sweep across the army
@export var ash_linger_wall := 1.6     ## jet cut; embers/ash drift, bones fall
@export var ash_return_wall := 0.9     ## match: back to the wall perch
@export var ash_settle_wall := 1.4     ## championship: slow wing-settle on the throne
@export var ash_flash_wall := 0.12     ## ignition flash before the skeleton swap
@export var ash_smolder_wall := 1.2    ## smoldering beat between swap and collapse
@export var ash_collapse_wall := 0.8   ## Death_A is retimed to fit this window
@export var ash_char_wall := 0.4       ## tint -> charcoal (Tidegrip char-in-place)
@export var ash_crumble_wall := 0.45   ## final sink into the stone, then freed
@export var ash_hover_height := 0.0    ## root y while breathing (body reads ~2 u up)
@export var ash_hover_backoff := 2.9   ## distance from the losers' centroid
@export var ashfall_slow_scale := 0.55
@export var ceremony_scale := 1.4      ## the wyrm swells for the ceremony
@export var champ_scale := 1.6         ## …and larger still upon the throne
@export var bank_radius := 8.6         ## inside the ±12 walls and 10.6-radius pillars
@export var bank_height := 3.5         ## bank floor — never below y≈3
@export var failsafe_wall_sec := 18.0

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

var _ash_active := false
var _ash_skip := false
var _ash_seq := 0
var _prev_time_scale := 1.0
var _ash_losers: Array = []
var _flames: Array = []                # GPUParticles3D children of the mouth
var _flame_core: GPUParticles3D = null
var _flame_tail: Array = []            # embers + drifting ash (the lingering tail)
var _remains: Array = []               # live skeleton entries: {node, anim, smoke, mats}
var _drift: GPUParticles3D = null      # championship tableau ember drift
var _champ_mode := false
var _end_pos := Vector3.ZERO           # tier-aware ceremony end pose
var _end_yaw := PI
var _end_scale := 1.15
var _end_idle_speed := 0.55

var _cine_cam: Camera3D = null         # the ceremony camera (windowed only)
var _cam_prev: Camera3D = null
var _cam_live := false
var _cam_tick := 0
var _cam_pos := Vector3.ZERO           # smoothed dolly position
var _cam_look := Vector3.ZERO          # smoothed look point (fast — never loses the wyrm)


func _ready() -> void:
	rig = DragonRigScript.spawn(self, "SpectatorDragon", Vector3.ZERO, 0.0, dragon_scale)
	position = perch_position
	rotation.y = perch_yaw
	rig.play_loop("Flying_Idle", idle_speed)
	if rig.anim != null:   # desync from the championship dragon's flap
		rig.anim.seek(randf() * rig.clip_length("Flying_Idle"))
	caption = CaptionScript.new()
	caption.name = "AshfallCaption"
	add_child(caption)
	_cine_cam = Camera3D.new()
	_cine_cam.name = "CeremonyCam"
	_cine_cam.top_level = true   # ignores the perch/bank motion of this node
	_cine_cam.current = false
	add_child(_cine_cam)
	_end_pos = perch_position
	_end_yaw = perch_yaw
	_end_scale = dragon_scale
	_end_idle_speed = idle_speed
	_build_gaze()
	_build_flame()
	_glance_in = randf_range(glance_min_gap, glance_max_gap)


func _process(delta: float) -> void:
	if _ash_active:
		return
	# Gentle bob at the roost (wall clock — the perch ignores slow-mo).
	# After a championship the roost IS the throne perch, not the wall.
	var home := THRONE_PERCH if _champ_mode else perch_position
	var t := float(Time.get_ticks_msec()) / 1000.0
	position = home + Vector3.UP * (sin(t * bob_speed * TAU * 0.5) * bob_amplitude)
	# Occasional head turn toward the last-moved piece.
	_glance_in -= clampf(delta / maxf(Engine.time_scale, 0.05), 0.0, 0.1)
	if _glance_in <= 0.0:
		_glance_in = randf_range(glance_min_gap, glance_max_gap)
		if _last_move_pos.is_finite() and not _reacting and not _duel_cam_active():
			_gaze_pulse(_last_move_pos, 0.75, 1.2)


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
	return _react("No", 0.7, Vector3.INF)


func react_brilliant() -> bool:
	return _react("Yes", 0.7, Vector3.INF)


func react_capture(square: Variant = null) -> bool:
	return _react("HitReact", 1.0, _to_world(square))


func _react(clip: String, speed: float, look_pos: Vector3) -> bool:
	if not can_react():
		return false
	_moves_since_reaction = 0
	_reacting = true
	if look_pos.is_finite():
		_last_move_pos = look_pos
		_gaze_pulse(look_pos, 0.9, 0.8)
	var dur := rig.play_once(clip, speed)
	var runner := func() -> void:
		await _wall_sleep(maxf(dur, 0.1))
		if is_instance_valid(self) and is_inside_tree():
			_reacting = false
			if not _ash_active:
				rig.play_loop("Flying_Idle", idle_speed, 0.4)
	runner.call()
	return true


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
	_end_pos = THRONE_PERCH if championship else perch_position
	_end_yaw = PI if championship else perch_yaw
	_end_scale = champ_scale if championship else dragon_scale
	_end_idle_speed = 0.45 if championship else idle_speed
	_ash_losers = []
	for p in (losers if not losers.is_empty() else _collect_losers(losing_side)):
		if is_instance_valid(p) and p is Node3D and not p.is_queued_for_deletion():
			_ash_losers.append(p)
	ashfall_started.emit()
	_arm_failsafe(seq)
	_gaze_off()
	_cam_take()   # windowed only: the ceremony camera (no-op headless)

	# ── I. THE LAUNCH — cinematic dip, the mark, wings up ──
	await _wall_lerp(seq, _set_ts, Engine.time_scale, ashfall_slow_scale, ash_ramp_wall)
	if _ash_seq != seq or _ash_skip:
		return
	caption.show_line("ASHFALL.")
	rig.play_loop("Fast_Flying", 0.75)   # slow, heavy wingbeats — a mountain flying
	_scale_ramp(seq, ceremony_scale, ash_bank_wall + ash_flare_wall)   # swells, never pops

	# ── II. THE BANK — one sweeping pass around the hall, filmed from
	# below: the low-angle camera pushes in as the wyrm thunders overhead.
	var start_pos := position
	var th0 := atan2(start_pos.x, start_pos.z)
	var prev_p := start_pos
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
		var p := start_pos.lerp(target, clampf(u / 0.15, 0.0, 1.0))
		var v := p - prev_p
		prev_p = p
		position = p
		if v.length() > 0.001:
			rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 0.35)
		rotation.z = -0.35 * sin(u * PI)   # lean into the turn
		# The awe shot: a low camera pulled back from the board — the wyrm
		# wheels across the hall as a winged SILHOUETTE (this asset's
		# majesty lives in its wingspan at distance, never in close-ups).
		_cam_track(Vector3(0.0, 0.7, -4.5), _body_pos())
		if u >= 1.0:
			break
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame

	# ── III. THE FLARE — wing-spread hover above the board center ──
	rig.play_loop("Flying_Idle", 0.6, 0.5)   # slow flap: the mighty hover
	var hover_center := Vector3(0.0, 1.5, 0.0)
	var f0_pos := position
	var f0_yaw := rotation.y
	var f0_roll := rotation.z
	var flare := func(u: float) -> void:
		position = f0_pos.lerp(hover_center, u) + Vector3.UP * sin(u * PI) * 0.5
		rotation.y = lerp_angle(f0_yaw, PI, u)
		rotation.z = lerpf(f0_roll, 0.0, u)
		_cam_track(Vector3(0.0, 0.9, -5.8), _body_pos())
	await _wall_lerp(seq, flare, 0.0, 1.0, ash_flare_wall)
	if _ash_seq != seq or _ash_skip:
		return

	# ── IV. THE INHALE — one beat of stillness before the judgment ──
	var inhale := func(u: float) -> void:
		position = hover_center + Vector3.UP * (0.18 * u)
		_cam_track(Vector3(0.0, 0.95, -5.3), _body_pos())
	await _wall_lerp(seq, inhale, 0.0, 1.0, ash_inhale_wall)
	if _ash_seq != seq or _ash_skip:
		return

	# ── V. THE BREATH — the fire sweep across the beaten army; every
	# warrior the jet touches burns down to a smoldering skeleton ──
	var focus := _losers_centroid()
	var away := perch_position - focus
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var breath_hover := Vector3(focus.x, ash_hover_height, focus.z) + away * ash_hover_backoff
	rig.play_once("Headbutt", 1.4, 0.2)   # the lunge that opens the jet
	_set_flame(true)
	var order := _sweep_order(breath_hover)
	var burned := {}
	var line := _kill_line(winning_house)
	var line_shown := false
	var jet_side := (focus - breath_hover).cross(Vector3.UP)
	jet_side = jet_side.normalized() if jet_side.length() > 0.01 else Vector3.RIGHT
	var inhale_pos := position
	var bt0 := Time.get_ticks_msec()
	while _ash_seq == seq and not _ash_skip:
		var u := clampf(float(Time.get_ticks_msec() - bt0) / (ash_breath_wall * 1000.0), 0.0, 1.0)
		position = inhale_pos.lerp(breath_hover, clampf(u / 0.2, 0.0, 1.0))
		var aim := _sweep_aim(order, u, focus)
		_aim_breath(aim, breath_hover)
		# Ignite each survivor as the jet passes its slot in the sweep.
		var slot := int(floor(u * order.size() - 0.0001)) if order.size() > 0 else -1
		for i in range(0, slot + 1):
			if not burned.has(i):
				burned[i] = true
				_incinerate(order[i], seq)
		if not line_shown and u >= 0.45:
			line_shown = true
			caption.show_line(line)
		_cam_track(focus + jet_side * 5.6 + Vector3.UP * 1.8
			- (focus - breath_hover).normalized() * 1.6,
			(focus + _body_pos()) * 0.5)
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
	if _flame_core != null:
		_flame_core.emitting = false
	rig.play_loop("Flying_Idle", 0.6, 0.4)
	var lt0 := Time.get_ticks_msec()
	while _ash_seq == seq and not _ash_skip:
		var el := float(Time.get_ticks_msec() - lt0) / 1000.0
		if el >= ash_linger_wall * 0.7:
			_set_flame_tail(false)   # emitters stop; live particles drift on
		if el >= ash_linger_wall and (_field_resolved() or el >= ash_linger_wall + 2.2):
			break
		_cam_track(focus + jet_side * 3.8 + Vector3.UP * 1.2
			- (focus - breath_hover).normalized() * 0.8,
			focus + Vector3.UP * 0.45)
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
	if _ash_seq != seq or _ash_skip:
		return

	if not championship:
		# ── VII. THE RETURN — back to the wall perch, size and clock restored ──
		rig.play_loop("Fast_Flying", 1.0, 0.3)
		_scale_ramp(seq, dragon_scale, ash_return_wall)
		var from := position
		var from_yaw := rotation.y
		var back := func(u: float) -> void:
			position = from.lerp(perch_position, u) + Vector3.UP * sin(u * PI) * 0.8
			rotation.y = lerp_angle(from_yaw, perch_yaw, u)
			_cam_home(u)
		await _wall_lerp(seq, back, 0.0, 1.0, ash_return_wall)
	else:
		# ── VII. THE CROWNING — one more bank, then the throne perch ──
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
	Engine.time_scale = _prev_time_scale
	_set_flame(false)
	if caption != null:
		caption.hide_line()
	for p in _ash_losers:   # end state: every loser gone, skipped or not
		if is_instance_valid(p) and p is Node3D:
			p.queue_free()
	_ash_losers.clear()
	for entry in _remains:   # …and every smoldering skeleton with them
		var n = entry.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_remains.clear()
	_cam_release()
	# Tier-aware end pose: match ends back on the wall perch at 1.15;
	# championship ends on the throne perch at 1.6 with the ember drift on.
	position = _end_pos
	rotation = Vector3(0.0, _end_yaw, 0.0)
	if rig != null:
		rig.scale = Vector3.ONE * _end_scale
		rig.play_loop("Flying_Idle", _end_idle_speed, 0.3)
	if _champ_mode:
		_ensure_drift()
	ashfall_finished.emit()


func _exit_tree() -> void:
	## Finally-style guarantee: a freed spectator never strands a slowed
	## clock or a stolen viewport (the DuelDirector hygiene rule).
	if _ash_active:
		_ash_active = false
		Engine.time_scale = _prev_time_scale
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


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z)   # native forward is +Z


func _aim_breath(aim: Vector3, hover: Vector3) -> void:
	rotation.y = _yaw_toward(hover, aim)
	var mouth := rig.mouth_node()
	if mouth == null:
		return
	var dir := aim - mouth.global_position
	if dir.length() < 0.05:
		return
	# Mouth convention: +Z points out of the jaws — looking_at(-dir) puts
	# -Z on -dir, i.e. +Z onto the target.
	mouth.global_basis = Basis.looking_at(-dir.normalized(), Vector3.UP)


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
	# Charred near-black bones with a dying ember glow (no lights).
	var mats := _override_mats(model)
	for e in mats:
		var m: StandardMaterial3D = e[0]
		m.albedo_color = CHARCOAL * 0.7   # charred near-black bone
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission = EMBER_GLOW * 0.22    # a dying inner glow, not a paint job
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
	return _remains.is_empty()


# ── flame (emissive particles ONLY — no Light3D on any path) ───────────────
# Builder lives in DragonRig.spawn_emitter (shared with the hall's tableau
# ember drift). The core jet cuts with the breath; embers + drifting ash
# are the LINGERING TAIL — long lifetimes carry them 3-4 s past the jet.


func _set_flame(on: bool) -> void:
	for f in _flames:
		if is_instance_valid(f):
			f.emitting = on


func _set_flame_tail(on: bool) -> void:
	for f in _flame_tail:
		if is_instance_valid(f):
			f.emitting = on


func _build_flame() -> void:
	var mouth := rig.mouth_node()
	if mouth == null:
		return
	# Core jet: fat additive tongues, white-gold -> orange-red -> gone.
	_flame_core = DragonRigScript.spawn_emitter(mouth, "FlameCore", {
		"amount": 150, "lifetime": 0.55, "size": 0.34,
		"velocity": Vector2(6.5, 9.0), "spread": 9.0,
		"gravity": Vector3(0.0, 1.4, 0.0), "grow": 2.6,
		"ramp": [
			[0.0, Color(1.0, 0.93, 0.6, 0.0)],
			[0.12, Color(1.0, 0.85, 0.4, 0.95)],
			[0.5, Color(1.0, 0.42, 0.1, 0.8)],
			[0.85, Color(0.7, 0.16, 0.03, 0.35)],
			[1.0, Color(0.25, 0.05, 0.01, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 2.6,
	})
	_flames.append(_flame_core)
	# Ember sparks: hot chips thrown past the jet — long-lived, they rain
	# and drift well after the breath ends.
	var embers := DragonRigScript.spawn_emitter(mouth, "Embers", {
		"amount": 110, "lifetime": 2.4, "size": 0.07,
		"velocity": Vector2(4.5, 8.5), "spread": 17.0,
		"gravity": Vector3(0.0, -1.7, 0.0), "grow": 0.7,
		"ramp": [
			[0.0, Color(1.0, 0.75, 0.3, 1.0)],
			[0.45, Color(1.0, 0.4, 0.08, 0.9)],
			[1.0, Color(0.5, 0.1, 0.02, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 3.2,
	})
	_flames.append(embers)
	_flame_tail.append(embers)
	# Drifting ash: grey flakes that hang in the torchlight and settle
	# slowly over the burned ground — the ceremony's aftertaste.
	var ash := DragonRigScript.spawn_emitter(mouth, "AshDrift", {
		"amount": 90, "lifetime": 3.4, "size": 0.09,
		"velocity": Vector2(2.0, 5.0), "spread": 26.0,
		"gravity": Vector3(0.0, -1.0, 0.0), "grow": 0.5,
		"ramp": [
			[0.0, Color(0.35, 0.33, 0.3, 0.0)],
			[0.15, Color(0.4, 0.37, 0.33, 0.8)],
			[1.0, Color(0.12, 0.11, 0.1, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	})
	_flames.append(ash)
	_flame_tail.append(ash)
	# Smoke wisps: unshaded soot, no emission, rises off the jet's tail.
	# (Kept small and faint — big translucent quads read blocky in stills.)
	_flames.append(DragonRigScript.spawn_emitter(mouth, "Smoke", {
		"amount": 42, "lifetime": 1.6, "size": 0.42,
		"velocity": Vector2(1.8, 3.0), "spread": 24.0,
		"gravity": Vector3(0.0, 1.1, 0.0), "grow": 2.6,
		"ramp": [
			[0.0, Color(0.12, 0.1, 0.09, 0.0)],
			[0.25, Color(0.14, 0.12, 0.11, 0.26)],
			[1.0, Color(0.05, 0.05, 0.05, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	}))


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
	_drift.position = Vector3.UP * 3.2
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


## Where the beast's body reads on screen: the rig ships mid-flight, the
## torso floating ~2 u above the armature root (scaled).
func _body_pos() -> Vector3:
	var s := rig.scale.x if rig != null else 1.0
	return global_position + Vector3.UP * (2.1 * s)


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
	var wh := winning_house if not winning_house.is_empty() else "The winning house"
	return DD.format_line(ASHFALL_LINES.pick_random(), {"wh": wh})
