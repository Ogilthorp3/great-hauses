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
## validate_piece is the shared assembly validator and role_offenders the
## shared MATERIAL-ROLE gate — tests/test_costumes.gd calls both, so the gate
## logic lives in exactly one place.

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


# ── THE ROLE GATE ──────────────────────────────────────────────────────────
#
# This replaced the PALETTE ENVELOPE on 2026-08-09, and the two failures it
# stands between are opposite ones.
#
# The envelope was written after a critic found un-tinted marketplace props: a
# fluorescent MAGENTA grimoire on every bishop, a LIME staff orb, a SALMON
# shield rim, an ORANGE-TAN bow, in all nine houses, because signature gear was
# attached after the tint "so it keeps its own colors". Its rule was absolute —
# EVERY rendered surface must sit on the house hue — and to make that survivable
# on skin, steel and horsehide the saturation ceiling was driven to 0.10 and
# then to 0.00. Nine monochrome armies. The owner, looking at them:
#
#   "The figurines [are] too much mono color, should be like a hockey team
#    jersey — colors of the team/house, but NOT everywhere. Horse should be
#    brown, black or white, something majestic."
#
# So the gate now asks the same question the pipeline does — WHAT IS THIS
# SURFACE — and holds each role to its own law:
#
#   KIT       must be ON one of the house's own colours (jersey, primary,
#             secondary or accent — a jersey is allowed its charge) and must
#             carry real chroma. A stripped dye leaves a stock pack colour, and
#             that is what goes red.
#   NATURAL   must be inside its material's own range AND must NOT be the
#             house's kit colour. Steel and stone are near-achromatic; leather,
#             wood, skin, bone and horse coats live in the pack's warm-brown
#             band or are neutral. Paint a horse blue and it leaves the band.
#   REGALIA   must stay metal — gold or steel, never the jersey.
#   HERALDRY  carries its own artwork; exempt by role, not by a name list.
#   UNCLASS.  is a failure. No surface may render without the table naming it.
#
# tests/test_costumes.gd runs BOTH negative controls: strip a dye off a prop
# and the gate must go red; paint a horse blue and the gate must go red.

## Chroma weight (HSV saturation x value) below which a colour carries no house
## information at all — iron, bone, shadow, a black horse. Naturals below it
## are legal by definition.
const ROLE_CHROMA_FLOOR := 0.10
## How far a KIT surface may sit from the nearest of its house's four declared
## colours, in VALUE-NORMALISED RGB (each colour divided by its own brightest
## channel, so a shaded tabard and the swatch it was painted from compare as
## the same colour). Written as a match rather than a hue window on purpose: a
## jersey's charge is very often WHITE or BLACK — Winterfang's #eef2f5,
## Hartcrown's #1d1a17 — and a hue window either rejects those or lets any
## grey through.
const KIT_MATCH := 0.26
## Steel, iron and stone are defined by being nearly colourless — this is the
## most saturation they may carry, whisper included.
const NATURAL_METAL_SAT := 0.30
## Leather, wood, skin, bone and horse coats live in the pack's own warm ramp.
const NATURAL_WARM_LO := 5.0
const NATURAL_WARM_HI := 58.0
## ...and how far a natural surface must stay from the house's kit colour, in
## plain RGB distance. A chestnut coat sits ~0.45 from Goldclaw's gold and a bay
## ~0.22 from Hartcrown's bronze — the tightest real pair, since a bronze house
## and a leather strap are honestly similar colours. A coat DYED in the jersey
## sits at 0.0, which is the control.
const NATURAL_KIT_DISTANCE := 0.14


