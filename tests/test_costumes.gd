extends SceneTree

# Headless suite for the HOUSE COSTUMES + PIECE READABILITY + BANNER-ROOK
# + MOUNTED-KNIGHT module: assembly correctness (right gear per type, right
# crest per house, skeleton cast only for Tidegrip, glyph ring present,
# horse+saddle+caparison under every knight), strict height-grading
# monotonicity, rig retarget compatibility for the skeleton cast, glyph-ring
# selection feedback, the banner-rook crumble path, and the mounted knight's
# duel choreography (step-in capture, rider-falls death, face-to-face turn).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_costumes.gd
# Exit code 0 = all green, 1 = failures.
#
# NOTE deliberately NO preload/const references to PieceAssets, PieceView or
# scripts that use them: -s runs never instance autoloads, and any script
# that names the PieceAssets global fails to COMPILE until a node called
# "PieceAssets" hangs under /root. So: shim the autoload first, then load()
# everything else. This file itself only touches those APIs through Variants.

var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its await
## resumes as if it finished — so "no FAIL lines" is NOT proof the suite ran.
## This floor turns silently-aborted tests into a loud failure.
const MIN_EXPECTED_CHECKS := 140

# PieceView.Type values (int-mirrored: PAWN ROOK KNIGHT BISHOP QUEEN KING).
const T_PAWN := 0
const T_ROOK := 1
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4
const T_KING := 5
const TYPE_NAMES := ["PAWN", "ROOK", "KNIGHT", "BISHOP", "QUEEN", "KING"]
## Height-grading display order (not enum order). The MOUNTED knight
## (ISSUES.md #1) sits between bishop and rook.
const GRADE_ORDER := [T_PAWN, T_BISHOP, T_KNIGHT, T_ROOK, T_QUEEN, T_KING]
const FROST := 0
const EMBER := 1

var assets: Node          # the PieceAssets shim
var piece_scene: PackedScene
var preview: GDScript     # costume_preview.gd (shared validator)
var registry: GDScript    # houses.gd


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Houses — costumes headless suite ===")
	# Shim the PieceAssets autoload FIRST (see NOTE above), then load.
	assets = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	piece_scene = load("res://scenes/piece_view.tscn")
	preview = load("res://src/board/costume_preview.gd")
	registry = load("res://src/houses/houses.gd")
	await process_frame
	await process_frame
	_test_skeleton_rig_compat()
	_test_assembly_every_combo()
	_test_royal_casting()
	_test_shield_types()
	_test_height_grading()
	_test_glyph_orientation()
	_test_mounted_knight()
	await _test_selection_feedback()
	await _test_rook_crumble()
	await _test_knight_death()
	await _test_knight_capture()
	await _test_knight_duel_facing()
	print("---")
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	if failures == 0:
		print("COSTUMES OK — all %d checks passed" % checks_run)
	else:
		print("COSTUMES FAILED — %d of %d checks failed" % [failures, checks_run])
	quit(0 if failures == 0 else 1)


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
		print("FAIL  %-58s expected %s, got %s" % [test_name, expected, actual])


func _spawn(piece_type: int, side: int, house_id: String) -> Node:
	var pv: Node = piece_scene.instantiate()
	root.add_child(pv)
	pv.setup(piece_type, side, house_id)
	return pv


## The Drowned Legion swap only holds if the skeleton cast is genuinely the
## same rig: same skeleton path the shared anim tracks address, same bones
## (the handslot/chest/head mounts included).
func _test_skeleton_rig_compat() -> void:
	var lib: AnimationLibrary = assets.shared_anims()
	var track_root := "Rig_Medium/Skeleton3D"
	var idle: Animation = lib.get_animation("Idle_A")
	var all_tracks_ok := true
	for t in idle.get_track_count():
		if not str(idle.track_get_path(t)).begins_with(track_root):
			all_tracks_ok = false
	check("anims: every Idle_A track drives %s" % track_root, true, all_tracks_ok)
	var skeleton_scenes: Dictionary = assets.SKELETON_SCENES
	for key in skeleton_scenes:
		var inst: Node = (skeleton_scenes[key] as PackedScene).instantiate()
		var skel := inst.get_node_or_null(track_root) as Skeleton3D
		check("skeleton cast %d: has %s" % [key, track_root], true, skel != null)
		if skel != null:
			for bone in ["handslot.l", "handslot.r", "head", "chest", "hips"]:
				check("skeleton cast %d: bone %s" % [key, bone],
						true, skel.find_bone(bone) != -1)
		inst.free()


