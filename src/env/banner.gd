class_name HallBanner
extends Node3D
## A wall-hung banner (KayKit banner_white) with a per-instance recolor API.
## Neutral undyed cloth by default; the integrator dyes each of the hall's
## nine banners to a Great House's colors at runtime.
##
## Orientation: the cloth drapes on this node's LOCAL +Z side — place it at
## a wall segment's origin with +Z pointing into the room (same convention
## as Torch). The mesh hangs y 0.53..3.73 above this node's origin.
##
## API (integrator hooks):
##   set_house_color(primary)      dye the cloth (tints the whole banner)
##   clear_house_color()           back to neutral undyed cloth
##   house_color                   Color property, NEUTRAL when undyed
##
## Sharing: undyed banners all share the imported material. The first
## recolor duplicates the material for THAT instance only (surface
## override), so dyeing banner 3 never touches banner 7.

const BANNER_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/banner_white.gltf")
const NEUTRAL := Color(0.68, 0.64, 0.57)  # undyed wool over the white texture

var house_color: Color = NEUTRAL:
	set(value):
		house_color = value
		_apply(value)

var _mesh: MeshInstance3D
var _owned_material: StandardMaterial3D  # per-instance copy, lazily created


func _ready() -> void:
	var model := BANNER_SCENE.instantiate()
	add_child(model)
	_mesh = _find_mesh(model)
	if _mesh == null:
		push_error("banner_white.gltf has no MeshInstance3D")
		return
	_apply(house_color)


func set_house_color(primary: Color) -> void:
	house_color = primary


func clear_house_color() -> void:
	house_color = NEUTRAL


func _apply(color: Color) -> void:
	if _mesh == null:
		return  # not in tree yet; _ready re-applies house_color
	if _owned_material == null:
		var src := _mesh.mesh.surface_get_material(0)
		_owned_material = src.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _owned_material)
	_owned_material.albedo_color = color


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
