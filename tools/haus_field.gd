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
## camera pose the player boots into), stands all nine hauses on the board
## plane, and reads the colours off the rendered frame.
##
## IT SAMPLED TWO SURFACES, AND THAT WAS THE DEFECT (art critic, 2026-08-09).
## The rig probed the PAWN DOME and the BISHOP MITRE and nothing else, so the
## palette pass that shipped on its numbers never looked at the KING. Five of
## nine kings were wearing crown_frost — sRGB #5b6371, a NAVY steel: the
## darkest, coolest object in their own armies, and the same navy Silverbrook
## wears as its identity. In Goldclaw vs Winterfang the gold king wore blue.
## A gate that measures two of six ranks is not a gate on the palette; it is a
## gate on two ranks.
##
## So it now samples EVERY rank, each on the surface that carries its haus:
##
##   PAWN    helm DOME        16 per army; at board distance the dome IS the pawn
##   BISHOP  mitre            the largest single kit cone in the cast
##   KNIGHT  CAPARISON        the banner cloth over the horse's flank
##   ROOK    BANNER           the watchtower's hanging cloth
##   KING    CAPE + CROWN     his mantle, and the regalia on his head
##   QUEEN   HOOD + TIARA     hers, and the regalia on hers
##
## ...and it no longer samples them by unprojecting a bone and hoping. THE
## SECOND HALF OF THE SAME DEFECT was the estimator: a patch centred on an
## unprojected mesh centre has no idea what is in FRONT of that mesh, and the
## first run of this very rewrite reported five kings' crowns as the colour of
## their own foreheads and all nine rook banners as the colour of the tower
## shadow they hang in. A rig that can be pointed at the wrong pixels will be.
##
## The estimator is now a SURFACE MASK. Every frame is grabbed twice:
##
##   1. the MASK frame — every target surface painted a unique flat id colour,
##      every other surface in the hall painted black, tonemap linear, glow and
##      fog off. Occlusion still happens, so the pixels wearing an id are
##      EXACTLY the pixels that surface actually shows the player;
##   2. the REAL frames — the hall as it ships.
##
## The sample is then the dominant colour bucket of the real frame OVER THAT
## MASK. A channel that shows fewer than MIN_PIXELS pixels is a MISS and says
## so; tools/haus_delta_e.py fails the gate on any MISS, which is the property
## that stops this class of miss recurring — a blind channel can no longer come
## back green.
##
## Six ranks do not fit in one frame from the gameplay camera — a piece one
## rank behind another is eaten by it at this pitch — so the rig runs three
## PASSES over the same stage, two ranks at a time (one in each row, which is
## the pair of lighting environments every haus has to survive).
##
## Usage (windowed — it needs a real rasteriser):
##   Godot --path . --resolution 1920x1080 res://tools/haus_field.tscn
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
## origin, so this is a rank of nine across each half — one row lit like a
## player's own army, one like the rival's, which is exactly the pair of
## lighting environments a haus has to survive.
const ROW_NEAR_Z := 2.5
const ROW_FAR_Z := -2.5
const COL_X0 := -4.0
const COL_STEP := 1.0

## The three passes: {near rank, far rank, frame name}.
const PASSES: Array = [
	{"near": 0, "far": 3, "tag": "pawn-bishop"},    # PAWN   / BISHOP
	{"near": 2, "far": 1, "tag": "knight-rook"},    # KNIGHT / ROOK
	{"near": 5, "far": 4, "tag": "king-queen"},     # KING   / QUEEN
]

## A channel with fewer visible pixels than this is not measured, it is
## guessed — so it is reported as a MISS and fails the gate. It is deliberately
## SMALL: the queen's tiara band is a hard-won slim ring (PieceView.TIARA_SCALE
## against CROWN_SCALE) and demanding a big pixel count of it would be
## demanding it stop being slim. Six pixels of a flat unlit metal, taken five
## times across a torch cycle, is a colour; zero is a blind channel.
const MIN_PIXELS := 6
## Colour cube for the dominant-bucket estimator. A median straddling a dome
## and the charge painted across it returns neither (goldclaw's gold dome once
## measured #702731 — its own crimson motif); quantising to a coarse cube,
## taking the fullest bucket and averaging inside it returns the surface and
## ignores the mark drawn on it.
const BUCKETS := 6

