extends Node3D
## TRIAL BY FIRE — what happens to a bannerman the wildfire reaches.
##
## THE RECIPE IS NOT MINE. src/cinematics/dragon_spectator.gd's `_incinerate`
## already solved this exact problem for the ashfall ceremony, and it solved it
## well: ignition flash -> the flesh burns off and a CHARRED KAYKIT SKELETON
## stands in the dead man's exact spot and facing -> a smouldering beat under
## thin wisps -> Death_A off the shared Rig_Medium library -> the bones sink
## into the stone. The swap is the whole trick: a piece that merely tints to
## charcoal reads as a recolour, and a piece that vanishes reads as a bug, but a
## man who becomes his own skeleton and THEN falls over reads as a man who
## burned. This module is that sequence, re-implemented here because the
## spectator's copy is private to its ceremony (it is driven by that class's
## sequence counter and skip machinery, neither of which exists in an arena),
## and retuned in three ways for this mode:
##
##   * GREEN. The flash and the dying glow are wildfire, not dragonfire — the
##     arena's whole colour contract (see arena_fx.gd).
##   * FASTER. The ceremony can spend 2.4 s on one warrior because nothing else
##     is happening. Here a chain can take six crates at once while two kings
##     are running for their lives, so the whole sequence fits in ~1.1 s and the
##     collapse starts while the fire is still up.
##   * FIRE-AND-FORGET. No sequence id, no skip: an arena teardown frees the
##     whole subtree, and every await checks is_instance_valid first.
##
## Emissive materials only — no Light3D on any path (the hall's eight omnis are
## the eight torches and the suites count them).

const RigScript := preload("res://src/cinematics/dragon_rig.gd")

## The charred cast, keyed by PieceView.Type. A LOCAL table, exactly as
## dragon_spectator keeps its own: PieceAssets is another lane's file and a
## presentation module does not get to add rows to it. Anything unlisted rises
## as a Rogue.
const SKELETONS := {
	0: preload("res://assets/kaykit-skeletons/Skeleton_Minion.glb"),   # pawn
	2: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # knight
	3: preload("res://assets/kaykit-skeletons/Skeleton_Mage.glb"),     # bishop
	4: preload("res://assets/kaykit-skeletons/Skeleton_Rogue.glb"),    # queen
	5: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # king
}
const SKELETON_DEFAULT: PackedScene = preload("res://assets/kaykit-skeletons/Skeleton_Rogue.glb")

const CHARCOAL := Color(0.075, 0.072, 0.068)
## THE HEAT IS WHITE-GREEN, THE EMBER IS DIM. Both were louder (1.35 and 0.62
## on green) and photographed as flat LIME BLOBS the size of a pawn: at that
## saturation the emission swamps the model and there is no skeleton to see,
## which throws away the entire point of the swap. A burning man is white-hot
## and a charred one is BLACK with a little life left in him.
const WILD_FLASH := Color(0.85, 1.15, 0.80)   ## the ignition — heat, not paint
const WILD_EMBER := Color(0.10, 0.40, 0.16)   ## the glow that cools in the bone

const FLASH_SEC := 0.13
const SMOULDER_SEC := 0.42
const COLLAPSE_SEC := 0.62
const SINK_SEC := 0.40

var _live: Array = []    ## every skeleton on the field, for teardown


## Burn one crate. `piece` is duck-typed: anything Node3D with an int
## `piece_type` works, which is what lets the headless mocks exercise it.
## Fire-and-forget; the piece is freed by this call's own coroutine.
func burn(piece: Node3D) -> void:
	if not is_instance_valid(piece):
		return
	var runner := func() -> void:
		var mats := _own_materials(piece)
		# 1. THE FLASH — every surface goes white-green hot.
		await _lerp(FLASH_SEC, func(f: float) -> void:
			if not is_instance_valid(piece):
				return
			for e in mats:
				var m: StandardMaterial3D = e[0]
				m.emission_enabled = true
				m.emission = WILD_FLASH * (0.4 + 2.6 * f))
		if not is_instance_valid(piece):
			return
		# 2. THE SWAP — same square, same facing, and a skeleton where he stood.
		var shell := _stand_remains(piece)
		piece.queue_free()
		if shell == null:
			return
		# 3. THE SMOULDER — a beat of stillness, then he goes down.
		await _wait(SMOULDER_SEC)
		await _collapse(shell)
	runner.call()


## Free every skeleton still on the field (arena reset / scene teardown).
func clear() -> void:
	for shell in _live:
		if is_instance_valid(shell):
			shell.queue_free()
	_live.clear()


func remains_count() -> int:
	var n := 0
	for shell in _live:
		if is_instance_valid(shell):
			n += 1
	return n


func _exit_tree() -> void:
	clear()


# ── internals ───────────────────────────────────────────────────────────────


