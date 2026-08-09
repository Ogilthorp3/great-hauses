extends Node3D
## Costume preview + verification rig (standalone; the game never loads this).
##
## Windowed (visual QA + screenshots):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/costume_preview.tscn
##   Renders all 9 houses' full sets in a grid (per-house rows + a legacy
##   FROST/EMBER row), saves one screenshot per house plus an all-houses
##   overview, a mounted-knight beauty shot and the pawn-helm parade
##   (pawn_helms.png + pawn_helm_hero.png) to
##   test_e2e/artifacts/module-previews/costumes/, then quits.
##   Each house shot has its KNIGHT selected so the glyph-ring brighten
##   shows next to at-rest rings.
##
## Headless (assembly gate, exit code = failures):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://scenes/costume_preview.tscn
##   Instantiates EVERY house×type combo (plus legacy both sides), runs
##   validate_piece on each, prints a summary, quits 0/1.
##
## validate_piece is the shared assembly validator — tests/test_costumes.gd
## calls it too, so the gate logic lives in exactly one place.

const PieceScene := preload("res://scenes/piece_view.tscn")

const SHOT_DIR := "res://test_e2e/artifacts/module-previews/costumes"
## Display order: reading order of the height grading, not enum order.
## The MOUNTED knight sits between QUEEN and KING (PieceAssets.TYPE_HEIGHT —
## the ensemble is normalized on the rider, so the horse adds mass below him
## instead of stealing his height).
const TYPE_ORDER: Array[int] = [
	PieceView.Type.PAWN, PieceView.Type.BISHOP, PieceView.Type.ROOK,
	PieceView.Type.QUEEN, PieceView.Type.KNIGHT, PieceView.Type.KING,
]
const COL_STEP := 1.35
const ROW_STEP := 2.6

var _rows: Dictionary = {}       # house_id ("" = legacy) -> Array[PieceView]
var _row_roots: Dictionary = {}  # house_id -> Node3D (hidden per-shot)
var _cam: Camera3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_run_headless_gate()
		return
	_build_stage()
	_build_grid()
	_run_windowed_shots()


# ── shared assembly validator ──────────────────────────────────────────────


