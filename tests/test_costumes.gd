extends SceneTree

# Headless suite for the HOUSE COSTUMES + PIECE READABILITY + BANNER-ROOK
# module: assembly correctness (right gear per type, right crest per house,
# skeleton cast only for Tidegrip, glyph ring present), strict height-grading
# monotonicity, rig retarget compatibility for the skeleton cast, glyph-ring
# selection feedback, and the banner-rook crumble path.
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
const MIN_EXPECTED_CHECKS := 70

# PieceView.Type values (int-mirrored: PAWN ROOK KNIGHT BISHOP QUEEN KING).
const T_PAWN := 0
const T_ROOK := 1
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4
const T_KING := 5
const TYPE_NAMES := ["PAWN", "ROOK", "KNIGHT", "BISHOP", "QUEEN", "KING"]
## Height-grading display order (not enum order).
const GRADE_ORDER := [T_PAWN, T_KNIGHT, T_BISHOP, T_ROOK, T_QUEEN, T_KING]
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
	await _test_selection_feedback()
	await _test_rook_crumble()
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


## set_selected brightens the ring's emissive glyph, deselect calms it.
func _test_selection_feedback() -> void:
	var pv := _spawn(T_KNIGHT, FROST, "winterfang")
	var rest: float = assets.GLYPH_ENERGY_REST
	var mat: StandardMaterial3D = pv._glyph_mat
	check("selection: rest energy", true,
			absf(mat.emission_energy_multiplier - rest) < 0.01)
	pv.set_selected(true)
	await create_timer(0.4).timeout
	check("selection: brightened", true,
			mat.emission_energy_multiplier > rest + 0.5)
	pv.set_selected(false)
	await create_timer(0.4).timeout
	check("selection: calmed again", true,
			absf(mat.emission_energy_multiplier - rest) < 0.05)
	pv.free()


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
