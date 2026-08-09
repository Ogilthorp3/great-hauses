extends Node3D
## THE NINE-HAUS FIELD — the instrument behind the colour pass (2026-08-09).
##
## The question "are these nine hauses confusable?" cannot be answered from
## the hex in the manifests. The hall is lit by eight ORANGE torches
## (src/env/torch.gd: light_color 1.0/0.58/0.28 at energy 2.7), a cool blue
## Sun, two fill directionals and a tonemapped Environment at exposure 1.12 —
## a transform that pulls every jersey toward amber and can collapse two
## swatches that separate cleanly in a palette file.
##
## So this rig rebuilds the GAME's stage exactly (same Environment values as
## scenes/game.tscn, the same GreatHall with its eight torches, the same
## camera pose the player boots into) and stands all nine hauses on the board
## plane at once. It then:
##
##   1. saves the field frame — the "board distance" look, judged by eye;
##   2. samples the RENDERED pixels of each haus's jersey and pawn dome
##      (median of a patch centred on an unprojected bone), and prints them
##      as HAUSFIELD lines for tools/haus_delta_e.py to turn into a CIELAB
##      pairwise matrix;
##   3. saves a probe overlay so a human can SEE that every sample landed on
##      the piece it claims and not on the stone behind it.
##
## Usage (windowed — it needs a real rasteriser):
##   Godot --path . --resolution 1920x1080 res://tools/haus_field.tscn
##   Godot --path . --resolution 1920x1080 res://tools/haus_field.tscn -- --cb
##
## NO new Light3D is created here beyond the two the GreatHall itself builds
## and the one Sun game.tscn ships: the eight omnis are all torches, and the
## suites assert it.

const PieceScene := preload("res://scenes/piece_view.tscn")
const HallScript := preload("res://src/env/great_hall.gd")

const SHOT_DIR := "res://test_e2e/artifacts/haus-field"

## The gameplay camera, copied from scenes/game.tscn: pivot at (0, 0.4, 0),
## the OrbitCamera's shipped yaw PI / pitch -0.85 / distance 11.5, fov 50.
const RIG_ORIGIN := Vector3(0.0, 0.4, 0.0)
const RIG_YAW := PI
const RIG_PITCH := -0.85
const RIG_DIST := 11.5
const CAM_FOV := 50.0

## Where the nine stand. The board is 8x8 at TILE_SIZE 1.0 centred on the
## origin, so this is a rank of nine across the near half and a rank of nine
## across the far half — near ones lit like a player's own army, far ones lit
## like the rival's, which is exactly the pair of lighting environments a
## haus has to survive.
const ROW_NEAR_Z := 2.5
const ROW_FAR_Z := -2.5
const COL_X0 := -4.0
const COL_STEP := 1.0

## Sample patch half-width in pixels — 17x17 at 1920x1080, which is roughly
## the whole helm dome and comfortably inside a mitre cone.
##
## The estimator is a DOMINANT-BUCKET one, not a mean and not a median. A
## median straddling a dome and the charge painted across it returns neither
## (goldclaw's gold dome measured #702731 — its own crimson motif — because
## the motif crosses the exact pixel the head bone unprojects to). Quantising
## to a coarse cube, taking the fullest bucket and averaging inside it returns
## the surface's colour and ignores the mark drawn on top of it.
const PATCH := 8
const BUCKETS := 6

var _cam: Camera3D
var _probes: Array = []       # {"px": Vector2i, "tag": String}
var _pieces: Array = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("haus_field needs a rasteriser — run it windowed")
		get_tree().quit(2)
		return
	_build_stage()
	_build_field()
	_run()