## Assembly correctness for one piece. Returns [] when the costume is right.
static func validate_piece(pv: PieceView, piece_type: int, house_id: String) -> Array[String]:
	var errs: Array[String] = []
	var tag := "%s/%s" % [house_id if not house_id.is_empty() else "legacy",
			PieceView.Type.keys()[piece_type]]
	if pv.get_child_count() == 0:
		return ["%s: setup built nothing" % tag]
	# TYPE: glyph ring under every piece, with its per-piece emissive material.
	if pv.find_child("GlyphRing", false, false) == null:
		errs.append("%s: no GlyphRing" % tag)
	elif pv._glyph_mat == null or not pv._glyph_mat.emission_enabled:
		errs.append("%s: glyph material missing/not emissive" % tag)
	# TYPE: signature gear.
	for spec: Dictionary in PieceAssets.gear_specs(piece_type):
		var prop := pv.find_child("Gear_%s" % spec["key"], true, false)
		if prop == null:
			errs.append("%s: missing gear %s" % [tag, spec["key"]])
		elif bool(spec["decal"]) and HouseRegistry.has_house(house_id) \
				and prop.find_child("SigilDecal", false, false) == null:
			errs.append("%s: shield lacks its sigil decal" % tag)
	# HOUSE: crest on knight/queen/king only, and only for real houses.
	var want_crest: bool = PieceAssets.wants_crest(piece_type) \
			and PieceAssets.crest_scene(house_id) != null
	var has_crest := pv.find_child("Crest", true, false) != null
	if want_crest != has_crest:
		errs.append("%s: crest %s, expected %s" % [tag, has_crest, want_crest])
	errs.append_array(_validate_helm(pv, piece_type, house_id, tag))
	# TYPE: king wears crown + cape; nobody else wears a node named Crown
	# (the e2e board-truth scenario greps for exactly that).
	var crowned := not pv.find_children("Crown", "", true, false).is_empty()
	if (piece_type == PieceView.Type.KING) != crowned:
		errs.append("%s: crown presence wrong (%s)" % [tag, crowned])
	var caped := pv.find_child("Cape", true, false) != null
	if (piece_type == PieceView.Type.KING) != caped:
		errs.append("%s: cape presence wrong (%s)" % [tag, caped])
	# TYPE: queen wears the slim Tiara (royal swap 2026-08-08); nobody else,
	# and never a node named Crown — e2e proves queens uncrowned by that name.
	var tiaraed := pv.find_child("Tiara", true, false) != null
	if (piece_type == PieceView.Type.QUEEN) != tiaraed:
		errs.append("%s: tiara presence wrong (%s)" % [tag, tiaraed])
	# TYPE: the knight is MOUNTED (ISSUES.md #1) — horse under him, saddle
	# and house-dressed caparison on the horse, rider seated above the saddle.
	# The mount is deliberately a STATIC unskinned mesh (see PieceAssets.HORSE)
	# animated procedurally, so what must be live is the idle-sway tween — not
	# an AnimationPlayer.
	if piece_type == PieceView.Type.KNIGHT:
		for part in ["Horse", "Saddle", "Caparison", "Rider"]:
			if pv.find_child(part, true, false) == null:
				errs.append("%s: mounted knight missing %s" % [tag, part])
		var cap := pv.find_child("Caparison", true, false) as MeshInstance3D
		if cap != null and cap.material_override == null:
			errs.append("%s: caparison not dressed" % tag)
		if pv._horse != null:
			if not pv._horse.find_children("*", "Skeleton3D", true, false).is_empty():
				errs.append("%s: horse must ship unskinned/static" % tag)
			var hide_mesh := pv._horse.find_child("Horse", true, false) as MeshInstance3D
			if hide_mesh == null:
				errs.append("%s: horse hide mesh missing" % tag)
			elif hide_mesh.get_surface_override_material(0) == null:
				errs.append("%s: horse hide not wearing the house tint" % tag)
		if pv._sway_tween == null or not pv._sway_tween.is_running():
			errs.append("%s: mount's idle sway not running" % tag)
		if pv._rider != null and pv._rider.position.y < 0.5:
			errs.append("%s: rider not seated above the mount" % tag)
	# HOUSE: Tidegrip fields skeletons; everyone else fields adventurers.
	if piece_type != PieceView.Type.ROOK:
		var skeletal := false
		for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
			if str(mi.name).begins_with("Skeleton_"):
				skeletal = true
				break
		var want_skeletal := house_id == PieceAssets.SKELETON_HOUSE
		if skeletal != want_skeletal:
			errs.append("%s: skeleton cast %s, expected %s" % [tag, skeletal, want_skeletal])
		if pv._anim == null:
			errs.append("%s: no AnimationPlayer" % tag)
	else:
		# BANNER-ROOK: tower body, sigil banner, flutter pennant.
		for part in ["TowerBody", "BannerCloth", "Pennant", "PennantPole"]:
			if pv.find_child(part, true, false) == null:
				errs.append("%s: watchtower missing %s" % [tag, part])
		var banner := pv.find_child("BannerCloth", true, false) as MeshInstance3D
		if banner != null:
			var bmat := banner.material_override as StandardMaterial3D
			if bmat == null or bmat.albedo_texture == null:
				errs.append("%s: banner has no texture" % tag)
		var pennant := pv.find_child("Pennant", true, false) as MeshInstance3D
		if pennant != null and not pennant.material_override is ShaderMaterial:
			errs.append("%s: pennant lacks the flutter ShaderMaterial" % tag)
	return errs


