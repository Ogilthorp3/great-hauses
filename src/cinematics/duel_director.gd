class_name DuelDirector
extends Node3D
## SLOW-MOTION BATTLE CAM — cinematic presentation layer for capture duels,
## promotions, and checkmate. Pure presentation: it never touches game state,
## it wraps choreography the caller provides (or a timed hold when none is).
##
## Public API (all awaitable sequences restore Engine.time_scale, camera and
## audio pitch on EVERY exit path — normal end, skip, failsafe, tree exit):
##   is_active() -> bool                      gate game input while true
##   play_duel(attacker, victim, meta, strike)
##   play_promotion(piece, meta)
##   play_checkmate(losing_king, winning_house, death, meta)
##   play_championship_tableau(throne_focus)  Grand Final: park on the throne
##   skip()                                   snap presentation to end state
##   duel_context(attacker, victim, meta)     caption token dict (testable)
##   pick_kill_line(ctx) / format_line(...)   kill-line pool (testable)
##
## Fighters are duck-typed Node3D: PieceView works out of the box (reads its
## `piece_type` / `side` ints); anything else can pass names via `meta`
## ("attacker_piece", "attacker_house", "victim_piece", "victim_house").
##
## time_scale hygiene (the obvious failure mode is a stuck 0.25):
##   - every sequence funnels through _finish() -> _restore_presentation()
##   - skip() restores immediately, then lets the wrapped choreography finish
##     at normal speed (game state is never abandoned)
##   - a wall-clock failsafe timer force-restores if a sequence overruns
##   - _exit_tree() restores if the director is freed mid-cinematic
## All cinematic timing runs on wall-clock ticks (immune to the very
## time_scale it manipulates), so total duel wall time stays <= ~5.5 s
## (face-off + rest-yaw beats add ~0.5 s to the old ~5 s budget).
##
## FACE TO FACE (2026-08-08): play_duel turns both combatants to meet
## before the strike and holds the lock through it; the survivor eases
## back to his side's resting yaw afterward. play_checkmate does the same
## for the king and his killer (nearest enemy, meta "attacker" override).

signal cinematic_started(kind: String)
signal cinematic_finished(kind: String)
## Integrator hook: fired at the end of the checkmate cinematic, after the
## 3 s hold, with the winning house display name. Wire the victory panel here.
signal victory_panel_requested(winning_house: String)

const LINES_PATH := "res://src/cinematics/kill_lines.json"
## Canonical nine-house registry (HouseRegistry module). When present, house
## identity passed via meta ("winterfang", "House Winterfang", or an
## archetype like "wolf") resolves to the registry's names/mottos/colors.
const HOUSES_REGISTRY_PATH := "res://src/houses/houses.json"
## Index-aligned with PieceView.Type and PieceView.House.
const PIECE_NAMES: Array[String] = ["pawn", "rook", "knight", "bishop", "queen", "king"]
const HOUSE_KEYS: Array[String] = ["FROST", "EMBER"]

# Wall-clock durations (seconds). Exported so tests can shrink them.
@export var swoop_wall := 0.55          ## orbit cam -> low duel angle
@export var return_wall := 0.5          ## duel angle -> back to orbit cam
@export var duel_ramp_down_wall := 0.4  ## time 1.0 -> duel_slow_scale
@export var duel_slow_hold_wall := 1.1  ## dwell at full slow-mo (the strike beat)
@export var duel_ramp_up_wall := 0.7    ## time back up to 1.0 (death plays out)
@export var duel_tail_wall := 1.2       ## hold when no strike callable is given
@export var duel_slow_scale := 0.25
@export var promo_wall := 2.2           ## promotion flourish hold
@export var promo_slow_scale := 0.6
@export var checkmate_slow_scale := 0.15
@export var checkmate_hold_wall := 3.0
@export var checkmate_orbit_speed := 0.35   ## rad/s around the dying king
@export var championship_glide_wall := 1.5  ## glide into the throne frame
@export var championship_hold_wall := 3.2   ## hold on the tableau, panel up
@export var championship_fov := 58.0
## Camera offset from the throne focus for the championship frame — a low 3/4
## hero angle from the board side that keeps dais, throne and dragon in shot.
@export var championship_cam_offset := Vector3(1.9, 0.1, -7.2)
@export var failsafe_wall_sec := 8.0    ## force-restore if a sequence overruns
@export var handheld_amp := 0.035       ## handheld noise amplitude (world units)
@export var duel_fov := 42.0
@export var face_off_wall := 0.22       ## combatants turn to meet (ease-out)
@export var face_rest_wall := 0.25      ## survivor eases back to his rest yaw
@export var tableau_caption_beat := 1.25  ## championship caption beat length