## Every house×type combo (plus legacy both sides) assembles correctly —
## the same validator the costume_preview headless gate runs.
func _test_assembly_every_combo() -> void:
	var combos: Array = []
	for hid in registry.house_ids():
		combos.append([hid, FROST])
	combos.append(["", FROST])
	combos.append(["", EMBER])
	for combo in combos:
		var errs_total: Array = []
		for t in GRADE_ORDER:
			var pv := _spawn(t, combo[1], combo[0])
			errs_total.append_array(preview.validate_piece(pv, t, combo[0]))
			pv.free()
		var label: String = combo[0] if not str(combo[0]).is_empty() \
				else "legacy-%d" % combo[1]
		check("assembly: %s full set" % label, "[]", str(errs_total))


## The royal swap (2026-08-08, user-verified in the previews): the goateed
## Ranger reads as a bearded MONARCH — he is the KING (crown + cape + sword);
## the clean-faced hooded rogue is the QUEEN (slim tiara + bow + quiver).
func _test_royal_casting() -> void:
	check("casting: king base model is the Ranger", true,
			str((assets.CHARACTER_SCENES[T_KING] as PackedScene).resource_path)
			.ends_with("Ranger.glb"))
	check("casting: queen base model is the hooded rogue", true,
			str((assets.CHARACTER_SCENES[T_QUEEN] as PackedScene).resource_path)
			.ends_with("Rogue_Hooded.glb"))
	var king := _spawn(T_KING, FROST, "winterfang")
	var queen := _spawn(T_QUEEN, FROST, "winterfang")
	check("casting: king bears a sword", true,
			king.find_child("Gear_sword", true, false) != null)
	check("casting: king wears no tiara", true,
			king.find_child("Tiara", true, false) == null)
	check("casting: queen wears the tiara, never a Crown node", true,
			queen.find_child("Tiara", true, false) != null
			and queen.find_child("Crown", true, false) == null)
	check("casting: queen keeps bow + quiver", true,
			queen.find_child("Gear_bow", true, false) != null
			and queen.find_child("Gear_quiver", true, false) != null)
	var crown := king.find_child("Crown", true, false) as Node3D
	var tiara := queen.find_child("Tiara", true, false) as Node3D
	check("casting: tiara visibly slimmer + flatter than the crown", true,
			crown != null and tiara != null
			and tiara.scale.x < crown.scale.x * 0.8
			and tiara.scale.y < crown.scale.y * 0.5)
	king.free()
	queen.free()


## Right shield per rank: pawn round, knight kite (shield_badge).
func _test_shield_types() -> void:
	var pawn := _spawn(T_PAWN, FROST, "goldclaw")
	check("pawn shield is the round shield", true,
			pawn.find_child("shield_round", true, false) != null)
	pawn.free()
	var knight := _spawn(T_KNIGHT, FROST, "goldclaw")
	check("knight shield is the kite shield", true,
			knight.find_child("shield_badge", true, false) != null)
	knight.free()


## Strict monotonic height grading pawn<knight<bishop<rook<queen<king,
## measured from the assembled models (not the config table), for the
## adventurer cast, the skeleton cast, and the legacy path.
func _test_height_grading() -> void:
	for hid in ["goldclaw", "tidegrip", ""]:
		var label: String = hid if not str(hid).is_empty() else "legacy"
		var prev := 0.0
		var monotonic := true
		var trail := ""
		for t in GRADE_ORDER:
			var pv := _spawn(t, FROST, hid)
			var h: float = preview.measured_height(pv)
			trail += "%s=%.3f " % [TYPE_NAMES[t], h]
			if h <= prev:
				monotonic = false
			# the assembled body must land on the design height
			check("%s %s: height %.2f" % [label, TYPE_NAMES[t],
					assets.piece_height(t)],
					true, absf(h - float(assets.piece_height(t))) < 0.01)
			prev = h
			pv.free()
		check("%s: heights strictly monotonic (%s)" % [label, trail.strip_edges()],
				true, monotonic)