## HOUSE: the per-house PAWN half-helm (ISSUES.md #3) — pawns of a real house
## wear one and NOBODY else does; it hangs off the head bone so the height law
## can't feel it; BOTH its surfaces are dressed (the dome in the house body
## color, the rim/motif in the house charge — critic defect #11: nine armies
## shipped with the same black dome and the pawn ranks were interchangeable);
## and the Barbarian's bear hood is off, because a helm under that hood is a
## helm nobody will ever see.
static func _validate_helm(pv: PieceView, piece_type: int, house_id: String,
		tag: String) -> Array[String]:
	var errs: Array[String] = []
	var want_helm: bool = PieceAssets.wants_helm(piece_type) \
			and PieceAssets.pawn_helm_scene(house_id) != null
	var helm := pv.find_child("Helm", true, false) as Node3D
	if want_helm != (helm != null):
		errs.append("%s: helm %s, expected %s" % [tag, helm != null, want_helm])
		return errs
	if helm == null:
		# No helm expected: the pawn body must still be wearing its own hood.
		for mi: MeshInstance3D in pv.find_children(
				PieceAssets.BEAR_HOOD_PATTERN, "MeshInstance3D", true, false):
			if not mi.visible:
				errs.append("%s: bear hood doffed with no helm to replace it" % tag)
		return errs
	var att := helm.get_parent() as BoneAttachment3D
	if att == null or att.bone_name != "head":
		errs.append("%s: helm not mounted on the head bone" % tag)
	if not helm.position.is_equal_approx(PieceView.HELM_MOUNT_POS):
		errs.append("%s: helm mounted at %v, expected %v"
				% [tag, helm.position, PieceView.HELM_MOUNT_POS])
	var accent_dressed := false
	var shell_dressed := false
	for mi: MeshInstance3D in helm.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s)
			if base == null:
				continue
			var mat_name := str(base.resource_name)
			if mat_name.begins_with(PieceAssets.HELM_ACCENT_MATERIAL) \
					and mi.get_surface_override_material(s) != null:
				accent_dressed = true
			if mat_name.begins_with(PieceAssets.HELM_IRON_MATERIAL) \
					and mi.get_surface_override_material(s) != null:
				shell_dressed = true
	if not accent_dressed:
		errs.append("%s: helm rim/motif not wearing the house charge" % tag)
	if not shell_dressed:
		errs.append("%s: helm dome not wearing the house color" % tag)
	# The bear hood must be HIDDEN (never freed — see PieceView._doff_bear_hood).
	for mi: MeshInstance3D in pv.find_children(
			PieceAssets.BEAR_HOOD_PATTERN, "MeshInstance3D", true, false):
		if mi.visible:
			errs.append("%s: bear hood still worn over the helm" % tag)
	return errs


# ── palette envelope (defects #6/#7) ───────────────────────────────────────
#
# The bug these constants exist to prevent: a material that never went through
# the house dye still renders, and a stock pack color becomes the loudest thing
# in the frame. Nine armies shipped with a fluorescent MAGENTA grimoire, a LIME
# staff orb, a SALMON shield rim, a FOREST-GREEN queen's hood and an ORANGE-TAN
# bow, in every house, because signature gear was attached after _tint_meshes
# "so it keeps its own colors".
#
# A surface is legal when BOTH hold:
#   1. its albedo TEXTURE is desaturated to the ceiling — no texel can shout
#      louder than PALETTE_TEXEL_LOUDNESS (saturation x value in HSV);
#   2. its flat albedo lands on a house hue (or is neutral / near-black, which
#      every palette contains — iron, bone, leather, shadow).

## Loudest texel any dyed surface may still carry (HSV saturation x value).
## A raw KayKit atlas scores 0.6+; the same atlas desaturated to the palette
## ceiling scores ~0.10.
const PALETTE_TEXEL_LOUDNESS := 0.22
## How far a flat albedo may sit from the nearest house hue, in degrees.
const PALETTE_HUE_TOL := 46.0
## Chroma weight (HSV saturation x value) below which a color carries no house
## information and is always legal — iron, bone, leather, shadow. A dark olive
## banner rod scores 0.05; the shipped magenta grimoire scored 0.53 and the
## lime staff orb 0.18.
const PALETTE_CHROMA_FLOOR := 0.10
## HERALDRY + REGALIA — deliberately outside the dye, by name:
##   sigil plate / banner cloth / caparison / pennant carry the house's own
##     artwork; dyeing them would dye the sigil.
##   crown / tiara / TiaraBand are gold-and-frost, the two metals of kingship
##     — that contrast against the house body IS the royal read (defect #3).
##   the glyph ring is a TYPE marker, not a house one.
const PALETTE_EXEMPT := ["SigilDecal", "BannerCloth", "Pennant", "Caparison",
		"Crown", "Tiara", "TiaraBand", "GlyphRing"]

