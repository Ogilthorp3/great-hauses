extends Node3D
## TRIAL BY FIRE — THE DRAGON IS THE CLOCK.
##
## The best reuse in the whole design, and the one that makes this mode belong
## to THIS game rather than being Bomberman with a chess skin. Every arena
## shooter needs a sudden-death timer and almost all of them draw a number on
## the screen. This one already had a dragon asleep on the stone beside the
## board, watching a war it was not invited to. So the timer IS the dragon: past
## the limit it stirs, hauls itself up, roars, and starts torching the outer
## ring inward — the same shrinking arena the genre invented, delivered by the
## animal that was in the room the whole time.
##
## WHAT IS REUSED, AND FROM WHERE:
##   * DragonRig (src/cinematics/dragon_rig.gd) — the rig, the SLUMBER coil, the
##     throat-coal emissive, the mouth bone attachment, and the emitter factory.
##   * The wake beat — rest -> stir -> rise -> roar — is dragon_spectator.gd's
##     arc, at a quarter of its length: the ceremony can spend 2.65 s standing
##     up because nothing else is on screen, and an arena cannot.
##   * DracarysVFX (assets/vfx/dracarys.gd) — the torrent itself, mounted on
##     rig.mouth_node() and aimed with aim()/start(), exactly the way the
##     ashfall mounts it. Retuned for board scale (reach 4.2 like the ceremony,
##     intensity trimmed) and fired in half-second bursts, one per pair of
##     squares it takes, instead of one long sweep.
##
## NO Light3D on any path. The kit creates none; this file creates none; the
## roar's kindling coals are emission on the rig's own materials.
##
## THE CAMERA/EXPOSURE CONTRACT. dracarys.gd lifts the WorldEnvironment exposure
## and shakes the bound camera, and restores both in cut()/hard_stop()/
## _exit_tree/PREDELETE. `auto_punch` is left OFF here: a fire that re-exposes
## the whole hall thirty times in a row is a strobe, not a threat.

const RigScript := preload("res://src/cinematics/dragon_rig.gd")
const DracarysScript := preload("res://assets/vfx/dracarys.gd")

## Where it sleeps: the east aisle, clear of the board and of the camera's orbit
## ring — the same reasoning (and very nearly the same spot) dragon_spectator
## worked out against the real gameplay camera, kept so the two modes stage the
## beast identically.
@export var rest_position := Vector3(6.6, -0.3, 0.6)
@export var rest_yaw := -PI * 0.30
@export var rest_idle_speed := 0.30
@export var rest_ember := 0.40
@export var woke_ember := 2.60
@export var rig_scale := 1.15
@export var awake_scale := 1.35
## The wake, in wall seconds. A quarter of the ceremony's: this one has to be
## over before the first squares burn.
@export var stir_wall := 0.35
@export var rise_wall := 0.45
@export var roar_wall := 0.75
## The perch it torches from. IN THE EAST AISLE, BESIDE the board — the same
## aisle it sleeps in, just airborne.
##
## The first cut put it over the FAR END at (0, 5.4, 7.4), which is where a
## dragon "should" be and which is off the top of the screen: the arena camera
## is raked 51 degrees down, so anything past the board's far rank projects
## above the frame, and the shot named `05_wyrm_wakes` came back with no wyrm in
## it. A clock you cannot see is not a clock. Beside the board it stays in frame
## the whole time, it RISES on screen out of the exact spot it was sleeping in
## (which is what sells the wake), and the jet crosses the arena sideways where
## the player can watch it travel instead of arriving down the camera's throat.
@export var hunt_position := Vector3(6.2, 2.6, 0.9)
@export var burst_sec := 0.55

signal woke

var rig: DragonRig = null
var _fx: Node3D = null
var _slumber = null
var _awake := false
var _waking := false
var _t := 0.0


func _ready() -> void:
	rig = RigScript.spawn(self, "TrialWyrm", Vector3.ZERO, 0.0, rig_scale)
	position = rest_position
	rotation.y = rest_yaw
	_slumber = rig.attach_slumber(RigScript.slumber_default(), 0.05, 0.55)
	_set_slumber(1.0)
	rig.play_loop("Perch_Idle", rest_idle_speed)
	if rig.anim != null:
		rig.anim.seek(randf() * rig.clip_length("Perch_Idle"))
	rig.set_ember_energy(rest_ember)


func is_awake() -> bool:
	return _awake


func _process(delta: float) -> void:
	_t += delta
	# THE COUCH: the coil folds the legs, so the rig sinks by exactly the height
	# the toe claws gained and the beast stays ON the stone. DragonRig exports
	# the constant for precisely this. (Same line dragon_spectator runs; without
	# it a sleeping wyrm hovers.)
	if rig != null and is_instance_valid(rig):
		rig.position.y = -RigScript.SLUMBER_ROOT_DROP * rig.scale.x * _weight()
	if _awake and not _waking:
		# a slow menace-bob on the hunting perch
		position = hunt_position + Vector3.UP * (sin(_t * 1.1) * 0.16)