var _active := false
var _kind := ""
var _seq := 0
var _skip := false
var _prev_time_scale := 1.0
var _audio_base: Array = []            # [{node, pitch}] captured at sequence start
var _props: Array = []                 # spawned flourish nodes, cleaned on restore

var _cam: Camera3D
var _prev_cam: Camera3D = null
var _cam_base := Transform3D.IDENTITY  # cinematic pose before handheld noise
var _cam_on := false
var _orbiting := false
var _shake := 0.0
var _shake_target := 0.0
var _noise := FastNoiseLite.new()
var _last_tick := 0

var _caption_layer: CanvasLayer
var _caption: Label
var _caption_fade := 0        # generation token for the wall-clock fades
var _lines: Dictionary = {}
var _canon: Dictionary = {}   # lowercase id/name/archetype -> house info dict
var _champion_house := ""     # remembered by play_checkmate for the tableau captions


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_cam = Camera3D.new()
	_cam.name = "CineCam"
	_cam.fov = duel_fov
	add_child(_cam)
	_cam.current = false   # never steal the viewport on entry
	_build_caption()
	_load_lines()


# ── public API ─────────────────────────────────────────────────────────────


func is_active() -> bool:
	return _active


## Snap the cinematic presentation to its end state instantly. The wrapped
## choreography (strike/death callable) is never aborted — it finishes at
## normal speed so game state stays correct.
func skip() -> void:
	if not _active or _skip:
		return
	_skip = true
	_restore_presentation()


## The capture duel cinematic. `strike` is the actual duel choreography
## (e.g. `func(): await mover.play_capture(victim)`); it runs UNDER the
## slow-mo curve. With no strike, a timed hold plays instead (test mode).
func play_duel(attacker: Node3D, victim: Node3D, meta: Dictionary = {},
		strike: Callable = Callable()) -> void:
	if _active or not is_inside_tree():
		if strike.is_valid():
			await strike.call()   # never drop gameplay, even if double-booked
		return
	var seq := _begin("duel")
	_arm_failsafe(seq, failsafe_wall_sec)
	_audio_capture()
	var line := pick_kill_line(duel_context(attacker, victim, meta))
	_cam_enter_duel(attacker, victim, seq)   # concurrent swoop
	# FACE TO FACE: both combatants turn to meet BEFORE the strike begins,
	# then a per-frame yaw hold keeps them locked through it — a stale
	# _face_home tween left by the preceding walk can never again leave a
	# duel fought back-to-back.
	await _face_off_pair(seq, attacker, victim)
	var strike_done := {"done": not strike.is_valid()}
	if strike.is_valid():
		var runner := func() -> void:
			await strike.call()
			strike_done["done"] = true
		runner.call()
	_face_hold(seq, attacker, victim, strike_done)   # concurrent yaw lock
	await _wall_lerp(seq, _set_ts, Engine.time_scale, duel_slow_scale, duel_ramp_down_wall)
	_show_caption(line, seq)
	await _wall_wait(seq, duel_slow_hold_wall)
	await _wall_lerp(seq, _set_ts, Engine.time_scale, _prev_time_scale, duel_ramp_up_wall)
	if not strike.is_valid():
		await _wall_wait(seq, duel_tail_wall)
	while not strike_done["done"]:   # death plays out at normal speed
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	_hide_caption()
	await _face_rest(attacker)   # survivor resumes his side's resting yaw
	await _cam_exit(seq)
	_finish(seq, "duel")


## Promotion flourish: rise of light + banner flutter + caption, gentle
## slow-mo dip. Run it overlapping the piece's own spawn_flourish().
func play_promotion(piece: Node3D, meta: Dictionary = {}) -> void:
	if _active or not is_inside_tree() or not is_instance_valid(piece):
		return
	var seq := _begin("promotion")
	_arm_failsafe(seq, failsafe_wall_sec)
	_audio_capture()
	var info := _fighter(piece, meta, "attacker")
	var beam := _spawn_beam(piece, info["color"])
	_spawn_banner(piece, info["color"])
	var text := "Rise."
	var pool: Array = _lines.get("promotion_lines", [])
	if not pool.is_empty():
		text = format_line(str(pool.pick_random()), {
			"p": info["piece"], "h": info["house"],
			"a": info["animal"], "m": info["motto"],
		})
	await _wall_lerp(seq, _set_ts, Engine.time_scale, promo_slow_scale, 0.25)
	_show_caption(text, seq)
	_animate_beam(beam, seq)   # concurrent
	await _wall_wait(seq, promo_wall)
	await _wall_lerp(seq, _set_ts, Engine.time_scale, _prev_time_scale, 0.25)
	_finish(seq, "promotion")