## The glyph ring counter-rotates against the piece's home yaw so the
## engraved glyph reads upright from the player camera for BOTH armies.
func _test_glyph_orientation() -> void:
	var frost := _spawn(T_PAWN, FROST, "goldclaw")
	check("frost glyph ring yaw", true,
			absf((frost.get_node("GlyphRing") as Node3D).rotation.y) < 0.001)
	frost.free()
	var ember := _spawn(T_PAWN, EMBER, "goldclaw")
	check("ember glyph ring counter-yaw", true,
			absf((ember.get_node("GlyphRing") as Node3D).rotation.y + PI) < 0.001)
	ember.free()


## The MOUNTED knight (ISSUES.md #1): horse+rider ensemble per house — the
## horse under him with saddle and house-dressed caparison, the rider (the
## house's cast: adventurer, or Tidegrip skeleton on the charred horse)
## seated STILL in the saddle with his signature gear and his house crest,
## the mount breathing on the procedural idle sway.
##
## The mount ships as a STATIC unskinned mesh (PieceAssets.HORSE documents
## why: Godot corrupts this FBX-lineage rig at chess-piece scale), so the
## contract asserted here is "no rig, sway tween live", NOT an animation
## player — the banner-rook's proven procedural pattern.
func _test_mounted_knight() -> void:
	for hid in ["goldclaw", "tidegrip", ""]:
		var label: String = hid if not str(hid).is_empty() else "legacy"
		var pv := _spawn(T_KNIGHT, FROST, hid)
		for part in ["Horse", "Saddle", "Caparison", "Rider"]:
			check("mounted %s: has %s" % [label, part], true,
					pv.find_child(part, true, false) != null)
		var cap := pv.find_child("Caparison", true, false) as MeshInstance3D
		check("mounted %s: caparison dressed" % label, true,
				cap != null and cap.material_override != null)
		if registry.has_house(hid):
			# The SAME composited cloth the house's rook flies (identity, not
			# a lookalike) — house colors, hem stripe, sigil on the flank.
			var rook := _spawn(T_ROOK, FROST, hid)
			var flag := rook.find_child("BannerCloth", true, false) as MeshInstance3D
			check("mounted %s: caparison wears the house banner cloth" % label,
					true, cap.material_override.albedo_texture != null
					and cap.material_override.albedo_texture
							== flag.material_override.albedo_texture)
			rook.free()
		else:
			check("mounted %s: caparison dyed in the side's cloth" % label, true,
					cap.material_override.albedo_texture == null
					and cap.material_override.albedo_color != Color.WHITE)
		# STATIC mount, procedurally animated (the documented decision).
		check("mounted %s: mount is unskinned/static" % label, true,
				pv._horse.find_children("*", "Skeleton3D", true, false).is_empty()
				and pv._horse.find_children("*", "AnimationPlayer", true, false).is_empty())
		check("mounted %s: mount breathes on the idle sway" % label, true,
				pv._sway_tween != null and pv._sway_tween.is_running())
		# HOUSE palette dresses the MOUNT too, not just the rider.
		var hide_mesh := pv._horse.find_child("Horse", true, false) as MeshInstance3D
		check("mounted %s: horse hide wears the house tint" % label, true,
				hide_mesh != null and hide_mesh.get_surface_override_material(0) != null)
		check("mounted %s: saddle keeps its leather" % label, true,
				(pv.find_child("Saddle", true, false) as MeshInstance3D)
						.get_surface_override_material(0) == null)
		# Seating: the rider rides ON the saddle — hips inside the seat slab,
		# never floating above it or sunk through the horse's back.
		var rider: Node3D = pv.find_child("Rider", true, false)
		var belly_y: float = _model_space_box(pv, "Caparison").position.y
		check("mounted %s: rider seated above the mount's belly line" % label, true,
				rider.position.y > belly_y)
		var saddle_top: float = _model_space_box(pv, "Saddle").end.y
		var hips_y: float = rider.position.y \
				+ _bone_y(pv, "hips")
		check("mounted %s: hips land in the saddle (%.2f vs seat %.2f)"
				% [label, hips_y, saddle_top], true,
				absf(hips_y - saddle_top) < 0.35)
		check("mounted %s: rider sits STILL (player parked)" % label, false,
				(pv._anim as AnimationPlayer).is_playing())
		check("mounted %s: seat pose bends the legs" % label, true,
				_bone_bent(pv, "upperleg.l") and _bone_bent(pv, "lowerleg.l"))
		check("mounted %s: sword rides with the RIDER" % label, true,
				rider != null and rider.find_child("Gear_sword", true, false) != null)
		check("mounted %s: house crest rides on the RIDER's head" % label,
				registry.has_house(hid),
				rider != null and rider.find_child("Crest", true, false) != null)
		var skeletal := false
		for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
			if str(mi.name).begins_with("Skeleton_"):
				skeletal = true
		check("mounted %s: skeletal rider iff Drowned Legion" % label,
				hid == "tidegrip", skeletal)
		pv.free()
	# The mount is HOUSE-COLORED, not one grey horse for everyone: two houses
	# must dress their caparison in visibly different cloth, and the Drowned
	# Legion's charger is charred darker than a living house's.
	var gold := _spawn(T_KNIGHT, FROST, "goldclaw")
	var winter := _spawn(T_KNIGHT, FROST, "winterfang")
	var tide := _spawn(T_KNIGHT, FROST, "tidegrip")
	check("mount palette: caparisons differ between houses", true,
			(gold.find_child("Caparison", true, false) as MeshInstance3D)
					.material_override.albedo_texture
			!= (winter.find_child("Caparison", true, false) as MeshInstance3D)
					.material_override.albedo_texture)
	check("mount palette: hides differ between houses", true,
			_hide_albedo(gold) != _hide_albedo(winter))
	check("mount palette: Drowned Legion's charger is charred darker", true,
			_hide_albedo(tide).v < _hide_albedo(gold).v)
	gold.free()
	winter.free()
	tide.free()


