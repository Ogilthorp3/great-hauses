class_name PieceView
extends Node3D
## A Great Houses combatant on the board — a real KayKit character (the
## banner watchtower for the rook, a MOUNTED horse+rider ensemble for the
## knight — ISSUES.md #1), tinted per house, animated from the shared
## Rig_Medium animation libraries (the mount carries no rig at all — it is
## driven procedurally, see below), and COSTUMED in two layers:
##
##   TYPE layer (identical across houses — instant readability):
##     strict height grading (PieceAssets.TYPE_HEIGHT) · signature gear
##     (pawn sword+round shield · knight ON HORSEBACK, sword+kite shield ·
##     bishop staff+tome · queen tiara+bow+quiver · king crown+cape+sword)
##     · an engraved type-glyph ring under every piece — HIDDEN at rest,
##     fading in on mouse hover (set_hovered), staying lit while selected
##     (set_selected also brightens the glyph to beacon energy). ISSUES.md #2.
##   HOUSE layer (flourish — never changes the type silhouette):
##     palette tints · helmet crests on knight/queen/king · sigil decals
##     on shields · the rook's banner + fluttering pennant · the knight's
##     caparison dressed in the house banner cloth (sigil on the flank) ·
##     Tidegrip fields the skeleton cast (same rig, same anims) on a
##     charred-dark horse.
##
## MOUNTED KNIGHT (ISSUES.md #1): the KayKit Knight sits a Quaternius CC0
## horse (fixed transform on the horse root, statically seat-posed — bend
## poses read fine at this poly scale). The horse is a STATIC standing mesh
## (its FBX-lineage rig corrupts in-engine at piece scale — see
## PieceAssets.HORSE) animated procedurally, banner-rook style: idle sway
## on the ensemble, a canter bob on moves (the rider sits still), a horse
## step-in under the rider's Throw for the capture duel, and on death the
## rider slides off through Death_A while the horse keels over sideways.
## Face-to-face duel rotation applies to this PieceView root, so the whole
## ensemble turns as one.
##
## Model-agnostic API (callers touch nothing else):
##   setup(type, side, house_id="") · move_to(world_pos, walk_time) ·
##   play_capture(victim) · die() · spawn_flourish() · set_selected(on) ·
##   set_hovered(on)
## house_id skins the piece with HouseRegistry tints; "" keeps the legacy
## FROST/EMBER consts (fully backward compatible).

signal move_finished
signal died

enum Type { PAWN, ROOK, KNIGHT, BISHOP, QUEEN, KING }
enum House { FROST, EMBER }  # cold grey-blue vs dark crimson

# House Frost = cold grey-blue; House Ember = dark crimson/gold. The pack
# albedo textures are desaturated (Image.adjust_bcs) then multiplied by the
# house tint — gritty war-camp colors, no candy.
const HOUSE_TINT := {
	House.FROST: Color(0.58, 0.7, 0.9),
	House.EMBER: Color(0.85, 0.38, 0.22),
}
const HOUSE_TINT_TOWER := {
	House.FROST: Color(0.52, 0.63, 0.8),
	House.EMBER: Color(0.75, 0.33, 0.2),
}
const TINT_SATURATION := 0.25

## Glyph-ring hover fade (ISSUES.md #2): hidden at rest, ~0.15 s in/out.
const RING_FADE_TIME := 0.15

const ANIM_IDLE := "Idle_A"
const ANIM_WALK := "Walking_A"
const ANIM_THROW := "Throw"
const ANIM_HIT := "Hit_A"
const ANIM_DEATH := "Death_A"
const ANIM_SPAWN := "Spawn_Ground"

## Ensemble proportions, tuned BY EYE against the rendered beauty shot (the
## KayKit cast is chibi — big head, wide shoulders — so a horse scaled to
## "anatomically right" reads as a pony under a giant). Horse-ensemble-local
## units, pre-normalization:
##   HORSE_SCALE  the mount's size against the rider's native size. It is a
##                straight trade: the ensemble is normalized to the type's
##                design height, so a bigger mount buys silhouette by
##                shrinking the rider. 0.58 was picked off rendered A/Bs
##                (0.52 · 0.58 · 0.62 · 0.68 · 0.85) — the horse owns the
##                shape while the helm and crest still read.
##   RIDER_POS    the seat: hips sink onto the saddle slab top
##                (3.675·HORSE_SCALE − hips-height 0.39) over the seat
##                center (0.55·HORSE_SCALE) — no float, no gap.
##   MODEL_YAW    stance. A chess piece is read head-on, and head-on a horse
##                is a narrow shape hiding behind its rider. Reining the
##                ensemble a quarter-turn presents head, barrel and the
##                caparison's full drape to the camera — THE cavalry read.
##                Applied to the Model, never the root, so duel face-offs
##                (which turn the root) still put the knight on his victim.
const KNIGHT_HORSE_SCALE := 0.58
const KNIGHT_RIDER_POS := Vector3(0.0, 1.74, 0.32)
const KNIGHT_MODEL_YAW := 30.0
## How far the rider tumbles off the saddle when the knight falls
## (ensemble-local; the slide runs while Death_A plays).
const KNIGHT_FALL_OFFSET := Vector3(1.6, -1.55, -0.2)

