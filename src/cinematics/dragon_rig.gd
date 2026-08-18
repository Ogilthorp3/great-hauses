class_name DragonRig
extends Node3D
## Shared controller for the championship dragon GLB — the single owner of
## the loader that used to live inline in GreatHall.summon_champion_dragon
## (refactored out 2026-08-08 so the spectator/ashfall module and the
## championship staging drive ONE rig instead of duplicating it).
##
## Owns: instancing assets/custom-props/dragon.glb, the no-new-lights
## emissive lift (the hall's 8-omni budget is FULL — glow comes from
## emission, never from Light3D), AnimationPlayer discovery, loop/one-shot
## clip helpers, the head-bone mouth mount used by the ashfall flame, the
## SLUMBER coil (`attach_slumber` / `slumber_default`) that folds a standing
## clip into a sleeping one, and `set_ember_energy` — the banked-vs-kindled
## throat coals, which are how this module sells "the eyes light" without a
## Light3D it is not allowed to have.
##
## THE SERPENT-WYRM (dragon-v2, installed 2026-08-09) replaced the Quaternius
## chibi. Clips as they arrive GODOT-SIDE (probed, not assumed — Godot's
## importer strips a trailing _Cycle/_Loop, which is why the GLB's
## `Flap_Cycle` lands as `Flap`):
##   Perch_Idle · Flying_Idle(=Hover) · Fast_Flying(=Flap) · Glide ·
##   Rear_Breathe(=Headbutt) · Land_Settle · Roar · HitReact · Yes · No
## The three aliases are byte-identical duplicates the asset ships on
## purpose so every incumbent call site kept working. `Death` and `Punch`
## are NOT authored; play_once/play_loop no-op on a missing clip.
##
## Rig: 42 bones — Root/Torso/Chest/Neck..Neck6/Head(+_end)/Jaw, 7-bone
## wings, 8-bone tail, real legs. Native forward is +Z (rotate PI to face
## -Z).
##
## THE ORIGIN MOVED — the one breaking change. The old rig hung its mesh
## around a MID-AIR root, so callers placed the root LOW and added a fudge.
## This `Root` sits ON THE GROUND between the feet; the torso mass centre is
## measured at BODY_RISE (0.95) × rig scale above it. Anywhere a dragon
## height was hardcoded against the old rig, the author's rule applies:
##     new_root_y = old_root_y + 1.15 × rig_scale
## (2.10 − 0.95 = 1.15). Applied 2026-08-09 to DragonSpectator's perch /
## hover / bank / throne constants and GreatHall.DRAGON_HOVER +
## spectator_perch().

const DRAGON_SCENE: PackedScene = preload("res://assets/custom-props/dragon.glb")

## THE HALL PALETTE — an open defect the asset's author flagged and this
## module owns (2026-08-09).
##
## The GLB ships a deliberately dark hide (albedo 0.118 linear / 0.378 sRGB,
## pushed cool) tuned against a FOUR-OMNI stand-in. Dropped into THIS hall —
## 8 warm torches, two cool fill directionals, a filmic tonemap at exposure
## 1.12 — plus the old flat warm emissive lift, it came back
## BROWN-MONOCHROME. Measured on in-game frames from the ceremony camera:
## hide median hue 240° sat 0.114 val 0.137, sail median hue 25° sat 0.142 —
## two materials a quarter of a saturation point apart, both in the mud, so
## hide, sail, plates and bone all read as ONE brown blob at hall distance.
##
## The fix is the ALBEDO, per the author's own note — nothing here depends on
## emission to read (the coals are authored bright). Three moves:
##   1. lift the hide OUT of the mud and push it further BLUE-slate,
##   2. push the sail the other way, WARM, so it separates by HUE and the
##      wings read as leather against cold scale instead of more of it,
##   3. stop painting a warm lift over everything — including the coals,
##      whose authored emission the old pass silently overwrote with it.
##
## ── THE WYRM WEARS NO HAUS (critic defect, 2026-08-09) ─────────────────────
## The pass above landed on an ICE-BLUE hide, which is Winterfang's colour
## (#7fb0d4 accent / #8d99a6 primary) — and Swiftcrest's (#7fb3d9 primary) and
## Silverbrook's (#8fb3d9 accent). For a whole match against any of the three
## the spectator looked like one side's mascot. The dragon is nobody's
## bannerman: it is the hall's own beast, so its hide is pushed OFF every
## heraldic hue in hauses/*/haus.json and onto DARK VIOLET-SLATE — a hue no
## haus owns (the nine live at 0-45 deg warm, 130-215 deg green/blue, and
## three near-blacks) — with the authored EMBER coals and a rust-leather sail
## as its only colour. Fire belongs to no haus either.
##
## The two scars that bound the numbers: albedo 0.118 came back a BLACK BLOB,
## and a warm lift over a near-black albedo came back UNDIFFERENTIATED BROWN.
## So the value stays in the band that was proven to read (0.40-0.59) and the
## separation is carried by HUE — slate hide vs rust sail vs ember coals —
## not by brightness.
const EMISSIVE_LIFT := Color(0.15, 0.145, 0.165)   # near-neutral, weaker
const HIDE_GAIN := 1.12
## Violet-slate, and deliberately NOT blue: b is barely over r, so the hide
## reads as charcoal-with-a-cast rather than as anybody's ice.
const HIDE_COOL := Color(1.12, 0.97, 1.06)
const SAIL_GAIN := 1.34
const SAIL_WARM := Color(1.34, 0.94, 0.70)
## The horns, claws and teeth. Pulled down and warmed off the near-WHITE it
## used to be — bone at 0.85 on a blue hide was the second half of the
## Winterfang read (their secondary is #eef2f5, snow).
const BONE_GAIN := 0.95
const BONE_WARM := Color(1.03, 0.97, 0.88)
## Board units from the armature root to the torso/chest mass centre at rig
## scale 1.0 (measured on the shipped GLB; feet at y = 0.000). This is the
## number every "where does the beast READ on screen" calculation uses.
const BODY_RISE := 0.95
const HEAD_BONE := "Head"
const HEAD_END_BONE := "Head_end"
const JAW_BONE := "Jaw"