## Every surface this piece renders that breaks its role's law.
## Returns [] when the piece reads as a house TEAM made of real materials.
static func role_offenders(pv: PieceView, house_id: String) -> Array[String]:
	var errs: Array[String] = []
	if not HouseRegistry.has_house(house_id):
		return errs
	var house_colors: Array[Color] = PieceAssets.house_palette(house_id)
	var kit: Color = PieceAssets.kit_color(house_id)
	for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var split: Dictionary = split_roles_of(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var cls: Dictionary = PieceAssets.classify(str(mi.name),
					"" if base == null else str(base.resource_name))
			var tag := "%s/%s#%d" % [house_id, mi.name, s]
			# UNCLASSIFIED wins over everything, INCLUDING a split map: a mesh
			# the table does not name must fail even when its surfaces happen to
			# be wearing dressed materials. Silently dyeing the unknown case is
			# the habit that produced nine monochrome armies.
			if int(cls["role"]) == PieceAssets.Role.UNCLASSIFIED:
				errs.append("%s: UNCLASSIFIED — PieceAssets.MATERIAL_ROLES names no rule for it" % tag)
				continue
			var role: int = split.get(s, cls["role"])
			var flat := _rendered_color(mi, s, mat)
			match role:
				PieceAssets.Role.KIT:
					errs.append_array(_judge_kit(tag, flat, house_colors,
							mi.get_surface_override_material(s) != null
							or mi.material_override != null))
				PieceAssets.Role.NATURAL:
					var stuff: int = int(cls["stuff"]) if split.is_empty() \
							else PieceAssets.Stuff.ATLAS
					errs.append_array(_judge_natural(tag, flat, kit, stuff))
				PieceAssets.Role.REGALIA:
					errs.append_array(_judge_regalia(tag, flat, kit))
	return errs


## KIT: actually dressed, and wearing one of the house's own four colours.
##
## The DRESSED half is the structural check and it is what the negative control
## trips: a surface the role dispatch never touched still renders, in whatever
## the marketplace painted it, and that is the failure the whole gate exists
## for. The COLOUR half is the semantic one — value-normalised so that a fold
## in shadow and the swatch it came from compare as the same colour.
static func _judge_kit(tag: String, flat: Color, house_colors: Array[Color],
		dressed: bool) -> Array[String]:
	var errs: Array[String] = []
	if not dressed:
		errs.append("%s: KIT surface is UNDRESSED — it renders whatever the pack painted it" % tag)
		return errs
	var best := 9.9
	for c: Color in house_colors:
		best = minf(best, _normalized_distance(flat, c))
	if best > KIT_MATCH:
		errs.append("%s: KIT colour %s matches no house colour (nearest %.2f > %.2f)"
				% [tag, flat.to_html(false), best, KIT_MATCH])
	return errs


## RGB distance between two colours with their VALUE divided out — "is this the
## same colour, lit differently?" A black surface has no direction, so it is
## compared to black directly.
static func _normalized_distance(a: Color, b: Color) -> float:
	var na := _unit_value(a)
	var nb := _unit_value(b)
	return Vector3(na.r - nb.r, na.g - nb.g, na.b - nb.b).length()


static func _unit_value(c: Color) -> Color:
	var m := maxf(maxf(c.r, c.g), maxf(c.b, 0.0001))
	if m < 0.02:
		return Color(0.0, 0.0, 0.0)
	return Color(c.r / m, c.g / m, c.b / m)


## NATURAL: inside its material's own range, and NOT the house's jersey.
static func _judge_natural(tag: String, flat: Color, kit: Color,
		stuff: int) -> Array[String]:
	var errs: Array[String] = []
	var dist := Vector3(flat.r - kit.r, flat.g - kit.g, flat.b - kit.b).length()
	if dist < NATURAL_KIT_DISTANCE:
		errs.append("%s: NATURAL surface is wearing the house kit (%s, distance %.2f)"
				% [tag, flat.to_html(false), dist])
	if flat.s * flat.v <= ROLE_CHROMA_FLOOR:
		return errs   # neutral: iron, shadow, a black horse — legal by nature
	var hue := flat.h * 360.0
	var warm := hue >= NATURAL_WARM_LO and hue <= NATURAL_WARM_HI
	match stuff:
		PieceAssets.Stuff.STEEL, PieceAssets.Stuff.STONE:
			if flat.s > NATURAL_METAL_SAT:
				errs.append("%s: steel/stone at saturation %.2f is painted, not metal (%s)"
						% [tag, flat.s, flat.to_html(false)])
		PieceAssets.Stuff.COAT:
			if not warm and flat.s > NATURAL_METAL_SAT:
				errs.append("%s: horse coat hue %.0f is not a coat — bay, chestnut, black, grey and dun only (%s)"
						% [tag, hue, flat.to_html(false)])
		PieceAssets.Stuff.GLOW, PieceAssets.Stuff.NONE:
			pass   # eye paint and witch-light own their colour
		_:
			if not warm and flat.s > NATURAL_METAL_SAT:
				errs.append("%s: natural surface hue %.0f is outside the leather/wood/skin/bone band (%s)"
						% [tag, hue, flat.to_html(false)])
	return errs


## REGALIA: gold or steel, and never the jersey — that contrast IS the royal
## read (critic P3: a steel-blue army wearing a steel-blue crown loses its king).
static func _judge_regalia(tag: String, flat: Color, kit: Color) -> Array[String]:
	var errs: Array[String] = []
	if flat.s > 0.55:
		errs.append("%s: REGALIA at saturation %.2f is paint, not metal (%s)"
				% [tag, flat.s, flat.to_html(false)])
	var dist := Vector3(flat.r - kit.r, flat.g - kit.g, flat.b - kit.b).length()
	if dist < NATURAL_KIT_DISTANCE:
		errs.append("%s: REGALIA is wearing the house kit (%s) — the crown must contrast"
				% [tag, flat.to_html(false)])
	return errs


## For a mesh whose surfaces came out of a role SPLIT, which of them are KIT.
## Empty for every other mesh.
##
## Asked through the LIVE PieceAssets autoload on purpose. A `-s` suite that
## shims its own PieceAssets node holds a second, empty cache — the split was
## recorded by the autoload the pieces were actually built with, and reading
## the shim's copy silently reports "nothing was ever split" (which is exactly
## how this gate first passed a queen whose robe it never checked).
static func split_roles_of(mi: MeshInstance3D) -> Dictionary:
	return PieceAssets.split_roles_for_split_mesh(mi.mesh)


## What this surface ACTUALLY renders: its flat albedo multiplied by the mean
## of the texels its own UVs land on (PieceAssets.surface_mean_color), never by
## the mean of the whole shared atlas — on a pack where one 1024² image paints
## skin, steel, leather and cloth, the atlas mean is nobody's colour.
static func _rendered_color(mi: MeshInstance3D, s: int,
		mat: StandardMaterial3D) -> Color:
	if mat.albedo_texture == null:
		return mat.albedo_color
	return mat.albedo_color * PieceAssets.surface_mean_color(
			mi.mesh, s, mat.albedo_texture)


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
		errs.append_array(role_offenders(pv, combo[0]))
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
