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

## ── THE FIELD IS DYED TO ITS CLOTH (critic defect P5, 2026-08-09) ──────────
## Measured on the shipped wide shot (showcase/02_great_hall_wide.png):
## Goldclaw's charge read at 4.2:1 against its crimson cloth and you saw the
## lion's sun at a glance; Winterfang's chevron came in at 1.99:1 inside its
## own shield on its own cream cloth, and at banner distance the device was
## simply not there. Two things were killing it and both are value, not
## colour: the shield's field is a mid slate that sits at the same value as
## pale cloth, and a 256 px device drawn ~40 px wide is sampled several mip
## levels down, where a thin white chevron averages INTO the field it lies on.
##
## The heraldic answer is the old one: a charge is placed on a field chosen to
## contrast the cloth. So the sigil's FIELD (its modal tone) is repainted per
## banner — deep when the cloth is light, pale when the cloth is dark — while
## the charge and the rim (everything far from the field in value) are kept
## exactly as the house drew them. The repaint happens BEFORE the mip chain is
## built, so every mip level averages the high-contrast version.
## A pixel this far (linear luminance) from the field tone counts as CHARGE
## and is left alone; nearer than this it is field and gets the new tincture.
const SIGIL_FIELD_SPAN := 0.15
## Linear luminance above which a cloth counts as "light" (take a deep field).
const SIGIL_CLOTH_LIGHT := 0.12
## Deep tincture: the cloth's own hue at this fraction of its value.
const SIGIL_GROUND_DARK := 0.16
## Pale tincture (dark cloth): how far toward parchment the field is carried.
const SIGIL_GROUND_LIGHT := 0.74
const SIGIL_PARCHMENT := Color(0.90, 0.87, 0.80)
## Working resolution of the repainted device. The banner is never wider than
## ~90 px on screen, the composite pass is O(n²) GDScript run nine times at
## hall build, and the mip chain is generated from this base.
const SIGIL_WORK_PX := 128

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
	# The sigil's field is dyed to the cloth it lies on, so a re-dye that left
	# the old device in place would hand back exactly the invisible charge this
	# module exists to prevent.
	if not house_id.is_empty() and _mesh != null:
		_build_sigil(house_id)


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
	var tex := _mipped_sigil(id, house_color)
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


## The house sigil, its field re-dyed to contrast `cloth`, with a mip chain
## built from the re-dyed art (null when the house has no art).
func _mipped_sigil(id: String, cloth: Color) -> Texture2D:
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
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > SIGIL_WORK_PX:
		img.resize(SIGIL_WORK_PX, SIGIL_WORK_PX, Image.INTERPOLATE_LANCZOS)
	_dye_field(img, cloth)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Repaint the sigil's FIELD (its modal tone) in a tincture that contrasts
## `cloth`, leaving the charge and the rim — every pixel more than
## SIGIL_FIELD_SPAN away in luminance — untouched. Mutates `img` in place.
func _dye_field(img: Image, cloth: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var field_lum := _field_luminance(img)
	if field_lum < 0.0:
		return   # nothing opaque to repaint
	var ground := field_tincture(cloth)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.02:
				continue
			var d: float = absf(luminance(c) - field_lum) / SIGIL_FIELD_SPAN
			if d >= 1.0:
				continue   # this is the charge (or the rim) — the house drew it
			var keep: float = d * d          # ease: the field goes fully over
			img.set_pixel(x, y, Color(
				lerpf(ground.r, c.r, keep),
				lerpf(ground.g, c.g, keep),
				lerpf(ground.b, c.b, keep), c.a))


## The tone the shield's field takes on this cloth: the cloth's own hue,
## deepened when the cloth is light and carried toward parchment when it is
## dark. Pure — unit-testable without a scene.
static func field_tincture(cloth: Color) -> Color:
	if luminance(cloth) >= SIGIL_CLOTH_LIGHT:
		return Color(cloth.r * SIGIL_GROUND_DARK, cloth.g * SIGIL_GROUND_DARK,
			cloth.b * SIGIL_GROUND_DARK, 1.0)
	return cloth.lerp(SIGIL_PARCHMENT, SIGIL_GROUND_LIGHT)


## Median luminance over the opaque pixels — the shield's field, which is the
## single largest tone in every one of the nine devices. -1.0 when nothing is
## opaque. Sampled on a grid: an exact median over 16 k pixels buys nothing a
## 4 k sample does not.
static func _field_luminance(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, int(sqrt(float(w * h) / 4096.0)))
	var lums := PackedFloat32Array()
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.a >= 0.5:
				lums.append(luminance(c))
			x += step
		y += step
	if lums.is_empty():
		return -1.0
	lums.sort()
	return lums[lums.size() / 2]


## WCAG relative luminance (Rec.709 over linearised sRGB) — the value a glance
## actually obeys, and the number the frame measurements are taken in.
static func luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## WCAG contrast ratio between two colours (1.0 = identical, 21.0 = max).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