## The chains the SLUMBER pose folds (measured names, asserted by
## tests/test_dragon.gd against the live skeleton).
const NECK_BONES: Array[String] = ["Neck", "Neck2", "Neck3", "Neck4", "Neck5", "Neck6"]
const TAIL_BONES: Array[String] = ["Tail", "Tail2", "Tail3", "Tail4",
	"Tail5", "Tail6", "Tail7", "Tail8"]
const LEG_BONES: Array[String] = ["Thigh.L", "Thigh.R", "Shin.L", "Shin.R",
	"Foot.L", "Foot.R"]

var anim: AnimationPlayer = null
var skeleton: Skeleton3D = null

var _mouth: Node3D = null
var _ember_mats: Array[StandardMaterial3D] = []


## Build a rig under `parent`. `pos`/`yaw`/`rig_scale` land on this wrapper
## node; the GLB scene hangs unscaled beneath it.
static func spawn(parent: Node, rig_name: String, pos: Vector3, yaw: float,
		rig_scale: float) -> DragonRig:
	var rig := DragonRig.new()
	rig.name = rig_name
	parent.add_child(rig)
	rig.position = pos
	rig.rotation.y = yaw
	rig.scale = Vector3.ONE * rig_scale
	return rig


## THE SOAR CYCLE (2026-08-18). `Fast_Flying` is 25 LINEAR keys per second on
## a 104-degree shoulder swing — a velocity corner every 2.4 rendered frames,
## which is what read as mechanical once the wyrm was big enough to see.
## `tools/blender/author_dragon_flight.py` re-times and re-samples those same
## authored poses into a smooth, asymmetric, overlapping cycle.
##
## It ships as an ANIMATION-ONLY companion file rather than inside dragon.glb,
## because re-exporting the shared asset compressed every existing clip to
## 40 % of its duration (glTF samples at the scene fps; the source is 24 and
## the new cycle needs 60) and the ashfall is choreographed against those
## lengths. Merging it here costs one instantiate at spawn and leaves
## dragon.glb byte-identical.
const SOAR_SCENE_PATH := "res://assets/custom-props/dragon_soar.glb"
const SOAR_CLIP := "Soar"


func _ready() -> void:
	var model := DRAGON_SCENE.instantiate()
	model.name = "Model"
	add_child(model)
	_apply_emissive_lift(model)
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	anim = anims[0] if not anims.is_empty() else null
	var skels := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if not skels.is_empty() else null
	_merge_soar()