## Head-bone mount for house crests (crown-attach pattern): sits above the
## crown line so king crest + crown coexist.
const CREST_MOUNT_POS := Vector3(0.0, 1.04, 0.0)
## Chest-bone mount for the king's cape (Skeleton_Rogue cape convention).
const CAPE_MOUNT_POS := Vector3(0.0, 0.04, -0.08)

var piece_type: Type = Type.PAWN
var side: House = House.FROST
## Canonical HouseRegistry id skinning this piece ("" = legacy FROST/EMBER).
var house_id := ""
## Set just before `died` fires — e2e reads it to prove a death anim played.
var death_anim := ""

var _model: Node3D
var _anim: AnimationPlayer  # null for the rook (static tower); the RIDER's for the knight
var _horse: Node3D          # knight only: the mount instance (static mesh)
var _rider: Node3D          # knight only: the seated character instance
var _sway_tween: Tween      # knight only: the procedural idle sway loop
var _home_yaw := 0.0
var _glyph_ring: Node3D
var _glyph_mat: StandardMaterial3D  # per-piece duplicate; brightened on select
var _glyph_tween: Tween
var _ring_meshes: Array[MeshInstance3D] = []  # faded via GeometryInstance3D.transparency
var _ring_fade_tween: Tween
var _ring_shown := false    # target state (true while fading in)
var _hovered := false
var _is_selected := false


func setup(new_type: Type, new_side: House, new_house_id: String = "") -> void:
	piece_type = new_type
	side = new_side
	house_id = new_house_id
	for child in get_children():
		child.queue_free()
	_anim = null
	_horse = null
	_rider = null
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	_glyph_ring = null
	_glyph_mat = null
	_ring_meshes = []
	_ring_shown = false
	_hovered = false
	_is_selected = false
	if piece_type == Type.ROOK:
		_build_tower()
	elif piece_type == Type.KNIGHT:
		_build_knight()
	else:
		_build_character()
	_build_glyph_ring()
	# Face the enemy line: Frost looks +Z (toward Ember), Ember looks -Z.
	_home_yaw = 0.0 if side == House.FROST else PI
	rotation.y = _home_yaw
	# Counter-rotate the ring so the engraved glyph reads upright from the
	# default camera (behind the player at -Z) for BOTH armies.
	if _glyph_ring != null:
		_glyph_ring.rotation.y = -_home_yaw
		if piece_type == Type.ROOK:
			# the watchtower plinth is wider than a character's feet — slide
			# the ring along its own forward axis so the medallion clears it
			_glyph_ring.translate_object_local(Vector3(0.0, 0.0, -0.14))


## Selection feedback: the ring stays lit for the whole selection and the
## engraved glyph warms from engraving to beacon.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_ring_visibility()
	if _glyph_mat == null:
		return
	if _glyph_tween != null:
		_glyph_tween.kill()
	var target := PieceAssets.GLYPH_ENERGY_SELECTED if selected \
			else PieceAssets.GLYPH_ENERGY_REST
	_glyph_tween = create_tween()
	_glyph_tween.tween_property(_glyph_mat, "emission_energy_multiplier",
			target, 0.15).set_trans(Tween.TRANS_SINE)


## Hover feedback (ISSUES.md #2): the type-glyph ring is hidden at rest and
## fades in while the mouse rests on this piece's square — BOTH armies
## reveal (knowing the rival's piece types matters too). game.gd drives it
## from BoardView.square_hovered.
func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_update_ring_visibility()


## True while the glyph ring is shown (or fading in) — hover or selection.
## Introspection for the costume suite + e2e hover assertions.
func glyph_ring_shown() -> bool:
	return _ring_shown


func _update_ring_visibility() -> void:
	_set_ring_shown(_hovered or _is_selected)


