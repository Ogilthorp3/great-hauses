extends SceneTree

# Headless suite for the HOUSE COSTUMES + PIECE READABILITY + BANNER-ROOK
# + MOUNTED-KNIGHT + PAWN-HELM module: assembly correctness (right gear per
# type, right crest per house, a distinct per-house half-helm on every pawn
# and on nobody else, skeleton cast only for Tidegrip, glyph ring present,
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
const MIN_EXPECTED_CHECKS := 380

# PieceView.Type values (int-mirrored: PAWN ROOK KNIGHT BISHOP QUEEN KING).
const T_PAWN := 0
const T_ROOK := 1
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4
const T_KING := 5
const TYPE_NAMES := ["PAWN", "ROOK", "KNIGHT", "BISHOP", "QUEEN", "KING"]
## Height-grading order (not enum order). The MOUNTED knight moved from
## between-bishop-and-rook to between-QUEEN-and-KING on 2026-08-08 — see
## PieceAssets.TYPE_HEIGHT: normalizing a horse+rider ensemble into a foot
## soldier's slot shrank the rider below pawn height and the horse to dog
## size. A man on a warhorse out-tops a standing queen; only the king out-tops
## him. The monotonic assertion below is unchanged in strength — it is the
## ORDER that moved, and it moved on purpose.
const GRADE_ORDER := [T_PAWN, T_BISHOP, T_ROOK, T_QUEEN, T_KNIGHT, T_KING]
const FROST := 0
const EMBER := 1

var assets: Node          # the PieceAssets shim
var piece_scene: PackedScene
var preview: GDScript     # costume_preview.gd (shared validator)
var registry: GDScript    # houses.gd


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — costumes headless suite ===")
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
	_test_pawn_helms()
	_test_mounted_knight()
	_test_royal_silhouette()
	_test_royal_band_reads()
	_test_royal_metal()
	_test_bishop_mitre()
	_test_glyph_medallion()
	_test_mount_barding()
	_test_horse_coats()
	_test_haus_separation()
	_test_material_role_table()
	_test_role_split()
	_test_role_gate()
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


## Strict monotonic height grading pawn<bishop<rook<queen<knight<king,
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


## The per-house PAWN HALF-HELM (ISSUES.md #3): every house's pawns wear THEIR
## OWN helm — a distinct asset per house, mounted on the head bone exactly like
## a royal crest, its rim/motif dyed in the house accent while the iron shell
## is left plain. Nobody but a pawn wears one, legacy sides wear none, the
## Barbarian's bear hood is hidden (never freed) so the helm is visible, and
## none of it may move the height grading.
func _test_pawn_helms() -> void:
	var mount_pos: Vector3 = Vector3(0.0, 0.945, 0.0)
	var scenes := {}
	var iron_albedo := {}
	var helm_charge := {}
	for hid in registry.house_ids():
		var pv := _spawn(T_PAWN, FROST, hid)
		var helm: Node3D = pv.find_child("Helm", true, false)
		check("helm %s: pawn wears a helm" % hid, true, helm != null)
		if helm == null:
			pv.free()
			continue
		# Mounted the crest way: a BoneAttachment3D on the rig's head bone, so
		# it tracks idle/walk/death for free.
		var att := helm.get_parent() as BoneAttachment3D
		check("helm %s: mounted on a head BoneAttachment3D" % hid, true,
				att != null and att.bone_name == "head" and att.name == "HelmMount")
		check("helm %s: at the measured skull-crown mount, unscaled" % hid, true,
				helm.position.is_equal_approx(mount_pos)
				and helm.scale.is_equal_approx(Vector3.ONE))
		# A helm WRAPS the skull; a crest TOWERS over it. Never both, never
		# the royal names (they are contracts the e2e board-truth greps for).
		check("helm %s: pawn wears no crest/crown/tiara" % hid, true,
				pv.find_child("Crest", true, false) == null
				and pv.find_child("Crown", true, false) == null
				and pv.find_child("Tiara", true, false) == null)
		check("helm %s: sits below the royal crest line" % hid, true,
				helm.position.y < 1.04)
		# THIS house's own helm, not a shared one: distinct scene per house,
		# and the mesh node inside carries the house name.
		var packed: PackedScene = assets.pawn_helm_scene(hid)
		scenes[hid] = packed.resource_path
		check("helm %s: helm mesh names its own house" % hid, true,
				helm.find_child("*%s*" % hid, true, false) != null)
		# BOTH surfaces are dressed now (critic defect #11): the dome in the
		# house body color, the rim/motif in the house CHARGE — the heraldic
		# color furthest from that dome, so the motif can never be
		# green-on-green again (defect #9). The dome must stay clearly darker
		# than the charge: a pawn is house-colored, not gilded.
		var charge_ok := false
		var shell_ok := false
		for mi: MeshInstance3D in helm.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
				var over := mi.get_surface_override_material(s) as StandardMaterial3D
				if base == null:
					continue
				if str(base.resource_name).begins_with(assets.HELM_ACCENT_MATERIAL):
					charge_ok = over != null and over.albedo_color != base.albedo_color
					if over != null:
						helm_charge[hid] = over.albedo_color
				elif str(base.resource_name).begins_with(assets.HELM_IRON_MATERIAL):
					shell_ok = over != null
					if over != null:
						iron_albedo[hid] = over.albedo_color
		check("helm %s: rim/motif dyed in the house charge" % hid, true, charge_ok)
		check("helm %s: dome dyed in the house color" % hid, true, shell_ok)
		# The two must actually contrast — that is the whole point of a charge.
		check("helm %s: charge separated from the dome" % hid, true,
				helm_charge.has(hid) and iron_albedo.has(hid)
				and Vector3((helm_charge[hid] as Color).r - (iron_albedo[hid] as Color).r,
						(helm_charge[hid] as Color).g - (iron_albedo[hid] as Color).g,
						(helm_charge[hid] as Color).b - (iron_albedo[hid] as Color).b
					).length() > 0.20)
		# THE CHARGE LAW, VALUE-ONLY (role pass, 2026-08-09). What P8 got right
		# is that a PALE, LOW-CHROMA plate on the top of a silhouette flares and
		# eats the head shape (measured then at value 0.78, peak 0.93, against a
		# 0.59 dome). What it got wrong was buying separation with CHROMA, which
		# walked the charge off the house's own palette — Thornvale's gold
		# #d3b04a came out #302300 and the role gate rightly refuses it.
		#
		# So a charge is now one of the house's DECLARED colours moved only along
		# VALUE, and the flare rule survives as a rule about NEUTRALS: a
		# colourless mark must be cut INTO its dome; a chromatic one (gold on
		# green, crimson on gold) may be laid on it, because that is heraldry.
		var dome_v: float = (iron_albedo[hid] as Color).v
		var charge: Color = helm_charge[hid]
		var on_palette := false
		for c: Color in assets.house_palette(hid):
			if absf(wrapf(c.h * 360.0 - charge.h * 360.0, -180.0, 180.0)) < 6.0 \
					and absf(c.s - charge.s) < 0.06:
				on_palette = true
		check("helm %s: the charge is one of the house's own colours (%s)"
				% [hid, charge.to_html(false)], true, on_palette)
		check("helm %s: a colourless charge is cut INTO the dome (%.2f vs %.2f, s=%.2f)"
				% [hid, charge.v, dome_v, charge.s], true,
				charge.s >= float(assets.CHARGE_NEUTRAL_SAT)
				or charge.v <= dome_v * float(assets.CHARGE_UNDER) + 0.001)
		# The bear hood must be OFF (it swallows the helm) and still THERE —
		# _raw_model_height counts it, so freeing it would rescale the pawn.
		var hoods: Array = pv.find_children("*BearHat*", "MeshInstance3D", true, false)
		var want_hood: bool = str(hid) != "tidegrip"  # the skeleton cast has none
		check("helm %s: bear hood still in the tree (hidden, not freed)" % hid,
				want_hood, not hoods.is_empty())
		for mi: MeshInstance3D in hoods:
			check("helm %s: bear hood doffed" % hid, false, mi.visible)
		# The helm hangs off a bone, so the height law cannot feel it.
		check("helm %s: height law untouched (%.3f)" % [hid,
				float(preview.measured_height(pv))], true,
				absf(float(preview.measured_height(pv))
						- float(assets.piece_height(T_PAWN))) < 0.01)
		pv.free()
	# One helm per house, never a shared one — asserted against the ROSTER, not
	# against the literal 9. Houses are discovered now (docs/HOUSE-PACK.md): the
	# nine ship, and a player may drop more into user://hauses/. The number 9
	# used to be written here, which meant installing a house someone else wrote
	# turned this suite red for a reason that had nothing to do with that house.
	# With the shipped nine and nothing installed this is the same check it
	# always was.
	check("helm: every house has its own helm asset, no sharing",
			registry.house_ids().size(),
			scenes.values().size() - _dupes(scenes.values()))
	# The Drowned Legion fields the pre-charred twin — same kraken geometry,
	# iron and rim baked black, mirroring its charred charger.
	check("helm: Drowned Legion wears the charred twin", true,
			str(scenes["tidegrip"]).contains("charred"))
	check("helm: the Drowned Legion's dome is charred darker", true,
			(iron_albedo["tidegrip"] as Color).get_luminance()
			< (iron_albedo["goldclaw"] as Color).get_luminance())
	# NINE DISTINCT PAWN RANKS (critic defects #10/#11): at board distance the
	# dome IS the pawn, so no two houses may dye theirs the same color.
	var dome_pairs := 0
	for a in iron_albedo:
		for b in iron_albedo:
			if str(a) >= str(b):
				continue
			var ca: Color = iron_albedo[a]
			var cb: Color = iron_albedo[b]
			if Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length() < 0.10:
				dome_pairs += 1
				print("      pawn domes too close: %s %s vs %s %s"
						% [a, ca.to_html(false), b, cb.to_html(false)])
	check("helm: no two houses share a pawn dome color", 0, dome_pairs)
	# Pawns ONLY — a helm on a bishop or a crest on a pawn would break the
	# rank read the whole costume system is built on.
	for t in [T_BISHOP, T_KNIGHT, T_ROOK, T_QUEEN, T_KING]:
		var pv := _spawn(t, FROST, "goldclaw")
		check("helm: %s wears no helm" % TYPE_NAMES[t], true,
				pv.find_child("Helm", true, false) == null)
		pv.free()
	# Legacy FROST/EMBER sides have no house, so no helm — and they keep the
	# bear hood they shipped with rather than standing there bare-headed.
	var legacy := _spawn(T_PAWN, FROST, "")
	check("helm: legacy pawn wears no helm", true,
			legacy.find_child("Helm", true, false) == null)
	var legacy_hoods: Array = legacy.find_children("*BearHat*", "MeshInstance3D", true, false)
	check("helm: legacy pawn keeps its bear hood", true,
			not legacy_hoods.is_empty()
			and (legacy_hoods[0] as MeshInstance3D).visible)
	legacy.free()