## Checkmate ending: deep slow-mo, camera slow-orbits the losing king while
## `death` (e.g. `func(): await king.die()`) plays, caption
## "<winning house> takes the throne", 3 s hold, then the victory panel hook
## fires. The death choreography finishes at normal speed after the hold.
func play_checkmate(losing_king: Node3D, winning_house: String,
		death: Callable = Callable(), meta: Dictionary = {}) -> void:
	if _active or not is_inside_tree():
		if death.is_valid():
			await death.call()
		return
	var seq := _begin("checkmate")
	_arm_failsafe(seq, maxf(failsafe_wall_sec, checkmate_hold_wall + 5.0))
	_audio_capture()
	var house_name := resolve_house_name(winning_house)
	_champion_house = house_name   # the tableau caption beat reads this later
	var caption := format_line(
		str(_lines.get("checkmate_line", "{wh} takes the throne")), {"wh": house_name})
	# The king dies facing his killer (meta "attacker" override, else the
	# nearest enemy piece) — and the killer faces the king he fells.
	var killer := _checkmate_killer(losing_king, meta)
	var death_done := {"done": not death.is_valid()}
	if killer != null:
		await _face_off_pair(seq, losing_king, killer)
		_face_hold(seq, losing_king, killer, death_done)
	if death.is_valid():
		var runner := func() -> void:
			await death.call()
			death_done["done"] = true
		runner.call()
	_cam_orbit_checkmate(losing_king, seq)   # concurrent swoop + orbit
	await _wall_lerp(seq, _set_ts, Engine.time_scale, checkmate_slow_scale, 0.45)
	_show_caption(caption, seq)
	await _wall_wait(seq, checkmate_hold_wall)
	await _wall_lerp(seq, _set_ts, Engine.time_scale, _prev_time_scale, 0.5)
	_hide_caption()
	_orbiting = false
	await _cam_exit(seq)
	victory_panel_requested.emit(house_name)
	while not death_done["done"]:
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	await _face_rest(killer)   # the killer resumes his rest yaw over the fallen
	_finish(seq, "checkmate")


## Championship ending: glide from the current camera to a hero frame on the
## Throne of Blades (throne_focus from GreatHall.throne_focus()), hold while
## the championship panel is up, then PARK the camera there — the Grand Final
## ends framing the throne. Touches neither time_scale nor audio; a click
## (skip) mid-tableau returns to the gameplay camera instead of parking.
## The next scene change (Return to the Hall of Banners / rematch) resets
## the viewport camera as usual.
func play_championship_tableau(throne_focus: Vector3, _meta: Dictionary = {}) -> void:
	if _active or not is_inside_tree():
		return
	var seq := _begin("championship")
	_arm_failsafe(seq, maxf(failsafe_wall_sec,
		championship_glide_wall + championship_hold_wall + 3.0))
	if _cam_take_viewport():
		var cam_pos := throne_focus + championship_cam_offset
		var target := Transform3D(
			Basis.looking_at(throne_focus - cam_pos, Vector3.UP), cam_pos)
		await _cam_glide(seq, target, championship_fov, championship_glide_wall, 0.3)
	# The caption beat over the tableau — the ceremony's mark, then the
	# crown. Strictly sequential (the two lines never overlap), padded so
	# the whole beat still spends exactly the championship hold.
	var hold0 := Time.get_ticks_msec()
	_show_caption("ASHFALL.", seq)
	await _wall_wait(seq, tableau_caption_beat)
	_hide_caption()
	await _wall_wait(seq, 0.2)
	if not _champion_house.is_empty():
		_show_caption(format_line(
			str(_lines.get("checkmate_line", "{wh} takes the throne")),
			{"wh": _champion_house}), seq)
		await _wall_wait(seq, tableau_caption_beat)
	var spent := float(Time.get_ticks_msec() - hold0) / 1000.0
	await _wall_wait(seq, maxf(0.0, championship_hold_wall - spent))
	if _cam_on and not _skip and _seq == seq:
		_cam_park()
	_finish(seq, "championship")


# ── caption lines (public for tests / integrator) ──────────────────────────


## Token dict for kill-line formatting. meta keys (all optional) override
## duck-typed reads: attacker_piece, attacker_house, victim_piece, victim_house.
func duel_context(attacker: Node3D, victim: Node3D, meta: Dictionary = {}) -> Dictionary:
	var a := _fighter(attacker, meta, "attacker")
	var v := _fighter(victim, meta, "victim")
	return {
		"ap": a["piece"], "vp": v["piece"],
		"ah": a["house"], "vh": v["house"],
		"aa": a["animal"], "va": v["animal"],
		"am": a["motto"], "vm": v["motto"],
	}