## THE WAKE. Awaitable, but the arena does not await it: the ring starts eating
## on its own schedule and the wyrm catches up, which is better than freezing
## the game for a cutscene while two kings are mid-chase.
func wake() -> void:
	if _awake or _waking:
		return
	_waking = true
	woke.emit()
	# I. THE STIR — the head comes off the stone and the coals kindle.
	var home := position
	await _lerp(stir_wall, func(u: float) -> void:
		_set_slumber(1.0 - _ease(u))
		if rig != null and is_instance_valid(rig):
			rig.set_ember_energy(lerpf(rest_ember, woke_ember, u)))
	if not is_instance_valid(self):
		return
	# II. THE RISE — `Land_Settle` played BACKWARDS is a beast standing up. The
	# clip marks are dragon_spectator's, measured there: before ~1.6 s the clip
	# is airborne and a "rise" whose last frames dangle reads as a puppet.
	var manual: bool = rig.play_manual("Land_Settle")
	await _lerp(rise_wall, func(u: float) -> void:
		if manual and rig != null and is_instance_valid(rig):
			rig.seek_clip(lerpf(2.46, 1.62, _ease(u)))
		position = home + Vector3.UP * (0.14 * u))
	if not is_instance_valid(self):
		return
	# III. THE ROAR — on the ground, before the wings. Separate phases, so the
	# sound always lands before the flight.
	rig.play_once("Roar", 1.0, 0.2)
	await _lerp(roar_wall, func(u: float) -> void:
		position = home + Vector3.UP * (0.12 * sin(u * PI)))
	if not is_instance_valid(self):
		return
	# IV. THE CLIMB to the hunting perch.
	rig.play_loop("Fast_Flying", 1.1, 0.3)
	var from := position
	var from_yaw := rotation.y
	await _lerp(0.9, func(u: float) -> void:
		var e := _ease(u)
		position = from.lerp(hunt_position, e) + Vector3.UP * sin(u * PI) * 0.7
		rotation.y = lerp_angle(from_yaw, PI, e)
		if rig != null and is_instance_valid(rig):
			rig.scale = Vector3.ONE * lerpf(rig_scale, awake_scale, e))
	if not is_instance_valid(self):
		return
	rig.play_loop("Flying_Idle", 0.7, 0.4)
	_set_slumber(0.0)
	_awake = true
	_waking = false


## Torch a square: turn the head onto it and fire a short burst of the torrent.
## Called once per closing-ring step; the kit's own tail keeps the stone
## smoking long after the jet cuts.
func torch(world: Vector3) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	# Face it even mid-wake — a wyrm that torches a square without looking at it
	# is a sprinkler.
	var d := world - global_position
	rotation.y = atan2(d.x, d.z)
	if not _awake:
		return
	_ensure_fx()
	if _fx == null:
		return
	var mouth := rig.mouth_node()
	if mouth == null:
		return
	rig.play_once("Headbutt", 1.5, 0.12)
	_fx.start(mouth, world, burst_sec)


func _ensure_fx() -> void:
	if _fx != null and is_instance_valid(_fx):
		_bind()
		return
	if rig == null or rig.mouth_node() == null:
		return
	_fx = DracarysScript.new()
	_fx.name = "WyrmTorrent"
	# ── TUNE BEFORE add_child: the kit bakes all of this into shader uniforms
	# and gradients inside _build(), which runs from its own _ready(). The
	# ashfall shipped for a day with an untuned fire for exactly this reason —
	# every assignment sat below add_child and never reached the flame.
	_fx.reach = 5.6                 # perch to board, not the kit's 9 m demo stage
	_fx.torrent_spread = 8.0
	_fx.ember_tail = 2.4
	_fx.ash_tail = 2.2
	_fx.intensity = 0.42            # a small dark hall, not an open field
	_fx.auto_punch = false          # thirty bursts of auto-exposure is a strobe
	add_child(_fx)
	_bind()


func _bind() -> void:
	if _fx == null or not is_instance_valid(_fx):
		return
	var vp := get_viewport()
	_fx.bind_camera(vp.get_camera_3d() if vp != null else null)
	var tree := get_tree()
	if tree != null:
		var found := tree.root.find_children("*", "WorldEnvironment", true, false)
		if not found.is_empty():
			_fx.bind_environment(found[0])


func _exit_tree() -> void:
	if _fx != null and is_instance_valid(_fx):
		_fx.hard_stop()   # restores the exposure and camera it borrowed


func _weight() -> float:
	return float(_slumber.weight) if _slumber != null else 0.0


func _set_slumber(w: float) -> void:
	if _slumber != null:
		_slumber.weight = clampf(w, 0.0, 1.0)


static func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


func _lerp(dur: float, setter: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(self) and is_inside_tree():
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		setter.call(u)
		if u >= 1.0:
			return
		await get_tree().process_frame