## Pull `Soar` out of the companion file and into THIS rig's player, with its
## track paths retargeted onto the paths this player already uses — so the
## merge cannot break on a node-naming difference between the two files.
## Silent no-op if the companion is absent: every caller stays duck-safe and
## falls back to `Fast_Flying`.
func _merge_soar() -> void:
	if anim == null or anim.has_animation(SOAR_CLIP):
		return
	if not ResourceLoader.exists(SOAR_SCENE_PATH):
		return
	# The prefix this player addresses its skeleton by, read off a clip that
	# is already known to work rather than assumed.
	var prefix := ""
	for clip in anim.get_animation_list():
		var existing := anim.get_animation(clip)
		for i in existing.get_track_count():
			var p := existing.track_get_path(i)
			if String(p.get_concatenated_subnames()) != "":
				prefix = String(p.get_name(0))
				for k in range(1, p.get_name_count()):
					prefix += "/" + String(p.get_name(k))
				break
		if prefix != "":
			break
	if prefix == "":
		return
	var inst: Node = (load(SOAR_SCENE_PATH) as PackedScene).instantiate()
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		inst.free()
		return
	var src: AnimationPlayer = players[0]
	# The companion carries exactly one clip. Godot's glTF importer names a
	# lone animation "Animation" rather than after the action, so match by
	# name when it happens to survive and fall back to "the only one there".
	var names := src.get_animation_list()
	var found := ""
	for n in names:
		if n.ends_with(SOAR_CLIP):
			found = n
			break
	if found == "" and names.size() == 1:
		found = names[0]
	if found == "":
		inst.free()
		return
	var clip_res: Animation = src.get_animation(found).duplicate()
	for i in clip_res.get_track_count():
		var sub := String(clip_res.track_get_path(i).get_concatenated_subnames())
		clip_res.track_set_path(i, NodePath(prefix + ":" + sub))
	clip_res.loop_mode = Animation.LOOP_LINEAR
	var lib := anim.get_animation_library("")
	if lib != null:
		lib.add_animation(SOAR_CLIP, clip_res)
	inst.free()


## Did the smooth cycle make it in? (Probed by tests and by the cinematic,
## which falls back to `Fast_Flying` when it did not.)
func has_soar() -> bool:
	return has_clip(SOAR_CLIP)


## The 8-omni budget is FULL — no light for the dragon. It is lit out of the
## gloom by material work alone: a per-ROLE albedo correction (see the
## palette block above) plus a faint self-glow. Roles come from the GLB's
## material names, which `dragon-v2/tools/verify_glb.py` asserts, so a
## rename cannot silently slip past this. An unrecognised material (any
## other model routed through this rig) falls back to the old flat lift.
func _apply_emissive_lift(model: Node) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = src.duplicate()
				_paint_for_hall(m)
				mi.set_surface_override_material(s, m)
				if m.resource_name.begins_with("dragon_ember"):
					_ember_mats.append(m)


## THE COALS, dimmed and kindled. The wyrm's throat/breast embers are the
## only part of it that can carry LIGHT as a dramatic beat, because the hall's
## 8-omni budget is full and this module may never add a Light3D: a sleeping
## dragon banks its fire (0.4) and a waking one kindles it (2.6). Nothing here
## creates or touches a light — it is the authored emission's energy
## multiplier and nothing else. Safe no-op on a rig whose GLB has no
## `dragon_ember*` material.
func set_ember_energy(mult: float) -> void:
	for m in _ember_mats:
		m.emission_energy_multiplier = maxf(mult, 0.0)


func ember_material_count() -> int:
	return _ember_mats.size()


static func _paint_for_hall(m: StandardMaterial3D) -> void:
	var role := m.resource_name
	if role.begins_with("dragon_ember"):
		# THE COALS. Authored bright and already emissive — the old pass
		# overwrote that emission with the flat lift and put the fire in the
		# throat out. Leave them exactly as the asset intends.
		m.emission_enabled = true
		return
	if role.begins_with("dragon_membrane"):
		# THE SAIL: dark ash-leather, pushed WARM so it separates from the
		# cold hide by hue rather than fighting it for value. The warm rim
		# (`dragon_membrane_edge`) keeps its authored glow.
		m.albedo_color = _tint(m.albedo_color, SAIL_GAIN, SAIL_WARM)
		if not m.emission_enabled:
			m.emission_enabled = true
			m.emission = EMISSIVE_LIFT
		return
	if role == "dragon_void":
		return   # eye sockets stay holes
	if role == "dragon_bone":
		m.albedo_color = _tint(m.albedo_color, BONE_GAIN, BONE_WARM)
		m.emission_enabled = true
		m.emission = EMISSIVE_LIFT
		return
	# THE HIDE (scale / scale_dark / scute / plate) and anything unnamed:
	# out of the mud and onto violet-slate — no haus's colour (see the palette
	# block up top for why it is not blue any more).
	var cool := HIDE_COOL if role.begins_with("dragon_") else Color.WHITE
	m.albedo_color = _tint(m.albedo_color, HIDE_GAIN, cool)
	m.emission_enabled = true
	m.emission = EMISSIVE_LIFT