func _build_stage() -> void:
	# The hall itself — walls, floor, pillars, tables, and the eight torches.
	var hall := Node3D.new()
	hall.name = "GreatHall"
	hall.set_script(HallScript)
	add_child(hall)

	# scenes/game.tscn's Environment, value for value.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.027, 0.024, 0.031, 1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.275, 0.265, 1)
	e.ambient_light_energy = 0.66
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.12
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.093, 0.115, 1)
	e.fog_density = 0.006
	env.environment = e
	add_child(env)

	# ...and its one shadow caster (the hall builds its own two fills).
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(
		Vector3(-0.7738, 0.0, 0.6331),
		Vector3(0.5645, 0.4525, 0.69),
		Vector3(-0.2866, 0.8917, -0.3503),
		Vector3(0.0, 8.0, 0.0))
	sun.light_color = Color(0.64, 0.7, 0.82, 1)
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 2.2
	add_child(sun)

	# A board-sized slab so the pieces stand on stone, not on the hall floor.
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.7, 0.3, 8.7)
	slab.mesh = box
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.07, 0.065, 0.06)
	smat.roughness = 1.0
	slab.material_override = smat
	slab.position = Vector3(0.0, 0.07, 0.0)
	add_child(slab)

	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.position = RIG_ORIGIN
	rig.rotation = Vector3(RIG_PITCH, RIG_YAW, 0.0)
	add_child(rig)
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 0.0, RIG_DIST)
	_cam.fov = CAM_FOV
	rig.add_child(_cam)
	_cam.current = true


## Nine hauses, twice. The two probes are chosen because they are the two
## biggest UNBROKEN kit surfaces a top-down gameplay camera actually sees:
##   PAWN  — the helm DOME. Sixteen of these per army; at board distance the
##           dome IS the pawn, so the dome is the army's mass colour.
##   BISHOP— the mitre CROWN, the largest single kit cone in the cast.
## The king was tried first and dropped: from this camera his cape hangs
## behind him and the probe lands on his own skin.
func _build_field() -> void:
	var ids := HouseRegistry.house_ids()
	for i in ids.size():
		var hid: String = ids[i]
		var x := COL_X0 + i * COL_STEP
		_spawn(PieceView.Type.PAWN, PieceView.House.FROST, hid,
			Vector3(x, 0.22, ROW_NEAR_Z))
		_spawn(PieceView.Type.BISHOP, PieceView.House.EMBER, hid,
			Vector3(x, 0.22, ROW_FAR_Z))


func _spawn(t: int, side: int, hid: String, pos: Vector3) -> PieceView:
	var pv: PieceView = PieceScene.instantiate()
	add_child(pv)
	pv.setup(t, side, hid)
	pv.position = pos
	_pieces.append({"pv": pv, "hid": hid, "type": t})
	return pv


## THE TORCHES FLICKER (src/env/torch.gd: energy 2.7 modulated by a per-torch
## sine). One grabbed frame therefore samples one arbitrary phase, and two runs
## of this rig disagreed by up to 2 dE — which is a measurement that cannot be
## reproduced, i.e. not a measurement. So the numbers are the MEDIAN of
## SAMPLE_FRAMES frames spread over a torch cycle; the saved PNG is still one
## real frame, because a median image is not something the game ever draws.
const SAMPLE_FRAMES := 5
const SAMPLE_GAP := 0.37   # seconds between grabs — coprime-ish with the flicker


func _run() -> void:
	await _settle()
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/field.png" % dir)
	var series: Array = [img]
	for i in SAMPLE_FRAMES - 1:
		await get_tree().create_timer(SAMPLE_GAP).timeout
		await RenderingServer.frame_post_draw
		series.append(get_viewport().get_texture().get_image())
	_measure(series)
	var overlay := _overlay(img)
	overlay.save_png("%s/field_probes.png" % dir)
	print("HAUSFIELD done — %s (median of %d frames)" % [dir, SAMPLE_FRAMES])
	get_tree().quit(0)


