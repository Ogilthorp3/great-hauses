extends SceneTree
## make_props.gd — build House Ravenmark's own helm and crest, with no Blender.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> \
##       -s res://houses/_examples/ravenmark/make_props.gd -- [out dir]
##
## Writes pawn_helm.glb and crest.glb next to house.json (or into `out dir`).
## It exists for two reasons:
##
##   1. It is how this example pack's art was actually made — a house pack in
##      this repo with art nobody can regenerate is exactly the "artifact older
##      than its own sources" defect this project has already caught once.
##   2. It is the shortest possible demonstration of the ENGINE'S DRESSING
##      CONTRACT (docs/HOUSE-PACK.md). Look at the material names below:
##
##        pawnhelm_iron / pawnhelm_accent   the two surfaces the game paints on
##                                          a pawn's half-helm — dome in the
##                                          house colour, rim and motif in its
##                                          charge. Name them this and you get
##                                          dressed for free.
##        the mesh node Crest_ravenmark     any mesh whose NODE name starts with
##                                          "Crest_" is KIT: the plume takes the
##                                          house jersey.
##        ravenmark_beak                    ...and the one surface that must NOT
##                                          take it. A beak is BONE. It is
##                                          declared "natural:bone" in
##                                          house.json, and that declaration is
##                                          why this raven has a pale beak
##                                          instead of a purple one.
##
## Authoring space is the KayKit Rig_Medium HEAD-BONE space used by
## tools/props/make_pawn_helms.py: origin = the skull-top contact point, +Y up,
## the face looking down +Z. A helm WRAPS the skull (it hangs below y=0 and
## keeps its motif under ~0.1 above it); a crest TOWERS over it.

const HELM_R := 0.50        # dome half-width, matching the shipped nine
const HELM_DROP := 0.60     # ...and how far it hangs below the crown line
const HELM_CEIL := 0.095    # nothing on a PAWN's helm may rise higher than this

const IRON := "pawnhelm_iron"
const ACCENT := "pawnhelm_accent"
const PLUME := "ravenmark_plume"
const BEAK := "ravenmark_beak"

## The pack's own palette. These are AUTHORED colours: the helm's two surfaces
## are repainted by the game (that is what the contract means), so what matters
## here is that they are near-neutral and let the dye land true. The crest's
## beak is not repainted — it is bone, and it ships bone-coloured.
const C_IRON := Color(0.168, 0.180, 0.200)
const C_ACCENT := Color(0.878, 0.878, 0.878)
const C_PLUME := Color(0.34, 0.30, 0.42)
const C_BONE := Color(0.882, 0.855, 0.784)


func _initialize() -> void:
	var out_dir := "res://houses/_examples/ravenmark"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = str(args[0])
	var abs_dir := ProjectSettings.globalize_path(out_dir) \
			if out_dir.begins_with("res://") or out_dir.begins_with("user://") else out_dir
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var rc := 0
	rc += _write(_build_helm(), abs_dir.path_join("pawn_helm.glb"))
	rc += _write(_build_crest(), abs_dir.path_join("crest.glb"))
	quit(1 if rc != 0 else 0)


# ── the helm: a wrapped skull with a raven's brow ──────────────────────────


func _build_helm() -> Node3D:
	var root := Node3D.new()
	root.name = "pawn_helm_ravenmark"
	var mi := MeshInstance3D.new()
	# The mesh node carries the house name: the costume suite asserts a pawn's
	# helm is ITS house's helm and not a shared one, by looking for the id here.
	mi.name = "Helm_ravenmark"
	var mesh := ArrayMesh.new()

	# 1. the dome — a half-ellipsoid open at the bottom, wrapping the skull
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_dome(iron, Vector3(0, -HELM_DROP, 0), Vector3(HELM_R, HELM_DROP + 0.02, HELM_R * 1.02), 18, 5)
	_commit(mesh, iron, IRON, C_IRON, 0.62)

	var acc := SurfaceTool.new()
	acc.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 2. the flared rim around the brow — every house's helm carries its charge
	#    here, so a footman reads by COLOUR even when his motif is 4 px tall
	_band(acc, -0.505, -0.415, HELM_R * 1.045, HELM_R * 1.10, 18)
	# 3. the beak: a straight corvid wedge over the nose, pointing down +Z
	_wedge(acc,
		Vector3(-0.085, -0.30, 0.36), Vector3(0.085, -0.30, 0.36),
		Vector3(-0.045, -0.20, 0.30), Vector3(0.045, -0.20, 0.30),
		Vector3(0.0, -0.325, 0.60))
	# 4. two feather tufts over the ears — the only thing that breaks the
	#    crown line, and only just (a pawn is humble)
	for side in [-1.0, 1.0]:
		_wedge(acc,
			Vector3(side * 0.30, -0.20, -0.10), Vector3(side * 0.44, -0.22, -0.16),
			Vector3(side * 0.26, -0.10, -0.04), Vector3(side * 0.40, -0.12, -0.10),
			Vector3(side * 0.33, HELM_CEIL, -0.30))
	_commit(mesh, acc, ACCENT, C_ACCENT, 0.55)

	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	return root


# ── the crest: a raven perched on the helm, wings folded ───────────────────