## Duplicate every surface material so the fire owns its own copy — PieceAssets
## hands out CACHED, SHARED materials and charring one in place would char every
## piece of that house wearing it. (The same note dragon_spectator carries; it
## is the kind of bug that only shows up on the second victim.)
func _own_materials(node: Node3D) -> Array:
	var mats: Array = []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
			mi.material_override = m
			mats.append([m, m.albedo_color])
			continue
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m2: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				mi.set_surface_override_material(s, m2)
				mats.append([m2, m2.albedo_color])
	return mats


func _stand_remains(piece: Node3D) -> Node3D:
	var parent := piece.get_parent()
	if parent == null or not is_instance_valid(parent):
		return null
	var victim_h := _height_of(piece)
	var pt = piece.get("piece_type")
	var packed: PackedScene = SKELETONS.get(
		int(pt) if typeof(pt) == TYPE_INT else -1, SKELETON_DEFAULT)
	var shell := Node3D.new()
	shell.name = "Charred"
	parent.add_child(shell)
	shell.global_position = piece.global_position
	shell.rotation.y = piece.global_rotation.y   # he falls facing where he stood
	var model := packed.instantiate()
	model.name = "Bones"
	shell.add_child(model)
	model.scale = Vector3.ONE * (victim_h / maxf(_height_of(model), 0.01))
	var mats := _own_materials(model)
	for e in mats:
		var m: StandardMaterial3D = e[0]
		m.albedo_color = CHARCOAL
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission = WILD_EMBER * 0.30
	var ap := _shared_anims(model)
	if ap != null and ap.has_animation("Idle_A"):
		ap.play("Idle_A")
		ap.speed_scale = 0.35   # dazed, smoking, about to fall
	var smoke := RigScript.spawn_emitter(shell, "Smoulder", {
		"amount": 10, "lifetime": 1.3, "size": 0.2,
		"velocity": Vector2(0.4, 0.95), "spread": 16.0,
		"direction": Vector3(0.0, 1.0, 0.0),
		"gravity": Vector3(0.0, 0.6, 0.0), "grow": 1.9,
		"ramp": [
			[0.0, Color(0.20, 0.26, 0.21, 0.0)],
			[0.25, Color(0.14, 0.16, 0.14, 0.30)],
			[1.0, Color(0.07, 0.08, 0.07, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	})
	smoke.position = Vector3.UP * (victim_h * 0.55)
	smoke.emitting = true
	shell.set_meta("mats", mats)
	shell.set_meta("anim", ap)
	shell.set_meta("smoke", smoke)
	_live.append(shell)
	return shell


func _collapse(shell: Node3D) -> void:
	if not is_instance_valid(shell):
		return
	var ap: AnimationPlayer = shell.get_meta("anim")
	if ap != null and is_instance_valid(ap) and ap.has_animation("Death_A"):
		# Retimed to the arena's budget: the ceremony can afford a slow fall,
		# a firefight cannot.
		ap.speed_scale = ap.get_animation("Death_A").length / COLLAPSE_SEC
		ap.play("Death_A", 0.08)
		await _wait(COLLAPSE_SEC)
	else:
		# No shared library (headless unit runs): tilt it over instead. The
		# module must still WORK with no autoloads, or it cannot be tested.
		var r0 := shell.rotation
		var tilt := Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.4, 0.4))
		await _lerp(COLLAPSE_SEC, func(f: float) -> void:
			if is_instance_valid(shell):
				shell.rotation = r0 + tilt * f)
	if not is_instance_valid(shell):
		return
	var smoke = shell.get_meta("smoke")
	if is_instance_valid(smoke):
		smoke.emitting = false
	var p0 := shell.position
	var mats: Array = shell.get_meta("mats")
	await _lerp(SINK_SEC, func(f: float) -> void:
		if not is_instance_valid(shell):
			return
		shell.position = p0 + Vector3.DOWN * (0.85 * f * f)
		shell.scale = Vector3.ONE * (1.0 - 0.22 * f)
		for e in mats:
			var m: StandardMaterial3D = e[0]
			m.emission = WILD_EMBER * 0.30 * (1.0 - f))
	_live.erase(shell)
	if is_instance_valid(shell):
		shell.queue_free()


## The shared Rig_Medium library, duck-fetched off the PieceAssets autoload and
## never referenced by name: a headless `-s` run has no autoloads and this
## module still has to compile and run there.
func _shared_anims(model: Node) -> AnimationPlayer:
	var pa := get_node_or_null("/root/PieceAssets")
	if pa == null or not pa.has_method("shared_anims"):
		return null
	var lib: AnimationLibrary = pa.shared_anims()
	if lib == null:
		return null
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	model.add_child(ap)
	ap.add_animation_library("", lib)
	return ap


func _height_of(node: Node3D) -> float:
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


## Wall-clock lerp. WALL, not engine: nothing in this mode bends time_scale, but
## a caller that does (a victory slow-mo, say) must not stretch the fire.
func _lerp(dur: float, setter: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(self) and is_inside_tree():
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		setter.call(u)
		if u >= 1.0:
			return
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await _lerp(sec, func(_u: float) -> void: pass)
