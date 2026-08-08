extends Node3D
## Costume preview + verification rig (standalone; the game never loads this).
##
## Windowed (visual QA + screenshots):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/costume_preview.tscn
##   Renders all 9 houses' full sets in a grid (per-house rows + a legacy
##   FROST/EMBER row), saves one screenshot per house plus an all-houses
##   overview to test_e2e/artifacts/module-previews/costumes/, then quits.
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
const TYPE_ORDER: Array[int] = [
	PieceView.Type.PAWN, PieceView.Type.KNIGHT, PieceView.Type.BISHOP,
	PieceView.Type.ROOK, PieceView.Type.QUEEN, PieceView.Type.KING,
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


## Measured world height of the piece body (the height-grading ground truth).
static func measured_height(pv: PieceView) -> float:
	if pv._model == null:
		return 0.0
	var raw := 0.0
	if pv.piece_type == PieceView.Type.ROOK:
		var body := pv._model.find_child("TowerBody", true, false) as MeshInstance3D
		if body != null:
			raw = body.mesh.get_aabb().end.y
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
		var knight: PieceView = _rows[hid][1]
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
	print("costume preview: wrote %d screenshots to %s" % [houses.size() + 1, dir])
	get_tree().quit(0)


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