func _set_ring_shown(shown: bool) -> void:
	if _glyph_ring == null or _ring_shown == shown:
		return
	_ring_shown = shown
	if _ring_fade_tween != null:
		_ring_fade_tween.kill()
	_glyph_ring.visible = true
	_ring_fade_tween = create_tween().set_parallel(true)
	for mi in _ring_meshes:
		_ring_fade_tween.tween_property(mi, "transparency",
				0.0 if shown else 1.0, RING_FADE_TIME) \
			.set_trans(Tween.TRANS_SINE)
	if not shown:
		# Fully faded out -> stop rendering the ring at all.
		_ring_fade_tween.chain().tween_callback(func() -> void:
			if not _ring_shown and _glyph_ring != null:
				_glyph_ring.visible = false)


# -- movement --------------------------------------------------------------


func move_to(world_pos: Vector3, walk_time: float = 0.4) -> void:
	## Walk (the tower glides with a slight bob) to a world position.
	## Await it; emits move_finished when the piece arrives.
	var start := position
	if start.distance_to(world_pos) < 0.01:
		move_finished.emit()
		return
	var dir := world_pos - start
	await _face(Vector3(dir.x, 0.0, dir.z))
	if piece_type != Type.KNIGHT and _anim != null:
		_anim.play(ANIM_WALK, 0.2)
	var tw := create_tween()
	if piece_type == Type.ROOK:
		# Static tower: glide with a subtle bob, no walk cycle to play.
		var bobs := maxf(1.0, roundf(dir.length()))
		var glide := func(t: float) -> void:
			position = start.lerp(world_pos, t) \
				+ Vector3.UP * absf(sin(t * PI * bobs)) * 0.05
		tw.tween_method(glide, 0.0, 1.0, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif piece_type == Type.KNIGHT:
		# CANTER: the static horse's procedural walk — the ensemble glides
		# under a stride bob with a gentle rocking pitch; the rider rides
		# the rhythm without moving a muscle.
		var strides := maxf(1.0, roundf(dir.length()))
		var canter := func(t: float) -> void:
			position = start.lerp(world_pos, t) \
				+ Vector3.UP * absf(sin(t * PI * strides * 2.0)) * 0.03
			if _model != null:
				_model.rotation.x = sin(t * PI * strides * 4.0) * 0.05
		tw.tween_method(canter, 0.0, 1.0, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(self, "position", world_pos, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if piece_type == Type.KNIGHT:
		if _model != null:
			_model.rotation.x = 0.0
	elif _anim != null:
		_anim.play(ANIM_IDLE, 0.25)
	_face_home()
	move_finished.emit()


func play_capture(victim: PieceView) -> void:
	## The capture duel: face the victim, strike (Throw — the free rig's
	## best attack read — sold with a weapon-trail flash), victim takes the
	## hit and dies. When the await returns the victim is dead and freed.
	## Mounted strike (knight): the horse steps in under the rider's Throw.
	var to_victim := victim.position - position
	await _face(Vector3(to_victim.x, 0.0, to_victim.z))
	victim.face_attacker(position)
	if _anim != null:
		if piece_type == Type.KNIGHT:
			_horse_step(to_victim)   # concurrent step-in while the rider strikes
		_anim.play(ANIM_THROW, 0.1)
		_anim.speed_scale = 1.3
		await get_tree().create_timer(0.5 / 1.3).timeout  # strike release beat
	else:
		await _tower_lunge(to_victim)
	_strike_flash(victim.position)
	await victim.die()
	if _anim != null:
		_anim.speed_scale = 1.0
		if piece_type == Type.KNIGHT:
			_reseat_rider()   # back to the still saddle pose, horse idles on
		else:
			_anim.play(ANIM_IDLE, 0.3)


func die() -> void:
	## Hit reaction, death animation, then the corpse sinks into the stone.
	## Emits died (with death_anim set) before freeing. Mounted death
	## (knight): the rider plays Death_A and tumbles out of the saddle while
	## the horse collapses through its own Death clip — same wall budget.
	if _anim != null:
		_anim.play(ANIM_HIT, 0.1)
		_anim.speed_scale = 1.2
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_HIT) / 1.2 - 0.1).timeout
		_anim.speed_scale = 1.0
		_anim.play(ANIM_DEATH, 0.1)
		death_anim = ANIM_DEATH
		if piece_type == Type.KNIGHT:
			_mounted_fall(PieceAssets.anim_length(ANIM_DEATH))   # concurrent
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_DEATH)).timeout
	else:
		death_anim = "Tower_Crumble"
		_drop_banner()   # the banner tears free and falls with the tower
		var fall := create_tween()
		fall.tween_property(self, "rotation:z", rotation.z + PI * 0.28, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await fall.finished
	var sink := create_tween()
	sink.tween_property(self, "position:y", position.y - 1.3, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await sink.finished
	died.emit()
	queue_free()


func spawn_flourish() -> void:
	## Promotion arrival: Spawn_Ground plus an amber light burst. The
	## mounted knight's rider stays seated — the ensemble gives a hop.
	if piece_type == Type.KNIGHT:
		if _model != null:
			var hop := create_tween()
			hop.tween_property(_model, "position:y", 0.06, 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			hop.tween_property(_model, "position:y", 0.0, 0.22) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	elif _anim != null:
		_anim.play(ANIM_SPAWN, 0.05)
	var burst := OmniLight3D.new()
	burst.light_color = Color(1.0, 0.72, 0.35)
	burst.light_energy = 0.0
	burst.omni_range = 2.6
	burst.position = Vector3(0.0, 0.7, 0.0)
	add_child(burst)
	var tw := create_tween()
	tw.tween_property(burst, "light_energy", 4.5, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(burst, "light_energy", 0.0, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(burst.queue_free)
	if piece_type != Type.KNIGHT and _anim != null:
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_SPAWN)).timeout
		_anim.play(ANIM_IDLE, 0.3)


func face_attacker(attacker_pos: Vector3) -> void:
	var dir := attacker_pos - position
	_face(Vector3(dir.x, 0.0, dir.z))  # fire-and-forget turn


# -- internals -------------------------------------------------------------


func _face(dir: Vector3) -> void:
	## Smooth-turn to look along dir (world space). Awaitable.
	if dir.length_squared() < 0.0001 or piece_type == Type.ROOK:
		return
	var target_yaw := atan2(dir.x, dir.z)
	if absf(wrapf(target_yaw - rotation.y, -PI, PI)) < 0.05:
		return
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", target_yaw, 0.14).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _face_home() -> void:
	if piece_type == Type.ROOK:
		return
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", _home_yaw, 0.18).set_trans(Tween.TRANS_SINE)


func _horse_step(to_victim: Vector3) -> void:
	## Mounted strike: the horse steps into the blow while the rider throws
	## — the whole ensemble advances and settles back. Fire-and-forget; the
	## step-back plays out under the victim's death.
	var dir := Vector3(to_victim.x, 0.0, to_victim.z).normalized()
	var start := position
	var tw := create_tween()
	tw.tween_property(self, "position", start + dir * 0.2, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", start, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _mounted_fall(window: float) -> void:
	## The knight's death, run concurrently with the rider's Death_A: the
	## rider tumbles out of the saddle to the ground on one side while the
	## horse keels over to the other, saddle and caparison riding it down
	## (they live inside the horse scene). The whole-piece sink in die()
	## then swallows the wreck.
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	if _rider != null:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_rider, "position",
				KNIGHT_RIDER_POS + KNIGHT_FALL_OFFSET, window * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_rider, "rotation:z", -0.4, window * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _horse != null:
		var htw := create_tween().set_parallel(true)
		htw.tween_property(_horse, "rotation:z", 1.35, window * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		htw.tween_property(_horse, "position",
				_horse.position + Vector3(-0.35, 0.0, 0.0), window * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _reseat_rider() -> void:
	## After a mounted strike the rider settles back into the still saddle
	## pose: blend to a neutral idle frame, freeze it, re-bend the seat.
	if _anim == null:
		return
	_anim.play(ANIM_IDLE, 0.25)
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(0.35).timeout
	if _anim == null or not is_inside_tree():
		return
	_anim.pause()
	_apply_seat_pose()


## The static seat, calibrated against measured bone positions (rider-local,
## hips at y 0.39): knees forward and level with the hips, shins hanging
## down-back with the heels under the knee, thighs splayed outward over the
## barrel, arms down at the reins line.
##   SEAT_THIGH  local-X on upperleg.*  — negative swings the knee forward/up
##   SEAT_SHIN   local-X on lowerleg.*  — positive drops the heel back down
##   SEAT_SPLAY  local-Z on upperleg.*  — NEGATIVE opens the legs outward
## Manual bone poses persist because the rider's player is PAUSED while
## mounted — duel clips (Throw/Hit/Death) override them for exactly as long
## as they play, and _reseat_rider re-applies the seat afterwards.
const SEAT_THIGH := -45.0
const SEAT_SHIN := 50.0
const SEAT_SPLAY := -40.0
const SEAT_UPPERARM := 64.0
const SEAT_LOWERARM := -30.0


func _apply_seat_pose() -> void:
	var skel := _skeleton()
	if skel == null:
		return
	for side_key in ["l", "r"]:
		var flip := 1.0 if side_key == "l" else -1.0
		var seat := {
			"upperleg." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_THIGH))
				* Quaternion(Vector3.BACK, deg_to_rad(SEAT_SPLAY * flip)),
			"lowerleg." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_SHIN)),
			"upperarm." + side_key: Quaternion(Vector3.BACK, deg_to_rad(SEAT_UPPERARM * flip)),
			"lowerarm." + side_key: Quaternion(Vector3.RIGHT, deg_to_rad(SEAT_LOWERARM)),
		}
		for bone_name in seat:
			var idx := skel.find_bone(bone_name)
			if idx != -1:
				skel.set_bone_pose_rotation(idx,
						skel.get_bone_rest(idx).basis.get_rotation_quaternion()
						* seat[bone_name])


func _tower_lunge(to_victim: Vector3) -> void:
	## The rook has no skeleton: sell the strike with a heavy tilt-slam.
	var dir := Vector3(to_victim.x, 0.0, to_victim.z).normalized()
	var start := position
	var tw := create_tween()
	tw.tween_property(self, "position", start + dir * 0.22 + Vector3.UP * 0.12, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position", start, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func _strike_flash(victim_pos: Vector3) -> void:
	## Quick weapon-trail flash between attacker and victim.
	var mid := (victim_pos - position) * 0.5 + Vector3(0.0, 0.55, 0.0)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.85, 0.22)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = mid
	quad.rotation.z = randf_range(-0.5, 0.5)
	add_child(quad)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(quad, "scale", Vector3(1.6, 0.4, 1.0), 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.24)
	tw.chain().tween_callback(quad.queue_free)


# -- construction ----------------------------------------------------------


func _build_character() -> void:
	_model = PieceAssets.character_scene(piece_type, house_id).instantiate()
	_model.name = "Model"
	# Strict height grading: normalize each model's raw height to the type's
	# design height, so pawn<knight<bishop<rook<queen<king holds no matter
	# which cast (adventurer or skeleton) a house fields.
	var raw_h := _raw_model_height(_model)
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	add_child(_model)
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)  # root_node ".." = the character scene root
	_anim.add_animation_library("", PieceAssets.shared_anims())
	_tint_meshes(_model, _tint_for("piece"), _saturation_for())
	# Gear/crest/crown attach AFTER _tint_meshes so they keep their own colors.
	_attach_gear()
	if PieceAssets.wants_crest(piece_type):
		_attach_crest()
	if piece_type == Type.KING:
		_attach_crown()
		_attach_cape()
	elif piece_type == Type.QUEEN:
		_attach_tiara()
	_anim.play(ANIM_IDLE)
	# Desynchronize the armies' idles.
	_anim.seek(randf() * PieceAssets.anim_length(ANIM_IDLE))
	_anim.speed_scale = randf_range(0.94, 1.06)


func _build_knight() -> void:
	## The MOUNTED knight (ISSUES.md #1): a horse+rider ensemble under one
	## Model root. The Quaternius horse is a static standing mesh animated
	## procedurally (see the class doc); the KayKit rider (adventurer or
	## Tidegrip skeleton — same casting table) sits a fixed transform in the
	## authored saddle, statically seat-posed. The Model carries the
	## quarter-turn reined stance (KNIGHT_MODEL_YAW) so the ensemble reads
	## as cavalry from the head-on gameplay camera while the ROOT still
	## points at the enemy line (and at duel victims). Height grading
	## normalizes the ENSEMBLE: the rider's helm is the reference point
	## (his crest, like the rook's pennant, is an accent above it).
	_model = Node3D.new()
	_model.name = "Model"
	_model.rotation.y = deg_to_rad(KNIGHT_MODEL_YAW)   # the reined-in stance
	add_child(_model)
	_horse = PieceAssets.HORSE.instantiate()
	_horse.name = "Horse"
	_horse.scale = Vector3.ONE * KNIGHT_HORSE_SCALE
	_model.add_child(_horse)
	_rider = PieceAssets.character_scene(piece_type, house_id).instantiate()
	_rider.name = "Rider"
	_rider.position = KNIGHT_RIDER_POS
	_model.add_child(_rider)
	var raw_h := KNIGHT_RIDER_POS.y + _raw_model_height(_rider)
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_rider.add_child(_anim)  # root_node ".." = the rider scene root
	_anim.add_animation_library("", PieceAssets.shared_anims())
	# Palette: rider tinted like any character; the mount DYED into the house
	# colors (charred near-dark under the Drowned Legion) so no army fields a
	# stock brown horse; the tack never — the caparison is dressed in the
	# house banner cloth below and the saddle keeps its leather.
	_tint_meshes(_rider, _tint_for("piece"), _saturation_for())
	var horse_tint := _tint_for("piece")
	if house_id == PieceAssets.SKELETON_HOUSE:
		horse_tint = horse_tint.darkened(0.32)   # charred, but still a horse
	_dye_mount(horse_tint)
	_dress_caparison()
	# Gear/crest attach AFTER the tints so they keep their own colors.
	_attach_gear()
	if PieceAssets.wants_crest(piece_type):
		_attach_crest()
	# The mount breathes (procedural sway, desynced); the rider sits STILL
	# — his player parks on a neutral frame and the seat pose bends him in.
	_start_idle_sway()
	_anim.play(ANIM_IDLE)
	_anim.advance(0.0)
	_anim.pause()
	_apply_seat_pose()


## The static horse's idle: a slow weight-shift sway on the ensemble root,
## randomized per piece so the armies never breathe in lockstep.
func _start_idle_sway() -> void:
	if _sway_tween != null:
		_sway_tween.kill()
	var amp := randf_range(0.010, 0.016)
	var half := randf_range(1.3, 1.8)
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_model, "rotation:z", amp, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_model, "rotation:z", -amp, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## HOUSE flourish: the mount wears its house's colors in the hide itself
## (PieceAssets.dyed_mount_material — the pack's untextured browns survive a
## multiply-tint unchanged, so they are re-dyed by luminance instead). Tack
## is excluded: the caparison gets the banner cloth, the saddle its leather.
## The eyes keep their own paint — a blue-eyed horse is a horse, a horse with
## house-colored eyeballs is a bug.
func _dye_mount(tint: Color) -> void:
	for mi: MeshInstance3D in _horse.find_children("*", "MeshInstance3D", true, false):
		if mi.name in ["Caparison", "Saddle"]:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src == null or not src is StandardMaterial3D:
				continue
			if str(src.resource_name).begins_with("Eye"):
				continue
			mi.set_surface_override_material(
				s, PieceAssets.dyed_mount_material(src, tint))


## HOUSE flourish: the knight's caparison wears the house banner cloth —
## primary-dyed, accent hem, the sigil reading on the horse's flank (the
## same composited texture the rook's banner flies; v=0 is the cloth TOP,
## matching the caparison's UVs). Legacy sides get plain dyed cloth.
func _dress_caparison() -> void:
	var cap := _model.find_child("Caparison", true, false) as MeshInstance3D
	if cap == null:
		return
	var mat := StandardMaterial3D.new()
	if HouseRegistry.has_house(house_id):
		mat.albedo_texture = PieceAssets.banner_texture(house_id)
	else:
		mat.albedo_color = HOUSE_TINT[side].darkened(0.12)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cap.material_override = mat


## Raw (unscaled) model height: top of the skinned meshes parented directly
## to the Skeleton3D. BoneAttachment3D accessories (hats, hoods) are
## excluded — their mesh AABBs live in bone space, not model space.
func _raw_model_height(model: Node3D) -> float:
	var top := 0.0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is BoneAttachment3D:
			continue
		top = maxf(top, mi.mesh.get_aabb().end.y)
	return top


func _skeleton() -> Skeleton3D:
	## The CHARACTER's rig — for the mounted knight that is the RIDER's
	## skeleton (the horse has its own; gear/crest/pose never touch it).
	var host: Node3D = _rider if _rider != null else _model
	var skels := host.find_children("*", "Skeleton3D", true, false)
	return null if skels.is_empty() else skels[0]


## Rigid mount on a rig bone (the crown-attach pattern, generalized).
func _bone_mount(bone: String, mount_name: String) -> BoneAttachment3D:
	var skel := _skeleton()
	if skel == null or skel.find_bone(bone) == -1:
		return null
	var att := BoneAttachment3D.new()
	att.name = mount_name
	att.bone_name = bone
	skel.add_child(att)
	return att


## TYPE signature gear: rigid props on the rig's handslot/chest bones.
## Same gear for every house — the type IS the gear.
func _attach_gear() -> void:
	for spec: Dictionary in PieceAssets.gear_specs(piece_type):
		var att := _bone_mount(spec["bone"], "GearMount_%s" % spec["key"])
		if att == null:
			continue
		var prop: Node3D = (spec["scene"] as PackedScene).instantiate()
		prop.name = "Gear_%s" % spec["key"]
		prop.position = spec["pos"]
		prop.rotation_degrees = spec["rot_deg"]
		prop.scale = Vector3.ONE * float(spec["scl"])
		att.add_child(prop)
		if bool(spec["decal"]) and HouseRegistry.has_house(house_id):
			_attach_sigil_decal(prop, spec)


## HOUSE flourish: the house sigil painted on the shield face.
func _attach_sigil_decal(shield: Node3D, spec: Dictionary) -> void:
	var decal := MeshInstance3D.new()
	decal.name = "SigilDecal"
	var quad := QuadMesh.new()
	var s := float(spec.get("decal_size", 0.5))
	quad.size = Vector2(s, s)
	decal.mesh = quad
	decal.material_override = PieceAssets.sigil_material(house_id)
	decal.position = spec.get("decal_pos", Vector3(0.0, 0.0, 0.2))
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.add_child(decal)


## HOUSE flourish: helmet crest on the head bone (knight/queen/king).
func _attach_crest() -> void:
	var packed: PackedScene = PieceAssets.crest_scene(house_id)
	if packed == null:
		return
	var att := _bone_mount("head", "CrestMount")
	if att == null:
		return
	var crest: Node3D = packed.instantiate()
	crest.name = "Crest"
	crest.position = CREST_MOUNT_POS
	att.add_child(crest)


func _attach_crown() -> void:
	## The king's crown (custom prop — measured numbers from the props'
	## INTEGRATION.md): a BoneAttachment3D on the Rig_Medium `head` bone so
	## the crown tracks idle, walk, and death animations for free. Attached
	## AFTER _tint_meshes so the crown keeps its own gold/frost materials.
	var att := _bone_mount("head", "CrownMount")
	if att == null:
		return
	var crown: Node3D = PieceAssets.crown_scene(_tint_for("piece")).instantiate()
	crown.name = "Crown"
	crown.position = Vector3(0.0, 0.80, 0.0)   # ring at the brow line
	crown.rotation.y = deg_to_rad(-20.0)       # battle-bent point toward the camera
	crown.scale = Vector3.ONE * 5.3            # 0.18 m prop on the stylized skull
	att.add_child(crown)


func _attach_tiara() -> void:
	## The queen's circlet (royal swap 2026-08-08): the same gold/frost crown
	## prop, scaled visibly slimmer and flatter — a light tiara band, never
	## mistakable for the king's full crown at gameplay distance. Named
	## "Tiara" (NOT "Crown") — e2e board-truth proves queens uncrowned by
	## grepping for a node named Crown.
	var att := _bone_mount("head", "TiaraMount")
	if att == null:
		return
	var tiara: Node3D = PieceAssets.crown_scene(_tint_for("piece")).instantiate()
	tiara.name = "Tiara"
	tiara.position = Vector3(0.0, 0.84, 0.0)   # band at the brow line
	tiara.scale = Vector3(3.9, 2.1, 3.9)       # slim ring, points flattened
	# The crown GLB's INTERNAL nodes are also named Crown* — rename them or
	# the queen reads "crowned" to every Crown-node check (e2e board-truth,
	# the costume validator). The name IS the contract.
	for child in tiara.find_children("*", "", true, false):
		if str(child.name).containsn("crown"):
			child.name = str(child.name).replacen("crown", "TiaraBand")
	att.add_child(tiara)


## TYPE signature gear (king): the cape, draped from the chest bone.
## Neutral cloth in the GLB; tinted here with the house secondary color
## (palette flourish only — the cape shape is the same for every house).
func _attach_cape() -> void:
	var att := _bone_mount("chest", "CapeMount")
	if att == null:
		return
	var cape: Node3D = PieceAssets.CAPE.instantiate()
	cape.name = "Cape"
	cape.position = CAPE_MOUNT_POS
	att.add_child(cape)
	var cape_tint: Color = HOUSE_TINT[side]
	if HouseRegistry.has_house(house_id):
		cape_tint = HouseRegistry.get_colors(house_id)["secondary"]
	_tint_meshes(cape, cape_tint, _saturation_for())


## TYPE readability: the engraved glyph ring under the piece. Child of the
## PieceView root (not the model) so height grading never rescales it.
## Built HIDDEN (transparency 1, invisible) — hover/selection reveal it.
func _build_glyph_ring() -> void:
	_glyph_ring = PieceAssets.glyph_ring_scene(piece_type).instantiate()
	_glyph_ring.name = "GlyphRing"
	_glyph_ring.position = Vector3(0.0, 0.002, 0.0)
	add_child(_glyph_ring)
	# Per-piece duplicate of the emissive glyph material so selection can
	# brighten THIS ring only.
	for mi: MeshInstance3D in _glyph_ring.find_children("*", "MeshInstance3D", true, false):
		_ring_meshes.append(mi)
		mi.transparency = 1.0   # hidden at rest (ISSUES.md #2)
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D \
					and src.resource_name == PieceAssets.GLYPH_MATERIAL_NAME:
				_glyph_mat = (src as StandardMaterial3D).duplicate()
				_glyph_mat.emission_energy_multiplier = PieceAssets.GLYPH_ENERGY_REST
				mi.set_surface_override_material(s, _glyph_mat)
	_glyph_ring.visible = false


func _build_tower() -> void:
	## The BANNER-ROOK: battle-worn watchtower, house banner down the face,
	## fluttering pennant on top (assets/custom-props/watchtower.glb).
	_model = PieceAssets.WATCHTOWER.instantiate()
	_model.name = "Model"
	var body := _model.find_child("TowerBody", true, false) as MeshInstance3D
	var raw_h := body.mesh.get_aabb().end.y if body != null else 1.35
	_model.scale = Vector3.ONE * (PieceAssets.piece_height(piece_type) / maxf(raw_h, 0.01))
	add_child(_model)
	# House tint on the masonry/wood only — banner and pennant carry the
	# house colors directly and are re-skinned below.
	_tint_meshes(_model, _tint_for("tower"), _saturation_for(),
			["BannerCloth", "Pennant"])
	_dress_banner()
	_dress_pennant()


func _dress_banner() -> void:
	var banner := _model.find_child("BannerCloth", true, false) as MeshInstance3D
	if banner == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PieceAssets.banner_texture(house_id)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	banner.material_override = mat


func _dress_pennant() -> void:
	var pennant := _model.find_child("Pennant", true, false) as MeshInstance3D
	if pennant == null:
		return
	var cloth: Color = HOUSE_TINT[side]
	if HouseRegistry.has_house(house_id):
		cloth = HouseRegistry.get_colors(house_id)["accent"]
	var mat := ShaderMaterial.new()
	mat.shader = PieceAssets.PENNANT_SHADER
	mat.set_shader_parameter("cloth_color", cloth)
	pennant.material_override = mat


func _drop_banner() -> void:
	## Crumble flourish: the banner tears off and falls with the tower.
	if _model == null:
		return
	var banner := _model.find_child("BannerCloth", true, false) as MeshInstance3D
	var holder := get_parent()
	if banner == null or holder == null:
		return
	var xform := banner.global_transform
	banner.get_parent().remove_child(banner)
	holder.add_child(banner)
	banner.global_transform = xform
	var mat := banner.material_override as StandardMaterial3D
	if mat != null:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := banner.create_tween().set_parallel(true)
	tw.tween_property(banner, "position:y", banner.position.y - 0.55, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(banner, "rotation:x", banner.rotation.x - 0.9, 0.7)
	if mat != null:
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(banner.queue_free)


## The multiply tint for this piece: HouseRegistry colors when a house id was
## given, the legacy FROST/EMBER consts otherwise.
func _tint_for(role: String) -> Color:
	if house_id.is_empty():
		return HOUSE_TINT[side] if role == "piece" else HOUSE_TINT_TOWER[side]
	return HouseRegistry.get_house_tint(house_id, role)


func _saturation_for() -> float:
	if house_id.is_empty():
		return TINT_SATURATION
	return HouseRegistry.get_tint_saturation(house_id)


func _tint_meshes(root: Node, tint: Color, saturation: float,
		skip_names: Array = []) -> void:
	## Per-side material overlay: multiply the pack's albedo texture by the
	## house tint, push roughness up. Tinted materials are cached and shared.
	## skip_names: MeshInstance3D names left untouched (banner, pennant).
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name in skip_names:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src == null or not src is StandardMaterial3D:
				continue
			mi.set_surface_override_material(
				s, PieceAssets.tinted_material(src, tint, saturation))