## Dominant colour of a PATCH-square centred on a piece's key surface, taken
## per frame and reduced by the median across frames (see SAMPLE_FRAMES).
func _measure(series: Array) -> void:
	var img: Image = series[0]
	for rec in _pieces:
		var pv: PieceView = rec["pv"]
		var hid: String = rec["hid"]
		var t: int = rec["type"]
		var targets: Array = []
		if t == PieceView.Type.PAWN:
			targets = [["dome", _material_center(pv, PieceAssets.HELM_IRON_MATERIAL)]]
		else:
			targets = [["mitre", _mesh_center(pv, "*_Hat")]]
		for pair in targets:
			var world: Variant = pair[1]
			if world == null:
				print("HAUSFIELD %s %s MISS (no node)" % [hid, pair[0]])
				continue
			if _cam.is_position_behind(world):
				print("HAUSFIELD %s %s MISS (behind camera)" % [hid, pair[0]])
				continue
			var px := Vector2i(_cam.unproject_position(world))
			var rs: Array = []
			var gs: Array = []
			var bs: Array = []
			for frame: Image in series:
				var s := _dominant_patch(frame, px)
				rs.append(s.r)
				gs.append(s.g)
				bs.append(s.b)
			rs.sort()
			gs.sort()
			bs.sort()
			var m := rs.size() / 2
			var c := Color(rs[m], gs[m], bs[m])
			_probes.append({"px": px, "tag": "%s/%s" % [hid, pair[0]]})
			print("HAUSFIELD %s %s %s px=%d,%d" % [hid, pair[0],
					c.to_html(false), px.x, px.y])


func _dominant_patch(img: Image, px: Vector2i) -> Color:
	var bins: Dictionary = {}     # bucket key -> [n, r_sum, g_sum, b_sum]
	for dx in range(-PATCH, PATCH + 1):
		for dy in range(-PATCH, PATCH + 1):
			var x := clampi(px.x + dx, 0, img.get_width() - 1)
			var y := clampi(px.y + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			var key := "%d,%d,%d" % [int(c.r * BUCKETS), int(c.g * BUCKETS),
					int(c.b * BUCKETS)]
			var e: Array = bins.get(key, [0, 0.0, 0.0, 0.0])
			e[0] += 1
			e[1] += c.r
			e[2] += c.g
			e[3] += c.b
			bins[key] = e
	var best: Array = [0, 0.0, 0.0, 0.0]
	for k in bins:
		if int(bins[k][0]) > int(best[0]):
			best = bins[k]
	var n := maxf(float(best[0]), 1.0)
	return Color(best[1] / n, best[2] / n, best[3] / n)


## Global centre of the surface whose AUTHORED material carries this name —
## the only way to say "the dome, not the rim it is welded to", since both are
## surfaces of one mesh.
func _material_center(pv: Node, needle: String) -> Variant:
	for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null or not str(base.resource_name).begins_with(needle):
				continue
			var box: AABB = mi.mesh.get_aabb()
			# The dome is the TOP of the helm; its AABB includes the rim
			# skirt, so bias the probe up into the cap.
			var c := box.position + box.size * 0.5 + Vector3(0.0, box.size.y * 0.12, 0.0)
			return mi.global_transform * c
	return null


## Global centre of the first visible mesh matching a pattern.
func _mesh_center(pv: Node, pattern: String) -> Variant:
	for mi: MeshInstance3D in pv.find_children(pattern, "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.mesh.get_aabb()
		return mi.global_transform * (box.position + box.size * 0.5)
	return null


## The saved frame with a ring drawn at every sample point — so a human can
## confirm each probe landed on its piece rather than on the stone behind it.
func _overlay(src: Image) -> Image:
	var img := src.duplicate() as Image
	for p in _probes:
		var px: Vector2i = p["px"]
		for d in range(-PATCH - 2, PATCH + 3):
			for e in [-PATCH - 2, PATCH + 2]:
				_dot(img, px.x + d, px.y + e)
				_dot(img, px.x + e, px.y + d)
	return img


func _dot(img: Image, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, Color(1.0, 0.0, 1.0))


func _settle() -> void:
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
