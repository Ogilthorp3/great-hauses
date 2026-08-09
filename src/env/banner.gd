class_name HallBanner
extends Node3D
## A wall-hung banner (KayKit banner_white) that flies ONE Great House: its
## dyed cloth AND its heraldic sigil.
##
## Neutral undyed cloth by default; the integrator dresses each of the hall's
## nine banners for the houses actually fighting the match (see
## GreatHall.dress_for_match). Before 2026-08-09 a banner could only be
## dyed — so every match hung anonymous coloured rectangles and the hall the
## war is fought in was the one room that did NOT say who was fighting
## (ISSUES.md P12). The sigil is what fixes that; the dye alone never did.
##
## Orientation: the cloth drapes on this node's LOCAL +Z side — place it at
## a wall segment's origin with +Z pointing into the room (same convention
## as Torch). The mesh hangs y 0.53..3.73 above this node's origin and spans
## x -0.75..0.75, its front face at z ~0.69 (probed in Godot, not assumed).
##
## API (integrator hooks):
##   set_house(id[, cloth])        fly a house: dye + its sigil (the dressing)
##   clear_house()                 back to neutral undyed cloth, sigil struck
##   set_house_color(primary)      dye the cloth only (sigil untouched)
##   clear_house_color()           back to neutral undyed cloth
##   house_color                   Color property, NEUTRAL when undyed
##   house_id                      String, "" when no sigil flies
##   has_sigil()                   test/e2e probe
##
## Sharing: undyed banners all share the imported material. The first
## recolor duplicates the material for THAT instance only (surface
## override), so dyeing banner 3 never touches banner 7. The sigil quad and
## its texture are per-instance too (nine 256px mips is nothing) — a static
## Resource cache is exactly the shutdown crash piece_assets.gd documents.
##
## NO Light3D on any path: the hall's 8-omni budget is FULL. The sigil is
## lifted out of the gloom with material emission, like every other prop.

const BANNER_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/banner_white.gltf")
const NEUTRAL := Color(0.68, 0.64, 0.57)  # undyed wool over the white texture

## Sigil placement on the cloth (local space; the numbers above are probed).
## The quad sits 0.011 proud of the frontmost cloth vertex — always in front,
## so it can never z-fight the drape.
const SIGIL_Z := 0.7005
const SIGIL_CENTER_Y := 2.33
const SIGIL_SIZE := 1.12
## Torch-glow lift so the charge reads on a dark wall at hall distance
## (matches the dragon rig's no-new-lights doctrine). Kept LOW on purpose:
## at 0.62 the self-glow swamped the sigil's own colours and every shield
## rendered as a white blob — measured at value 0.95 / saturation 0.03 on
## in-game frames, i.e. no heraldry left at all (2026-08-09).
const SIGIL_EMISSION := 0.10

var house_color: Color = NEUTRAL:
	set(value):
		house_color = value
		_apply(value)

## Which house flies here ("" = plain cloth, no sigil).
var house_id: String = ""

var _mesh: MeshInstance3D
var _owned_material: StandardMaterial3D  # per-instance copy, lazily created
var _sigil: MeshInstance3D = null
var _sigil_mat: StandardMaterial3D = null
var _pending_house := ""                 # set_house before _ready


func _ready() -> void:
	var model := BANNER_SCENE.instantiate()
	add_child(model)
	_mesh = _find_mesh(model)
	if _mesh == null:
		push_error("banner_white.gltf has no MeshInstance3D")
		return
	_apply(house_color)
	if not _pending_house.is_empty():
		var id := _pending_house
		_pending_house = ""
		set_house(id, house_color)


## THE DRESSING: fly `id`'s sigil here and dye the cloth. `cloth` defaults to
## the house's primary; pass a secondary/accent when a wall wants variety
## (the hall does — see GreatHall.dress_for_match).
func set_house(id: String, cloth: Variant = null) -> void:
	if id.is_empty():
		clear_house()
		return
	house_id = id
	var dye: Color = cloth if cloth is Color else HouseRegistry.get_colors(id)["primary"]
	house_color = dye
	if _mesh == null:
		_pending_house = id   # _ready re-runs the dressing
		return
	_build_sigil(id)


## Strike the colours: neutral cloth, no sigil.
func clear_house() -> void:
	house_id = ""
	_pending_house = ""
	if _sigil != null and is_instance_valid(_sigil):
		_sigil.queue_free()
	_sigil = null
	_sigil_mat = null
	house_color = NEUTRAL


func set_house_color(primary: Color) -> void:
	house_color = primary


func clear_house_color() -> void:
	house_color = NEUTRAL


## Test/e2e probe: is a sigil actually hanging on this banner?
func has_sigil() -> bool:
	return _sigil != null and is_instance_valid(_sigil) and _sigil.visible


func _apply(color: Color) -> void:
	if _mesh == null:
		return  # not in tree yet; _ready re-applies house_color
	if _owned_material == null:
		var src := _mesh.mesh.surface_get_material(0)
		_owned_material = src.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _owned_material)
	_owned_material.albedo_color = color


## Hang the house's sigil on the cloth. The generated PNGs ship WITHOUT
## mipmaps (assets/sigils/*.png.import, mipmaps/generate=false) and a banner
## is ~40 px wide from the player's camera — sampled straight, the charge
## crawls and aliases into noise. Mips are built here at load time instead,
## which needs no edit to an .import file outside this module's lane.
func _build_sigil(id: String) -> void:
	var tex := _mipped_sigil(id)
	if tex == null:
		return
	if _sigil == null or not is_instance_valid(_sigil):
		var quad := QuadMesh.new()
		quad.size = Vector2(SIGIL_SIZE, SIGIL_SIZE)
		_sigil_mat = StandardMaterial3D.new()
		_sigil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sigil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_sigil_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_sigil_mat.roughness = 1.0
		_sigil_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_sigil_mat.emission_enabled = true
		_sigil_mat.emission = Color.WHITE
		_sigil_mat.emission_energy_multiplier = SIGIL_EMISSION
		_sigil_mat.render_priority = 1   # after the cloth it lies on
		quad.material = _sigil_mat
		_sigil = MeshInstance3D.new()
		_sigil.name = "Sigil"
		_sigil.mesh = quad
		_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sigil.position = Vector3(0.0, SIGIL_CENTER_Y, SIGIL_Z)
		add_child(_sigil)
	_sigil_mat.albedo_texture = tex
	_sigil_mat.emission_texture = tex
	_sigil.visible = true


## The house sigil with a mip chain (null when the house has no art).
func _mipped_sigil(id: String) -> Texture2D:
	var src := HouseRegistry.load_sigil(id)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	img = img.duplicate()
	if img.is_compressed():
		if img.decompress() != OK:
			return src
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