var _cam: Camera3D
var _env: Environment
var _pieces: Array = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("haus_field needs a rasteriser — run it windowed")
		get_tree().quit(2)
		return
	_build_stage()
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
	_env = e
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
	slab.name = "Slab"
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


## One pass's cast: nine hauses of the near rank across the near row, nine of
## the far rank across the far one.
func _build_field(near_type: int, far_type: int) -> void:
	var ids := HouseRegistry.house_ids()
	for i in ids.size():
		var hid: String = ids[i]
		var x := COL_X0 + i * COL_STEP
		_spawn(near_type, PieceView.House.FROST, hid,
			Vector3(x, 0.22, ROW_NEAR_Z))
		_spawn(far_type, PieceView.House.EMBER, hid,
			Vector3(x, 0.22, ROW_FAR_Z))


func _clear_field() -> void:
	for rec in _pieces:
		var pv: PieceView = rec["pv"]
		if is_instance_valid(pv):
			pv.queue_free()
	_pieces.clear()


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
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for pass_spec: Dictionary in PASSES:
		_build_field(int(pass_spec["near"]), int(pass_spec["far"]))
		await _settle()
		var tag: String = str(pass_spec["tag"])
		# 1. the MASK frame — who owns which pixel.
		var plan := _paint_mask()
		await _flush()
		var mask := get_viewport().get_texture().get_image()
		_restore_mask()
		await _flush()
		# 2. the REAL frames — the hall as it ships.
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/field_%s.png" % [dir, tag])
		var series: Array = [img]
		for i in SAMPLE_FRAMES - 1:
			await get_tree().create_timer(SAMPLE_GAP).timeout
			await RenderingServer.frame_post_draw
			series.append(get_viewport().get_texture().get_image())
		var owned := _measure(mask, plan, series)
		_paint_overlay(img, owned).save_png("%s/field_%s_probes.png" % [dir, tag])
		_clear_field()
		await get_tree().process_frame
	print("HAUSFIELD done — %s (median of %d frames, %d passes)"
			% [dir, SAMPLE_FRAMES, PASSES.size()])
	get_tree().quit(0)


# -- WHICH SURFACE CARRIES WHICH RANK ---------------------------------------
#
# Every entry is [channel name, Array of [MeshInstance3D, surface]]. Surfaces,
# not meshes: a KayKit figure is one atlas, so the king's tabard and the skin
# under it are the SAME mesh until the role split separates them — and it is
# the KIT half that carries the haus.

func _channels(pv: PieceView, t: int) -> Array:
	match t:
		PieceView.Type.PAWN:
			return [["dome", _by_material(pv, PieceAssets.HELM_IRON_MATERIAL)]]
		PieceView.Type.BISHOP:
			return [["mitre", _by_mesh(pv, "*_Hat")]]
		PieceView.Type.KNIGHT:
			return [["caparison", _by_mesh(pv, "Caparison")]]
		PieceView.Type.ROOK:
			return [["banner", _by_mesh(pv, "BannerCloth")]]
		PieceView.Type.KING:
			# THE KING'S MANTLE, and it took three runs to name it correctly.
			# He wears TWO capes: the attached cape.glb prop (mesh node "Cape",
			# which hangs down his back and shows this camera nothing but a
			# shadowed rim — eight of nine measured the same #1f232e, a rim and
			# not a haus) and the cast's own `Ranger_Cape` / `Skeleton*_Cape`,
			# which is the big coloured mantle a player actually sees. "*Cape"
			# catches both, the tabard's KIT half joins them, and the dominant
			# bucket picks whichever of the three the camera is really showing.
			var kit := _by_mesh(pv, "*Cape")
			kit.append_array(_kit_of(pv, "*_Body"))
			var out: Array = [["cape", kit]]
			out.append_array(_regalia_channels(pv, "Crown", "crown"))
			return out
		PieceView.Type.QUEEN:
			var hood := _kit_of(pv, "*_Head")
			hood.append_array(_kit_of(pv, "*_Body"))
			var out: Array = [["hood", hood]]
			out.append_array(_regalia_channels(pv, "Tiara", "tiara"))
			return out
	return []