## Pick a house-flavored kill line: prefers lines keyed to the attacker or
## victim piece, falls back to the generic pool, formats all tokens.
func pick_kill_line(ctx: Dictionary) -> String:
	var matched: Array = []
	var generic: Array = []
	for e in _lines.get("kill_lines", []):
		if typeof(e) != TYPE_DICTIONARY or not e.has("text"):
			continue
		if e.has("attacker") and str(e["attacker"]) != str(ctx.get("ap", "")):
			continue
		if e.has("victim") and str(e["victim"]) != str(ctx.get("vp", "")):
			continue
		if e.has("attacker") or e.has("victim"):
			matched.append(e)
		else:
			generic.append(e)
	var pool := generic
	if not matched.is_empty() and (generic.is_empty() or randf() < 0.65):
		pool = matched
	if pool.is_empty():
		return "So falls the %s of %s." % [ctx.get("vp", "warrior"), ctx.get("vh", "the enemy")]
	return format_line(str(pool.pick_random()["text"]), ctx)


static func format_line(text: String, ctx: Dictionary) -> String:
	var out := text
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


func resolve_house_name(key_or_name: String) -> String:
	return str(_house_info(key_or_name)["name"])


# ── face-to-face choreography (2026-08-08) ─────────────────────────────────
# Battle doctrine: no duel is fought back-to-back. The director rotates the
# fighters' root Node3Ds directly (PieceView internals are never touched);
# towers (piece_type 1) are exempt — a watchtower has no face. Fighters'
# native forward is +Z; resting yaw is the piece's own spawn orientation
# (duck-read _home_yaw) or the side convention (FROST +Z, EMBER -Z).

const TYPE_TOWER := 1


static func _has_facing(n: Node3D) -> bool:
	if not is_instance_valid(n):
		return false
	var pt = n.get("piece_type")
	return not (typeof(pt) == TYPE_INT and int(pt) == TYPE_TOWER)


static func _yaw_from_to(from: Node3D, to_pos: Vector3) -> float:
	var d := to_pos - from.global_position
	return atan2(d.x, d.z)


static func _rest_yaw(n: Node3D, fallback: float) -> float:
	var hy = n.get("_home_yaw")
	if typeof(hy) == TYPE_FLOAT:
		return float(hy)
	var s = n.get("side")
	if typeof(s) == TYPE_INT:
		return 0.0 if int(s) == 0 else PI
	return fallback


## Both fighters turn to meet: ~0.2 s wall-clock ease-out on rotation.y.
## Aborts (leaving yaw wherever it is) on skip/supersede — the wrapped
## choreography still runs and settles its own pose.
func _face_off_pair(seq: int, a: Node3D, b: Node3D) -> void:
	if not (is_instance_valid(a) and is_instance_valid(b)):
		return
	var turn_a := _has_facing(a)
	var turn_b := _has_facing(b)
	if not turn_a and not turn_b:
		return
	var ya0 := a.rotation.y
	var yb0 := b.rotation.y
	var t0 := Time.get_ticks_msec()
	while true:
		if _seq != seq or _skip:
			return
		if not (is_instance_valid(a) and is_instance_valid(b)):
			return
		var u := clampf(float(Time.get_ticks_msec() - t0) / (face_off_wall * 1000.0), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)   # ease-out: the snap of meeting eyes
		if turn_a:
			a.rotation.y = lerp_angle(ya0, _yaw_from_to(a, b.global_position), e)
		if turn_b:
			b.rotation.y = lerp_angle(yb0, _yaw_from_to(b, a.global_position), e)
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


## Concurrent per-frame yaw lock while `done["done"]` is false: keeps the
## pair meeting eye-to-eye through lunges and death throes, and outlives
## any stale fire-and-forget rotation tween from earlier gameplay.
func _face_hold(seq: int, a: Node3D, b: Node3D, done: Dictionary) -> void:
	var runner := func() -> void:
		while _seq == seq and not _skip and not bool(done.get("done", true)):
			if is_instance_valid(a) and is_instance_valid(b):
				if _has_facing(a):
					a.rotation.y = _yaw_from_to(a, b.global_position)
				if _has_facing(b):
					b.rotation.y = _yaw_from_to(b, a.global_position)
			var tree := get_tree()
			if tree == null:
				return
			await tree.process_frame
	runner.call()


## Survivor eases back to his side's resting yaw. Runs on the skip path too
## (instant snap there) — a duel may not leave a stray facing behind.
func _face_rest(survivor: Node3D) -> void:
	if survivor == null or not is_instance_valid(survivor) or not _has_facing(survivor):
		return
	var rest := _rest_yaw(survivor, survivor.rotation.y)
	if _skip:
		survivor.rotation.y = rest
		return
	var y0 := survivor.rotation.y
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(survivor):
		var u := clampf(float(Time.get_ticks_msec() - t0) / (face_rest_wall * 1000.0), 0.0, 1.0)
		survivor.rotation.y = lerp_angle(y0, rest, 1.0 - pow(1.0 - u, 3.0))
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


