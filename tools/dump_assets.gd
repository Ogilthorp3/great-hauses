extends SceneTree
## dump_assets.gd — print the mesh/material inventory of every dressable asset.
##
## The material-ROLE table (PieceAssets.MATERIAL_ROLES) has to name real
## surfaces, so this is the instrument that reads them off disk instead of
## guessing. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       -s res://tools/dump_assets.gd

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
	"res://assets/quaternius-animals/horse.glb",
	"res://assets/custom-props/crown.glb",
	"res://assets/custom-props/crown_frost.glb",
	"res://assets/custom-props/cape.glb",
	"res://assets/custom-props/watchtower.glb",
	"res://assets/custom-props/crests/crest_winterfang.glb",
	"res://assets/custom-props/pawn-helms/pawn_helm_winterfang.glb",
	"res://assets/custom-props/glyph-rings/glyph_ring_pawn.glb",
]


func _initialize() -> void:
	for p in PATHS:
		var packed: PackedScene = load(p)
		if packed == null:
			print("MISSING ", p)
			continue
		var inst: Node = packed.instantiate()
		print("\n=== ", p, " ===")
		_walk(inst, 0)
		inst.free()
	quit(0)


func _walk(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var parts := PackedStringArray()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var mname := "<null>" if mat == null else str(mat.resource_name)
			var tex := "-" if mat == null or mat.albedo_texture == null \
					else str(mat.albedo_texture.resource_path).get_file()
			var col := "-" if mat == null else mat.albedo_color.to_html(false)
			parts.append("s%d[%s tex=%s alb=%s]" % [s, mname, tex, col])
		extra = "  MESH tris=%d  %s" % [_tris(mi.mesh), " ".join(parts)]
	print(pad, n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_walk(c, depth + 1)


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else 0) / 3
	return n