## Every surface this piece renders that is outside its house's palette.
## Returns [] when the whole piece reads as one house.
static func palette_offenders(pv: PieceView, house_id: String) -> Array[String]:
	var errs: Array[String] = []
	if not HouseRegistry.has_house(house_id):
		return errs
	var hues: Array[float] = []
	for c: Color in PieceAssets.house_palette(house_id):
		if c.s * c.v > PALETTE_CHROMA_FLOOR:
			hues.append(c.h * 360.0)
	for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or _palette_exempt(mi, pv):
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var tag := "%s/%s#%d" % [house_id, mi.name, s]
			var loud := _texel_loudness(mat.albedo_texture)
			if loud > PALETTE_TEXEL_LOUDNESS:
				errs.append("%s: undyed texture (loudness %.2f)" % [tag, loud])
			var flat := mat.albedo_color * _texture_mean(mat.albedo_texture)
			if flat.s * flat.v <= PALETTE_CHROMA_FLOOR:
				continue
			var best := 360.0
			for h in hues:
				best = minf(best, absf(wrapf(flat.h * 360.0 - h, -180.0, 180.0)))
			if best > PALETTE_HUE_TOL:
				errs.append("%s: hue %.0f is %.0f deg off the house palette (%s)"
						% [tag, flat.h * 360.0, best, flat.to_html(false)])
	return errs


static func _palette_exempt(mi: MeshInstance3D, pv: PieceView) -> bool:
	var node: Node = mi
	while node != null and node != pv:
		for name in PALETTE_EXEMPT:
			if str(node.name).containsn(name):
				return true
		node = node.get_parent()
	return false


static var _palette_stats: Dictionary = {}   # texture rid -> [loudness, mean]


## [loudest texel (HSV s*v), mean color] of a texture, sampled on a grid.
static func _palette_probe(tex: Texture2D) -> Array:
	if tex == null:
		return [0.0, Color.WHITE]
	var key := tex.get_instance_id()
	if _palette_stats.has(key):
		return _palette_stats[key]
	var img := tex.get_image()
	if img == null:
		_palette_stats[key] = [0.0, Color.WHITE]
		return _palette_stats[key]
	if img.is_compressed():
		img.decompress()
	var steps := 24
	var loud := 0.0
	var sum := Color(0.0, 0.0, 0.0)
	var n := 0
	for iy in steps:
		for ix in steps:
			var px := img.get_pixel(
					int((ix + 0.5) / steps * img.get_width()),
					int((iy + 0.5) / steps * img.get_height()))
			if px.a < 0.5:
				continue
			loud = maxf(loud, px.s * px.v)
			sum += px
			n += 1
	var mean := Color.WHITE if n == 0 else Color(sum.r / n, sum.g / n, sum.b / n)
	_palette_stats[key] = [loud, mean]
	return _palette_stats[key]


static func _texel_loudness(tex: Texture2D) -> float:
	return float(_palette_probe(tex)[0])


static func _texture_mean(tex: Texture2D) -> Color:
	return _palette_probe(tex)[1]


## Measured world height of the piece body (the height-grading ground truth).
static func measured_height(pv: PieceView) -> float:
	if pv._model == null:
		return 0.0
	var raw := 0.0
	if pv.piece_type == PieceView.Type.ROOK:
		var body := pv._model.find_child("TowerBody", true, false) as MeshInstance3D
		if body != null:
			raw = body.mesh.get_aabb().end.y
	elif pv.piece_type == PieceView.Type.KNIGHT:
		# the mounted ensemble's reference: the seated rider's helm
		raw = pv._rider.position.y + pv._raw_model_height(pv._rider)
	else:
		raw = pv._raw_model_height(pv._model)
	return raw * pv._model.scale.y


# ── headless gate ──────────────────────────────────────────────────────────