## Gain + hue push, alpha untouched and every channel clamped (a Color
## multiplied by a float in GDScript also scales alpha — the exact trap the
## dracarys kit documents).
static func _tint(c: Color, gain: float, tint: Color) -> Color:
	return Color(
		clampf(c.r * gain * tint.r, 0.0, 1.0),
		clampf(c.g * gain * tint.g, 0.0, 1.0),
		clampf(c.b * gain * tint.b, 0.0, 1.0),
		c.a)


# -- clips -----------------------------------------------------------------


func has_clip(clip: String) -> bool:
	return anim != null and anim.has_animation(clip)


func clip_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return anim.get_animation(clip).length


## Loop `clip` (loop mode forced onto the imported animation, which ships
## one-shot) at `speed`. Safe no-op when the clip is missing.
func play_loop(clip: String, speed: float = 1.0, blend: float = 0.3) -> void:
	if not has_clip(clip):
		return
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.speed_scale = speed
	anim.play(clip, blend)


## Play `clip` once at `speed`; returns its wall-clock duration (0.0 when
## missing) so callers can await their own clocks — this never blocks.
func play_once(clip: String, speed: float = 1.0, blend: float = 0.15) -> float:
	if not has_clip(clip):
		return 0.0
	anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	anim.speed_scale = speed
	anim.play(clip, blend)
	return clip_length(clip) / maxf(speed, 0.01)


## Take the playhead by hand: the clip is loaded and PAUSED, and the caller
## drives it with seek_clip() off its own wall clock.
##
## Why the ceremony needs this: `Rear_Breathe` is authored inhale (0.00-0.92)
## → HELD BLAST (0.92-1.33) → recoil (1.75-2.25). The shot is that 0.41 s
## hold — but the ASHFALL breath sweeps fire across a whole army over ~2.8 s
## of wall clock under a 0.55 time_scale. No single playback speed can make
## a 0.41 s hold cover a 2.8 s sweep AND keep the lunge snappy, so the
## ceremony maps wall time onto clip time itself (see _breath_clip_time).
## Returns false when the clip is missing.
func play_manual(clip: String) -> bool:
	if not has_clip(clip):
		return false
	anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	anim.speed_scale = 1.0
	anim.play(clip)
	anim.pause()
	anim.seek(0.0, true)
	return true


## Park a hand-driven playhead at `t` seconds (see play_manual).
func seek_clip(t: float) -> void:
	if anim == null:
		return
	anim.seek(maxf(t, 0.0), false)


# -- THE SLUMBER POSE ------------------------------------------------------
# `Perch_Idle` is a SETTLED pose, not a SLEEPING one: wings furled and breath
# slow, but the neck still carries the gothic arc and the head rides at
# y 1.91 (rig scale 1.0) — an animal standing watch. A dragon that is already
# alert has nowhere to escalate to, which is the whole reason the wake exists.
#
# This modifier folds the clip into a coil: neck down over the forefeet,
# chin toward the stone, tail curled around the flank, haunches couched, plus
# a slow breathing swell. It runs in the skeleton's modification stack, i.e.
# AFTER the AnimationPlayer has written its pose, and POST-multiplies each
# bone's local rotation — so it rides on top of any clip instead of fighting
# it, and `weight` cross-fades the coil in and out (1 = asleep, 0 = the clip
# as authored). Every angle below is applied about the BONE's own axes, whose
# world orientation was measured off the shipped GLB, not guessed.