func _dupes(values: Array) -> int:
	var seen := {}
	var n := 0
	for v in values:
		if seen.has(v):
			n += 1
		seen[v] = true
	return n


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
		# The MOUNT is dressed too — but in its own COAT, not in the house
		# (see _test_horse_coats: the animal is an animal).
		var hide_mesh := pv._horse.find_child("Horse", true, false) as MeshInstance3D
		check("mounted %s: horse hide wears its house's coat" % label, true,
				hide_mesh != null and hide_mesh.get_surface_override_material(0) != null)
		# The saddle is LEATHER, and leather is NATURAL (the role pass,
		# 2026-08-09). It used to be dyed with the hide "so no army rides on
		# stock brown tack" — which is exactly the reasoning that ended up
		# painting a house colour onto every surface in the game. Tack is tack.
		var saddle_mat := (pv.find_child("Saddle", true, false) as MeshInstance3D) \
				.get_surface_override_material(0) as StandardMaterial3D
		check("mounted %s: saddle is dressed" % label, true, saddle_mat != null)
		if saddle_mat != null:
			var sh := saddle_mat.albedo_color.h * 360.0
			check("mounted %s: saddle stays leather (%s)"
					% [label, saddle_mat.albedo_color.to_html(false)], true,
					saddle_mat.albedo_color.s <= 0.20 or (sh >= 5.0 and sh <= 58.0))
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


## ROYAL SILHOUETTE FROM ABOVE (critic defect #3, 2026-08-08). The gameplay
## camera looks DOWN. What a player sees of a royal is the top of a head — and
## with the crown scaled inside the skull line, Winterfang's king and queen
## were the same large pale-blue dome at board distance: "the player cannot
## find their own king."
##
## The rule this pins: a KING'S crown must break his own head silhouette (its
## spiked ring wider than the skull, so it reads from directly overhead), and
## a QUEEN'S tiara must NOT (it is a band on a bare head, the opposite read).
## Measured on every house, both casts, in head-bone space.
func _test_royal_silhouette() -> void:
	for hid in ["winterfang", "goldclaw", "tidegrip"]:
		var king := _spawn(T_KING, FROST, hid)
		var queen := _spawn(T_QUEEN, FROST, hid)
		var head_r: float = _head_half_width(king)
		var crown_r: float = _prop_radius(king.find_child("Crown", true, false))
		var tiara_r: float = _prop_radius(queen.find_child("Tiara", true, false))
		check("royals %s: crown breaks the skull line (%.2f vs head %.2f)"
				% [hid, crown_r, head_r], true, crown_r > head_r)
		check("royals %s: tiara stays inside it (%.2f vs head %.2f)"
				% [hid, tiara_r, head_r], true, tiara_r < head_r * 0.85)
		check("royals %s: the two footprints are far apart" % hid, true,
				crown_r > tiara_r * 1.6)
		king.free()
		queen.free()


