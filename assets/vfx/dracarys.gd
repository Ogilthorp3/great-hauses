extends Node3D
class_name DracarysVFX
## DRACARYS VFX KIT — the fire, independent of whatever dragon wins.
##
## Six layers, all built in code, all driven off ONE public call:
##
##   1. CORE JET        a shader-driven pressure stem + streaked particles
##   2. ROLLING BODY    slow turbulent billows that cool and curl upward
##   3. EMBERS + ASH    dragging sparks that outlive the jet ~4 s, then ashfall
##   4. GROUND FIRE     a pool where the torrent lands, fading to smoke
##   5. HEAT SHIMMER    screen-space refraction over and behind the flame
##   6. IMPACT PUNCH    camera shake + exposure/glow kick (reusable, restoring)
##
## HARD CONSTRAINT HONOURED: this file NEVER creates a Light3D. The hall's
## 8-omni budget is full. Firelight is sold with HDR emissive particles, an
## additive ground-glow quad, and an OPTIONAL WorldEnvironment lift that is
## always restored (see "RESTORE CONTRACT" below).
##
## RESTORE CONTRACT
## ----------------
## Anything this kit changes outside its own subtree is (a) recorded on first
## touch, (b) restored by `restore_environment()` / `restore_camera()`, and
## (c) those two are called unconditionally by `hard_stop()`, by the normal
## end of the sequence, by `_exit_tree()` and by NOTIFICATION_PREDELETE.
## Both restores are idempotent. A stuck exposure is a shipping bug, so the
## kit treats "the effect ended" and "the effect was skipped" as the same
## code path — there is no success-only restore.
##
## SKIP SAFETY
## -----------
## `hard_stop()` clears every particle buffer in the same frame, zeroes every
## shader `amount` uniform, cancels all pending scheduled callbacks and fades,
## restores camera + environment, and emits `finished`. It is safe to call at
## any time, twice, or when nothing is running.
##
## TIME SCALE
## ----------
## All internal sequencing is WALL CLOCK (Time.get_ticks_usec), so the kit is
## immune to the `Engine.time_scale` the ceremony bends around it.
##
## Typical use (see DRACARYS-API.md):
##     var fx := preload("res://.../dracarys.gd").new()
##     add_child(fx)
##     fx.bind_camera(get_viewport().get_camera_3d())
##     fx.bind_environment($WorldEnvironment)
##     await fx.fire(head_bone_attachment, board_centre, 2.6)

# ── signals ────────────────────────────────────────────────────────────────

## Emitted the frame the jet punches out (stem snap + shock ring + punch).
signal ignited
## Emitted when the jet is cut and only the tail (embers/ash/smoke) remains.
signal torrent_cut
## Emitted when the torrent reaches the aim point and the ground pool lights.
signal impacted
## Emitted when the whole effect (including the tail) is done, OR immediately
## on hard_stop(). Always fires exactly once per fire() call.
signal finished

# ── configuration ──────────────────────────────────────────────────────────

## Distance from muzzle to impact, in metres. Drives jet speed, stem length,
## shimmer size and the ground-pool radius. Overridden per shot by `fire()`
## when an explicit target is given.
@export var reach: float = 6.0
## Global brightness multiplier on every HDR colour. 1.0 assumes a dark hall
## with glow enabled and roughly filmic tonemapping.
@export var intensity: float = 1.0
## Half-angle spread of the rolling body, degrees. Bigger = fatter torrent.
@export var torrent_spread: float = 15.0
## World Y of the floor the ground fire pools on.
@export var floor_y: float = 0.0
## Layer 5 toggle. Screen-space refraction; safe on the Forward Mobile
## renderer but the single most expensive layer — first thing to drop on a
## low-end device tier.
@export var heat_shimmer_enabled: bool = true
## Layer 6 toggle for the WorldEnvironment lift (camera shake is separate).
@export var environment_lift_enabled: bool = true
## When true, fire() fires punch_camera()/punch_exposure() itself using the
## bound camera + environment. Set false if the ceremony wants to drive them.
@export var auto_punch: bool = true
## Seconds the embers keep living after the jet is cut (the brief asks 3-4).
@export var ember_tail: float = 4.0
## Seconds of ash drift after the embers are gone.
@export var ash_tail: float = 4.5

const JET_STEM_SHADER := preload("res://assets/vfx/jet_stem.gdshader")
const GROUND_GLOW_SHADER := preload("res://assets/vfx/ground_glow.gdshader")
const SHOCK_RING_SHADER := preload("res://assets/vfx/shock_ring.gdshader")
const HEAT_SHIMMER_SHADER := preload("res://assets/vfx/heat_shimmer.gdshader")

# ── palette (HDR — values above 1.0 are what makes glow bloom) ─────────────

# Values above 1.0 bloom. They are deliberately MODEST: additive particles
# stack, so a "hot" per-particle colour plus 200 overlapping quads saturates
# the frame to white paste. Density does the brightness, not the constant.
const WHITE_HOT := Color(2.60, 2.25, 1.72)
const YELLOW_HOT := Color(2.45, 1.30, 0.32)
const ORANGE := Color(1.70, 0.50, 0.072)
const DEEP_RED := Color(0.86, 0.11, 0.018)
const EMBER_RED := Color(0.62, 0.07, 0.012)
# Deliberately DARK. Smoke in an unlit hall is not lit by anything; a bright
# grey makes a cotton-wool blob that is brighter than the stone behind it.
const SMOKE_GREY := Color(0.105, 0.098, 0.092)
const ASH_GREY := Color(0.34, 0.325, 0.30)

# Wall-clock phase offsets, seconds from ignition. Documented in the API doc;
# the demo's screenshot schedule is derived from these.
const T_STEM_SNAP := 0.10      # stem reaches full bore
const T_BODY_IN := 0.05        # rolling body joins
const T_EMBER_IN := 0.09       # jet-riding sparks join
const T_SMOKE_IN := 0.32       # dark smoke starts curling off the body
const CUT_RETRACT := 0.16      # stem retract time when the jet is cut
const GROUND_FADE := 3.20      # ground glow dies SLOWLY: stone smoulders
## The solid stem is the pressure ROOT near the lips, not the whole beam —
## particles own the rest. A stem the full length of the shot reads as a laser.
const STEM_FRACTION := 0.52

## Base (min, max) launch speeds at reach == 6 m. SINGLE SOURCE: both the
## builder and _scale_to_reach() read these. They used to be duplicated as
## literals in two places, and the scale pass silently reverted every tuning
## change made in the builder.
const CORE_V := Vector2(17.0, 25.0)
const BODY_V := Vector2(19.0, 30.0)
## Kept modest ON PURPOSE. These are scaled by reach AND stretched by
## velocity-alignment, so a high value throws multi-metre quads clear across
## the hall (and past the camera) as dark red smears.
const BLAST_V := Vector2(22.0, 40.0)

# ── runtime state ──────────────────────────────────────────────────────────

var _built := false
var _active := false
var _run_id := 0

var muzzle: Node3D            # the aimed rig (all forward-facing layers)
var ground: Node3D            # parked at the impact point

var _stem: MeshInstance3D
var _stem_mat: ShaderMaterial
var _stem_mesh: CylinderMesh
var _muzzle_ring: MeshInstance3D
var _muzzle_ring_mat: ShaderMaterial
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _shimmer: MeshInstance3D
var _shimmer_mat: ShaderMaterial
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _ground_ring: MeshInstance3D
var _ground_ring_mat: ShaderMaterial

