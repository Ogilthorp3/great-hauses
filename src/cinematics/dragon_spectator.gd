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
## ASHFALL (awaitable): play_ashfall(losing_side[, winning_house, losers])
##   swoop from the perch to the losing army, hover low, breathe fire —
##   GPUParticles3D flame cone + embers + smoke from the mouth, EMISSIVE
##   MATERIALS ONLY (the hall's 8-omni budget is FULL: this module adds NO
##   Light3D nodes on any path) — sweeping across the survivors; each one
##   chars to charcoal over 0.4 s and crumbles into the stone. Caption:
##   "ASHFALL." then the winning house's kill line. Wall-clock <= 6 s.
##   Click/Esc skips straight to the end state (all losers removed,
##   Engine.time_scale restored). time_scale hygiene mirrors DuelDirector:
##   restored on normal end, skip, failsafe, and _exit_tree.
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

# ASHFALL wall-clock timings (exported so tests can shrink them).
# Budget: ramp 0.25 + swoop 1.3 + breath 2.8 + return 0.9 ≈ 5.3 s <= 6 s.
@export var ash_ramp_wall := 0.25
@export var ash_swoop_wall := 1.3
@export var ash_breath_wall := 2.8
@export var ash_return_wall := 0.9
@export var ash_char_wall := 0.4       ## tint -> charcoal
@export var ash_crumble_wall := 0.45   ## tilt + sink, then freed
@export var ash_hover_height := 0.0    ## root y while breathing (body reads ~2 u up)
@export var ash_hover_backoff := 2.9   ## distance from the losers' centroid
@export var ashfall_slow_scale := 0.55
@export var failsafe_wall_sec := 9.0

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
	_build_gaze()
	_build_flame()
	_glance_in = randf_range(glance_min_gap, glance_max_gap)


func _process(delta: float) -> void:
	if _ash_active:
		return
	# Gentle bob at the perch (wall clock — the perch ignores slow-mo).
	var t := float(Time.get_ticks_msec()) / 1000.0
	position = perch_position + Vector3.UP * (sin(t * bob_speed * TAU * 0.5) * bob_amplitude)
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


## The checkmate execution. Awaitable; call AFTER the losing king's death
## cinematic released and BEFORE the victory/championship flow. `losers`
## may be passed explicitly (the integrator's own view list); when empty
## the tree is duck-scanned for Node3D with side == losing_side.
## `winning_house` is the display name used in the kill-line caption.
func play_ashfall(losing_side: int, winning_house: String = "",
		losers: Array = []) -> void:
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
	_prev_time_scale = Engine.time_scale
	_ash_losers = []
	for p in (losers if not losers.is_empty() else _collect_losers(losing_side)):
		if is_instance_valid(p) and p is Node3D and not p.is_queued_for_deletion():
			_ash_losers.append(p)
	ashfall_started.emit()
	_arm_failsafe(seq)
	_gaze_off()

	# The dive — cinematic dip, caption, Fast_Flying down to the survivors.
	await _wall_lerp(seq, _set_ts, Engine.time_scale, ashfall_slow_scale, ash_ramp_wall)
	caption.show_line("ASHFALL.")
	var focus := _losers_centroid()
	var away := perch_position - focus
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var hover := Vector3(focus.x, ash_hover_height, focus.z) + away * ash_hover_backoff
	rig.play_once("Fast_Flying", 1.0)
	if rig.has_clip("Fast_Flying"):
		rig.anim.get_animation("Fast_Flying").loop_mode = Animation.LOOP_LINEAR
	var start_pos := position
	var start_yaw := rotation.y
	var target_yaw := _yaw_toward(hover, focus)
	var swoop := func(u: float) -> void:
		position = start_pos.lerp(hover, u) + Vector3.UP * sin(u * PI) * 0.6
		rotation.y = lerp_angle(start_yaw, target_yaw, u)
	await _wall_lerp(seq, swoop, 0.0, 1.0, ash_swoop_wall)
	if _ash_seq != seq or _ash_skip:
		return   # skip() already snapped to the end state

	# The breath — hover flap, fire on, sweep across the losers.
	rig.play_loop("Flying_Idle", 1.0, 0.3)
	rig.play_once("Headbutt", 1.4, 0.2)   # the lunge that opens the jet
	_set_flame(true)
	var order := _sweep_order(hover)
	var burned := {}
	var line := _kill_line(winning_house)
	var line_shown := false
	var t0 := Time.get_ticks_msec()
	while _ash_seq == seq and not _ash_skip:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (ash_breath_wall * 1000.0), 0.0, 1.0)
		var aim := _sweep_aim(order, u, focus)
		_aim_breath(aim, hover)
		# Char each survivor as the jet passes its slot in the sweep.
		var slot := int(floor(u * order.size() - 0.0001)) if order.size() > 0 else -1
		for i in range(0, slot + 1):
			if not burned.has(i):
				burned[i] = true
				_char_and_crumble(order[i], seq)
		if not line_shown and u >= 0.45:
			line_shown = true
			caption.show_line(line)
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
			_char_and_crumble(order[i], seq)

	# The return — fire off, back to the perch, clock restored.
	_set_flame(false)
	rig.play_once("Fast_Flying", 1.0)
	var from := position
	var from_yaw := rotation.y
	var back := func(u: float) -> void:
		position = from.lerp(perch_position, u) + Vector3.UP * sin(u * PI) * 0.4
		rotation.y = lerp_angle(from_yaw, perch_yaw, u)
	await _wall_lerp(seq, back, 0.0, 1.0, ash_return_wall)
	_ash_finish(seq)


