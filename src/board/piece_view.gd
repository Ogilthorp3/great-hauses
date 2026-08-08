class_name PieceView
extends Node3D
## A Great Houses combatant on the board — a real KayKit character (or a
## Kenney castle tower for the rook), tinted per house, animated from the
## shared Rig_Medium animation libraries.
##
## Model-agnostic API (callers touch nothing else):
##   setup(type, side) · move_to(world_pos, walk_time) ·
##   play_capture(victim) · die() · spawn_flourish()

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

const CHARACTER_SCENES := {
	Type.PAWN: preload("res://assets/kaykit-adventurers/Barbarian.glb"),
	Type.KNIGHT: preload("res://assets/kaykit-adventurers/Knight.glb"),
	Type.BISHOP: preload("res://assets/kaykit-adventurers/Mage.glb"),
	Type.QUEEN: preload("res://assets/kaykit-adventurers/Ranger.glb"),
	Type.KING: preload("res://assets/kaykit-adventurers/Rogue_Hooded.glb"),
}
const TOWER_BASE := preload("res://assets/kenney-castle-kit/tower-square-base.glb")
const TOWER_TOP := preload("res://assets/kenney-castle-kit/tower-square-top.glb")

const ANIM_IDLE := "Idle_A"
const ANIM_WALK := "Walking_A"
const ANIM_THROW := "Throw"
const ANIM_HIT := "Hit_A"
const ANIM_DEATH := "Death_A"
const ANIM_SPAWN := "Spawn_Ground"

const CHARACTER_SCALE := 0.46
const KING_SCALE := 0.56       # no crown prop in the free packs — the king reads by size
const TOWER_SCALE := 0.78      # imported tower base is 1.0u tall + 0.3u crenellated top

var piece_type: Type = Type.PAWN
var side: House = House.FROST
## Set just before `died` fires — e2e reads it to prove a death anim played.
var death_anim := ""

var _model: Node3D
var _anim: AnimationPlayer  # null for the rook (static tower)
var _home_yaw := 0.0


func setup(new_type: Type, new_side: House) -> void:
	piece_type = new_type
	side = new_side
	for child in get_children():
		child.queue_free()
	_anim = null
	if piece_type == Type.ROOK:
		_build_tower()
	else:
		_build_character()
	# Face the enemy line: Frost looks +Z (toward Ember), Ember looks -Z.
	_home_yaw = 0.0 if side == House.FROST else PI
	rotation.y = _home_yaw


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
	if _anim != null:
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
	else:
		tw.tween_property(self, "position", world_pos, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _anim != null:
		_anim.play(ANIM_IDLE, 0.25)
	_face_home()
	move_finished.emit()


func play_capture(victim: PieceView) -> void:
	## The capture duel: face the victim, strike (Throw — the free rig's
	## best attack read — sold with a weapon-trail flash), victim takes the
	## hit and dies. When the await returns the victim is dead and freed.
	var to_victim := victim.position - position
	await _face(Vector3(to_victim.x, 0.0, to_victim.z))
	victim.face_attacker(position)
	if _anim != null:
		_anim.play(ANIM_THROW, 0.1)
		_anim.speed_scale = 1.3
		await get_tree().create_timer(0.5 / 1.3).timeout  # strike release beat
	else:
		await _tower_lunge(to_victim)
	_strike_flash(victim.position)
	await victim.die()
	if _anim != null:
		_anim.speed_scale = 1.0
		_anim.play(ANIM_IDLE, 0.3)


func die() -> void:
	## Hit reaction, death animation, then the corpse sinks into the stone.
	## Emits died (with death_anim set) before freeing.
	if _anim != null:
		_anim.play(ANIM_HIT, 0.1)
		_anim.speed_scale = 1.2
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_HIT) / 1.2 - 0.1).timeout
		_anim.speed_scale = 1.0
		_anim.play(ANIM_DEATH, 0.1)
		death_anim = ANIM_DEATH
		await get_tree().create_timer(PieceAssets.anim_length(ANIM_DEATH)).timeout
	else:
		death_anim = "Tower_Crumble"
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
	## Promotion arrival: Spawn_Ground plus an amber light burst.
	if _anim != null:
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
	if _anim != null:
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
	_model = CHARACTER_SCENES[piece_type].instantiate()
	_model.name = "Model"
	var s := KING_SCALE if piece_type == Type.KING else CHARACTER_SCALE
	_model.scale = Vector3.ONE * s
	add_child(_model)
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	_model.add_child(_anim)  # root_node ".." = the character scene root
	_anim.add_animation_library("", PieceAssets.shared_anims())
	_tint_meshes(_model, HOUSE_TINT[side])
	_anim.play(ANIM_IDLE)
	# Desynchronize the armies' idles.
	_anim.seek(randf() * PieceAssets.anim_length(ANIM_IDLE))
	_anim.speed_scale = randf_range(0.94, 1.06)


func _build_tower() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	var base := TOWER_BASE.instantiate()
	var top := TOWER_TOP.instantiate()
	top.position.y = 1.0  # stack the crenellated top on the 1u-tall base
	_model.add_child(base)
	_model.add_child(top)
	_model.scale = Vector3.ONE * TOWER_SCALE
	add_child(_model)
	_tint_meshes(_model, HOUSE_TINT_TOWER[side])


func _tint_meshes(root: Node, tint: Color) -> void:
	## Per-side material overlay: multiply the pack's albedo texture by the
	## house tint, push roughness up. Tinted materials are cached and shared.
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src == null or not src is StandardMaterial3D:
				continue
			mi.set_surface_override_material(
				s, PieceAssets.tinted_material(src, tint, TINT_SATURATION))