## The piece the king dies facing: meta["attacker"] when the integrator
## passes one, else the nearest enemy piece on the board (duck-typed side/
## piece_type ints — the checkmating piece is almost always the closest).
func _checkmate_killer(king: Node3D, meta: Dictionary) -> Node3D:
	var m = meta.get("attacker")
	if m is Node3D and is_instance_valid(m):
		return m
	if not is_instance_valid(king):
		return null
	var ks = king.get("side")
	if typeof(ks) != TYPE_INT:
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_d := INF
	for n in tree.root.find_children("*", "Node3D", true, false):
		if n == king or n.is_queued_for_deletion():
			continue
		var s = n.get("side")
		var pt = n.get("piece_type")
		if typeof(s) != TYPE_INT or typeof(pt) != TYPE_INT or int(s) == int(ks):
			continue
		var d := (n as Node3D).global_position.distance_squared_to(king.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


# ── skip input: any click or Esc while active ──────────────────────────────


func _input(event: InputEvent) -> void:
	if not _active:
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


# ── sequence plumbing / time_scale hygiene ─────────────────────────────────


func _begin(kind: String) -> int:
	_seq += 1
	_active = true
	_skip = false
	_kind = kind
	_prev_time_scale = Engine.time_scale
	cinematic_started.emit(kind)
	return _seq


func _finish(seq: int, kind: String) -> void:
	if seq != _seq:
		return   # superseded (should not happen — _active guards re-entry)
	_restore_presentation()
	_active = false
	cinematic_finished.emit(kind)


## Idempotent: time_scale, audio pitch, caption, camera, props all back.
## Called from _finish(), skip(), the failsafe, and _exit_tree().
func _restore_presentation() -> void:
	Engine.time_scale = _prev_time_scale
	_audio_restore()
	if _caption_layer != null:
		_caption_fade += 1   # kill any in-flight fade; the hard reset wins
		_caption_layer.visible = false
	_shake_target = 0.0
	_shake = 0.0
	_orbiting = false
	for pr in _props:
		if is_instance_valid(pr):
			pr.queue_free()
	_props.clear()
	if _cam_on:
		_cam_restore()


func _exit_tree() -> void:
	## Finally-style guarantee: a freed/detached director never strands a
	## slowed clock or pitched-down audio.
	if _active:
		Engine.time_scale = _prev_time_scale
		_audio_restore()
		for pr in _props:
			if is_instance_valid(pr):
				pr.queue_free()
		_props.clear()
		if _cam_on and is_instance_valid(_prev_cam):
			_prev_cam.current = true
		_cam_on = false
		_active = false


func _arm_failsafe(seq: int, wall_sec: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(wall_sec, true, false, true)   # ignore_time_scale
	t.timeout.connect(_on_failsafe.bind(seq))


func _on_failsafe(seq: int) -> void:
	if _seq == seq and _active and not _skip:
		push_warning("DuelDirector failsafe: '%s' overran — restoring presentation" % _kind)
		skip()


func _set_ts(v: float) -> void:
	Engine.time_scale = v
	var factor := clampf(v, 0.25, 1.0)   # audio pitch follows the slow-mo
	for e in _audio_base:
		var p = e["node"]
		if is_instance_valid(p):
			p.pitch_scale = maxf(0.05, e["pitch"] * factor)


func _audio_capture() -> void:
	_audio_base.clear()
	var tree := get_tree()
	if tree == null:
		return
	for cls in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for p in tree.root.find_children("*", cls, true, false):
			_audio_base.append({"node": p, "pitch": p.pitch_scale})


func _audio_restore() -> void:
	for e in _audio_base:
		var p = e["node"]
		if is_instance_valid(p):
			p.pitch_scale = e["pitch"]
	_audio_base.clear()


# ── wall-clock interpolation (immune to Engine.time_scale) ─────────────────


static func _ease_cubic(u: float) -> float:
	if u < 0.5:
		return 4.0 * u * u * u
	return 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0


## Interpolate `setter(value)` from -> to over `dur` wall seconds with cubic
## in-out easing. Aborts (without touching the value) on skip or supersede.
func _wall_lerp(seq: int, setter: Callable, from: float, to: float, dur: float) -> void:
	if dur <= 0.0:
		if _seq == seq and not _skip:
			setter.call(to)
		return
	var t0 := Time.get_ticks_msec()
	while true:
		if _seq != seq or _skip:
			return
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		setter.call(lerpf(from, to, _ease_cubic(u)))
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _wall_wait(seq: int, sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _seq != seq or _skip:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


# ── camera work ────────────────────────────────────────────────────────────


func _process(_delta: float) -> void:
	if not _cam_on:
		return
	var now := Time.get_ticks_msec()
	var wdt := clampf(float(now - _last_tick) / 1000.0, 0.0, 0.1)
	_last_tick = now
	_shake = lerpf(_shake, _shake_target, 1.0 - exp(-6.0 * wdt))
	var t := float(now) / 1000.0
	var off := Vector3(
		_noise.get_noise_2d(t * 2.3, 0.0),
		_noise.get_noise_2d(0.0, t * 2.9),
		_noise.get_noise_2d(t * 1.7, 100.0)) * _shake
	var roll := _noise.get_noise_2d(t * 1.3, 50.0) * _shake * 0.5
	var xf := _cam_base
	xf.origin += xf.basis * off
	xf.basis = xf.basis.rotated((xf.basis * Vector3.FORWARD).normalized(), roll)
	_cam.global_transform = xf


## Swoop from the current viewport camera to a low side angle framing both
## fighters. No-op when there is no active camera (headless unit tests).
func _cam_enter_duel(attacker: Node3D, victim: Node3D, seq: int) -> void:
	if not _cam_take_viewport():
		return
	var a := attacker.global_position if is_instance_valid(attacker) else Vector3.ZERO
	var v := victim.global_position if is_instance_valid(victim) else a + Vector3.FORWARD
	var mid := (a + v) * 0.5 + Vector3.UP * 0.55
	var axis := v - a
	axis.y = 0.0
	axis = axis.normalized() if axis.length() > 0.01 else Vector3.FORWARD
	var side := axis.cross(Vector3.UP).normalized()
	var back := clampf(a.distance_to(v) * 1.55, 2.0, 4.5)
	var p1 := mid + side * back + Vector3.UP * 0.42
	var p2 := mid - side * back + Vector3.UP * 0.42
	var from := _cam_base.origin
	var cam_pos := p1 if from.distance_to(p1) <= from.distance_to(p2) else p2
	var target := Transform3D(Basis.looking_at(mid - cam_pos, Vector3.UP), cam_pos)
	await _cam_glide(seq, target, duel_fov, swoop_wall, 0.35)


## Swoop to the dying king, then slow-orbit it until _orbiting is cleared.
func _cam_orbit_checkmate(king: Node3D, seq: int) -> void:
	if not _cam_take_viewport():
		return
	var focus := king.global_position + Vector3.UP * 0.6 \
		if is_instance_valid(king) else Vector3.UP * 0.6
	var radius := 2.8
	var height := 1.15
	var to_cam := _cam_base.origin - focus
	to_cam.y = 0.0
	var ang := atan2(to_cam.x, to_cam.z) if to_cam.length() > 0.01 else 0.0
	var start_pos := focus + Vector3(sin(ang), 0.0, cos(ang)) * radius + Vector3.UP * height
	var target := Transform3D(Basis.looking_at(focus - start_pos, Vector3.UP), start_pos)
	_orbiting = true
	await _cam_glide(seq, target, 46.0, 0.6, 0.25)
	var last := Time.get_ticks_msec()
	while _orbiting and _seq == seq and not _skip and _cam_on:
		var now := Time.get_ticks_msec()
		var wdt := clampf(float(now - last) / 1000.0, 0.0, 0.1)
		last = now
		ang += wdt * checkmate_orbit_speed
		if is_instance_valid(king):
			focus = focus.lerp(king.global_position + Vector3.UP * 0.6, 0.05)
		var pos := focus + Vector3(sin(ang), 0.0, cos(ang)) * radius + Vector3.UP * height
		_cam_base = Transform3D(Basis.looking_at(focus - pos, Vector3.UP), pos)
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


## Adopt the viewport camera pose and become current. False when headless
## test rigs have no camera (camera phases are then skipped entirely).
func _cam_take_viewport() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var prev := vp.get_camera_3d()
	if prev == null or prev == _cam:
		return false
	_prev_cam = prev
	_cam_base = prev.global_transform
	_cam.global_transform = prev.global_transform
	_cam.fov = prev.fov
	_cam.current = true
	_cam_on = true
	_shake_target = handheld_amp
	_last_tick = Time.get_ticks_msec()
	return true


func _cam_glide(seq: int, target: Transform3D, target_fov: float,
		dur: float, arc: float) -> void:
	var start := _cam_base
	var start_fov := _cam.fov
	var sq := start.basis.get_rotation_quaternion()
	var tq := target.basis.get_rotation_quaternion()
	var setter := func(e: float) -> void:
		var pos := start.origin.lerp(target.origin, e) + Vector3.UP * (sin(e * PI) * arc)
		_cam_base = Transform3D(Basis(sq.slerp(tq, e)), pos)
		_cam.fov = lerpf(start_fov, target_fov, e)
	await _wall_lerp(seq, setter, 0.0, 1.0, dur)


func _cam_exit(seq: int) -> void:
	if not _cam_on:
		return
	_shake_target = 0.0
	var end := _prev_cam.global_transform if is_instance_valid(_prev_cam) else _cam_base
	var end_fov := _prev_cam.fov if is_instance_valid(_prev_cam) else _cam.fov
	await _cam_glide(seq, end, end_fov, return_wall, 0.0)
	_cam_restore()


func _cam_restore() -> void:
	if not _cam_on:
		return
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	_cam.current = false
	_cam_on = false
	_prev_cam = null


func _cam_park() -> void:
	## Championship ending shot: leave the cine cam live on its final frame.
	## Clearing _cam_on first makes _restore_presentation/_cam_restore no-ops,
	## so _finish() releases the director without yanking the camera back.
	_shake_target = 0.0
	_shake = 0.0
	_cam.global_transform = _cam_base   # settle any handheld residue
	_cam_on = false
	_prev_cam = null


# ── caption UI ─────────────────────────────────────────────────────────────


func _build_caption() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.name = "CineCaption"
	_caption_layer.layer = 90
	_caption_layer.visible = false
	add_child(_caption_layer)
	_caption = Label.new()
	_caption.name = "CaptionLabel"
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(
		["Didot", "Georgia", "Palatino", "Times New Roman", "serif"])
	serif.font_italic = true
	_caption.add_theme_font_override("font", serif)
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color(0.91, 0.85, 0.68))
	_caption.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A styled backing plate: the kill line lands over torchlit armor as
	# often as over dark stone, and a bare glyph shadow was not enough to
	# carry it. Hugs the text (the label sizes to content), so it never
	# becomes a slab across the frame.
	_caption.add_theme_stylebox_override("normal", caption_backing())
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	# Bottom sixth of the frame — the fight happens in the middle third and
	# the caption may never sit in it (ISSUES.md #4).
	_caption.offset_top = -160.0
	_caption.offset_bottom = -96.0
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption_layer.add_child(_caption)


## The caption backing plate — public so CineCaption and the HUD's own
## captions dress in the same clothes (one voice, one look).
static func caption_backing() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.028, 0.032, 0.62)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 10.0
	sb.border_color = Color(0.72, 0.58, 0.32, 0.4)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	return sb


## True while a cinematic caption is on screen. The HUD's own captions
## (rival banter, Oracle reason) hold off while this is true so two voices
## never share one frame (ISSUES.md #4).
func caption_visible() -> bool:
	return _caption_layer != null and _caption_layer.visible


func _show_caption(text: String, seq: int) -> void:
	if _caption == null:
		return
	_caption_fade += 1   # any in-flight fade-out loses the layer
	_caption.text = text
	_caption.modulate = Color(1, 1, 1, 0)
	_caption_layer.visible = true
	var setter := func(a: float) -> void:
		_caption.modulate = Color(1, 1, 1, a)
	_wall_lerp(seq, setter, 0.0, 1.0, 0.25)   # concurrent fade-in


func _hide_caption(fade_sec: float = 0.3) -> void:
	## Fade OUT (wall clock, slow-mo immune) — a caption that snapped off
	## mid-frame read as a debug panel being toggled. `restore()` still kills
	## the layer instantly; this is the graceful path.
	if _caption_layer == null or not _caption_layer.visible:
		return
	_caption_fade += 1
	var my := _caption_fade
	if fade_sec <= 0.0 or _caption == null:
		_caption_layer.visible = false
		return
	var t0 := Time.get_ticks_msec()
	while _caption_layer != null and _caption_layer.visible and _caption_fade == my:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (fade_sec * 1000.0), 0.0, 1.0)
		_caption.modulate = Color(1, 1, 1, 1.0 - u)
		if u >= 1.0:
			_caption_layer.visible = false
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