## THE QUEEN WHO WORE NO TIARA (critic blocker, 2026-08-09).
##
## _test_royal_silhouette above measures the tiara against the HEAD and passed
## nine times over on an army whose queen showed zero pixels of either regalia
## tone: it never asks whether anything is standing in front of the band. Her
## own house CREST was — Winterfang's is a wolf pelt that hangs off the skull
## rather than sitting on it, and the circlet lived inside it.
##
## So this is the missing question, asked the way the defect was found: cast a
## ray from every tiara triangle toward the gameplay camera and count the ones
## the crest does not block. Both directions, because either army can field any
## house — the near army's queen is seen from behind the head, the far army's
## from in front, and a crest that clears one can swallow the other.
##
## Measured before the fix (near / far): winterfang 0.0/0.0, duskfire 55.6/65.4,
## thornvale 68.5/62.6, tidegrip 74.0/70.1, silverbrook 79.6/95.7, swiftcrest
## 84.7/93.7, ashwyrm 87.4/96.6, goldclaw 89.6/91.3, hartcrown 90.4/87.1.
## After PieceView's crest fit, winterfang reads 55.2/61.1 and no house lost
## ground. The floor is set under the pack, not under winterfang: a house that
## drops below it has hidden its own regalia, whichever house it is.
##
## The negative control is the defect itself — put a crest back where Winterfang's
## used to hang and this must go red.
const BAND_VISIBLE_FLOOR := 0.25
## game.tscn's camera: pivot (0, 0.4, 0), yaw PI, pitch -0.85 -> forward
## (0, -0.7513, 0.6600). The direction from a piece TOWARD the lens is its
## negation; the far army (yaw PI) sees it mirrored in Z.
const BAND_VIEW_NEAR := Vector3(0.0, 0.7513, -0.6600)
const BAND_VIEW_FAR := Vector3(0.0, 0.7513, 0.6600)


func _test_royal_band_reads() -> void:
	var worst := 2.0
	var worst_hid := ""
	for hid in registry.house_ids():
		var queen := _spawn(T_QUEEN, FROST, hid)
		var crest: Node3D = queen.find_child("Crest", true, false)
		var tiara: Node3D = queen.find_child("Tiara", true, false)
		check("band %s: she has a crest and a tiara to measure" % hid, true,
				crest != null and tiara != null)
		if crest == null or tiara == null:
			queen.free()
			continue
		var blockers: PackedVector3Array = _tris(crest)
		var band: PackedVector3Array = _tris(tiara)
		for view in [["near", BAND_VIEW_NEAR], ["far", BAND_VIEW_FAR]]:
			var seen: float = _unblocked(band, blockers, view[1])
			if seen < worst:
				worst = seen
				worst_hid = "%s (%s)" % [hid, str(view[0])]
			check("band %s: the tiara reads from the %s army (%.0f%% clear)"
					% [hid, str(view[0]), seen * 100.0], true,
					seen >= BAND_VISIBLE_FLOOR)
		queen.free()
	check("band: worst house %s at %.0f%%" % [worst_hid, worst * 100.0], true,
			worst >= BAND_VISIBLE_FLOOR)
	# CONTROL — hang a crest where Winterfang's used to, and the gate must fire.
	var probe := _spawn(T_QUEEN, FROST, "winterfang")
	var c: Node3D = probe.find_child("Crest", true, false)
	var t: Node3D = probe.find_child("Tiara", true, false)
	if c != null and t != null:
		c.scale = Vector3.ONE
		c.position = Vector3(0.0, 1.04, 0.0)   # the mount that shipped the defect
		var buried: float = _unblocked(_tris(t), _tris(c), BAND_VIEW_NEAR)
		check("band control: the old drape mount buries the band (%.0f%%)"
				% (buried * 100.0), true, buried < BAND_VISIBLE_FLOOR)
	probe.free()