var _core: GPUParticles3D
var _blast: GPUParticles3D     # one-shot ignition front
var _body: GPUParticles3D
var _jet_embers: GPUParticles3D
var _smoke: GPUParticles3D
var _splash: GPUParticles3D
var _ground_flame: GPUParticles3D
var _ground_smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _ash: GPUParticles3D

var _noise_tex: NoiseTexture2D
var _puff_tex: GradientTexture2D
var _core_tex: GradientTexture2D
var _spark_tex: GradientTexture2D

## The reusable ignition shake envelope (0..1 over its own duration).
var shake_envelope: Curve

# tracked aim
var _track_node: Node3D = null
var _track_xform := Transform3D.IDENTITY
var _target := Vector3.ZERO
var _shot_reach := 6.0

# wall-clock scheduling
var _last_us := 0
var _pending: Array = []      # {"t": float, "cb": Callable}
var _fades: Array = []        # {"set": Callable, "a": float, "b": float,
                              #  "d": float, "t": float, "wait": float}
var _shakes: Array = []       # {"cam": Camera3D, "t": float, ...}

# bound externals + saved originals (RESTORE CONTRACT)
var _camera: Camera3D = null
var _world_env: WorldEnvironment = null
var _cam_saved: Dictionary = {}
var _env_saved: Dictionary = {}

# ── lifecycle ──────────────────────────────────────────────────────────────


func _ready() -> void:
	_last_us = Time.get_ticks_usec()
	if not _built:
		_build()
	set_process(true)


func _exit_tree() -> void:
	restore_camera()
	restore_environment()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		restore_camera()
		restore_environment()


# ── public API ─────────────────────────────────────────────────────────────


## Bind the camera the IMPACT PUNCH shakes. Optional; punch_camera() also
## takes an explicit camera.
func bind_camera(cam: Camera3D) -> void:
	_camera = cam


## Bind the WorldEnvironment the exposure/glow kick lifts. Optional.
func bind_environment(we: WorldEnvironment) -> void:
	_world_env = we


## Point the rig. `from` may be a Node3D (tracked live every frame — use the
## dragon's head-bone attachment) or a Transform3D / Vector3 (static).
## Safe to call every frame mid-torrent to sweep the beam across the board.
func aim(from: Variant, target: Vector3) -> void:
	if from is Node3D:
		_track_node = from
		_track_xform = (from as Node3D).global_transform
	elif from is Transform3D:
		_track_node = null
		_track_xform = from
	elif from is Vector3:
		_track_node = null
		_track_xform = Transform3D(Basis.IDENTITY, from)
	_target = target
	_apply_aim()


## THE SHOT. Awaitable: returns when the tail has fully died (or immediately
## after hard_stop()). `duration` is the length of the jet itself; the tail
## adds roughly `ember_tail + ash_tail` seconds of embers/ash/smoke.
func fire(from: Variant, target: Vector3, duration: float = 2.6) -> void:
	start(from, target, duration)
	if _active:
		await finished


## Non-blocking form of fire(). Use when the ceremony drives its own timeline.
func start(from: Variant, target: Vector3, duration: float = 2.6) -> void:
	if not _built:
		_build()
	hard_stop()          # never stack two torrents
	_run_id += 1
	var rid := _run_id
	_active = true

	aim(from, target)
	_shot_reach = maxf(_track_xform.origin.distance_to(target), 0.75)
	_scale_to_reach(_shot_reach)

	# hard_stop() hides every emitter (that is how it clears instantly) —
	# un-hide them or the whole torrent renders nothing but the stem.
	for p in _all_emitters():
		if p != null:
			p.visible = true

	var travel := clampf(_shot_reach / 26.0, 0.05, 0.35)   # jet time of flight

	# ── t = 0 : IGNITION ───────────────────────────────────────────────────
	_stem.visible = true
	_stem_mat.set_shader_parameter("amount", 0.0)
	_fade(func(v: float) -> void: _stem_mat.set_shader_parameter("amount", v),
		0.0, 1.0, T_STEM_SNAP, 0.0, "stem_a")
	var stem_len := _shot_reach * STEM_FRACTION
	_stem_mesh.height = 0.25 * stem_len
	_fade(func(v: float) -> void: _set_stem_length(v),
		0.22 * stem_len, stem_len, T_STEM_SNAP * 1.35, 0.0, "stem_l")

	_core.emitting = true
	_blast.restart()
	_blast.emitting = true
	_jet_embers.emitting = true          # sparks fly on frame ONE, not later
	_burst_ring(_muzzle_ring, _muzzle_ring_mat, 0.17, 1.15 * _pow_scale(), 2.2)
	_pop_flash()

	if heat_shimmer_enabled and _shimmer != null:
		_shimmer.visible = true
		_fade(func(v: float) -> void: _shimmer_mat.set_shader_parameter("amount", v),
			0.0, 1.0, 0.14, 0.0, "shim")

	if auto_punch:
		if _camera != null:
			punch_camera(_camera)
		if environment_lift_enabled and _world_env != null:
			punch_exposure(_world_env, duration)

	ignited.emit()

	# ── the layers stagger in ──────────────────────────────────────────────
	_after(T_BODY_IN, func() -> void: _body.emitting = true, rid)
	_after(T_SMOKE_IN, func() -> void: _smoke.emitting = true, rid)

	# ── impact: ground fire lights when the torrent arrives ────────────────
	_after(travel, func() -> void: _impact(rid), rid)

	# ── the cut ────────────────────────────────────────────────────────────
	_after(maxf(duration, 0.2), func() -> void: cut(), rid)

	# ── the tail, then done ────────────────────────────────────────────────
	# Last ash particle dies at cut + 0.6 (ash-in) + ash_tail*0.5 (emit
	# window) + ash_tail (lifetime). +0.4 slack. See TIMELINE in the API doc.
	var tail := maxf(duration, 0.2) + 0.6 + ash_tail * 1.5 + 0.4
	_after(tail, func() -> void: _complete(rid), rid)


## Cut the jet early but LET THE TAIL LIVE (embers keep flying, ash falls,
## smoke curls). This is the graceful stop; `hard_stop()` is the skip.
func cut() -> void:
	if not _active:
		return
	var rid := _run_id
	_core.emitting = false
	_body.emitting = false
	_jet_embers.emitting = false
	_fade(func(v: float) -> void: _stem_mat.set_shader_parameter("amount", v),
		1.0, 0.0, CUT_RETRACT, 0.0, "stem_a")
	_fade(func(v: float) -> void: _set_stem_length(v),
		_shot_reach * STEM_FRACTION, 0.18 * _shot_reach * STEM_FRACTION,
		CUT_RETRACT, 0.0, "stem_l")
	_after(CUT_RETRACT, func() -> void: _stem.visible = false, rid)
	if heat_shimmer_enabled and _shimmer != null:
		_fade(func(v: float) -> void: _shimmer_mat.set_shader_parameter("amount", v),
			1.0, 0.0, 0.9, 0.15, "shim")
	# Ground flame burns on a beat longer, then becomes smoke.
	_after(0.45, func() -> void:
		_ground_flame.emitting = false
		_ground_smoke.emitting = true, rid)
	_fade(func(v: float) -> void: _glow_mat.set_shader_parameter("amount", v),
		1.0, 0.0, GROUND_FADE, 0.35, "glow_a")
	_after(0.9, func() -> void: _smoke.emitting = false, rid)
	# Sparks stop feeding ~1 s after the cut; the last one lives `ember_tail`
	# beyond that, which is the 3-4 s ember tail the brief asks for.
	_after(0.9, func() -> void: _sparks.emitting = false, rid)
	# ASH: starts as the fire dies and drifts down over the aftermath.
	_after(0.6, func() -> void: _ash.emitting = true, rid)
	_after(0.6 + ash_tail * 0.5, func() -> void: _ash.emitting = false, rid)
	_after(1.6, func() -> void: _ground_smoke.emitting = false, rid)
	# Environment lift releases with the flame, not with the tail.
	if environment_lift_enabled and _world_env != null:
		_release_exposure(0.75)
	torrent_cut.emit()