## A regalia prop, one channel per SURFACE. The crown is one metal in two
## states of itself — a dark tarnished band under polished points — and a
## dominant-bucket estimator over the whole prop returns whichever tone happens
## to own more pixels, which is a coin toss decided by how much of the band the
## wearer's crest covers. Measured separately, each tone is its own answer:
## are all nine bands the same, are all nine points the same, and does at least
## one of them reach away from the army it is worn on.
func _regalia_channels(pv: PieceView, node_name: String, base: String) -> Array:
	var per_surface: Dictionary = {}
	for pair: Array in _by_mesh_under(pv, node_name):
		var s := int(pair[1])
		if not per_surface.has(s):
			per_surface[s] = []
		(per_surface[s] as Array).append(pair)
	var keys: Array = per_surface.keys()
	keys.sort()
	var out: Array = []
	for s: int in keys:
		out.append([base if s == 0 else "%spoints" % base, per_surface[s]])
	if out.is_empty():
		out.append([base, []])   # say so, loudly, rather than vanish
	return out


## Every surface whose AUTHORED material carries this name — the only way to
## say "the dome, not the rim it is welded to", since both are surfaces of one
## mesh.
func _by_material(pv: Node, needle: String) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in pv.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base != null and str(base.resource_name).begins_with(needle):
				out.append([mi, s])
	return out