class Slumber:
	extends SkeletonModifier3D

	var weight := 1.0            ## 1 = fully coiled, 0 = the clip untouched
	var breath_rate := 0.55      ## rad/s of the breathing sine
	var breath_amp := 0.0        ## radians of chest swell at weight 1

	var _bends: Array = []       ## [[bone_index, Vector3 euler], ...]
	var _breath_bone := -1
	var _t := 0.0
	var calls := 0               ## the stack ran this many times

	## THE ONLY PLACE THE COILED POSE EXISTS. Godot runs the modifier stack,
	## hands the result to the skin, then RESTORES the animation pose — so
	## `skeleton.get_bone_global_pose()` read from _process/_ready reports the
	## clip's pose and a coil that never moved a vertex would look identical to
	## one that did. Name bones here and the modifier writes their post-coil
	## skeleton-space origins into `sampled` from inside its own pass; that is
	## what tests/test_dragon.gd asserts against, and what the pose was
	## calibrated with.
	var sample_bones: Array = []
	var sampled: Dictionary = {}

	func build(sk: Skeleton3D, table: Array, breath_bone: String) -> void:
		_bends.clear()
		if sk == null:
			return
		for e: Array in table:
			var i := sk.find_bone(str(e[0]))
			if i != -1:
				_bends.append([i, e[1] as Vector3])
		_breath_bone = sk.find_bone(breath_bone)

	func bend_count() -> int:
		return _bends.size()

	## Godot 4.5+ drives the stack through the delta form; the base class's
	## compatibility path is what would otherwise call `_process_modification`.
	func _process_modification_with_delta(delta: float) -> void:
		calls += 1
		var sk := get_skeleton()
		if sk == null:
			return
		if weight > 0.0005:
			_t += delta
			for b: Array in _bends:
				var i: int = b[0]
				sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i)
					* Quaternion.from_euler((b[1] as Vector3) * weight))
			if _breath_bone != -1 and breath_amp > 0.0:
				var s := sin(_t * breath_rate) * breath_amp * weight
				sk.set_bone_pose_rotation(_breath_bone,
					sk.get_bone_pose_rotation(_breath_bone)
					* Quaternion.from_euler(Vector3(s, 0.0, 0.0)))
		# Sampled at EVERY weight, including 0 — a test that compares the
		# coiled pose against the clip's own pose needs both halves.
		for bn in sample_bones:
			var bi := sk.find_bone(bn)
			if bi != -1:
				sampled[bn] = _chain(sk, bi).origin

	## Skeleton-space transform of `idx` walked by hand up the parent chain.
	## `get_bone_global_pose()` may NOT be called from inside the stack — it
	## forces a full transform update, which re-enters the modifier list and
	## hangs the process (measured, 2026-08-09).
	static func _chain(sk: Skeleton3D, idx: int) -> Transform3D:
		var t := sk.get_bone_pose(idx)
		var p := sk.get_bone_parent(idx)
		while p != -1:
			t = sk.get_bone_pose(p) * t
			p = sk.get_bone_parent(p)
		return t


## THE COIL, in degrees, calibrated on the shipped rig (see the probe note in
## `Slumber.sampled` for why it had to be measured from inside the stack).
##
## ── SLEEPING ANIMALS FOLD (critic defect, 2026-08-09) ─────────────────────
## The previous profile [44, 36, 18, -22, -36, -34] summed to ~+6°, which kept
## the SKULL LEVEL — and level is right, but it left the neck EXTENDED. The
## head finished 1.37 rig-units out from the chest at the end of a near-
## straight line, jaws parted: measured on the shipped gameplay frame that is
## ~150 px of bare neck between body and skull, and "level plus long" is the
## silhouette of a shed skin, not of a sleeping animal. The critic's word for
## it was "a dead lizard".
##
## What a sleeping animal does is FOLD. This profile carries the head all the
## way back to the flank: down hard through the base (57, 62, 66, 44 — the
## neck descends in front of the shoulder), then the crown UNFOLDS (-5, -54)
## so the skull comes level again instead of rolling under, while a LATERAL
## curl growing along the same chain (SLUMBER_NECK_LAT) sweeps the whole
## return out to the near flank so it never ploughs through the chest.
##
## Measured landing (rig-local, feet at y = 0; subtract SLUMBER_ROOT_DROP for
## height above the stone):
##       head   (-0.44, 0.45, 0.09)   0.67 from the chest  (was 1.37)
##       snout  (-0.64, 0.36,-0.17)   0.04 above the stone, pointing BACK
##   muzzle sits BELOW the head origin, i.e. the skull is upright, not rolled.
## The head lies on the stone beside the shoulder with the neck folded over
## it and the horns swept along that curve — the same C the tail already
## makes, closing toward the camera.
const SLUMBER_NECK := [57.0, 62.0, 66.0, 44.0, -5.0, -54.0]
## The lateral half of the fold, about each neck bone's own Z (the bones run
## along local Y, so X is the pitch and Z is the sideways bend — the same
## convention the tail's curl term uses). NEGATIVE sweeps toward local -X,
## which at `rest_yaw` is the CAMERA's side: the head folds in front of the
## flank where it can be seen, not behind it where it cannot.
const SLUMBER_NECK_LAT := [-4.0, -2.0, -1.0, -9.0, -27.0, -44.0]
const SLUMBER_HEAD := -36.0      ## the skull rolls back level on the fold
const SLUMBER_HEAD_LAT := 48.0   ## …and turns its cheek down onto the stone
## THE JAWS CLOSE. `Perch_Idle` is a standing-watch clip and holds the mouth
## slightly open; parted jaws on a coiled beast read as a carcass, and this is
## the one bone that says "asleep" rather than "dead" for free.
const SLUMBER_JAW := 9.0
const SLUMBER_TORSO := 8.0       ## shoulders slump forward
const SLUMBER_TAIL_DOWN := 8.0   ## per tail joint — the whip onto the floor
const SLUMBER_TAIL_CURL := 16.0  ## per tail joint — curled around the flank
const SLUMBER_THIGH := 45.0      ## couched: knees up, haunches down…
const SLUMBER_SHIN := -38.0
const SLUMBER_FOOT := 25.0
## THE WINGS, mantled. `Perch_Idle`'s "furled" still tents the elbows 0.31
## above the spine, and from the gameplay camera (which looks DOWN at ~49°)
## that tent is the loudest shape the beast has — the first render of the
## sleeper read as a folded umbrella. X drops the elbow to the line of the
## back, Z draws the whole wing in against the flank; mirrored per side.
const SLUMBER_WING1 := Vector3(-12.0, 0.0, 20.0)
const SLUMBER_WING2 := Vector3(-22.0, 0.0, 0.0)
## …which lifts the toe claws 0.325 in rig-local units, so the node drops by
## the same amount and the claws stay ON the stone instead of floating.
## Measured landing at this drop: snout y +0.03, tail belly y 0.00, chest
## y 0.63 — chin and tail on the floor, body couched over its own feet.
const SLUMBER_ROOT_DROP := 0.32