# ── flourish props (promotion) ─────────────────────────────────────────────


func _spawn_beam(piece: Node3D, tint: Color) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.3
	cyl.height = 2.6
	beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.4)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0.0, 1.3, 0.0)
	beam.scale = Vector3(1.0, 0.05, 1.0)
	piece.add_child(beam)
	_props.append(beam)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.6
	light.omni_range = 3.0
	light.position = Vector3(0.0, 1.0, 0.0)
	piece.add_child(light)
	_props.append(light)
	return beam


func _animate_beam(beam: MeshInstance3D, seq: int) -> void:
	var setter := func(e: float) -> void:
		if not is_instance_valid(beam):
			return
		beam.scale = Vector3(1.0, clampf(e * 2.2, 0.05, 1.0), 1.0)
		var mat: StandardMaterial3D = beam.material_override
		if mat != null:
			mat.albedo_color.a = 0.4 * clampf((1.0 - e) * 2.4, 0.0, 1.0)
	await _wall_lerp(seq, setter, 0.0, 1.0, promo_wall * 0.9)


func _spawn_banner(piece: Node3D, tint: Color) -> MeshInstance3D:
	var banner := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(0.46, 0.72)
	plane.subdivide_width = 6
	plane.subdivide_depth = 10
	banner.mesh = plane
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	float hang = UV.y;   // 0 at the rod, 1 at the free hem
	VERTEX.z += sin(TIME * 5.0 + VERTEX.y * 5.0 + VERTEX.x * 2.0) * 0.07 * hang;
	VERTEX.x += sin(TIME * 3.4 + VERTEX.y * 3.0) * 0.02 * hang;
}
void fragment() {
	ALBEDO = tint.rgb * (0.75 + 0.25 * (1.0 - UV.y));
	ALPHA = tint.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 0.92))
	banner.material_override = mat
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	banner.position = Vector3(0.0, 1.95, 0.0)
	banner.rotation.y = 0.5
	piece.add_child(banner)
	_props.append(banner)
	return banner