## Model-space AABB of a named mesh under the ensemble (mounted-knight rig).
func _model_space_box(pv: Node, mesh_name: String) -> AABB:
	var mi := pv.find_child(mesh_name, true, false) as MeshInstance3D
	var horse: Node3D = pv._horse
	return (horse.transform * mi.transform) * mi.mesh.get_aabb()


## Rider-local Y of a posed bone on the seated rider.
func _bone_y(pv: Node, bone: String) -> float:
	var skel: Skeleton3D = pv._skeleton()
	return skel.get_bone_global_pose(skel.find_bone(bone)).origin.y


## True when the seat pose actually moved this bone off its rest rotation.
func _bone_bent(pv: Node, bone: String) -> bool:
	var skel: Skeleton3D = pv._skeleton()
	var i := skel.find_bone(bone)
	if i == -1:
		return false
	return skel.get_bone_pose_rotation(i).angle_to(
			skel.get_bone_rest(i).basis.get_rotation_quaternion()) > 0.2


## The house tint actually painted on the horse's hide.
func _hide_albedo(pv: Node) -> Color:
	var hide_mesh := (pv._horse as Node3D).find_child("Horse", true, false) as MeshInstance3D
	return (hide_mesh.get_surface_override_material(0) as StandardMaterial3D).albedo_color