func _run_headless_gate() -> void:
	var combos: Array = []
	for hid in HouseRegistry.house_ids():
		for t in TYPE_ORDER:
			combos.append([hid, t, PieceView.House.FROST])
	for t in TYPE_ORDER:   # legacy compatibility — both sides
		combos.append(["", t, PieceView.House.FROST])
		combos.append(["", t, PieceView.House.EMBER])
	var failures := 0
	for combo in combos:
		var pv: PieceView = PieceScene.instantiate()
		add_child(pv)
		pv.setup(combo[1], combo[2], combo[0])
		var errs := validate_piece(pv, combo[1], combo[0])
		for e in errs:
			print("COSTUME FAIL  ", e)
		failures += errs.size()
		pv.free()
	print("=== costume gate: %d combos, %d failures ===" % [combos.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)


# ── windowed preview ───────────────────────────────────────────────────────


func _build_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.17, 0.16, 0.15)
	fmat.roughness = 1.0
	floor_mesh.material_override = fmat
	floor_mesh.position = Vector3(3.4, 0.0, 9.0)
	add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.085, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true


func _build_grid() -> void:
	var houses := HouseRegistry.house_ids()
	houses.append("")   # legacy row at the back
	for row in houses.size():
		var hid: String = houses[row]
		var pieces: Array = []
		var row_root := Node3D.new()
		row_root.name = "Row_%s" % (hid if not hid.is_empty() else "legacy")
		add_child(row_root)
		for col in TYPE_ORDER.size():
			var pv: PieceView = PieceScene.instantiate()
			row_root.add_child(pv)
			# EMBER faces -Z — straight into the preview camera.
			pv.setup(TYPE_ORDER[col], PieceView.House.EMBER, hid)
			# pawn on screen-left: camera looks +Z, so world +X is screen-left
			pv.position = Vector3(
				(TYPE_ORDER.size() - 1 - col) * COL_STEP, 0.0, row * ROW_STEP)
			pieces.append(pv)
		_rows[hid] = pieces
		_row_roots[hid] = row_root


func _run_windowed_shots() -> void:
	await get_tree().create_timer(0.9).timeout   # let idles settle
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var houses := HouseRegistry.house_ids()
	houses.append("")
	var x_mid := (TYPE_ORDER.size() - 1) * COL_STEP * 0.5
	for row in houses.size():
		var hid: String = houses[row]
		var z := row * ROW_STEP
		# frame ONLY this house's row
		for other in _row_roots:
			(_row_roots[other] as Node3D).visible = other == hid
		# knight selected: shows the glyph-ring brighten in every house shot
		var knight: PieceView = _rows[hid][TYPE_ORDER.find(PieceView.Type.KNIGHT)]
		knight.set_selected(true)
		_cam.position = Vector3(x_mid, 2.7, z - 2.9)
		_cam.look_at(Vector3(x_mid, 0.45, z))
		await _settle()
		await _shot("%s/%s.png" % [dir, hid if not hid.is_empty() else "legacy"])
		knight.set_selected(false)
	for other in _row_roots:
		(_row_roots[other] as Node3D).visible = true
	_cam.position = Vector3(x_mid - 6.5, 8.5, -5.5)
	_cam.look_at(Vector3(x_mid, 0.4, (houses.size() - 1) * ROW_STEP * 0.45))
	await _settle()
	await _shot("%s/overview.png" % dir)
	# The mounted-knight beauty shot (ISSUES.md #1): one house's knight,
	# framed close and low from the 3/4 front — the cavalry silhouette check.
	var hero_hid := "goldclaw"
	for other in _row_roots:
		(_row_roots[other] as Node3D).visible = other == hero_hid
	var hero: PieceView = _rows[hero_hid][TYPE_ORDER.find(PieceView.Type.KNIGHT)]
	for pv: PieceView in _rows[hero_hid]:
		pv.visible = pv == hero   # the knight alone in frame
	var hp := hero.global_position
	_cam.position = hp + Vector3(0.60, 0.52, -0.80)
	_cam.look_at(hp + Vector3(0.0, 0.40, 0.0))
	await _settle()
	await _shot("%s/mounted_knight.png" % dir)
	for pv: PieceView in _rows[hero_hid]:
		pv.visible = true
	for other in _row_roots:
		(_row_roots[other] as Node3D).visible = true
	await _shoot_pawn_helms(dir)
	print("costume preview: wrote %d screenshots to %s" % [houses.size() + 5, dir])
	get_tree().quit(0)