# ── fighter identity (duck-typed, meta-overridable) ────────────────────────


func _fighter(node: Node3D, meta: Dictionary, prefix: String) -> Dictionary:
	var piece_name := str(meta.get(prefix + "_piece", ""))
	var house_key := str(meta.get(prefix + "_house", ""))
	if piece_name.is_empty() and is_instance_valid(node):
		var pt = node.get("piece_type")
		if typeof(pt) == TYPE_INT and pt >= 0 and pt < PIECE_NAMES.size():
			piece_name = PIECE_NAMES[pt]
	if piece_name.is_empty():
		piece_name = "warrior"
	if house_key.is_empty() and is_instance_valid(node):
		var s = node.get("side")
		if typeof(s) == TYPE_INT and s >= 0 and s < HOUSE_KEYS.size():
			house_key = HOUSE_KEYS[s]
	var info := _house_info(house_key)
	info["piece"] = piece_name
	return info


func _house_info(key_or_name: String) -> Dictionary:
	var lk := key_or_name.strip_edges().to_lower()
	if _canon.has(lk):
		return _canon[lk].duplicate()   # caller mutates (adds "piece")
	var houses: Dictionary = _lines.get("houses", {})
	var h: Dictionary = houses.get(key_or_name.to_upper(), {})
	if h.is_empty():
		for k in houses:
			if str(houses[k].get("name", "")).nocasecmp_to(key_or_name) == 0:
				h = houses[k]
				break
	var fallback_name := key_or_name if not key_or_name.is_empty() else "an unnamed house"
	return {
		"name": str(h.get("name", fallback_name)),
		"house": str(h.get("name", fallback_name)),
		"animal": str(h.get("animal", "wolf")),
		"motto": str(h.get("motto", "We Endure")),
		"color": Color.from_string(str(h.get("color", "#d8b46a")), Color(0.85, 0.7, 0.4)),
	}