## Snap the execution to its end state: all losers removed, clock restored,
## dragon back on the perch. Wired to click/Esc while active.
func skip() -> void:
	if not _ash_active or _ash_skip:
		return
	_ash_skip = true
	_ash_finish(_ash_seq)


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
	position = perch_position
	rotation.y = perch_yaw
	if rig != null:
		rig.play_loop("Flying_Idle", idle_speed, 0.3)
	ashfall_finished.emit()


func _exit_tree() -> void:
	## Finally-style guarantee: a freed spectator never strands a slowed
	## clock (the DuelDirector hygiene rule, applied here).
	if _ash_active:
		_ash_active = false
		Engine.time_scale = _prev_time_scale


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


func _char_and_crumble(piece: Node3D, seq: int) -> void:
	## Fire-and-forget per-piece death: tint -> charcoal over ash_char_wall,
	## then tilt + sink + free. Materials are DUPLICATED per surface so the
	## shared PieceAssets cache is never contaminated.
	if not is_instance_valid(piece):
		return
	var mats: Array = []
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
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
	var runner := func() -> void:
		var charred := func(f: float) -> void:
			if not is_instance_valid(piece):
				return
			for e in mats:
				var m: StandardMaterial3D = e[0]
				m.albedo_color = (e[1] as Color).lerp(CHARCOAL, f)
				m.emission_enabled = true
				m.emission = EMBER_GLOW * (1.0 - f)   # the glow cools as it chars
		await _wall_lerp(seq, charred, 0.0, 1.0, ash_char_wall)
		if not is_instance_valid(piece):
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
	runner.call()


# ── flame (emissive particles ONLY — no Light3D on any path) ───────────────


func _set_flame(on: bool) -> void:
	for f in _flames:
		if is_instance_valid(f):
			f.emitting = on


func _build_flame() -> void:
	var mouth := rig.mouth_node()
	if mouth == null:
		return
	# Core jet: fat additive tongues, white-gold -> orange-red -> gone.
	_flames.append(_emitter(mouth, "FlameCore", {
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
	}))
	# Ember sparks: tiny hot chips thrown past the jet.
	_flames.append(_emitter(mouth, "Embers", {
		"amount": 80, "lifetime": 0.95, "size": 0.07,
		"velocity": Vector2(4.5, 8.5), "spread": 17.0,
		"gravity": Vector3(0.0, -3.2, 0.0), "grow": 0.7,
		"ramp": [
			[0.0, Color(1.0, 0.75, 0.3, 1.0)],
			[0.6, Color(1.0, 0.4, 0.08, 0.9)],
			[1.0, Color(0.5, 0.1, 0.02, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 3.2,
	}))
	# Smoke wisps: unshaded soot, no emission, rises off the jet's tail.
	_flames.append(_emitter(mouth, "Smoke", {
		"amount": 42, "lifetime": 1.6, "size": 0.55,
		"velocity": Vector2(1.8, 3.0), "spread": 24.0,
		"gravity": Vector3(0.0, 1.1, 0.0), "grow": 3.2,
		"ramp": [
			[0.0, Color(0.12, 0.1, 0.09, 0.0)],
			[0.25, Color(0.14, 0.12, 0.11, 0.4)],
			[1.0, Color(0.05, 0.05, 0.05, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	}))


func _emitter(parent: Node3D, node_name: String, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.emitting = false
	p.speed_scale = 1.5   # reads fierce under the ashfall slow-mo
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)   # +Z out of the jaws
	pm.spread = cfg["spread"]
	pm.initial_velocity_min = (cfg["velocity"] as Vector2).x
	pm.initial_velocity_max = (cfg["velocity"] as Vector2).y
	pm.gravity = cfg["gravity"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.09
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, cfg["grow"] / 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for stop in cfg["ramp"]:
		offs.append(stop[0])
		cols.append(stop[1])
	grad.offsets = offs
	grad.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(cfg["size"], cfg["size"])
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = cfg["blend"]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if float(cfg["emission_energy"]) > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.12)
		mat.emission_energy_multiplier = cfg["emission_energy"]
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


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