## The PAWN-HELM parade (ISSUES.md #3): every house's pawn pulled out of its
## row into one formation and shot three times — the nine-house contact sheet
## (the "can I tell the houses apart?" gate), a living-house hero, and the
## Drowned Legion's charred twin on the skeleton cast. Positions/visibility and
## the camera's projection are restored afterwards so nothing downstream
## inherits the parade layout.
##
## The contact sheet is ORTHOGRAPHIC and STAGGERED (5 front, 4 behind) for one
## reason: nine figures across a single 16:9 frame is width-bound — in one line
## each pawn gets 1/9 of the width and ends up too small for its motif to
## survive. Two staggered ranks double the width per pawn, and orthographic
## projection stops the outer houses from shrinking and turning away from the
## camera, so all nine are judged on equal terms.
const PARADE_COLS := 5
const PARADE_X_STEP := 0.50
const PARADE_Z_STEP := 1.00
const PARADE_ORTHO_SIZE := 1.62
const PARADE_PITCH_DEG := 26.0

func _shoot_pawn_helms(dir: String) -> void:
	var pawn_col := TYPE_ORDER.find(PieceView.Type.PAWN)
	var houses := HouseRegistry.house_ids()
	var saved: Dictionary = {}
	var pawns: Array[PieceView] = []
	for other in _row_roots:
		(_row_roots[other] as Node3D).visible = not str(other).is_empty()
	for i in houses.size():
		var hid: String = houses[i]
		var pawn: PieceView = _rows[hid][pawn_col]
		for pv: PieceView in _rows[hid]:
			pv.visible = pv == pawn
		saved[pawn] = pawn.position
		# The camera looks +Z, so world +X is screen-LEFT: count columns down
		# from the right so the houses read left-to-right in registry order.
		var rank := i / PARADE_COLS
		var file := i % PARADE_COLS
		pawn.position = Vector3(
			float(PARADE_COLS - 1 - file) * PARADE_X_STEP + rank * PARADE_X_STEP * 0.5,
			0.0, rank * PARADE_Z_STEP)
		pawns.append(pawn)
	var mid := (PARADE_COLS - 1) * PARADE_X_STEP * 0.5 + PARADE_X_STEP * 0.25
	var focus := Vector3(mid, 0.42, PARADE_Z_STEP * 0.5)
	var pitch := deg_to_rad(PARADE_PITCH_DEG)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = PARADE_ORTHO_SIZE
	_cam.position = focus + Vector3(0.0, sin(pitch), -cos(pitch)) * 6.0
	_cam.look_at(focus)
	await _settle()
	await _shot("%s/pawn_helms.png" % dir)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	# Two close 3/4 heroes: a living house, then the Drowned Legion's charred
	# twin on the skeleton cast — the two castings a helm has to sit on.
	for shot in [["winterfang", "pawn_helm_hero"],
			[PieceAssets.SKELETON_HOUSE, "pawn_helm_drowned"]]:
		var hero: PieceView = _rows[shot[0]][pawn_col]
		for pawn: PieceView in pawns:
			pawn.visible = pawn == hero
		var hp := hero.global_position
		_cam.position = hp + Vector3(0.34, 0.80, -0.58)
		_cam.look_at(hp + Vector3(0.0, 0.50, 0.0))
		await _settle()
		await _shot("%s/%s.png" % [dir, shot[1]])
	for pawn: PieceView in pawns:
		pawn.position = saved[pawn]
	for hid in houses:
		for pv: PieceView in _rows[hid]:
			pv.visible = true
	for other in _row_roots:
		(_row_roots[other] as Node3D).visible = true


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("costume preview WARN: no viewport image for %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		print("costume preview WARN: save failed (%d): %s" % [err, path])