## Every surface of every visible mesh matching a pattern.
func _by_mesh(pv: Node, pattern: String) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in pv.find_children(pattern, "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			out.append([mi, s])
	return out


## Every surface of every mesh UNDER a named node — the crown and the tiara are
## prop scenes, not single meshes.
func _by_mesh_under(pv: Node, node_name: String) -> Array:
	var root := pv.find_child(node_name, true, false) as Node3D
	if root == null:
		return []
	return _by_mesh(root, "*")


## The KIT half of a role-split mesh (PieceAssets.role_split_mesh). A body is
## a tabard AND a breastplate AND a leather strap; only the tabard is the haus.
func _kit_of(pv: Node, pattern: String) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in pv.find_children(pattern, "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var split: Dictionary = PieceAssets.split_roles_for_split_mesh(mi.mesh)
		for s in mi.mesh.get_surface_count():
			if int(split.get(s, PieceAssets.Role.UNCLASSIFIED)) == PieceAssets.Role.KIT:
				out.append([mi, s])
	return out


# -- THE MASK ---------------------------------------------------------------

## Flat unshaded ids on the target surfaces, black on everything else. Returns
## the plan: an Array of {"tag", "id"}. Restore with _restore_mask().
var _mask_saved: Array = []        # [mi, surface (-1 = material_override), prev]
var _mask_hidden: Array = []       # nodes hidden for the mask frame only
var _mask_env: Dictionary = {}


func _paint_mask() -> Array:
	var plan: Array = []
	var targets: Dictionary = {}    # mi -> {surface -> id Color}
	var idx := 0
	for rec in _pieces:
		for spec: Array in _channels(rec["pv"], int(rec["type"])):
			if idx >= ID_CAPACITY:
				push_error("haus_field: %d channels in one pass, %d ids available"
						% [idx + 1, ID_CAPACITY])
				get_tree().quit(3)
				return plan
			var id := _id_color(idx)
			idx += 1
			var tag := "%s/%s" % [rec["hid"], spec[0]]
			plan.append({"tag": tag, "id": id})
			if (spec[1] as Array).is_empty():
				print("HAUSFIELD %s %s MISS (the piece renders no such surface)"
						% [rec["hid"], spec[0]])
			for pair: Array in spec[1]:
				var mi: MeshInstance3D = pair[0]
				if not targets.has(mi):
					targets[mi] = {}
				targets[mi][int(pair[1])] = id
	# The hall and the board slab are HIDDEN for the mask frame. They stand
	# behind and under the pieces from this camera, so nothing they occlude
	# changes — and with them gone no lit masonry can land on an id's lattice
	# cell. (MultiMesh and any other renderable in the hall is out of reach of
	# a material_override sweep, which is how the stone got in the first time.)
	for node in [get_node_or_null("GreatHall"), get_node_or_null("Slab")]:
		if node != null:
			_mask_hidden.append(node)
			(node as Node3D).visible = false
	# Everything in the hall goes black; the targets then get their ids back,
	# per SURFACE (a material_override would paint the whole mesh).
	for mi: MeshInstance3D in _all_meshes():
		_mask_saved.append([mi, -1, mi.material_override])
		if targets.has(mi):
			mi.material_override = null
			for s in mi.mesh.get_surface_count():
				_mask_saved.append([mi, s, mi.get_surface_override_material(s)])
				mi.set_surface_override_material(s, _flat(
						targets[mi].get(s, Color.BLACK)))
		else:
			mi.material_override = _flat(Color.BLACK)
	# ...and the frame is graded LINEAR with no glow and no fog, so an id
	# arrives at the framebuffer as the id.
	_mask_env = {"tone": _env.tonemap_mode, "exp": _env.tonemap_exposure,
			"glow": _env.glow_enabled, "fog": _env.fog_enabled}
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = false
	_env.fog_enabled = false
	return plan


func _restore_mask() -> void:
	for entry in _mask_saved:
		var mi: MeshInstance3D = entry[0]
		if not is_instance_valid(mi):
			continue
		if int(entry[1]) < 0:
			mi.material_override = entry[2]
		else:
			mi.set_surface_override_material(int(entry[1]), entry[2])
	_mask_saved.clear()
	for node in _mask_hidden:
		if is_instance_valid(node):
			(node as Node3D).visible = true
	_mask_hidden.clear()
	_env.tonemap_mode = _mask_env["tone"]
	_env.tonemap_exposure = _mask_env["exp"]
	_env.glow_enabled = _mask_env["glow"]
	_env.fog_enabled = _mask_env["fog"]


func _all_meshes() -> Array:
	return find_children("*", "MeshInstance3D", true, false)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Ids on a 5x5x5 lattice at 0.2 spacing, brightest channel never below 0.4 —
## far enough apart that a nearest-id classification survives the last bit of
## rounding in the framebuffer, and far enough from black that the painted-out
## hall can never be mistaken for a target.
## Eight levels on a 0.1 lattice x three zero-channel patterns = 192 ids. It
## was 48 and that was not enough: adding the crown's second tone took one pass
## to 54 channels, the ids WRAPPED, and a whole haus's six channels came back
## as zero pixels because another haus had already claimed their lattice cells.
## _paint_mask now refuses to run rather than wrap.
const ID_STEPS := [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const ID_CAPACITY := 192


## An id's cell on the 0.1 lattice, as one integer.
func _lattice_key(c: Color) -> int:
	return int(round(c.r * 10.0)) * 121 + int(round(c.g * 10.0)) * 11 \
			+ int(round(c.b * 10.0))


## EVERY id has exactly one channel at zero. A NEUTRAL id is what broke the
## first mask run: id #0 came out (0.4,0.4,0.4) and the hall's own warm stone
## quantised onto the same lattice cell, so Winterfang's "crown" was measured
## as 4666 pixels of masonry. Two-channel ids cannot be confused with lit stone,
## and the hall is hidden for the mask frame besides — belt and braces, because
## this is precisely the failure mode the whole rewrite exists to end.
func _id_color(i: int) -> Color:
	var n: int = ID_STEPS.size()
	var a: int = i % n
	var b: int = (i / n) % n
	var zero: int = (i / (n * n)) % 3
	var col := Color(0.0, 0.0, 0.0)
	match zero:
		0:
			col.g = ID_STEPS[a]
			col.b = ID_STEPS[b]
		1:
			col.r = ID_STEPS[a]
			col.b = ID_STEPS[b]
		_:
			col.r = ID_STEPS[a]
			col.g = ID_STEPS[b]
	return col


# -- THE MEASUREMENT --------------------------------------------------------

## Dominant colour of each channel's own pixels, per frame, reduced by the
## median across frames. Returns {tag -> Array[Vector2i]} for the overlay.
func _measure(mask: Image, plan: Array, series: Array) -> Dictionary:
	var owned: Dictionary = {}
	for entry in plan:
		owned[str(entry["tag"])] = []
	# Classify by QUANTISED id rather than by scanning the plan per pixel: the
	# ids sit on a 0.1 lattice, so rounding each channel onto that lattice is an
	# exact identification and the whole 2-megapixel frame is one dictionary
	# lookup per pixel instead of thirty-six comparisons.
	var by_key: Dictionary = {}
	for entry in plan:
		var key := _lattice_key(entry["id"])
		if by_key.has(key):
			push_error("haus_field: id collision between %s and %s"
					% [by_key[key], entry["tag"]])
		by_key[key] = str(entry["tag"])
	var flat := mask.duplicate() as Image
	flat.convert(Image.FORMAT_RGBA8)
	var data := flat.get_data()
	var w := flat.get_width()
	var h := flat.get_height()
	var lut := PackedInt32Array()
	lut.resize(256)
	for v in 256:
		lut[v] = int(round(float(v) / 255.0 * 10.0))
	for i in w * h:
		var key: int = lut[data[i * 4]] * 121 + lut[data[i * 4 + 1]] * 11 \
				+ lut[data[i * 4 + 2]]
		if not by_key.has(key):
			continue
		(owned[by_key[key]] as Array).append(Vector2i(i % w, i / w))
	for entry in plan:
		var tag: String = str(entry["tag"])
		var px: Array = owned[tag]
		var parts := tag.split("/")
		if px.size() < MIN_PIXELS:
			print("HAUSFIELD %s %s MISS (%d px visible, floor %d)"
					% [parts[0], parts[1], px.size(), MIN_PIXELS])
			continue
		var rs: Array = []
		var gs: Array = []
		var bs: Array = []
		for frame: Image in series:
			var s := _dominant(frame, px)
			rs.append(s.r)
			gs.append(s.g)
			bs.append(s.b)
		rs.sort()
		gs.sort()
		bs.sort()
		var m := rs.size() / 2
		var col := Color(rs[m], gs[m], bs[m])
		print("HAUSFIELD %s %s %s px=%d" % [parts[0], parts[1],
				col.to_html(false), px.size()])
	return owned


func _dominant(img: Image, px: Array) -> Color:
	var bins: Dictionary = {}     # bucket key -> [n, r_sum, g_sum, b_sum]
	for p: Vector2i in px:
		var c := img.get_pixel(p.x, p.y)
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


## The real frame with every measured pixel tinted magenta — so a human can
## SEE which pixels each number was taken from, rather than trusting a square
## drawn near a bone. (The square is what hid the crown defect twice.)
func _paint_overlay(src: Image, owned: Dictionary) -> Image:
	var img := src.duplicate() as Image
	for tag in owned:
		for p: Vector2i in owned[tag]:
			var c := img.get_pixel(p.x, p.y)
			img.set_pixel(p.x, p.y, c.lerp(Color(1.0, 0.0, 1.0), 0.55))
	return img


func _flush() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _settle() -> void:
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