## SKIP. Instantly clears every particle, kills every shader contribution,
## cancels all pending work, and restores camera + environment. Idempotent.
func hard_stop() -> void:
	_run_id += 1                       # orphans every pending callback
	_pending.clear()
	_fades.clear()
	for p in _all_emitters():
		if p == null:
			continue
		p.emitting = false
		p.restart()                    # clears the buffer this frame
		p.emitting = false
		p.visible = false
	if _stem != null:
		_stem.visible = false
		_stem_mat.set_shader_parameter("amount", 0.0)
	if _shimmer != null:
		_shimmer.visible = false
		_shimmer_mat.set_shader_parameter("amount", 0.0)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("amount", 0.0)
	if _muzzle_ring != null:
		_muzzle_ring.visible = false
	if _ground_ring != null:
		_ground_ring.visible = false
	if _flash != null:
		_flash.visible = false
	_shakes.clear()
	restore_camera()
	restore_environment()
	var was := _active
	_active = false
	if was:
		finished.emit()


func is_active() -> bool:
	return _active


## Tuning / QA helper: show ONLY the heat shimmer, with no fire behind it, so
## the refraction can be judged and A/B'd on its own. Also the cheapest way to
## confirm the Forward Mobile screen-texture path is alive on a device tier
## before shipping to it. Not used by the ceremony.
func preview_shimmer(on: bool, from: Variant = null,
		target: Vector3 = Vector3.ZERO) -> void:
	if not _built:
		_build()
	if _shimmer == null:
		return
	if on and from != null:
		aim(from, target)
		_shot_reach = maxf(_track_xform.origin.distance_to(target), 0.75)
		_scale_to_reach(_shot_reach)
	_shimmer.visible = on
	_shimmer_mat.set_shader_parameter("amount", 1.0 if on else 0.0)
	_face_shimmer()


# ── LAYER 6 — IMPACT PUNCH (reusable; the ceremony may call these alone) ───


## Short, animator-safe camera shake. Uses Camera3D.h_offset / v_offset / fov
## ONLY — it never writes the camera transform, so a ceremony tween driving
## the camera position keeps working underneath it. Restores exactly.
## `amplitude` is in camera-space metres of screen offset at t=0.
func punch_camera(cam: Camera3D, amplitude: float = 0.15,
		duration: float = 0.65, frequency: float = 26.0,
		fov_kick: float = 2.6) -> void:
	if cam == null:
		return
	if not _cam_saved.has(cam.get_instance_id()):
		_cam_saved[cam.get_instance_id()] = {
			"cam": cam,
			"h": cam.h_offset,
			"v": cam.v_offset,
			"fov": cam.fov,
		}
	_shakes.append({
		"cam": cam,
		"t": 0.0,
		"amp": amplitude,
		"dur": maxf(duration, 0.05),
		"freq": frequency,
		"fov": fov_kick,
		"ph": randf() * TAU,
	})


## The ignition shake envelope as a reusable Curve (fast attack, hard decay).
## Sampled 0..1 across the shake duration. Exposed so ceremony code can reuse
## the same feel for other hits, or hand it to an AnimationPlayer.
static func make_shake_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0), 0.0, 40.0)
	c.add_point(Vector2(0.035, 1.0), 0.0, -6.0)
	c.add_point(Vector2(0.22, 0.42))
	c.add_point(Vector2(0.55, 0.13))
	c.add_point(Vector2(1.0, 0.0))
	return c


## Bloom / exposure kick on ignition. NO Light3D: this is the only way the
## fire brightens the hall. Records originals on first touch;
## `restore_environment()` puts every field back exactly.
## `hold` is how long the lift stays up before `_release_exposure` decays it
## (fire() passes the jet duration).
func punch_exposure(we: WorldEnvironment, hold: float = 2.6,
		exposure_mul: float = 1.24, glow_add: float = 0.40,
		ambient_add: float = 0.16, attack: float = 0.07) -> void:
	if we == null or we.environment == null:
		return
	var env := we.environment
	if _env_saved.is_empty():
		_env_saved = {
			"env": env,
			"exposure": env.tonemap_exposure,
			"glow_enabled": env.glow_enabled,
			"glow_intensity": env.glow_intensity,
			"glow_bloom": env.glow_bloom,
			"ambient_source": env.ambient_light_source,
			"ambient_energy": env.ambient_light_energy,
			"ambient_color": env.ambient_light_color,
		}
	var base_exp: float = _env_saved["exposure"]
	var base_glow: float = _env_saved["glow_intensity"]
	var base_amb: float = _env_saved["ambient_energy"]
	# Only touch ambient if the scene already uses a colour ambient — silently
	# switching ambient_light_source would change the whole hall's look.
	var amb_ok: bool = env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR \
		or env.ambient_light_source == Environment.AMBIENT_SOURCE_BG
	if amb_ok:
		env.ambient_light_color = Color(1.0, 0.62, 0.30)

	_fade(func(v: float) -> void: env.tonemap_exposure = v,
		base_exp, base_exp * exposure_mul, attack, 0.0, "exp")
	_fade(func(v: float) -> void: env.glow_intensity = v,
		base_glow, base_glow + glow_add, attack, 0.0, "glow")
	if amb_ok:
		_fade(func(v: float) -> void: env.ambient_light_energy = v,
			base_amb, base_amb + ambient_add, attack, 0.0, "amb")
	# A slow settle back toward base while the jet burns, so the peak reads as
	# the ignition instant rather than as a permanently brighter room.
	# Same "exp" tag: it replaces the attack ramp instead of racing it.
	var rid := _run_id
	_after(attack, func() -> void:
		_fade(func(v: float) -> void: env.tonemap_exposure = v,
			base_exp * exposure_mul,
			base_exp * (1.0 + (exposure_mul - 1.0) * 0.45),
			maxf(hold * 0.6, 0.2), 0.0, "exp"), rid)


## Decay any environment lift back to the recorded originals over `dur`, then
## clear the record. Called by cut(); hard_stop() snaps instead.
func _release_exposure(dur: float) -> void:
	if _env_saved.is_empty():
		return
	var env: Environment = _env_saved["env"]
	if env == null:
		_env_saved.clear()
		return
	var base_exp: float = _env_saved["exposure"]
	var base_glow: float = _env_saved["glow_intensity"]
	var base_amb: float = _env_saved["ambient_energy"]
	_fade(func(v: float) -> void: env.tonemap_exposure = v,
		env.tonemap_exposure, base_exp, dur, 0.0, "exp")
	_fade(func(v: float) -> void: env.glow_intensity = v,
		env.glow_intensity, base_glow, dur, 0.0, "glow")
	_fade(func(v: float) -> void: env.ambient_light_energy = v,
		env.ambient_light_energy, base_amb, dur, 0.0, "amb")
	var rid := _run_id
	_after(dur + 0.05, func() -> void: restore_environment(), rid)