## Build the coil's per-bone angle table (radians in, so the probe can sweep).
## Signs come from the measured bone frames: every bone runs along its own
## local Y, so X is the PITCH (a NEGATIVE rotation about local X folds a neck
## bone forward and down) and Z is the LATERAL bend. The tail bones point
## backward, which is why their local Z reads as a horizontal curl and their X
## term drops the whip onto the stone; the neck bones point up, so their Z is
## the sideways sweep that carries the head to the flank.
##
## `neck_lat` is optional: an empty array is the pure-sagittal fold the coil
## shipped with before the head came back to the flank.
static func slumber_table(neck: Array, head: float, torso: float,
		tail_down: float, tail_curl: float,
		thigh: float, shin: float, foot: float,
		wing1 := Vector3.ZERO, wing2 := Vector3.ZERO,
		neck_lat: Array = [], head_lat := 0.0, jaw := 0.0) -> Array:
	var table: Array = []
	# The wings are MIRRORED, so the left side takes the negated yaw/roll
	# terms; only the pitch (X, the fold) is common to both.
	for w: Array in [["Wing1.R", wing1], ["Wing1.L", _mirror(wing1)],
			["Wing2.R", wing2], ["Wing2.L", _mirror(wing2)]]:
		if (w[1] as Vector3).length_squared() > 0.0:
			table.append([w[0], w[1]])
	table.append(["Torso", Vector3(-torso, 0.0, 0.0)])
	for i in NECK_BONES.size():
		var a: float = float(neck[i]) if i < neck.size() else 0.0
		var l: float = float(neck_lat[i]) if i < neck_lat.size() else 0.0
		table.append([NECK_BONES[i], Vector3(-a, 0.0, l)])
	table.append([HEAD_BONE, Vector3(-head, 0.0, head_lat)])
	# THE JAW closes the OTHER way round from the neck: it hangs forward off
	# the skull, so a POSITIVE local-X rotation swings it UP against the upper
	# teeth. (`Perch_Idle` never touches this bone — measured — so whatever the
	# rest pose leaves parted stays parted for the whole match unless the coil
	# shuts it.)
	if not is_zero_approx(jaw):
		table.append([JAW_BONE, Vector3(jaw, 0.0, 0.0)])
	for b in TAIL_BONES:
		table.append([b, Vector3(-tail_down, 0.0, tail_curl)])
	for b in ["Thigh.L", "Thigh.R"]:
		table.append([b, Vector3(thigh, 0.0, 0.0)])
	for b in ["Shin.L", "Shin.R"]:
		table.append([b, Vector3(shin, 0.0, 0.0)])
	for b in ["Foot.L", "Foot.R"]:
		table.append([b, Vector3(foot, 0.0, 0.0)])
	return table


static func _mirror(e: Vector3) -> Vector3:
	return Vector3(e.x, -e.y, -e.z)


## The calibrated coil, ready to hand to `attach_slumber`.
static func slumber_default() -> Array:
	var d := PI / 180.0
	var neck: Array = []
	for a in SLUMBER_NECK:
		neck.append(float(a) * d)
	var lat: Array = []
	for a in SLUMBER_NECK_LAT:
		lat.append(float(a) * d)
	return slumber_table(neck, SLUMBER_HEAD * d, SLUMBER_TORSO * d,
		SLUMBER_TAIL_DOWN * d, SLUMBER_TAIL_CURL * d,
		SLUMBER_THIGH * d, SLUMBER_SHIN * d, SLUMBER_FOOT * d,
		SLUMBER_WING1 * d, SLUMBER_WING2 * d,
		lat, SLUMBER_HEAD_LAT * d, SLUMBER_JAW * d)