func _load_lines() -> void:
	var f := FileAccess.open(LINES_PATH, FileAccess.READ)
	if f == null:
		push_warning("DuelDirector: cannot open %s — captions fall back to plain text" % LINES_PATH)
		_lines = {}
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("DuelDirector: %s is not a JSON object — captions degraded" % LINES_PATH)
		_lines = {}
	else:
		_lines = data
	_load_canonical_houses()


## Merge the HouseRegistry nine-house roster (if shipped) so meta-passed
## house ids/names/archetypes resolve to the canonical display identity.
func _load_canonical_houses() -> void:
	_canon.clear()
	var f := FileAccess.open(HOUSES_REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return   # registry not present — the local houses table covers it
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for h in data.get("houses", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var colors: Dictionary = h.get("colors", {})
		var info := {
			"name": str(h.get("name", "")),
			"house": str(h.get("name", "")),
			"animal": str(h.get("archetype", "wolf")),
			"motto": str(h.get("motto", "We Endure")).rstrip(". "),
			"color": Color.from_string(
				str(colors.get("accent", colors.get("primary", "#d8b46a"))),
				Color(0.85, 0.7, 0.4)),
		}
		if info["name"].is_empty():
			continue
		for k: String in [str(h.get("id", "")), str(h.get("name", "")), str(h.get("archetype", ""))]:
			var lk: String = k.strip_edges().to_lower()
			if not lk.is_empty() and not _canon.has(lk):
				_canon[lk] = info