## RESTORE CONTRACT — put the WorldEnvironment back exactly as found.
## Idempotent; safe to call when nothing was ever changed.
func restore_environment() -> void:
	if _env_saved.is_empty():
		return
	var env: Environment = _env_saved.get("env")
	if env != null and is_instance_valid(env):
		env.tonemap_exposure = _env_saved["exposure"]
		env.glow_enabled = _env_saved["glow_enabled"]
		env.glow_intensity = _env_saved["glow_intensity"]
		env.glow_bloom = _env_saved["glow_bloom"]
		env.ambient_light_source = _env_saved["ambient_source"]
		env.ambient_light_energy = _env_saved["ambient_energy"]
		env.ambient_light_color = _env_saved["ambient_color"]
	_env_saved.clear()


## RESTORE CONTRACT — put every shaken camera back exactly as found.
func restore_camera() -> void:
	for key in _cam_saved.keys():
		var rec: Dictionary = _cam_saved[key]
		var cam: Camera3D = rec.get("cam")
		if cam != null and is_instance_valid(cam):
			cam.h_offset = rec["h"]
			cam.v_offset = rec["v"]
			cam.fov = rec["fov"]
	_cam_saved.clear()
	_shakes.clear()


# ── per-frame (wall clock) ─────────────────────────────────────────────────


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_us) / 1_000_000.0
	_last_us = now
	dt = clampf(dt, 0.0, 0.25)          # survive a hitch / breakpoint

	if _track_node != null and is_instance_valid(_track_node):
		_track_xform = _track_node.global_transform
		_apply_aim()

	_advance_fades(dt)
	_advance_pending(dt)
	_advance_shakes(dt)
	_face_shimmer()


func _advance_fades(dt: float) -> void:
	var i := _fades.size() - 1
	while i >= 0:
		var f: Dictionary = _fades[i]
		if f["wait"] > 0.0:
			f["wait"] = f["wait"] - dt
			i -= 1
			continue
		f["t"] = f["t"] + dt
		var u: float = clampf(f["t"] / f["d"], 0.0, 1.0)
		# ease-out: fast attack, soft landing
		var e: float = 1.0 - pow(1.0 - u, 2.0)
		(f["set"] as Callable).call(lerpf(f["a"], f["b"], e))
		if u >= 1.0:
			_fades.remove_at(i)
		i -= 1


func _advance_pending(dt: float) -> void:
	var i := _pending.size() - 1
	while i >= 0:
		var p: Dictionary = _pending[i]
		p["t"] = p["t"] - dt
		if p["t"] <= 0.0:
			_pending.remove_at(i)
			if p["rid"] == _run_id:
				(p["cb"] as Callable).call()
		i -= 1


func _advance_shakes(dt: float) -> void:
	var i := _shakes.size() - 1
	while i >= 0:
		var s: Dictionary = _shakes[i]
		var cam: Camera3D = s["cam"]
		if cam == null or not is_instance_valid(cam):
			_shakes.remove_at(i)
			i -= 1
			continue
		s["t"] = s["t"] + dt
		var u: float = clampf(s["t"] / s["dur"], 0.0, 1.0)
		var env: float = shake_envelope.sample_baked(u)
		var rec: Dictionary = _cam_saved.get(cam.get_instance_id(), {})
		var h0: float = rec.get("h", 0.0)
		var v0: float = rec.get("v", 0.0)
		var f0: float = rec.get("fov", cam.fov)
		var w: float = s["t"] * s["freq"] * TAU
		cam.h_offset = h0 + sin(w + s["ph"]) * s["amp"] * env
		cam.v_offset = v0 + sin(w * 1.37 + s["ph"] * 2.1) * s["amp"] * 0.78 * env
		cam.fov = f0 + s["fov"] * pow(1.0 - u, 3.0)
		if u >= 1.0:
			cam.h_offset = h0
			cam.v_offset = v0
			cam.fov = f0
			_shakes.remove_at(i)
		i -= 1


func _face_shimmer() -> void:
	if _shimmer == null or not _shimmer.visible:
		return
	var cam := _camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var mid := muzzle.global_transform.origin \
		+ (-muzzle.global_transform.basis.z) * (_shot_reach * 0.46) \
		+ Vector3.UP * (_shot_reach * 0.06)
	_shimmer.global_position = mid
	var to_cam := cam.global_transform.origin - mid
	if to_cam.length_squared() < 0.0004:
		return
	var up := Vector3.UP
	if absf(to_cam.normalized().dot(up)) > 0.985:
		up = Vector3.FORWARD
	_shimmer.look_at(cam.global_transform.origin, up)


# ── internals ──────────────────────────────────────────────────────────────


func _after(delay: float, cb: Callable, rid: int = -1) -> void:
	_pending.append({
		"t": maxf(delay, 0.0),
		"cb": cb,
		"rid": _run_id if rid < 0 else rid,
	})


## Wall-clock tween of one float. `tag` makes a fade EXCLUSIVE: adding a
## tagged fade cancels any live fade with the same tag, so a release ramp can
## never be fought by the attack ramp it supersedes (that is how exposure gets
## stuck at a half-restored value).
func _fade(setter: Callable, a: float, b: float, d: float,
		wait: float = 0.0, tag: String = "") -> void:
	if tag != "":
		var i := _fades.size() - 1
		while i >= 0:
			if _fades[i].get("tag", "") == tag:
				_fades.remove_at(i)
			i -= 1
	_fades.append({
		"set": setter, "a": a, "b": b, "tag": tag,
		"d": maxf(d, 0.0001), "t": 0.0, "wait": wait,
	})


## HDR flame colour: scales RGB by `intensity` and sets alpha EXPLICITLY.
## (Color * float in GDScript also scales alpha — doing that to a gradient
## stop silently destroys the ramp's fade-out.)
func _hot(c: Color, a: float = 1.0) -> Color:
	return Color(c.r * intensity, c.g * intensity, c.b * intensity, a)


func _pow_scale() -> float:
	return clampf(_shot_reach / 6.0, 0.35, 2.5)


func _impact(rid: int) -> void:
	if rid != _run_id:
		return
	ground.global_position = Vector3(_target.x, floor_y + 0.02, _target.z)
	var r := clampf(_shot_reach * 0.30, 0.9, 3.2)
	_scale_ground(r)
	_glow.visible = true
	_glow_mat.set_shader_parameter("amount", 0.0)
	_fade(func(v: float) -> void: _glow_mat.set_shader_parameter("amount", v),
		0.0, 1.0, 0.12)
	_ground_flame.emitting = true
	_sparks.emitting = true
	_splash.restart()
	_splash.emitting = true
	_burst_ring(_ground_ring, _ground_ring_mat, 0.34, r * 1.7, 1.3)
	impacted.emit()


func _complete(rid: int) -> void:
	if rid != _run_id:
		return
	for p in _all_emitters():
		if p != null:
			p.emitting = false
	restore_camera()
	restore_environment()
	_active = false
	finished.emit()


func _burst_ring(node: MeshInstance3D, mat: ShaderMaterial, dur: float,
		scale_to: float, energy: float) -> void:
	if node == null:
		return
	node.visible = true
	node.scale = Vector3.ONE * (scale_to * 0.18)
	mat.set_shader_parameter("energy", energy * intensity)
	mat.set_shader_parameter("amount", 1.0)
	mat.set_shader_parameter("radius", 0.22)
	mat.set_shader_parameter("thickness", 0.30)
	var rid := _run_id
	_fade(func(v: float) -> void: node.scale = Vector3.ONE * v,
		scale_to * 0.18, scale_to, dur)
	_fade(func(v: float) -> void: mat.set_shader_parameter("radius", v),
		0.22, 0.86, dur)
	_fade(func(v: float) -> void: mat.set_shader_parameter("thickness", v),
		0.30, 0.06, dur)
	_fade(func(v: float) -> void: mat.set_shader_parameter("amount", v),
		1.0, 0.0, dur)
	_after(dur + 0.02, func() -> void: node.visible = false, rid)