func _build_crest() -> Node3D:
	var root := Node3D.new()
	root.name = "crest_ravenmark"
	var mi := MeshInstance3D.new()
	# "Crest_*" is an ENGINE contract: any mesh node named this way is KIT and
	# takes the house jersey. The house id in the name is the costume suite's
	# per-house check, same as the helm.
	mi.name = "Crest_ravenmark"
	var mesh := ArrayMesh.new()

	var plume := SurfaceTool.new()
	plume.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body: a tapered blade of feathers rising back over the skull
	_wedge(plume,
		Vector3(-0.13, -0.02, -0.16), Vector3(0.13, -0.02, -0.16),
		Vector3(-0.10, 0.30, -0.30), Vector3(0.10, 0.30, -0.30),
		Vector3(0.0, 0.50, -0.62))
	# the head, thrust forward on a short neck
	_dome(plume, Vector3(0.0, 0.26, 0.16), Vector3(0.13, 0.14, 0.17), 12, 4)
	_wedge(plume,
		Vector3(-0.10, 0.10, -0.06), Vector3(0.10, 0.10, -0.06),
		Vector3(-0.11, 0.26, 0.06), Vector3(0.11, 0.26, 0.06),
		Vector3(0.0, 0.30, 0.20))
	# the folded wings, swept back down both flanks
	for side in [-1.0, 1.0]:
		_wedge(plume,
			Vector3(side * 0.10, 0.06, -0.10), Vector3(side * 0.20, 0.02, -0.06),
			Vector3(side * 0.13, 0.30, -0.26), Vector3(side * 0.26, 0.24, -0.20),
			Vector3(side * 0.30, -0.10, -0.56))
	_commit(mesh, plume, PLUME, C_PLUME, 0.75)

	# THE BEAK IS BONE. Declared "natural:bone" in house.json, which is what
	# keeps the house purple off it — the single most important line in this
	# whole example.
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	_wedge(bone,
		Vector3(-0.055, 0.30, 0.18), Vector3(0.055, 0.30, 0.18),
		Vector3(-0.045, 0.22, 0.18), Vector3(0.045, 0.22, 0.18),
		Vector3(0.0, 0.265, 0.46))
	_commit(mesh, bone, BEAK, C_BONE, 0.5)

	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	return root


# ── geometry helpers ───────────────────────────────────────────────────────


## Half-ellipsoid centred at `c`, `r` its three radii, open at the bottom.
func _dome(st: SurfaceTool, c: Vector3, r: Vector3, segments: int, rings: int) -> void:
	for ring in rings:
		var t0 := float(ring) / rings
		var t1 := float(ring + 1) / rings
		for s in segments:
			var a0 := TAU * s / segments
			var a1 := TAU * (s + 1) / segments
			var p00 := _on_dome(c, r, a0, t0)
			var p01 := _on_dome(c, r, a1, t0)
			var p10 := _on_dome(c, r, a0, t1)
			var p11 := _on_dome(c, r, a1, t1)
			_tri(st, p00, p10, p11, c)
			_tri(st, p00, p11, p01, c)


func _on_dome(c: Vector3, r: Vector3, ang: float, t: float) -> Vector3:
	var phi := t * PI * 0.5
	return c + Vector3(cos(ang) * r.x * cos(phi), r.y * sin(phi), sin(ang) * r.z * cos(phi))


## A flared band (truncated cone) — the helm's brow rim.
func _band(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float,
		segments: int) -> void:
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var axis := Vector3(0.0, (y0 + y1) * 0.5, 0.0)
		_tri(st, b0, t0, t1, axis)
		_tri(st, b0, t1, b1, axis)


## A closed wedge: a quad base (bl, br, tl, tr) drawn to a single tip.
func _wedge(st: SurfaceTool, bl: Vector3, br: Vector3, tl: Vector3, tr: Vector3,
		tip: Vector3) -> void:
	var mid := (bl + br + tl + tr + tip) / 5.0
	_tri(st, bl, br, tip, mid)
	_tri(st, br, tr, tip, mid)
	_tri(st, tr, tl, tip, mid)
	_tri(st, tl, bl, tip, mid)
	_tri(st, bl, tl, tr, mid)
	_tri(st, bl, tr, br, mid)


## One triangle of a convex shell, facing outward from `centre`.
##
## WINDING IS NOT COSMETIC, AND IT IS NOT INTUITIVE — this example twice
## rendered helms that the screenshot showed as bare skulls while every
## automated check passed, because the mesh, the materials and the roles were
## all exactly right and the faces were simply pointing the wrong way.
##
## The convention is measurable, so it was measured rather than guessed. In the
## shipped pawn helms (which render), the geometric winding normal
## (b-a)x(c-a) points TOWARD the shape's centre on 102 of 118 triangles, and
## DISAGREES with the vertex normal on all of them. That is Godot's front-face
## rule after the glTF import flips Z. So:
##
##   winding   -> oriented so (b-a)x(c-a) points INWARD  (this is the front face)
##   normal    -> the outward direction, supplied per vertex (this is the light)
##
## Every shape here is convex, so "outward" is just the direction away from an
## interior point.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		centre: Vector3) -> void:
	var mid := (a + b + c) / 3.0
	var outward := (mid - centre).normalized()
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(outward)
		st.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
		st.add_vertex(v)


func _commit(mesh: ArrayMesh, st: SurfaceTool, mat_name: String, albedo: Color,
		roughness: float) -> void:
	var mat := StandardMaterial3D.new()
	# THE NAME IS THE CONTRACT — the game finds these by resource_name, never by
	# surface index, and a runtime glTF parse preserves it.
	mat.resource_name = mat_name
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = 0.0
	st.set_material(mat)
	var made := st.commit()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made.surface_get_arrays(0))
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _write(node: Node3D, path: String) -> int:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(node, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	var tris := 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var box := AABB()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		box = mi.mesh.get_aabb()
	if err == OK:
		print("PROP OK    %-14s %4d tris  aabb %v .. %v" % [path.get_file(), tris,
				box.position, box.end])
	else:
		print("PROP FAIL  %s (err %d)" % [path, err])
	node.free()
	return 0 if err == OK else 1