## Every triangle under `node`, in the BoneAttachment3D's space (crest, tiara
## and crown are siblings there, so their coordinates are directly comparable).
func _tris(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if node == null:
		return out
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var chain := mi.transform
		var p := mi.get_parent()
		while p != null and p != node:
			chain = (p as Node3D).transform * chain
			p = p.get_parent()
		var xf: Transform3D = node.transform * chain
		for v in mi.mesh.get_faces():
			out.append(xf * v)
	return out


## Fraction of sample points on `probe`'s triangles from which a ray along
## `dir` escapes without hitting one of `blockers`' triangles.
func _unblocked(probe: PackedVector3Array, blockers: PackedVector3Array,
		dir: Vector3) -> float:
	if probe.is_empty():
		return 0.0
	var seen := 0
	var total := 0
	var i := 0
	while i + 2 < probe.size():
		var g: Vector3 = (probe[i] + probe[i + 1] + probe[i + 2]) / 3.0
		for pt in [g, probe[i].lerp(g, 0.1), probe[i + 1].lerp(g, 0.1),
				probe[i + 2].lerp(g, 0.1)]:
			total += 1
			var origin: Vector3 = (pt as Vector3) + dir * 0.002
			var hit := false
			var j := 0
			while j + 2 < blockers.size():
				if Geometry3D.ray_intersects_triangle(origin, dir,
						blockers[j], blockers[j + 1], blockers[j + 2]) != null:
					hit = true
					break
				j += 3
			if not hit:
				seen += 1
		i += 3
	return float(seen) / maxf(float(total), 1.0)


## THE KING WORE THE ENEMY'S COLOUR (art critic, 2026-08-09).
##
## P3 inverted the crown mapping — cold armies in gold, warm armies in steel —
## and the inversion is what made the defect visible: crown_frost's albedo is
## #5b6371, a NAVY steel, so Hartcrown, Ashwyrm, Goldclaw, Duskfire and
## Thornvale all crowned their kings in the darkest coolest object in their own
## army, and in the same navy Silverbrook wears as its identity. In Goldclaw vs
## Winterfang the gold king wore blue.
##
## The rule that replaced it: a crown is REGALIA and carries NO haus signal at
## all. One metal, identical on all nine — which makes it a RANK marker, worn
## by both kings in every match, and therefore unable to name the wrong haus.
##
## Uniformity costs the contrast the old mapping was buying, so the crown now
## carries its contrast inside itself: a dark tarnished band under polished
## points. This asserts all of it — the uniformity, the two tones, the value
## step, and (the part that is easy to lose) that BOTH tones stay clear of
## every haus's own jersey and at least one of them cuts hard against every
## haus's own dome.
const REGALIA_TONE_STEP := 40.0        # dE2000 between band and points
const REGALIA_CONTRAST_FLOOR := 20.0   # ...and against the army it is worn on
const REGALIA_KIT_GAP := 0.14          # costume_preview.NATURAL_KIT_DISTANCE


func _test_royal_metal() -> void:
	var ids: Array = registry.house_ids()
	# 1. ONE crown. Not "a crown per temperature" — one PackedScene, shared.
	var first: PackedScene = assets.crown_scene(registry.get_house_tint(ids[0], "kit"))
	for hid in ids:
		var packed: PackedScene = assets.crown_scene(
				registry.get_house_tint(hid, "kit"))
		check("royal metal %s: crown carries no haus signal (same prop)" % hid,
				true, packed == first)

	# 2. ...rendered as exactly two REGALIA tones, named by MATERIAL_ROLES.
	var band := Color.BLACK
	var points := Color.BLACK
	for hid in ids:
		var king := _spawn(T_KING, FROST, hid)
		var queen := _spawn(T_QUEEN, FROST, hid)
		for pair in [["Crown", king], ["Tiara", queen]]:
			var prop := (pair[1] as Node).find_child(
					str(pair[0]), true, false) as Node3D
			check("royal metal %s: the %s is on the head" % [hid, pair[0]],
					true, prop != null)
			if prop == null:
				continue
			var tones := {}
			for mi: MeshInstance3D in prop.find_children(
					"*", "MeshInstance3D", true, false):
				for s in mi.mesh.get_surface_count():
					var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
					var mat := mi.get_active_material(s) as StandardMaterial3D
					if base == null or mat == null:
						continue
					tones[str(base.resource_name)] = mat.albedo_color
					check("royal metal %s: %s#%d is REGALIA" % [hid, pair[0], s],
							assets.Role.REGALIA,
							assets.classify(str(mi.name),
									str(base.resource_name))["role"])
					# A metal with no diffuse response renders black wherever it
					# catches no highlight — the whole P3 failure.
					check("royal metal %s: %s#%d keeps a diffuse response"
							% [hid, pair[0], s], true, mat.metallic <= 0.40)
			check("royal metal %s: the %s wears both tones" % [hid, pair[0]],
					true, tones.has(assets.CROWN_BAND_MATERIAL)
					and tones.has(assets.CROWN_POINT_MATERIAL))
			if tones.has(assets.CROWN_BAND_MATERIAL):
				band = tones[assets.CROWN_BAND_MATERIAL]
				points = tones[assets.CROWN_POINT_MATERIAL]
		king.free()
		queen.free()

	# 3. The two tones are one metal in two states — a real value step apart.
	var step: float = _delta_e2000(_lab(band), _lab(points))
	check("royal metal: band %s and points %s are %.0f dE apart"
			% [band.to_html(false), points.to_html(false), step], true,
			step >= REGALIA_TONE_STEP)
	check("royal metal: both tones read as metal, not paint", true,
			band.s <= 0.55 and points.s <= 0.55)

	# 4. Neither tone is any haus's jersey, and one of them cuts hard against
	#    every haus's own dome — which is the contrast the per-haus mapping
	#    used to buy, bought back without a haus signal.
	var worst := 999.0
	var worst_hid := ""
	for hid in ids:
		var kit: Color = registry.get_house_tint(hid, "kit")
		var dome := Color(kit.r * 0.72, kit.g * 0.72, kit.b * 0.72)
		for pair in [["band", band], ["points", points]]:
			var c: Color = pair[1]
			check("royal metal %s: the %s is not the jersey" % [hid, str(pair[0])],
					true, _rgb_gap(c, kit) > REGALIA_KIT_GAP)
		var reach: float = maxf(
				minf(_delta_e2000(_lab(band), _lab(kit)),
						_delta_e2000(_lab(band), _lab(dome))),
				minf(_delta_e2000(_lab(points), _lab(kit)),
						_delta_e2000(_lab(points), _lab(dome))))
		if reach < worst:
			worst = reach
			worst_hid = hid
		# The bright tone outshines every dome: the colour half of "the king is
		# the brightest man on his own army".
		check("royal metal %s: the points sit above the dome in L* (%.0f vs %.0f)"
				% [hid, _lab(points).x, _lab(dome).x], true,
				_lab(points).x > _lab(dome).x)
	check("royal metal: worst army contrast %.1f dE (%s)" % [worst, worst_hid],
			true, worst >= REGALIA_CONTRAST_FLOOR)


## THE BISHOP'S MITRE (critic P9, 2026-08-09). He measured the dimmest piece on
## the near back rank, so the hat is rebuilt into TWO surfaces and painted: a
## lit cone, a house-charge band. Asserted here because the split lives in a
## mesh rebuild that no other gate would notice going missing.
func _test_bishop_mitre() -> void:
	for hid in ["winterfang", "goldclaw", "tidegrip"]:
		var pv := _spawn(T_BISHOP, FROST, hid)
		var raw: Color = registry.get_house_tint(hid, "kit")
		# THE BISHOP'S VALUE LIFT IS RETIRED (role pass, 2026-08-09). It existed
		# because a multiply-tint over the mage's dark navy atlas could only go
		# darker; his robe is KIT now and takes the jersey at full strength, so
		# the lift on top of that made him the BRIGHTEST piece on his own back
		# rank instead of the dimmest. What still has to hold is the invariant
		# the lift was always bound by: this rank moves on VALUE only — it can
		# never become a way to smuggle a piece out of its house.
		check("mitre %s: the bishop paints in his own house's jersey" % hid, true,
				absf(pv._body_tint().h - raw.h) < 0.005
				and absf(pv._body_tint().s - raw.s) < 0.005)
		var hats: Array = pv.find_children("*Hat*", "MeshInstance3D", true, false)
		check("mitre %s: the bishop still wears a hat" % hid, true, not hats.is_empty())
		var cone: Color = Color.BLACK
		var band: Color = Color.BLACK
		var painted := 0
		for mi: MeshInstance3D in hats:
			check("mitre %s: hat rebuilt into cone + brim surfaces" % hid, true,
					mi.mesh.get_surface_count() >= 2)
			var brim: Dictionary = pv._mitre_brim.get(mi, {})
			check("mitre %s: the brim surfaces are identified" % hid, true,
					not brim.is_empty())
			for s in mi.mesh.get_surface_count():
				var over := mi.get_surface_override_material(s) as StandardMaterial3D
				if over == null:
					continue
				painted += 1
				# PAINTED, not tinted: the mage atlas is one dark navy patch and
				# a multiply over it can only ever go darker.
				check("mitre %s: surface %d painted, atlas dropped" % [hid, s],
						true, over.albedo_texture == null)
				if brim.has(s):
					band = over.albedo_color
				else:
					cone = over.albedo_color
		check("mitre %s: every hat surface painted" % hid, true, painted >= 2)
		check("mitre %s: the band reads against the cone (%.2f)" % [hid,
				_rgb_gap(cone, band)], true, _rgb_gap(cone, band) > 0.20)
		# WHICH half is the lit one is no longer fixed (role pass, 2026-08-09).
		# The old law required the band to be darker, and "darker" is exactly how
		# it kept electing near-black: Winterfang's band came out #2a2e32 against
		# a 0.67 cone and the near bishop read as a black ring with a blue nub in
		# it. A band is a herald's colour at a herald's value — Winterfang's is
		# now its ice-blue accent, brighter than the cone, and Goldclaw's is its
		# crimson primary, darker. What must hold is that the band is a colour
		# the house actually owns.
		var on_palette := false
		for c: Color in assets.house_palette(hid):
			if absf(wrapf(c.h * 360.0 - band.h * 360.0, -180.0, 180.0)) < 6.0 \
					and absf(c.s - band.s) < 0.06:
				on_palette = true
		check("mitre %s: the band is one of the house's own colours (%s)"
				% [hid, band.to_html(false)], true, on_palette)
		pv.free()


## THE GLYPH MEDALLION (critic P7, 2026-08-09): "the darkest object on the
## selection tile — a near-black disc sitting on the bright amber squircle".
## The plate/disc/inlay ship near-black AND used to receive their own piece's
## contact shadow, so the marker could only ever read on dark stone. All four
## ring materials are now dressed in the house body color and shadow-exempt.
func _test_glyph_medallion() -> void:
	for hid in ["winterfang", "duskfire"]:
		var pv := _spawn(T_ROOK, FROST, hid)
		var ring: Node3D = pv.get_node("GlyphRing")
		var seen := {}
		for mi: MeshInstance3D in ring.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
				var over := mi.get_surface_override_material(s) as StandardMaterial3D
				if base == null:
					continue
				var name := str(base.resource_name)
				if over == null:
					continue
				seen[name] = over
				check("medallion %s: %s exempt from its own contact shadow"
						% [hid, name], true, over.disable_receive_shadows)
		for want in [assets.RING_MEDAL_MATERIAL, assets.RING_STONE_MATERIAL,
				assets.RING_INLAY_MATERIAL, assets.GLYPH_MATERIAL_NAME]:
			check("medallion %s: %s dressed" % [hid, want], true, seen.has(want))
		# The plate has to sit between the two grounds it is drawn on: brighter
		# than the dark board stone (~0.15 rendered), darker than the amber
		# selection wash. Its own disc stays darker still, so it reads as inset.
		var medal: StandardMaterial3D = seen.get(assets.RING_MEDAL_MATERIAL)
		var stone: StandardMaterial3D = seen.get(assets.RING_STONE_MATERIAL)
		if medal != null and stone != null:
			check("medallion %s: plate lifted off black (%.2f)"
					% [hid, medal.albedo_color.v], true,
					medal.albedo_color.v > 0.22)
			check("medallion %s: plate reads above its own disc" % hid, true,
					medal.albedo_color.v > stone.albedo_color.v)
		pv.free()


## THE MOUNT'S BARDING (critic P6, 2026-08-09; re-roled 2026-08-09): the near
## army is read from ABOVE, where the rider occludes the horse, so the mount
## carries a CRINET down the neck and a CHANFRON on the head — the two parts a
## plan view otherwise loses.
##
## The two are no longer the same thing. The crinet is CLOTH, so it is KIT and
## wears the jersey: it is the mark that says whose cavalry this is from
## directly above. The chanfron is a STEEL face plate, so it is natural — it
## breaks the coat up by being metal, not by being painted. Both must still
## separate from the coat, or they rejoin the blob they exist to break.
func _test_mount_barding() -> void:
	for hid in ["winterfang", "goldclaw", "tidegrip"]:
		var pv := _spawn(T_KNIGHT, FROST, hid)
		var hide: Color = _hide_albedo(pv)
		var kit: Color = registry.get_house_tint(hid, "kit")
		for part in ["Crinet", "Chanfron"]:
			var mi := pv._horse.find_child(part, true, false) as MeshInstance3D
			check("barding %s: mount wears a %s" % [hid, part], true, mi != null)
			if mi == null:
				continue
			var mat := mi.get_surface_override_material(0) as StandardMaterial3D
			check("barding %s: %s is dressed" % [hid, part], true, mat != null)
			if mat == null:
				continue
			var c: Color = mat.albedo_color
			if part == "Crinet":
				# The KIT band — the one mark on the mount a plan view can name.
				check("barding %s: the crinet flies the house colour" % hid, true,
						absf(wrapf(c.h * 360.0 - kit.h * 360.0, -180.0, 180.0)) < 30.0)
				check("barding %s: the crinet separates from the coat (%.2f)"
						% [hid, _rgb_gap(c, hide)], true, _rgb_gap(c, hide) > 0.14)
			else:
				# The chanfron breaks the coat up by being METAL, not by being
				# painted — so it is judged as steel, never as a house mark. On a
				# grey house it is deliberately close to the coat: a steel plate
				# on a grey horse is a steel plate on a grey horse.
				check("barding %s: the chanfron stays STEEL, not painted (s=%.2f)"
						% [hid, c.s], true, c.s < 0.30)
				check("barding %s: the chanfron is not the jersey" % hid, true,
						_rgb_gap(c, kit) > 0.14)
		pv.free()


## THE HORSE'S COAT (the owner's rule, 2026-08-09): "Horse should be brown,
## black or white, something majestic." Nine houses used to ride nine horses
## dyed in nine house colours — a steel-blue charger, a gold one. The animal is
## now an animal, and its house identity is worn on the caparison over it.
func _test_horse_coats() -> void:
	var coats := {}
	for hid in registry.house_ids():
		var pv := _spawn(T_KNIGHT, FROST, hid)
		var hide: Color = _hide_albedo(pv)
		var kit: Color = registry.get_house_tint(hid, "kit")
		var hue := hide.h * 360.0
		check("coat %s: the hide is a coat, not a jersey (%s)"
				% [hid, hide.to_html(false)], true,
				hide.s <= 0.20 or (hue >= 5.0 and hue <= 58.0))
		check("coat %s: the hide is not the house colour (%.2f)"
				% [hid, _rgb_gap(hide, kit)], true, _rgb_gap(hide, kit) > 0.14)
		# ...and the mount still says whose it is, on the cloth over it.
		var cap := pv.find_child("Caparison", true, false) as MeshInstance3D
		check("coat %s: the caparison still carries the house" % hid, true,
				cap != null and cap.material_override != null
				and (cap.material_override as StandardMaterial3D).albedo_texture != null)
		coats[hid] = hide
		pv.free()
	check("coats: the mapping is written down, one per house",
			registry.house_ids().size(), coats.size())
	# Variety: the nine are not one horse repeated. Grouped by coat name, at
	# least four visibly different animals take the field.
	var families := {}
	for hid in coats:
		families[registry.get_house_coat(hid)] = true
	check("coats: at least four different coats are fielded (%s)"
			% str(families.keys()), true, families.size() >= 4)


func _rgb_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## THE NINE MUST BE UNMISTAKABLE (the owner, 2026-08-09: "make sure that
## hauses have enough different colors so there is no confusion between them").
##
## Every previous separation check in this file is an RGB DISTANCE with a
## hand-picked floor, and RGB distance is not what an eye measures: it rates
## two dark blues as far apart as a dark blue and a mid yellow. Both earlier
## critics found ONE confusable pair each and both got a LOCAL patch, and the
## pile-ups survived every time — because nothing here could see a PILE. It
## takes a full pairwise matrix in a perceptual space to notice that three
## hauses are blue and three are warm gold.
##
## So this is the real instrument, in the suite: CIELAB + CIEDE2000 over all
## 36 pairs, and then the same 36 pairs again through each of the three
## dichromacy simulations, because a pair that separates for a trichromat and
## collapses for a deuteranope is not separated — that is 8 % of men.
##
## The floors are set BELOW the shipped palette's measured minima, on purpose:
## this is a regression gate, not a target. What the numbers meant when they
## were set (tools/haus_palette_check.py, same maths, same day):
##      declared jerseys   min 22.6 dE2000, dichromatic min 8.1
##      pawn-dome albedos  min 15.8 dE2000, dichromatic min 5.9
## and BEFORE the pass: jerseys 13.0 / 1.9 — Winterfang's ice and Swiftcrest's
## sky, which a deuteranope could not tell apart at all.
##
## tools/haus_field.gd is the other half and is not replaceable by this: it
## renders all nine under the hall's eight ORANGE torches and samples the
## pixels, because the light moves every one of these colours before a player
## sees it (as rendered: 15.7 dE, from 9.0).
const SEP_KIT_FLOOR := 16.0
const SEP_KIT_CB_FLOOR := 6.0
const SEP_DOME_FLOOR := 12.0
const SEP_DOME_CB_FLOOR := 4.5
## ...and the SPREAD. Nine hues at one brightness and one saturation is the
## other way to be confusing, and it is the way that also looks like plastic:
## a pale haus, a near-black haus, a muted haus and a vivid haus are four
## distinguishable armies even at one hue apart, and no amount of hue
## juggling substitutes for that. Winterfang is the pale one (v 0.93),
## Hartcrown the near-black (v 0.23) — do not "fix" either by saturating it.
const SEP_VALUE_SPAN := 0.45
const SEP_CHROMA_SPAN := 0.35


func _test_haus_separation() -> void:
	var ids: Array = registry.house_ids()
	var kits := {}
	for hid in ids:
		kits[hid] = registry.get_house_tint(hid, "kit")
	_check_separation("jersey", kits, SEP_KIT_FLOOR, SEP_KIT_CB_FLOOR)

	# The pawn DOME, which is the colour an army has 16 of: the jersey cut by
	# the helm's shell weight (and cut harder for the Drowned Legion's charred
	# twin). Two jerseys can clear the floor and still land their domes on top
	# of each other, because that cut is not the same for every haus.
	var domes := {}
	for hid in ids:
		var pv := _spawn(T_PAWN, FROST, hid)
		var helm: Node = pv.find_child("Helm", true, false)
		for mi: MeshInstance3D in (helm as Node3D).find_children(
				"*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if base == null or not str(base.resource_name).begins_with(
						assets.HELM_IRON_MATERIAL):
					continue
				var over := mi.get_surface_override_material(s) as StandardMaterial3D
				if over != null:
					domes[hid] = over.albedo_color
		pv.free()
	check("separation: every haus reported a pawn dome", ids.size(), domes.size())
	_check_separation("pawn dome", domes, SEP_DOME_FLOOR, SEP_DOME_CB_FLOOR)

	# VALUE and CHROMA as axes, not side effects.
	var v_lo := 9.9
	var v_hi := -1.0
	var s_lo := 9.9
	var s_hi := -1.0
	for hid in kits:
		var c: Color = kits[hid]
		v_lo = minf(v_lo, c.v)
		v_hi = maxf(v_hi, c.v)
		s_lo = minf(s_lo, c.s)
		s_hi = maxf(s_hi, c.s)
	check("separation: the nine span VALUE (%.2f-%.2f)" % [v_lo, v_hi], true,
			v_hi - v_lo >= SEP_VALUE_SPAN)
	check("separation: the nine span CHROMA (%.2f-%.2f)" % [s_lo, s_hi], true,
			s_hi - s_lo >= SEP_CHROMA_SPAN)


## One channel's full pairwise matrix, in plain sight and under all three
## dichromacies. Prints every offending pair rather than just failing, because
## "which pair" is the whole diagnosis.
func _check_separation(label: String, table: Dictionary, floor_de: float,
		cb_floor: float) -> void:
	var names: Array = table.keys()
	for sim in ["", "deuteranopia", "protanopia", "tritanopia"]:
		var labs := {}
		for hid in names:
			var c: Color = table[hid]
			labs[hid] = _lab(_dichromat(c, sim))
		var worst := 9999.0
		var worst_pair := ""
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: String = names[i]
				var b: String = names[j]
				var d: float = _delta_e2000(labs[a], labs[b])
				if d < worst:
					worst = d
					worst_pair = "%s/%s" % [a, b]
				if d < (floor_de if sim.is_empty() else cb_floor):
					print("      %s%s too close: %s %s vs %s %s (dE %.1f)"
							% [label, "" if sim.is_empty() else " (" + sim + ")",
							a, (table[a] as Color).to_html(false),
							b, (table[b] as Color).to_html(false), d])
		check("separation: %s%s min dE2000 %.1f (%s)" % [label,
				"" if sim.is_empty() else " / " + sim, worst, worst_pair],
				true, worst >= (floor_de if sim.is_empty() else cb_floor))


## Brettel/Vienot dichromacy simulation through LMS. "" = normal vision.
func _dichromat(c: Color, kind: String) -> Color:
	if kind.is_empty():
		return c
	var lin := Vector3(_srgb_to_linear(c.r), _srgb_to_linear(c.g),
			_srgb_to_linear(c.b))
	var lms := Vector3(
			0.31399022 * lin.x + 0.63951294 * lin.y + 0.04649755 * lin.z,
			0.15537241 * lin.x + 0.75789446 * lin.y + 0.08670142 * lin.z,
			0.01775239 * lin.x + 0.10944209 * lin.y + 0.87256922 * lin.z)
	match kind:
		"protanopia":
			lms.x = 1.05118294 * lms.y - 0.05116099 * lms.z
		"deuteranopia":
			lms.y = 0.9513092 * lms.x + 0.04866992 * lms.z
		"tritanopia":
			lms.z = -0.86744736 * lms.x + 1.86727089 * lms.y
	var back := Vector3(
			5.47221206 * lms.x - 4.6419601 * lms.y + 0.16963708 * lms.z,
			-1.1252419 * lms.x + 2.29317094 * lms.y - 0.1678952 * lms.z,
			0.02980165 * lms.x - 0.19318073 * lms.y + 1.16364789 * lms.z)
	return Color(_linear_to_srgb(back.x), _linear_to_srgb(back.y),
			_linear_to_srgb(back.z))


func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _linear_to_srgb(v: float) -> float:
	var c := clampf(v, 0.0, 1.0)
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


## sRGB -> CIELAB (D65). Vector3(L, a, b).
func _lab(c: Color) -> Vector3:
	var r := _srgb_to_linear(c.r)
	var g := _srgb_to_linear(c.g)
	var b := _srgb_to_linear(c.b)
	var xyz := Vector3(
			(0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047,
			0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
			(0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
	var f := Vector3(_lab_f(xyz.x), _lab_f(xyz.y), _lab_f(xyz.z))
	return Vector3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else (903.3 * t + 16.0) / 116.0


## CIEDE2000. The perceptual metric, not the 1976 Euclidean one: Lab distance
## badly over-rates saturated blues and under-rates near-neutrals, which are
## exactly the two regions this palette deliberately uses.
func _delta_e2000(p: Vector3, q: Vector3) -> float:
	var c1 := Vector2(p.y, p.z).length()
	var c2 := Vector2(q.y, q.z).length()
	var cbar := (c1 + c2) * 0.5
	var c7 := pow(cbar, 7.0)
	var gg := 0.5 * (1.0 - sqrt(c7 / (c7 + pow(25.0, 7.0))))
	var a1 := (1.0 + gg) * p.y
	var a2 := (1.0 + gg) * q.y
	var cp1 := Vector2(a1, p.z).length()
	var cp2 := Vector2(a2, q.z).length()
	var h1 := 0.0 if is_zero_approx(a1) and is_zero_approx(p.z) \
			else fposmod(rad_to_deg(atan2(p.z, a1)), 360.0)
	var h2 := 0.0 if is_zero_approx(a2) and is_zero_approx(q.z) \
			else fposmod(rad_to_deg(atan2(q.z, a2)), 360.0)
	var dl := q.x - p.x
	var dc := cp2 - cp1
	var dh := 0.0
	if cp1 * cp2 > 0.0:
		dh = wrapf(h2 - h1, -180.0, 180.0)
	var dhh := 2.0 * sqrt(cp1 * cp2) * sin(deg_to_rad(dh * 0.5))
	var lbar := (p.x + q.x) * 0.5
	var cpbar := (cp1 + cp2) * 0.5
	var hbar := h1 + h2
	if cp1 * cp2 > 0.0:
		hbar = h1 + wrapf(h2 - h1, -180.0, 180.0) * 0.5
		hbar = fposmod(hbar, 360.0)
	var t := 1.0 - 0.17 * cos(deg_to_rad(hbar - 30.0)) \
			+ 0.24 * cos(deg_to_rad(2.0 * hbar)) \
			+ 0.32 * cos(deg_to_rad(3.0 * hbar + 6.0)) \
			- 0.20 * cos(deg_to_rad(4.0 * hbar - 63.0))
	var cp7 := pow(cpbar, 7.0)
	var rc := 2.0 * sqrt(cp7 / (cp7 + pow(25.0, 7.0)))
	var sl := 1.0 + (0.015 * pow(lbar - 50.0, 2.0)) / sqrt(20.0 + pow(lbar - 50.0, 2.0))
	var sc := 1.0 + 0.045 * cpbar
	var sh := 1.0 + 0.015 * cpbar * t
	var rt := -sin(deg_to_rad(2.0 * 30.0 * exp(-pow((hbar - 275.0) / 25.0, 2.0)))) * rc
	return sqrt(pow(dl / sl, 2.0) + pow(dc / sc, 2.0) + pow(dhh / sh, 2.0)
			+ rt * (dc / sc) * (dhh / sh))


## Widest half-extent of the character's head/skull mesh (model space).
func _head_half_width(pv: Node) -> float:
	var widest := 0.0
	for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
		var n := str(mi.name)
		if not (n.containsn("head") or n.containsn("skull")):
			continue
		widest = maxf(widest, mi.mesh.get_aabb().size.x * 0.5)
	return widest


## Footprint radius of a head prop in its BoneAttachment3D's space.
func _prop_radius(prop: Node) -> float:
	if prop == null:
		return 0.0
	var node := prop as Node3D
	var r := 0.0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (node.transform * mi.transform) * mi.mesh.get_aabb()
		r = maxf(r, maxf(maxf(absf(box.position.x), absf(box.end.x)),
				maxf(absf(box.position.z), absf(box.end.z))))
	return r


## THE ROLE GATE (owner critique, 2026-08-09 — replaces the palette envelope).
##
## The envelope required EVERY surface to sit on the house hue, and to make
## that survivable on skin, steel and horsehide its saturation ceiling was
## driven to zero. Nine monochrome armies. The owner: "too much mono color,
## should be like a hockey team jersey — colors of the team/house, but NOT
## everywhere. Horse should be brown, black or white, something majestic."
##
## So the gate now holds each ROLE to its own law: KIT must be dressed and
## wearing one of its house's own colours; NATURAL must be inside its
## material's range and must NOT be the house kit; REGALIA must stay metal;
## an UNCLASSIFIED surface is a failure. costume_preview.role_offenders owns
## the law, PieceAssets.MATERIAL_ROLES owns the classification.
##
## THREE NEGATIVE CONTROLS, because a gate that fires on nothing is not a
## gate: strip a dye and it must go red (the original discipline), paint a
## horse blue and it must go red (its mirror — the defect this pass exists to
## end), and rename a surface out of the table and it must go red (the
## unclassified case must fail loudly, never default to "dye it").
func _test_role_gate() -> void:
	for hid in registry.house_ids():
		var offenders: Array = []
		for t in GRADE_ORDER:
			var pv := _spawn(t, FROST, hid)
			offenders.append_array(preview.role_offenders(pv, hid))
			pv.free()
		check("roles %s: whole army obeys its material roles" % hid,
				"[]", str(offenders))
	# CONTROL 1 — strip the dye off one prop.
	var probe := _spawn(T_BISHOP, FROST, "winterfang")
	var tome: Node3D = probe.find_child("Gear_tome", true, false)
	for mi: MeshInstance3D in tome.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, null)
	check("roles: the gate detects an undressed prop", true,
			not preview.role_offenders(probe, "winterfang").is_empty())
	probe.free()
	# CONTROL 2 — paint a horse blue. The mount's house identity lives in its
	# CAPARISON; the animal is an animal, and a blue horse must fail.
	var blue := _spawn(T_KNIGHT, FROST, "goldclaw")
	var hide := (blue._horse as Node3D).find_child("Horse", true, false) as MeshInstance3D
	var painted := StandardMaterial3D.new()
	painted.albedo_color = Color(0.18, 0.36, 0.86)
	hide.set_surface_override_material(0, painted)
	var blue_errs: Array = preview.role_offenders(blue, "goldclaw")
	check("roles: the gate detects a BLUE HORSE", true, not blue_errs.is_empty())
	check("roles: ...and names the coat as the offender", true,
			str(blue_errs).containsn("coat"))
	blue.free()
	# CONTROL 3 — a surface the table does not name.
	var stray := _spawn(T_PAWN, FROST, "thornvale")
	var body := stray.find_child("Barbarian_Body", true, false) as MeshInstance3D
	check("roles: (control 3 needs the pawn body mesh)", true, body != null)
	if body != null:
		body.name = "Barbarian_Poncho"
		check("roles: an UNCLASSIFIED surface fails loudly", true,
				str(preview.role_offenders(stray, "thornvale")).containsn("UNCLASSIFIED"))
	stray.free()


## THE ROLE TABLE ITSELF. Every rule dispatches to a real role, the nine
## houses each declare a jersey and a coat, and no two houses wear the same
## jersey — nine armies that look alike is the failure mode this whole pass
## exists to end, and it is cheapest to catch in the data.
func _test_material_role_table() -> void:
	var seen_roles := {}
	for rule: Dictionary in assets.MATERIAL_ROLES:
		check("role table: rule %s names a pattern" % str(rule.get("n")), true,
				not str(rule.get("n", "")).is_empty())
		seen_roles[rule["role"]] = true
	for want in [assets.Role.KIT, assets.Role.NATURAL, assets.Role.REGALIA,
			assets.Role.HERALDRY, assets.Role.MIXED]:
		check("role table: dispatches to role %d" % want, true, seen_roles.has(want))
	check("role table: an unnamed surface classifies as UNCLASSIFIED",
			assets.Role.UNCLASSIFIED,
			assets.classify("Nothing_The_Table_Knows", "nor_this")["role"])
	var kits := {}
	for hid in registry.house_ids():
		var kit: Color = assets.kit_color(hid)
		check("jersey %s: declared and saturated (s=%.2f)" % [hid, kit.s], true,
				kit.s >= 0.40)
		kits[hid] = kit
		var coat: Dictionary = assets.coat_palette(hid)
		for part in ["Main", "Main_Light", "Main_Dark", "Muzzle", "Hair", "Hooves"]:
			check("coat %s: names %s" % [hid, part], true, coat.has(part))
		# A COAT IS NEVER A HOUSE HUE (the owner's rule, in data): bay,
		# chestnut, black, grey and dun are warm browns or neutrals, full stop.
		for part in coat:
			var c: Color = coat[part]
			var hue := c.h * 360.0
			check("coat %s/%s is a real coat colour (%s)" % [hid, part,
					c.to_html(false)], true,
					c.s <= 0.20 or (hue >= 5.0 and hue <= 58.0))
			check("coat %s/%s is not the jersey" % [hid, part], true,
					Vector3(c.r - kit.r, c.g - kit.g, c.b - kit.b).length() > 0.14)
	var close := 0
	for a in kits:
		for b in kits:
			if str(a) >= str(b):
				continue
			var ca: Color = kits[a]
			var cb: Color = kits[b]
			if Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length() < 0.20:
				close += 1
				print("      jerseys too close: %s %s vs %s %s"
						% [a, ca.to_html(false), b, cb.to_html(false)])
	check("jerseys: no two houses wear the same one", 0, close)


## THE MIXED SPLIT. A KayKit figure is painted from one atlas, so the tabard
## and the breastplate under it are the SAME surface until the role split
## separates them by texel. Two things have to hold or the jersey is a lie:
## the split must actually produce both halves on a body that has both, and it
## must not move a vertex — the height law measures these meshes' AABBs.
func _test_role_split() -> void:
	# The QUEEN, deliberately: the Rogue_Hooded atlas paints a saturated teal
	# robe over bare skin on ONE mesh, which is the exact case the split exists
	# for. (The knight's body is a counter-example worth knowing — his plate
	# carries no cloth at all, so his mesh splits into one natural surface and
	# his house is carried by his cape, his shield and his horse's caparison.)
	var pv := _spawn(T_QUEEN, FROST, "goldclaw")
	var body := pv.find_child("RogueHooded_Body", true, false) as MeshInstance3D
	check("split: the queen's robe mesh survives", true, body != null)
	if body == null:
		pv.free()
		return
	# Asked through costume_preview (i.e. the LIVE autoload), never through this
	# suite's PieceAssets shim: the shim is a second instance with an empty
	# cache, so it would report "nothing was split" for every mesh in the game.
	var roles: Dictionary = preview.split_roles_of(body)
	check("split: the body was split by role", true, roles.size() >= 2)
	var kit_surfaces := 0
	var nat_surfaces := 0
	for s in roles:
		if int(roles[s]) == assets.Role.KIT:
			kit_surfaces += 1
		else:
			nat_surfaces += 1
	check("split: the body has a KIT half (the tabard)", true, kit_surfaces >= 1)
	check("split: ...and a NATURAL half (the plate under it)", true, nat_surfaces >= 1)
	# The pack's own palette, as the classifier reads it — the evidence behind
	# MATERIAL_ROLES, from tools/dump_uv_palette.gd.
	for probe in [[Color.html("#086050"), assets.Role.KIT, "the rogue's teal"],
			[Color.html("#2078b7"), assets.Role.KIT, "the ranger's blue cape"],
			[Color.html("#b71860"), assets.Role.KIT, "the grimoire's magenta"],
			[Color.html("#788087"), assets.Role.NATURAL, "sword steel"],
			[Color.html("#b07050"), assets.Role.NATURAL, "skin"],
			[Color.html("#7c3c2c"), assets.Role.NATURAL, "leather"],
			[Color.html("#d7af87"), assets.Role.NATURAL, "bone"],
			[Color.html("#181818"), assets.Role.NATURAL, "shadow"]]:
		check("split: %s classifies right" % probe[2], probe[1],
				assets.texel_role(probe[0]))
	pv.free()


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