## The over-bright bloom at the lips on the frame the jet lights. Short
## enough (0.16 s) that it reads as a detonation rather than as a lamp.
func _pop_flash() -> void:
	if _flash == null:
		return
	var rid := _run_id
	var s := _pow_scale()
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.35 * s
	_fade(func(v: float) -> void: _flash.scale = Vector3.ONE * v,
		0.28 * s, 1.05 * s, 0.16, 0.0, "flash_s")
	_fade(func(v: float) -> void:
		_flash_mat.albedo_color = Color(2.4 * intensity, 1.5 * intensity,
			0.70 * intensity, v),
		0.9, 0.0, 0.16, 0.0, "flash_a")
	_after(0.18, func() -> void: _flash.visible = false, rid)


func _set_stem_length(l: float) -> void:
	_stem_mesh.height = l
	_stem_mat.set_shader_parameter("stem_height", l)
	_stem.position = Vector3(0.0, 0.0, -l * 0.5)


func _apply_aim() -> void:
	if muzzle == null:
		return
	muzzle.global_position = _track_xform.origin
	var dir := _target - _track_xform.origin
	if dir.length_squared() < 0.0004:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.985:
		up = Vector3.FORWARD
	muzzle.look_at(_track_xform.origin + dir, up)


func _all_emitters() -> Array:
	return [_core, _blast, _body, _jet_embers, _smoke, _splash,
		_ground_flame, _ground_smoke, _sparks, _ash]


# ── build ──────────────────────────────────────────────────────────────────


func _kit_dir() -> String:
	var s := get_script() as Script
	if s == null or s.resource_path.is_empty():
		return "res://"
	return s.resource_path.get_base_dir()


func _build() -> void:
	_built = true
	shake_envelope = make_shake_curve()
	shake_envelope.bake()
	_noise_tex = _make_noise()
	# Low-centre-alpha puffs MERGE into a mass; high-alpha puffs read as a bag
	# of circles. This single gradient is most of the difference between
	# "flame" and "visible sprites".
	_puff_tex = _radial([[0.0, 0.52], [0.32, 0.34], [0.68, 0.11], [1.0, 0.0]])
	_core_tex = _radial([[0.0, 1.0], [0.13, 0.72], [0.48, 0.20], [1.0, 0.0]])
	_spark_tex = _radial([[0.0, 1.0], [0.36, 0.80], [1.0, 0.0]])

	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	add_child(muzzle)
	ground = Node3D.new()
	ground.name = "Ground"
	ground.top_level = true          # stays where the fire LANDS, not on the head
	add_child(ground)

	_build_core_jet()
	_build_flame_body()
	_build_embers_and_smoke()
	_build_ground()
	_build_shimmer()
	_scale_to_reach(reach)


# -- LAYER 1: CORE JET ------------------------------------------------------