## Mounted death: the rider plays Death_A and tumbles out of the saddle
## while the horse keels over sideways (procedural — the mount is static);
## died fires with death_anim=Death_A (the duel/e2e contract is unchanged)
## and the idle sway is killed so nothing keeps breathing under the wreck.
func _test_knight_death() -> void:
	var pv := _spawn(T_KNIGHT, FROST, "winterfang")
	var rider: Node3D = pv.find_child("Rider", true, false)
	var horse: Node3D = pv._horse
	# [died, death_anim, rider slide x at death, horse keel-over at death]
	var died_flag: Array = [false, "", 0.0, 0.0]
	pv.died.connect(func() -> void:
		died_flag[0] = true
		died_flag[1] = pv.death_anim
		if is_instance_valid(rider):
			died_flag[2] = rider.position.x
		if is_instance_valid(horse):
			died_flag[3] = horse.rotation.z)
	check("knight death: rider starts in the saddle", true,
			rider != null and absf(rider.position.x) < 0.01)
	check("knight death: horse starts upright", true, absf(horse.rotation.z) < 0.01)
	pv.die()   # fire and forget; probe the stages
	await create_timer(1.2).timeout
	check("knight death: horse keeling over", true, horse.rotation.z > 0.2)
	check("knight death: rider tipping out of the saddle", true, rider.position.x > 0.2)
	check("knight death: idle sway stopped", true,
			pv._sway_tween == null or not pv._sway_tween.is_running())
	var deadline := Time.get_ticks_msec() + 8000
	while not died_flag[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	check("knight death: died emitted", true, died_flag[0])
	check("knight death: death anim", "Death_A", died_flag[1])
	check("knight death: rider slid off the saddle", true, float(died_flag[2]) > 1.0)
	check("knight death: horse ended on its side", true, float(died_flag[3]) > 1.0)


## Mounted strike: play_capture fells the victim (horse step-in + rider
## Throw), the victim dies through the standard Death_A contract, and the
## knight settles back — ensemble returned to its square, mount still
## breathing, rider re-seated and parked still again.
func _test_knight_capture() -> void:
	var pv := _spawn(T_KNIGHT, FROST, "goldclaw")
	var victim := _spawn(T_PAWN, EMBER, "ashwyrm")
	pv.position = Vector3.ZERO
	victim.position = Vector3(0.0, 0.0, 1.2)
	var victim_death: Array = [""]
	victim.died.connect(func() -> void: victim_death[0] = victim.death_anim)
	await pv.play_capture(victim)
	check("knight capture: victim fell through Death_A", "Death_A", victim_death[0])
	check("knight capture: victim consumed", true,
			not is_instance_valid(victim) or victim.is_queued_for_deletion())
	check("knight capture: ensemble stepped back onto its square", true,
			pv.position.distance_to(Vector3.ZERO) < 0.02)
	check("knight capture: mount still breathing", true,
			pv._sway_tween != null and pv._sway_tween.is_running())
	await create_timer(0.6).timeout   # _reseat_rider settles
	check("knight capture: rider parked still again", false,
			(pv._anim as AnimationPlayer).is_playing())
	check("knight capture: rider re-seated in the saddle", true,
			_bone_bent(pv, "upperleg.l") and _bone_bent(pv, "lowerleg.l"))
	pv.free()


## Face-to-face doctrine on REAL mounted pieces: the tower exemption must
## NOT exempt knights — the whole ensemble root turns to meet the victim.
func _test_knight_duel_facing() -> void:
	var dd_script: GDScript = load("res://src/cinematics/duel_director.gd")
	var d: Node3D = dd_script.new()
	d.swoop_wall = 0.05
	d.return_wall = 0.05
	d.duel_ramp_down_wall = 0.05
	d.duel_slow_hold_wall = 0.15
	d.duel_ramp_up_wall = 0.05
	d.duel_tail_wall = 0.05
	d.face_off_wall = 0.1
	d.face_rest_wall = 0.1
	d.failsafe_wall_sec = 5.0
	root.add_child(d)
	var knight := _spawn(T_KNIGHT, FROST, "goldclaw")
	var victim := _spawn(T_PAWN, EMBER, "duskfire")
	knight.position = Vector3(-0.8, 0.0, 0.0)
	victim.position = Vector3(0.8, 0.0, 0.2)
	knight.rotation.y = 0.0
	victim.rotation.y = 0.0
	var probe := {"knight_on_victim": false}
	var strike := func() -> void:
		var dir: Vector3 = (victim.global_position - knight.global_position).normalized()
		var fwd: Vector3 = knight.global_transform.basis.z.normalized()
		probe["knight_on_victim"] = fwd.dot(dir) > 0.9
		await create_timer(0.1).timeout
	await d.play_duel(knight, victim, {}, strike)
	check("knight facing: ensemble root turned onto the victim", true,
			probe["knight_on_victim"])
	check("knight facing: knight back at resting yaw", true,
			absf(wrapf(knight.rotation.y - 0.0, -PI, PI)) < 0.06)
	check("knight facing: time_scale restored", true,
			is_equal_approx(Engine.time_scale, 1.0))
	d.free()
	knight.free()
	victim.free()


## Hover-only glyph rings (ISSUES.md #2): the ring is HIDDEN at rest, fades
## in on set_hovered, stays lit while selected (selection also brightens the
## glyph to beacon energy), and fades back out when hover + selection end.
func _test_selection_feedback() -> void:
	var pv := _spawn(T_KNIGHT, FROST, "winterfang")
	var rest: float = assets.GLYPH_ENERGY_REST
	var mat: StandardMaterial3D = pv._glyph_mat
	var ring: Node3D = pv.get_node("GlyphRing")
	# Hidden at rest — the ring node exists but renders nothing.
	check("hover: ring hidden at rest", true,
			not bool(pv.glyph_ring_shown()) and not ring.visible)
	check("selection: rest energy", true,
			absf(mat.emission_energy_multiplier - rest) < 0.01)
	# Hover fades the ring in (~0.15 s).
	pv.set_hovered(true)
	await create_timer(0.4).timeout
	check("hover: ring shown on hover", true,
			bool(pv.glyph_ring_shown()) and ring.visible)
	check("hover: ring meshes fully faded in", true, _ring_max_transparency(pv) < 0.05)
	check("hover: hover alone keeps rest energy", true,
			absf(mat.emission_energy_multiplier - rest) < 0.01)
	# Leaving the square fades it back out and stops rendering it.
	pv.set_hovered(false)
	await create_timer(0.4).timeout
	check("hover: ring hidden after leave", true,
			not bool(pv.glyph_ring_shown()) and not ring.visible)
	# Selection keeps the ring lit with no hover at all, at beacon energy.
	pv.set_selected(true)
	await create_timer(0.4).timeout
	check("selection: ring lit while selected", true,
			bool(pv.glyph_ring_shown()) and ring.visible)
	check("selection: brightened", true,
			mat.emission_energy_multiplier > rest + 0.5)
	pv.set_selected(false)
	await create_timer(0.4).timeout
	check("selection: calmed again", true,
			absf(mat.emission_energy_multiplier - rest) < 0.05)
	check("selection: ring hidden after deselect", true,
			not bool(pv.glyph_ring_shown()) and not ring.visible)
	# Layering: deselecting under a live hover keeps the ring shown (the
	# hover owns it); only leaving the square finally hides it.
	pv.set_hovered(true)
	pv.set_selected(true)
	pv.set_selected(false)
	await create_timer(0.4).timeout
	check("layering: hover holds the ring after deselect", true,
			bool(pv.glyph_ring_shown()) and ring.visible)
	pv.set_hovered(false)
	await create_timer(0.4).timeout
	check("layering: leaving the square hides the ring", true,
			not bool(pv.glyph_ring_shown()) and not ring.visible)
	pv.free()


func _ring_max_transparency(pv: Node) -> float:
	var worst := 0.0
	for mi: MeshInstance3D in (pv.get_node("GlyphRing") as Node3D) \
			.find_children("*", "MeshInstance3D", true, false):
		worst = maxf(worst, mi.transparency)
	return worst


## The banner-rook crumble: die() must still work, the banner tears free
## (reparents off the piece) and the death anim is the tower crumble.
func _test_rook_crumble() -> void:
	var pv := _spawn(T_ROOK, FROST, "ashwyrm")
	var died_flag: Array = [false, ""]   # [emitted, death_anim at emit time]
	pv.died.connect(func() -> void:
		died_flag[0] = true
		died_flag[1] = pv.death_anim)
	check("crumble: banner starts on the tower", true,
			pv.find_child("BannerCloth", true, false) != null)
	pv.die()   # fire and forget; poll the stages
	await create_timer(0.3).timeout
	check("crumble: banner detached from the piece", true,
			pv.find_child("BannerCloth", true, false) == null)
	check("crumble: banner fell to the world", true,
			root.find_child("BannerCloth", true, false) != null)
	await create_timer(1.3).timeout   # die() frees the piece when it finishes
	check("crumble: died emitted", true, died_flag[0])
	check("crumble: death anim", "Tower_Crumble", died_flag[1])
	await create_timer(0.6).timeout
	check("crumble: banner cleaned up", true,
			root.find_child("BannerCloth", true, false) == null)
