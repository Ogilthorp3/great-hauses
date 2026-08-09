extends SceneTree
## dump_uv_palette.gd — what colour does each body MESH actually wear?
##
## The KayKit casts paint a whole character from ONE 1024² atlas, so a mesh
## name alone does not say whether that mesh is cloth, steel or skin: the
## `*_Body` mesh carries a tabard AND a breastplate AND leather straps. This
## walks each mesh's UVs, samples the atlas under them, and prints the colour
## census per mesh — the evidence the ROLE table is written from.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       -s res://tools/dump_uv_palette.gd

const PATHS := [
	"res://assets/kaykit-adventurers/Barbarian.glb",
	"res://assets/kaykit-adventurers/Knight.glb",
	"res://assets/kaykit-adventurers/Mage.glb",
	"res://assets/kaykit-adventurers/Rogue_Hooded.glb",
	"res://assets/kaykit-adventurers/Ranger.glb",
	"res://assets/kaykit-skeletons/Skeleton_Minion.glb",
	"res://assets/kaykit-skeletons/Skeleton_Warrior.glb",
	"res://assets/kaykit-skeletons/Skeleton_Mage.glb",
	"res://assets/kaykit-skeletons/Skeleton_Rogue.glb",
	"res://assets/kaykit-adventurers/props/sword_1handed.gltf",
	"res://assets/kaykit-adventurers/props/shield_round.gltf",
	"res://assets/kaykit-adventurers/props/shield_badge.gltf",
	"res://assets/kaykit-adventurers/props/staff.gltf",
	"res://assets/kaykit-adventurers/props/spellbook_closed.gltf",
	"res://assets/kaykit-adventurers/props/bow_withString.gltf",
	"res://assets/kaykit-adventurers/props/quiver.gltf",
]


func _initialize() -> void:
	for p in PATHS:
		var packed: PackedScene = load(p)
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		print("\n=== ", str(p).get_file(), " ===")
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			_census(mi)
		inst.free()
	quit(0)


func _census(mi: MeshInstance3D) -> void:
	var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		print("  ", mi.name, "  (untextured)")
		return
	var img := mat.albedo_texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var tally := {}
	var total := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if uvs == null or uvs.is_empty():
			continue
		# Weight each triangle by its UV area so a big flat tabard outranks a
		# dense cluster of tiny trim triangles.
		var tris: int = (idx.size() / 3) if idx != null and not idx.is_empty() else 0
		for t in tris:
			var a := uvs[idx[t * 3]]
			var b := uvs[idx[t * 3 + 1]]
			var c := uvs[idx[t * 3 + 2]]
			var centroid := (a + b + c) / 3.0
			var px := img.get_pixel(
					clampi(int(centroid.x * w), 0, w - 1),
					clampi(int(centroid.y * h), 0, h - 1))
			var key := Color(
					floorf(px.r * 32.0) / 32.0,
					floorf(px.g * 32.0) / 32.0,
					floorf(px.b * 32.0) / 32.0).to_html(false)
			tally[key] = int(tally.get(key, 0)) + 1
			total += 1
	var rows: Array = []
	for k in tally:
		rows.append([k, tally[k]])
	rows.sort_custom(func(x, y): return x[1] > y[1])
	var line := ""
	for i in mini(6, rows.size()):
		var col := Color.html(str(rows[i][0]))
		line += "%s(%.0f%% h%.0f s%.2f v%.2f) " % [rows[i][0],
				100.0 * float(rows[i][1]) / maxf(total, 1),
				col.h * 360.0, col.s, col.v]
	print("  %-32s %s" % [mi.name, line])