func _build_core_jet() -> void:
	# 1a. the pressure stem (mesh + shader) — the "forced out" read.
	_stem_mesh = CylinderMesh.new()
	# ~1:5 flare. A 1:13 needle reads as a laser, not as pressurised fire.
	_stem_mesh.top_radius = 1.05          # far end, wide
	_stem_mesh.bottom_radius = 0.13       # the lips, tight
	_stem_mesh.height = reach
	_stem_mesh.radial_segments = 18
	_stem_mesh.rings = 1
	_stem_mesh.cap_top = false
	_stem_mesh.cap_bottom = false

	_stem_mat = ShaderMaterial.new()
	_stem_mat.shader = JET_STEM_SHADER
	_stem_mat.set_shader_parameter("noise_tex", _noise_tex)
	_stem_mat.set_shader_parameter("energy", 1.5 * intensity)
	_stem_mat.set_shader_parameter("tip_bite", 1.7)
	# Low density_power = the whole cross-section glows (a volume of fire).
	# High values light only the centreline, which is what makes it a laser.
	_stem_mat.set_shader_parameter("density_power", 1.1)
	_stem_mat.set_shader_parameter("throat", 0.05)
	_stem_mat.set_shader_parameter("amount", 0.0)
	_stem_mat.set_shader_parameter("stem_height", reach)
	_stem_mat.set_shader_parameter("core_color", Color(1.0, 0.97, 0.88))
	_stem_mat.set_shader_parameter("mid_color", Color(1.0, 0.50, 0.10))
	_stem_mat.set_shader_parameter("tail_color", Color(0.90, 0.14, 0.02))
	_stem_mesh.material = _stem_mat

	_stem = MeshInstance3D.new()
	_stem.name = "JetStem"
	_stem.mesh = _stem_mesh
	_stem.rotation.x = -PI * 0.5          # cylinder +Y  ->  muzzle forward (-Z)
	_stem.position = Vector3(0.0, 0.0, -reach * 0.5)
	_stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stem.visible = false
	muzzle.add_child(_stem)

	# 1b. the streaked particles riding the stem.
	_core = _particles("CoreJet", 340, 0.46)
	_core.explosiveness = 0.0
	_core.randomness = 0.25
	_core.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := _core.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 3.2                        # NARROW — this is a jet, not a puff
	pm.initial_velocity_min = CORE_V.x
	pm.initial_velocity_max = CORE_V.y
	pm.damping_min = 5.0
	pm.damping_max = 11.0                  # the taper: it runs out of pressure
	pm.gravity = Vector3(0.0, 1.1, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.045
	pm.scale_min = 0.75
	pm.scale_max = 1.35
	pm.scale_curve = _curve([[0.0, 0.16], [0.10, 0.42], [0.45, 1.0],
		[0.78, 1.15], [1.0, 0.55]])
	pm.color_ramp = _ramp([
		[0.0, _hot(WHITE_HOT, 0.85)],
		[0.10, _hot(YELLOW_HOT, 0.76)],
		[0.30, _hot(ORANGE, 0.56)],
		[0.62, _hot(DEEP_RED, 0.28)],
		[1.0, _hot(EMBER_RED, 0.0)],
	])
	_core.draw_pass_1 = _quad(Vector2(0.26, 0.92), _core_tex, false)

	# 1c. IGNITION BLAST FRONT — a single hard shove of flame on frame one.
	# Without this the effect "switches on"; with it, it detonates.
	_blast = _particles("IgnitionBlast", 200, 0.55)
	_blast.one_shot = true
	_blast.explosiveness = 1.0
	_blast.randomness = 0.55
	# Streak the blast along its velocity: on the ignition frame the particles
	# have barely travelled, so only motion-stretched tongues read as "thrown".
	# Un-stretched they read as a cauliflower of round puffs.
	_blast.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var bm := _blast.process_material as ParticleProcessMaterial
	bm.direction = Vector3(0.0, 0.0, -1.0)
	bm.spread = 11.0                       # a lance, not a shuttlecock
	bm.initial_velocity_min = BLAST_V.x
	bm.initial_velocity_max = BLAST_V.y
	bm.damping_min = 6.5
	bm.damping_max = 13.0                  # stall distance ~1.7-6 m
	bm.gravity = Vector3(0.0, 2.0, 0.0)
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bm.emission_sphere_radius = 0.07
	bm.angle_min = -180.0
	bm.angle_max = 180.0
	bm.turbulence_enabled = true
	bm.turbulence_noise_strength = 2.1
	bm.turbulence_noise_scale = 2.2
	bm.turbulence_influence_max = 0.55
	bm.scale_min = 0.5
	bm.scale_max = 1.1
	bm.scale_curve = _curve([[0.0, 0.55], [0.3, 1.05], [1.0, 1.3]])
	bm.color_ramp = _ramp([
		[0.0, _hot(WHITE_HOT, 0.24)],
		[0.06, _hot(YELLOW_HOT, 0.34)],
		[0.20, _hot(ORANGE, 0.46)],
		[0.50, _hot(DEEP_RED, 0.20)],
		# Near-zero by 0.78: the survivors are big stretched quads hanging in
		# open air, and they read as red smears painted on the back wall.
		[0.78, Color(0.30, 0.03, 0.005, 0.05)],
		[1.0, Color(0.15, 0.02, 0.0, 0.0)],
	])
	_blast.draw_pass_1 = _quad(Vector2(0.55, 1.95), _puff_tex, false)


# -- LAYER 2: ROLLING FLAME BODY -------------------------------------------


func _build_flame_body() -> void:
	_body = _particles("FlameBody", 820, 1.15)
	_body.randomness = 0.45
	_body.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# Velocity-aligned, elongated quads read as FLAME TONGUES; round
	# billboards read as a cloud of dots no matter how many you add. As the
	# billows slow and buoyancy takes over, their velocity turns upward and
	# the tongues stand up on their own — that IS the "curls upward at the far
	# end" beat, for free.
	_body.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := _body.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = torrent_spread
	# Stall distance is roughly velocity/damping. Keep that band wide enough
	# that the mass spreads ALONG the run — too much damping and the whole
	# body piles into a ball at the lips, which is the classic "dragon burps"
	# failure.
	pm.initial_velocity_min = BODY_V.x
	pm.initial_velocity_max = BODY_V.y
	pm.damping_min = 3.4
	pm.damping_max = 5.4
	pm.gravity = Vector3(0.0, 1.5, 0.0)    # buoyancy -> the far end curls UP
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.10
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.9
	pm.turbulence_noise_scale = 1.7
	pm.turbulence_noise_speed = Vector3(0.6, 0.35, 0.6)
	# Keep influence LOW. High turbulence flings individual quads clear of the
	# stream, and a lone velocity-aligned quad in open air is a petal, not
	# flame. Turbulence should agitate the mass, not disperse it.
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.30
	pm.scale_min = 0.5
	pm.scale_max = 1.45
	# Barely grows late. A velocity-aligned quad that gets big AND slow turns
	# into a drifting petal — the single ugliest artefact in this whole kit.
	pm.scale_curve = _curve([[0.0, 0.14], [0.20, 0.58], [0.60, 1.0], [1.0, 1.12]])
	# Alphas stay LOW on purpose: the torrent's brightness comes from many
	# overlapping quads, which is what produces turbulent structure instead of
	# a bag of glowing circles.
	# Cooling happens EARLY in the lifetime on purpose. The fast particles
	# cover most of the reach in the first third of their life, so a ramp that
	# cools late leaves the whole torrent yellow-white with no deep-red tail.
	pm.color_ramp = _ramp([
		[0.0, _hot(WHITE_HOT, 0.30)],
		[0.06, _hot(YELLOW_HOT, 0.42)],
		[0.20, _hot(ORANGE, 0.52)],
		[0.42, _hot(DEEP_RED, 0.11)],
		# Hard fade by 0.58: a late-life particle is big, isolated and slow,
		# and at any visible alpha it reads as a drifting petal rather than
		# as flame. Kill it while it is still inside the mass.
		[0.54, Color(0.42, 0.05, 0.01, 0.04)],
		[1.0, Color(0.12, 0.02, 0.0, 0.0)],
	])
	_body.draw_pass_1 = _quad(Vector2(0.52, 1.28), _puff_tex, false)


# -- LAYER 3: EMBERS + ASH (muzzle half; ground half in _build_ground) ------


func _build_embers_and_smoke() -> void:
	_jet_embers = _particles("JetEmbers", 260, 3.0)
	_jet_embers.randomness = 0.6
	_jet_embers.transform_align = \
		GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := _jet_embers.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 17.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 26.0
	pm.damping_min = 2.0
	pm.damping_max = 5.5                   # drag
	pm.gravity = Vector3(0.0, -6.2, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.1
	pm.turbulence_noise_scale = 3.4
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.35
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.scale_curve = _curve([[0.0, 1.0], [0.6, 0.72], [1.0, 0.15]])
	pm.alpha_curve = _curve([[0.0, 1.0], [0.18, 0.72], [0.28, 1.0],
		[0.46, 0.55], [0.6, 0.95], [0.82, 0.4], [1.0, 0.0]])   # flicker
	pm.color_ramp = _ramp([
		[0.0, _hot(WHITE_HOT, 0.9)],
		[0.12, _hot(YELLOW_HOT, 0.95)],
		[0.45, _hot(ORANGE, 0.9)],
		[0.8, _hot(EMBER_RED, 0.75)],
		[1.0, Color(0.35, 0.03, 0.0, 0.0)],
	])
	_jet_embers.draw_pass_1 = _quad(Vector2(0.038, 0.22), _spark_tex, false)

	# dark smoke curling off the rolling body (alpha, not additive)
	_smoke = _particles("JetSmoke", 210, 3.4, false)
	_smoke.randomness = 0.5
	_smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var sm := _smoke.process_material as ParticleProcessMaterial
	sm.direction = Vector3(0.0, 0.15, -1.0).normalized()
	sm.spread = 22.0
	sm.initial_velocity_min = 8.0
	sm.initial_velocity_max = 18.0
	sm.damping_min = 1.3
	sm.damping_max = 2.8                   # must TRAIL the torrent, not sit
	sm.gravity = Vector3(0.0, 1.5, 0.0)
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.angular_velocity_min = -30.0
	sm.angular_velocity_max = 30.0
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.4
	sm.turbulence_noise_scale = 1.3
	sm.turbulence_influence_min = 0.2
	sm.turbulence_influence_max = 0.7
	sm.scale_min = 0.8
	sm.scale_max = 1.5
	sm.scale_curve = _curve([[0.0, 0.35], [0.5, 1.0], [1.0, 1.35]])
	sm.color_ramp = _ramp([
		[0.0, Color(SMOKE_GREY.r, SMOKE_GREY.g, SMOKE_GREY.b, 0.0)],
		[0.22, Color(0.17, 0.13, 0.11, 0.20)],
		[0.55, Color(SMOKE_GREY.r, SMOKE_GREY.g, SMOKE_GREY.b, 0.16)],
		[1.0, Color(0.09, 0.086, 0.082, 0.0)],
	], false)
	_smoke.draw_pass_1 = _quad(Vector2(1.2, 1.2), _puff_tex, true, false)


# -- LAYER 4: GROUND FIRE (+ the long ember tail and the ashfall) -----------


func _build_ground() -> void:
	# the no-Light3D firelight pool
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GROUND_GLOW_SHADER
	_glow_mat.set_shader_parameter("noise_tex", _noise_tex)
	_glow_mat.set_shader_parameter("energy", 1.05 * intensity)
	_glow_mat.set_shader_parameter("hot_core", 0.10)
	_glow_mat.set_shader_parameter("amount", 0.0)
	var gq := QuadMesh.new()
	gq.size = Vector2(1.0, 1.0)
	gq.material = _glow_mat
	_glow = MeshInstance3D.new()
	_glow.name = "GroundGlow"
	_glow.mesh = gq
	_glow.rotation.x = -PI * 0.5           # lie flat on the stone
	_glow.position.y = 0.015
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	ground.add_child(_glow)

	_ground_ring_mat = ShaderMaterial.new()
	_ground_ring_mat.shader = SHOCK_RING_SHADER
	_ground_ring_mat.set_shader_parameter("ring_color", Color(1.0, 0.62, 0.24))
	var rq := QuadMesh.new()
	rq.size = Vector2(1.0, 1.0)
	rq.material = _ground_ring_mat
	_ground_ring = MeshInstance3D.new()
	_ground_ring.name = "GroundRing"
	_ground_ring.mesh = rq
	_ground_ring.rotation.x = -PI * 0.5
	_ground_ring.position.y = 0.05
	_ground_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_ring.visible = false
	ground.add_child(_ground_ring)

	# the pool of flame
	_ground_flame = _particles("GroundFlame", 380, 1.15, true, ground)
	_ground_flame.randomness = 0.5
	# Same trick: upward-aligned tongues licking off the stone.
	_ground_flame.transform_align = \
		GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var gf := _ground_flame.process_material as ParticleProcessMaterial
	gf.direction = Vector3(0.0, 1.0, 0.0)
	gf.spread = 24.0
	gf.initial_velocity_min = 1.6
	gf.initial_velocity_max = 5.2
	gf.gravity = Vector3(0.0, 1.4, 0.0)
	gf.damping_min = 1.0
	gf.damping_max = 3.0
	gf.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	gf.emission_box_extents = Vector3(1.0, 0.05, 1.0)
	gf.turbulence_enabled = true
	gf.turbulence_noise_strength = 1.3
	gf.turbulence_noise_scale = 2.0
	gf.turbulence_influence_max = 0.5
	gf.scale_min = 0.45
	gf.scale_max = 1.15
	gf.scale_curve = _curve([[0.0, 0.30], [0.4, 1.0], [1.0, 0.55]])
	gf.color_ramp = _ramp([
		[0.0, _hot(YELLOW_HOT, 0.55)],
		[0.25, _hot(ORANGE, 0.50)],
		[0.65, _hot(DEEP_RED, 0.32)],
		[1.0, Color(0.3, 0.03, 0.0, 0.0)],
	])
	_ground_flame.draw_pass_1 = _quad(Vector2(0.46, 1.15), _puff_tex, false)

	# the impact splash — one-shot radial burst along the stone
	_splash = _particles("ImpactSplash", 220, 0.85, true, ground)
	_splash.one_shot = true
	_splash.explosiveness = 1.0
	_splash.emitting = false
	_splash.transform_align = \
		GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var sp := _splash.process_material as ParticleProcessMaterial
	sp.direction = Vector3(0.0, 0.35, 0.0)
	sp.spread = 88.0
	sp.flatness = 0.55                     # hugs the floor
	sp.initial_velocity_min = 7.0
	sp.initial_velocity_max = 17.0
	sp.damping_min = 8.0
	sp.damping_max = 16.0
	sp.gravity = Vector3(0.0, 1.0, 0.0)
	sp.scale_min = 0.6
	sp.scale_max = 1.6
	sp.scale_curve = _curve([[0.0, 0.4], [0.35, 1.0], [1.0, 0.35]])
	sp.color_ramp = _ramp([
		[0.0, _hot(YELLOW_HOT, 0.60)],
		[0.18, _hot(YELLOW_HOT, 0.52)],
		[0.5, _hot(ORANGE, 0.42)],
		[1.0, Color(0.4, 0.04, 0.0, 0.0)],
	])
	_splash.draw_pass_1 = _quad(Vector2(0.34, 0.78), _core_tex, false)

	# LAYER 3 (ground half): the sparks that OUTLIVE the jet
	_sparks = _particles("Sparks", 320, ember_tail, true, ground)
	_sparks.randomness = 0.7
	_sparks.transform_align = \
		GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var sk := _sparks.process_material as ParticleProcessMaterial
	sk.direction = Vector3(0.0, 1.0, 0.0)
	sk.spread = 52.0
	sk.initial_velocity_min = 3.5
	sk.initial_velocity_max = 12.0
	sk.damping_min = 1.2
	sk.damping_max = 3.4                   # drag
	sk.gravity = Vector3(0.0, -5.4, 0.0)   # and gravity
	sk.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sk.emission_box_extents = Vector3(0.9, 0.1, 0.9)
	sk.turbulence_enabled = true
	sk.turbulence_noise_strength = 1.5
	sk.turbulence_noise_scale = 2.8
	sk.turbulence_influence_min = 0.1
	sk.turbulence_influence_max = 0.45
	sk.scale_min = 0.45
	sk.scale_max = 1.25
	sk.scale_curve = _curve([[0.0, 1.0], [0.7, 0.8], [1.0, 0.1]])
	sk.alpha_curve = _curve([[0.0, 1.0], [0.12, 0.55], [0.2, 1.0],
		[0.38, 0.42], [0.5, 0.9], [0.68, 0.3], [0.85, 0.6], [1.0, 0.0]])
	sk.color_ramp = _ramp([
		[0.0, _hot(YELLOW_HOT, 0.95)],
		[0.3, _hot(ORANGE, 0.9)],
		[0.7, _hot(EMBER_RED, 0.8)],
		[1.0, Color(0.25, 0.02, 0.0, 0.0)],
	])
	_sparks.draw_pass_1 = _quad(Vector2(0.032, 0.17), _spark_tex, false)

	# ground smoke — what the pool becomes
	_ground_smoke = _particles("GroundSmoke", 110, 3.6, false, ground)
	_ground_smoke.randomness = 0.5
	_ground_smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var gs := _ground_smoke.process_material as ParticleProcessMaterial
	gs.direction = Vector3(0.0, 1.0, 0.0)
	gs.spread = 30.0
	gs.initial_velocity_min = 0.8
	gs.initial_velocity_max = 2.6
	gs.gravity = Vector3(0.0, 0.75, 0.0)
	gs.damping_min = 0.4
	gs.damping_max = 1.4
	gs.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	gs.emission_box_extents = Vector3(1.0, 0.05, 1.0)
	gs.angle_min = -180.0
	gs.angle_max = 180.0
	gs.angular_velocity_min = -18.0
	gs.angular_velocity_max = 18.0
	gs.turbulence_enabled = true
	gs.turbulence_noise_strength = 1.0
	gs.turbulence_noise_scale = 1.2
	gs.turbulence_influence_max = 0.6
	gs.scale_min = 0.9
	gs.scale_max = 2.2
	gs.scale_curve = _curve([[0.0, 0.4], [0.5, 1.0], [1.0, 1.9]])
	gs.color_ramp = _ramp([
		[0.0, Color(0.26, 0.14, 0.08, 0.0)],
		[0.12, Color(0.26, 0.16, 0.11, 0.32)],
		[0.5, Color(SMOKE_GREY.r, SMOKE_GREY.g, SMOKE_GREY.b, 0.24)],
		[1.0, Color(0.09, 0.09, 0.09, 0.0)],
	], false)
	_ground_smoke.draw_pass_1 = _quad(Vector2(1.7, 1.7), _puff_tex, true, false)

	# LAYER 3 (ash): slow grey fall over the aftermath
	_ash = _particles("Ashfall", 420, ash_tail, false, ground)
	_ash.position.y = 1.9          # ash is BORN in the smoke column, then falls
	_ash.randomness = 0.8
	_ash.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var ah := _ash.process_material as ParticleProcessMaterial
	ah.direction = Vector3(0.0, 1.0, 0.0)
	ah.spread = 180.0
	ah.initial_velocity_min = 0.3
	ah.initial_velocity_max = 2.2
	ah.gravity = Vector3(0.0, -0.42, 0.0)  # DOWN, slowly
	ah.damping_min = 0.8
	ah.damping_max = 2.0
	ah.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ah.emission_box_extents = Vector3(1.6, 1.4, 1.6)
	ah.angle_min = -180.0
	ah.angle_max = 180.0
	ah.angular_velocity_min = -40.0
	ah.angular_velocity_max = 40.0
	ah.turbulence_enabled = true
	ah.turbulence_noise_strength = 0.9
	ah.turbulence_noise_scale = 2.2
	ah.turbulence_influence_min = 0.15
	ah.turbulence_influence_max = 0.55
	ah.scale_min = 0.35
	ah.scale_max = 1.0
	ah.scale_curve = _curve([[0.0, 0.7], [0.3, 1.0], [1.0, 0.8]])
	ah.color_ramp = _ramp([
		[0.0, Color(0.55, 0.36, 0.22, 0.0)],
		[0.08, Color(0.52, 0.34, 0.21, 0.75)],
		[0.35, Color(ASH_GREY.r, ASH_GREY.g, ASH_GREY.b, 0.62)],
		[0.8, Color(0.28, 0.27, 0.26, 0.34)],
		[1.0, Color(0.22, 0.21, 0.20, 0.0)],
	], false)
	_ash.draw_pass_1 = _quad(Vector2(0.13, 0.13), _spark_tex, true, false)

	# muzzle shock ring lives on the muzzle, built here for material reuse
	_muzzle_ring_mat = ShaderMaterial.new()
	_muzzle_ring_mat.shader = SHOCK_RING_SHADER
	_muzzle_ring_mat.set_shader_parameter("ring_color", Color(1.0, 0.80, 0.48))
	_muzzle_ring_mat.set_shader_parameter("inner_glow", 0.45)
	var mq := QuadMesh.new()
	mq.size = Vector2(1.0, 1.0)
	mq.material = _muzzle_ring_mat
	_muzzle_ring = MeshInstance3D.new()
	_muzzle_ring.name = "MuzzleRing"
	_muzzle_ring.mesh = mq
	_muzzle_ring.position = Vector3(0.0, 0.0, -0.18)
	_muzzle_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_ring.visible = false
	muzzle.add_child(_muzzle_ring)

	# muzzle flash — a camera-facing bloom at the lips on the ignition frame
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_texture = _core_tex
	_flash_mat.albedo_color = Color(3.1, 2.0, 0.95, 1.0)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.billboard_keep_scale = true
	_flash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flash_mat.disable_receive_shadows = true
	_flash_mat.disable_ambient_light = true
	var fq := QuadMesh.new()
	fq.size = Vector2(1.0, 1.0)
	fq.material = _flash_mat
	_flash = MeshInstance3D.new()
	_flash.name = "MuzzleFlash"
	_flash.mesh = fq
	_flash.position = Vector3(0.0, 0.0, -0.12)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	muzzle.add_child(_flash)


# -- LAYER 5: HEAT SHIMMER --------------------------------------------------


func _build_shimmer() -> void:
	if not heat_shimmer_enabled:
		return
	_shimmer_mat = ShaderMaterial.new()
	_shimmer_mat.shader = HEAT_SHIMMER_SHADER
	_shimmer_mat.set_shader_parameter("noise_tex", _noise_tex)
	_shimmer_mat.set_shader_parameter("amount", 0.0)
	# 0.055 of SCREEN_UV is 5.5% of the frame — that is a liquid smear, not
	# heat. Real heat haze is a couple of pixels.
	_shimmer_mat.set_shader_parameter("strength", 0.017)
	_shimmer_mat.set_shader_parameter("edge_softness", 0.92)
	_shimmer_mat.set_shader_parameter("tiling", 3.1)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _shimmer_mat
	_shimmer = MeshInstance3D.new()
	_shimmer.name = "HeatShimmer"
	_shimmer.mesh = q
	_shimmer.top_level = true            # positioned in world space each frame
	_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shimmer.visible = false
	# Draw EARLY (treated as far away). The screen-texture copy happens when
	# the first material sampling it renders; if the shimmer draws after the
	# flame it samples a copy taken BEFORE the flame existed and paints the
	# bare wall straight over the torrent — a wall-textured hole punched
	# through the fire. Negative sorting_offset puts it behind. Learned the
	# hard way; do not "fix" this to a positive value.
	_shimmer.sorting_offset = -4.0
	add_child(_shimmer)


# -- scaling -----------------------------------------------------------------


func _scale_to_reach(r: float) -> void:
	_shot_reach = r
	var s := clampf(r / 6.0, 0.3, 3.0)
	if _stem_mesh != null:
		_stem_mesh.top_radius = 0.72 * s
		_stem_mesh.bottom_radius = 0.13 * maxf(s * 0.75, 0.35)
		_set_stem_length(r * STEM_FRACTION)
	var vs := clampf(s, 0.5, 2.0)
	if _core != null:
		var pm := _core.process_material as ParticleProcessMaterial
		pm.initial_velocity_min = CORE_V.x * vs
		pm.initial_velocity_max = CORE_V.y * vs
	if _body != null:
		var bm := _body.process_material as ParticleProcessMaterial
		bm.initial_velocity_min = BODY_V.x * vs
		bm.initial_velocity_max = BODY_V.y * vs
	if _blast != null:
		var zm := _blast.process_material as ParticleProcessMaterial
		zm.initial_velocity_min = BLAST_V.x * vs
		zm.initial_velocity_max = BLAST_V.y * vs
	if _shimmer != null:
		_shimmer.scale = Vector3(r * 1.15, r * 0.78, 1.0)


func _scale_ground(radius: float) -> void:
	if _glow != null:
		_glow.scale = Vector3(radius * 4.2, radius * 4.2, 1.0)
	if _ground_ring != null:
		_ground_ring.scale = Vector3.ONE * radius * 2.0
	for p in [_ground_flame, _ground_smoke, _sparks, _splash]:
		if p == null:
			continue
		var pm := p.process_material as ParticleProcessMaterial
		if pm.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			var e := pm.emission_box_extents
			pm.emission_box_extents = Vector3(radius, e.y, radius)
	if _ash != null:
		# Ash falls over a wider area than the pool — but not SO wide that the
		# same particle budget spreads to invisible confetti.
		var am := _ash.process_material as ParticleProcessMaterial
		am.emission_box_extents = Vector3(radius * 1.15, 1.5, radius * 1.15)


# -- factories ---------------------------------------------------------------


func _particles(nm: String, amount: int, life: float,
		additive: bool = true, parent: Node3D = null) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false                # world space: the trail stays put
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Generous AABB — an under-sized visibility_aabb silently culls the whole
	# torrent the moment the camera looks slightly away. Classic trap.
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	p.process_material = ParticleProcessMaterial.new()
	p.set_meta("additive", additive)
	if parent == null:
		muzzle.add_child(p)
	else:
		parent.add_child(p)
	return p


func _quad(size: Vector2, tex: Texture2D, billboard: bool,
		additive: bool = true) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive \
		else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true   # HDR particle colour -> ALBEDO
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if billboard \
		else BaseMaterial3D.BILLBOARD_DISABLED
	m.billboard_keep_scale = true
	q.material = m
	return q


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 2.0
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _ramp(stops: Array, hdr: bool = true) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = hdr                       # WITHOUT THIS every colour clamps to 1
	t.width = 128
	return t


func _radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(Color(1.0, 1.0, 1.0, s[1]))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _make_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 0x0D24C0            # seeded: deterministic across runs
	n.frequency = 0.021
	n.fractal_octaves = 4
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.52
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = false
	t.generate_mipmaps = false
	return t