# -- THE FLIGHT SWAY ------------------------------------------------------
# The authored flight clips move the WINGS. They do not move the animal: the
# neck holds one pose through a banking turn and the tail trails dead
# straight behind, so a wyrm driven along a spline reads as a model being
# carried on a stick — Bert's word for the first cut was "a robot".
#
# What a flying serpent actually does, and what this modifier adds on top of
# whatever clip is playing (it runs in the skeleton's modification stack,
# AFTER the AnimationPlayer has written its pose, and POST-multiplies each
# bone's local rotation, exactly like Slumber):
#
#   THE HEAD LEADS.  An animal looks where it is going before it gets there.
#     The lateral bend is spread along the neck and grows toward the skull,
#     so the head swings into a turn ahead of the body and the whole neck
#     draws the arc instead of hinging at one joint.
#   THE TAIL LAGS, AND WAVES.  The tail is thrown to the OUTSIDE of a turn
#     (it has mass and it is behind the turn), and a sine travels down its
#     eight joints so it is never a straight rod — the wave is phase-shifted
#     per joint, which is what makes a serpent read as a serpent.
#   THE NECK BREATHES WITH THE CLIMB.  Nose up on a climb, tucked on a dive.
#
# Angles are small on purpose (single digits per joint): the effect is the
# SUM along a chain of six or eight, and anything larger fights the clip.
# Signs are in the same convention Slumber measured on this rig — each bone
# runs along its own local Y, so local X is the PITCH and local Z is the
# LATERAL bend.
class FlightSway:
	extends SkeletonModifier3D

	## Driven by the flier each frame; all three are already smoothed there.
	var turn := 0.0        ## signed turn rate, radians/sec (+ = to its left)
	var climb := 0.0       ## -1 (diving) .. +1 (climbing)
	var weight := 1.0      ## 0 disables the whole modifier

	var lead_per_neck := 7.0    ## degrees of lateral lead at the LAST neck bone
	var lag_per_tail := 5.0     ## degrees of lateral lag at the last tail bone
	var wave_deg := 3.2         ## travelling wave amplitude per tail joint
	var wave_rate := 2.1        ## rad/sec the wave travels
	var wave_lag := 0.55        ## radians of phase per joint down the chain
	var climb_deg := 6.0        ## neck pitch at |climb| = 1

	var _neck: Array[int] = []
	var _tail: Array[int] = []
	var _head := -1
	var _t := 0.0
	var calls := 0              ## the stack ran this many times (probe)

	func build(sk: Skeleton3D) -> void:
		_neck.clear()
		_tail.clear()
		if sk == null:
			return
		for n in NECK_BONES:
			var i := sk.find_bone(n)
			if i != -1:
				_neck.append(i)
		for n in TAIL_BONES:
			var i := sk.find_bone(n)
			if i != -1:
				_tail.append(i)
		_head = sk.find_bone(HEAD_BONE)

	func chain_counts() -> Vector2i:
		return Vector2i(_neck.size(), _tail.size())

	func _process_modification_with_delta(delta: float) -> void:
		calls += 1
		var sk := get_skeleton()
		if sk == null or weight <= 0.001:
			return
		_t += delta
		var d := PI / 180.0
		# THE NECK: lateral lead ramping toward the skull, plus climb pitch.
		var n := _neck.size()
		for k in n:
			var i: int = _neck[k]
			# quadratic ramp: the base barely moves, the crown carries it
			var ramp := float(k + 1) / float(n)
			var lat := -turn * lead_per_neck * d * ramp * ramp * weight
			var pitch := climb * climb_deg * d * ramp * 0.5 * weight
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i)
				* Quaternion.from_euler(Vector3(pitch, 0.0, lat)))
		if _head != -1:
			sk.set_bone_pose_rotation(_head, sk.get_bone_pose_rotation(_head)
				* Quaternion.from_euler(Vector3(climb * climb_deg * d * 0.4 * weight,
					0.0, -turn * lead_per_neck * d * 0.6 * weight)))
		# THE TAIL: lag to the outside + a wave travelling down the chain.
		var m := _tail.size()
		for k in m:
			var i: int = _tail[k]
			var ramp := float(k + 1) / float(m)
			var lag := turn * lag_per_tail * d * ramp * weight
			var wave := sin(_t * wave_rate - float(k) * wave_lag) \
				* wave_deg * d * (0.35 + 0.65 * ramp) * weight
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i)
				* Quaternion.from_euler(Vector3(0.0, 0.0, lag + wave)))


## Attach (once) the flight-sway modifier to this rig's skeleton — the
## secondary motion that makes a flying wyrm read as an animal rather than a
## mesh on a spline. Returns null on a rig with no skeleton (duck-safe), and
## is independent of Slumber: the two are never driven at once (a coiled
## sleeper is not flying), but nothing here breaks if both are attached.
func attach_flight_sway() -> FlightSway:
	if skeleton == null:
		return null
	var s := FlightSway.new()
	s.name = "FlightSway"
	skeleton.add_child(s)
	s.build(skeleton)
	return s


## Attach (once) the slumber modifier to this rig's skeleton. Returns null on
## a rig with no skeleton — every caller must stay duck-safe.
func attach_slumber(table: Array, breath_amp: float, breath_rate: float) -> Slumber:
	if skeleton == null:
		return null
	var s := Slumber.new()
	s.name = "SlumberCoil"
	s.breath_amp = breath_amp
	s.breath_rate = breath_rate
	skeleton.add_child(s)
	s.build(skeleton, table, "Chest")
	return s


# -- emissive particle builder (shared: ashfall flame, ember drift) --------


## A soft radial alpha falloff, built once per emitter.
##
## THIS IS THE FIX FOR "BARE OPAQUE SQUARES". Every emitter this factory
## built used to ship a QuadMesh with NO albedo_texture — so each particle
## drew a flat, hard-edged, screen-aligned RECTANGLE of uniform alpha. That
## is exactly what the art critic saw and named ("bare opaque squares… JPEG
## compression blocks, not embers"). Swapping the ashfall flame for the
## dracarys kit did NOT fix it: the smoulder wisps and the tableau ember
## drift still came through here, and grey rectangles were still hanging in
## the hall after the fire (caught by eye on in-game frames 2026-08-09, then
## pinned down by dyeing the kit's own billboards red and watching the
## squares stay grey — they were never the kit's).
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.22), Color(1.0, 1.0, 1.0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 96
	t.height = 96
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## GPUParticles3D factory for every dragon effect — EMISSIVE MATERIALS ONLY
## (the hall's 8-omni budget is FULL: this helper never creates a Light3D).
## cfg keys: amount, lifetime, size, velocity(Vector2 min/max), spread,
## gravity, grow, ramp([[offset, Color], ...]), blend, emission_energy;
## optional: direction (default +Z out of the jaws), emission_radius.
static func spawn_emitter(parent: Node3D, node_name: String, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.emitting = false
	p.speed_scale = 1.5   # reads fierce under the ashfall slow-mo
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = cfg.get("direction", Vector3(0.0, 0.0, 1.0))
	pm.spread = cfg["spread"]
	pm.initial_velocity_min = (cfg["velocity"] as Vector2).x
	pm.initial_velocity_max = (cfg["velocity"] as Vector2).y
	pm.gravity = cfg["gravity"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = cfg.get("emission_radius", 0.09)
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
	mat.albedo_texture = _soft_dot()   # never ship an untextured quad
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if float(cfg["emission_energy"]) > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.12)
		mat.emission_energy_multiplier = cfg["emission_energy"]
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


# -- head-bone mount (ashfall flame origin) --------------------------------


## A Node3D riding the Head bone at the snout tip, +Z aimed out of the
## mouth. Lazily built; null when the rig has no head bone (never the case
## for the shipped GLB, but the rig stays duck-safe).
func mouth_node() -> Node3D:
	if _mouth != null:
		return _mouth
	if skeleton == null:
		return null
	var head := skeleton.find_bone(HEAD_BONE)
	if head == -1:
		return null
	var att := BoneAttachment3D.new()
	att.name = "MouthMount"
	att.bone_name = HEAD_BONE
	skeleton.add_child(att)
	var mouth := Node3D.new()
	mouth.name = "Mouth"
	att.add_child(mouth)
	# Place the mouth just past the snout: Head_end in head-bone space.
	var head_rest := skeleton.get_bone_global_rest(head)
	var end_idx := skeleton.find_bone(HEAD_END_BONE)
	if end_idx != -1:
		var local_end: Vector3 = head_rest.affine_inverse() \
			* skeleton.get_bone_global_rest(end_idx).origin
		mouth.position = local_end * 1.15
		# Aim +Z along the bone (out of the mouth): -Z toward the head.
		if local_end.length() > 0.001:
			mouth.basis = Basis.looking_at(-local_end.normalized(), Vector3.FORWARD)
	_mouth = mouth
	return _mouth
