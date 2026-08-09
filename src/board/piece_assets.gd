extends Node
## Autoload "PieceAssets" — shared runtime caches for PieceView: the merged
## Rig_Medium animation library, per-house tinted materials, and the
## HOUSE-COSTUMES registry (type heights, signature gear, house crests,
## type-glyph rings, the banner watchtower, the knight's horse, the
## Tidegrip drowned legion).
##
## Deliberately an autoload NODE rather than `static var`s on PieceView:
## script statics holding Resources crash Godot during engine shutdown
## (teardown-order bug — bit us as a SIGSEGV after quit(0) in e2e runs).
## An autoload releases its references in normal tree teardown.
##
## TWO LAYERS, NEVER CONFUSED (the costume design principle):
##   piece TYPE  = silhouette + signature gear + height grading — identical
##                 logic across all houses, instantly readable;
##   HOUSE       = crest/shield-sigil/palette flourish — never changes the
##                 type silhouette.
##
## Dictionaries below key piece types by INT to avoid a parse-time cycle
## with class_name PieceView; the values mirror PieceView.Type order:
##   0 PAWN · 1 ROOK · 2 KNIGHT · 3 BISHOP · 4 QUEEN · 5 KING

const ANIM_GENERAL := preload("res://assets/kaykit-adventurers/Rig_Medium_General.glb")
const ANIM_MOVEMENT := preload("res://assets/kaykit-adventurers/Rig_Medium_MovementBasic.glb")

## The knight's mount (ISSUES.md #1): Quaternius CC0 horse (poly.pizza
## qvTrSG9pZF) run through tools/props/convert_horse.py — a STATIC standing
## pose plus the authored war-tack: "Saddle" and the house-dressable
## "Caparison" cloth. Deliberately unskinned: Godot corrupts this rig's
## skinned mesh at chess-piece instance scales (front half vanishes,
## camera-angle-dependently — Metal, Mobile and Forward+ alike), while
## static meshes render flawlessly. PieceView drives idle-sway, canter-bob
## and the death collapse procedurally — the banner-rook's proven pattern.
const HORSE := preload("res://assets/quaternius-animals/horse.glb")

const CROWN_GOLD := preload("res://assets/custom-props/crown.glb")
const CROWN_FROST := preload("res://assets/custom-props/crown_frost.glb")
const CAPE := preload("res://assets/custom-props/cape.glb")
const WATCHTOWER := preload("res://assets/custom-props/watchtower.glb")
const PENNANT_SHADER := preload("res://src/board/pennant_flutter.gdshader")

const LOOPED_ANIMS := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C",
		"Running_A", "Running_B"]

## TYPE layer — strict height grading (world units, tallest body point).
## pawn < bishop < knight < rook < queen < king, tuned so a full army reads
## at a glance from the default gameplay camera. The rook's reference is its
## TowerBody stone (the pennant pole is an accent allowed to poke above).
## The MOUNTED knight (ISSUES.md #1) moved up a slot — a rider on horseback
## reads taller than a foot bishop; his reference is the rider's helm (the
## crest, like the pennant, is an accent above it).
const TYPE_HEIGHT := {
	0: 0.78,   # PAWN
	1: 1.02,   # ROOK (TowerBody stone height)
	2: 0.98,   # KNIGHT (mounted: rider's helm atop the horse)
	3: 0.94,   # BISHOP
	4: 1.14,   # QUEEN
	5: 1.26,   # KING
}

## TYPE layer — the adventurer cast (all houses except Tidegrip).
## Royal swap 2026-08-08 (user-verified in the previews): the Ranger model
## has a goatee — it reads as a bearded MONARCH, not a queen — while the
## hooded rogue's clean face reads queenly. King = Ranger (crown + cape +
## sword), queen = Rogue_Hooded (tiara + bow + quiver).
const CHARACTER_SCENES := {
	0: preload("res://assets/kaykit-adventurers/Barbarian.glb"),     # PAWN
	2: preload("res://assets/kaykit-adventurers/Knight.glb"),        # KNIGHT (the RIDER — mounted on HORSE)
	3: preload("res://assets/kaykit-adventurers/Mage.glb"),          # BISHOP
	4: preload("res://assets/kaykit-adventurers/Rogue_Hooded.glb"),  # QUEEN
	5: preload("res://assets/kaykit-adventurers/Ranger.glb"),        # KING
}

## HOUSE layer — the Tidegrip Drowned Legion: same rig (Rig_Medium, same
## bones, same shared anims), skeleton cast swapped in wholesale.
const SKELETON_HOUSE := "tidegrip"
const SKELETON_SCENES := {
	0: preload("res://assets/kaykit-skeletons/Skeleton_Minion.glb"),   # PAWN
	2: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # KNIGHT
	3: preload("res://assets/kaykit-skeletons/Skeleton_Mage.glb"),     # BISHOP
	4: preload("res://assets/kaykit-skeletons/Skeleton_Rogue.glb"),    # QUEEN
	5: preload("res://assets/kaykit-skeletons/Skeleton_Warrior.glb"),  # KING
}

## TYPE layer — signature gear (KayKit adventurers prop set). Rigid mounts
## on Rig_Medium bones; handslot.* are the pack's purpose-built prop bones.
## pos/rot/scl are in bone space, tuned against the costume preview.
const GEAR_SWORD := preload("res://assets/kaykit-adventurers/props/sword_1handed.gltf")
const GEAR_SHIELD_ROUND := preload("res://assets/kaykit-adventurers/props/shield_round.gltf")
const GEAR_SHIELD_KITE := preload("res://assets/kaykit-adventurers/props/shield_badge.gltf")
const GEAR_STAFF := preload("res://assets/kaykit-adventurers/props/staff.gltf")
const GEAR_TOME := preload("res://assets/kaykit-adventurers/props/spellbook_closed.gltf")
const GEAR_BOW := preload("res://assets/kaykit-adventurers/props/bow_withString.gltf")
const GEAR_QUIVER := preload("res://assets/kaykit-adventurers/props/quiver.gltf")

const GEAR_SPECS := {
	0: [   # PAWN — footman: sword + round shield
		{"key": "sword", "scene": GEAR_SWORD, "bone": "handslot.r",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
		{"key": "shield", "scene": GEAR_SHIELD_ROUND, "bone": "handslot.l",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": true,
			"decal_pos": Vector3(0.0, 0.0, 0.21), "decal_size": 0.52},
	],
	1: [],  # ROOK — the watchtower carries the banner instead
	2: [   # KNIGHT — sword + kite shield
		{"key": "sword", "scene": GEAR_SWORD, "bone": "handslot.r",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
		{"key": "shield", "scene": GEAR_SHIELD_KITE, "bone": "handslot.l",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": true,
			"decal_pos": Vector3(0.0, -0.04, 0.14), "decal_size": 0.48},
	],
	3: [   # BISHOP — staff + tome
		{"key": "staff", "scene": GEAR_STAFF, "bone": "handslot.r",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
		{"key": "tome", "scene": GEAR_TOME, "bone": "handslot.l",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
	],
	4: [   # QUEEN — bow + quiver on the back
		{"key": "bow", "scene": GEAR_BOW, "bone": "handslot.l",
			"pos": Vector3.ZERO, "rot_deg": Vector3(-90.0, 0.0, 0.0),
			"scl": 1.0, "decal": false},
		{"key": "quiver", "scene": GEAR_QUIVER, "bone": "chest",
			"pos": Vector3(0.0, 0.55, -0.35), "rot_deg": Vector3(10.0, 0.0, 12.0),
			"scl": 1.0, "decal": false},
	],
	5: [   # KING — sword in hand; crown + cape attach separately
		{"key": "sword", "scene": GEAR_SWORD, "bone": "handslot.r",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
	],
}

## TYPE layer — engraved glyph rings (assets from tools/props/make_glyph_rings.py).
const GLYPH_RINGS := {
	0: preload("res://assets/custom-props/glyph-rings/glyph_ring_pawn.glb"),
	1: preload("res://assets/custom-props/glyph-rings/glyph_ring_rook.glb"),
	2: preload("res://assets/custom-props/glyph-rings/glyph_ring_knight.glb"),
	3: preload("res://assets/custom-props/glyph-rings/glyph_ring_bishop.glb"),
	4: preload("res://assets/custom-props/glyph-rings/glyph_ring_queen.glb"),
	5: preload("res://assets/custom-props/glyph-rings/glyph_ring_king.glb"),
}
const GLYPH_MATERIAL_NAME := "glyphring_glyph"
const GLYPH_ENERGY_REST := 1.1
const GLYPH_ENERGY_SELECTED := 3.4

## HOUSE layer — helmet crests (tools/props/make_crests.py), worn by
## knight/queen/king only. Pawns wear the humbler half-helm below — never a
## crest: the two registries are deliberately SEPARATE lists, because adding
## PAWN to this one would put a royal crest on every footman.
const CRESTED_TYPES: Array[int] = [2, 4, 5]
const CREST_SCENES := {
	"hartcrown": preload("res://assets/custom-props/crests/crest_hartcrown.glb"),
	"winterfang": preload("res://assets/custom-props/crests/crest_winterfang.glb"),
	"ashwyrm": preload("res://assets/custom-props/crests/crest_ashwyrm.glb"),
	"tidegrip": preload("res://assets/custom-props/crests/crest_tidegrip.glb"),
	"thornvale": preload("res://assets/custom-props/crests/crest_thornvale.glb"),
	"duskfire": preload("res://assets/custom-props/crests/crest_duskfire.glb"),
	"swiftcrest": preload("res://assets/custom-props/crests/crest_swiftcrest.glb"),
	"silverbrook": preload("res://assets/custom-props/crests/crest_silverbrook.glb"),
	"goldclaw": preload("res://assets/custom-props/crests/crest_goldclaw.glb"),
}

## HOUSE layer — PAWN half-helms (ISSUES.md #3, tools/props/make_pawn_helms.py).
## Worn by pawns ONLY, and deliberately quieter than the royal crest above: a
## crest sits ABOVE the skull (mount y 1.04, reaching ~0.85 higher still), a
## helm WRAPS it (mount y 0.945, ≤0.21 of motif above the crown line). The
## player reads "pawn" first and "which house" second.
##
## Each helm carries its house's archetype in ~200 tris — wolf ear plates,
## lion mane-comb, stag antler nubs, dragon saw-ridge, kraken tentacles, rose
## browline beads, sun disc, falcon wing-flares, trout fin — and exactly two
## materials, found BY NAME (never by surface index): HELM_IRON_MATERIAL is
## the shell (left as plain dark iron — that restraint is what keeps a pawn
## humble) and HELM_ACCENT_MATERIAL is the flared rim plus the motif, authored
## near-white so the multiply tint lands the house color true. The rim carries
## the accent on every helm, so a house reads by COLOR even when its motif is
## only a few pixels tall on the board.
const HELMED_TYPES: Array[int] = [0]
const PAWN_HELM_SCENES := {
	"hartcrown": preload("res://assets/custom-props/pawn-helms/pawn_helm_hartcrown.glb"),
	"winterfang": preload("res://assets/custom-props/pawn-helms/pawn_helm_winterfang.glb"),
	"ashwyrm": preload("res://assets/custom-props/pawn-helms/pawn_helm_ashwyrm.glb"),
	"tidegrip": preload("res://assets/custom-props/pawn-helms/pawn_helm_tidegrip.glb"),
	"thornvale": preload("res://assets/custom-props/pawn-helms/pawn_helm_thornvale.glb"),
	"duskfire": preload("res://assets/custom-props/pawn-helms/pawn_helm_duskfire.glb"),
	"swiftcrest": preload("res://assets/custom-props/pawn-helms/pawn_helm_swiftcrest.glb"),
	"silverbrook": preload("res://assets/custom-props/pawn-helms/pawn_helm_silverbrook.glb"),
	"goldclaw": preload("res://assets/custom-props/pawn-helms/pawn_helm_goldclaw.glb"),
}
## HOUSE layer — the Drowned Legion's twin: identical kraken geometry with the
## iron and rim baked charred (the crown.glb / crown_frost.glb precedent, one
## asset swap instead of a runtime material branch). Tidegrip's pawns are
## drowned skeletons on a charred charger; their helm came out of the same fire.
const PAWN_HELM_CHARRED := preload("res://assets/custom-props/pawn-helms/pawn_helm_tidegrip_charred.glb")
const HELM_IRON_MATERIAL := "pawnhelm_iron"
const HELM_ACCENT_MATERIAL := "pawnhelm_accent"
## The Barbarian pawn body ships wearing a full bear-skull hood that swallows
## any helm — PieceView hides (never frees) meshes matching this.
const BEAR_HOOD_PATTERN := "*BearHat*"

var _shared_anims: AnimationLibrary
var _tint_cache: Dictionary = {}    # "<material rid>|<tint html>" -> StandardMaterial3D
var _desat_cache: Dictionary = {}   # texture rid id -> Texture2D
var _sigil_mat_cache: Dictionary = {}   # house_id -> StandardMaterial3D
var _banner_tex_cache: Dictionary = {}  # house_id -> Texture2D


## Both Rig_Medium libraries merged once; the same rig drives every character
## — including the Tidegrip skeletons (same bones, verified by test_costumes).
func shared_anims() -> AnimationLibrary:
	if _shared_anims != null:
		return _shared_anims
	_shared_anims = AnimationLibrary.new()
	for packed: PackedScene in [ANIM_GENERAL, ANIM_MOVEMENT]:
		var inst := packed.instantiate()
		var player: AnimationPlayer = inst.get_node("AnimationPlayer")
		for anim_name in player.get_animation_list():
			if not _shared_anims.has_animation(anim_name):
				_shared_anims.add_animation(anim_name, player.get_animation(anim_name))
		inst.free()
	for anim_name in LOOPED_ANIMS:
		_shared_anims.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	return _shared_anims


func anim_length(anim_name: String) -> float:
	return shared_anims().get_animation(anim_name).length


# -- TYPE layer ------------------------------------------------------------


## Design height (world units) for a piece type — the height grading law.
func piece_height(piece_type: int) -> float:
	return TYPE_HEIGHT[piece_type]


## The character scene for a type: the adventurer cast, or the skeleton cast
## for the Drowned Legion. Callers pass PieceView.Type != ROOK.
func character_scene(piece_type: int, house_id: String) -> PackedScene:
	if house_id == SKELETON_HOUSE:
		return SKELETON_SCENES[piece_type]
	return CHARACTER_SCENES[piece_type]


## Signature-gear mount specs for a type (Array of Dictionaries; see GEAR_SPECS).
func gear_specs(piece_type: int) -> Array:
	return GEAR_SPECS[piece_type]


func glyph_ring_scene(piece_type: int) -> PackedScene:
	return GLYPH_RINGS[piece_type]


# -- HOUSE layer -----------------------------------------------------------


func wants_crest(piece_type: int) -> bool:
	return piece_type in CRESTED_TYPES


## The helmet-crest scene for a house (null for legacy sides / unknown ids).
func crest_scene(house_id: String) -> PackedScene:
	return CREST_SCENES.get(house_id)


func wants_helm(piece_type: int) -> bool:
	return piece_type in HELMED_TYPES


## The PAWN half-helm scene for a house (null for legacy sides / unknown ids —
## legacy pawns keep the bear hood they shipped with). The Drowned Legion
## fields the pre-charred twin.
func pawn_helm_scene(house_id: String) -> PackedScene:
	if house_id == SKELETON_HOUSE:
		return PAWN_HELM_CHARRED
	return PAWN_HELM_SCENES.get(house_id)


## Crown-variant mapping (kings only, custom-props INTEGRATION.md): a house
## whose piece tint leans blue — cold houses (Winterfang, Tidegrip,
## Swiftcrest, Silverbrook, legacy FROST) — crowns its king in frost silver;
## warm tints wear the battle-worn gold.
func crown_scene(tint: Color) -> PackedScene:
	return CROWN_FROST if tint.b > tint.r else CROWN_GOLD


## Shield-decal material: the house sigil PNG as an alpha-scissor plate,
## painted-heraldry style. Cached per house.
func sigil_material(house_id: String) -> StandardMaterial3D:
	if _sigil_mat_cache.has(house_id):
		return _sigil_mat_cache[house_id]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = HouseRegistry.load_sigil(house_id)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	mat.metallic = 0.0
	_sigil_mat_cache[house_id] = mat
	return mat


## The rook banner texture: house-cloth ground with the sigil blended over
## it (the sigil PNGs are transparent-background). v=0 is the banner TOP
## (the cloth's UVs follow the Godot image convention). Cached per house.
func banner_texture(house_id: String) -> Texture2D:
	if _banner_tex_cache.has(house_id):
		return _banner_tex_cache[house_id]
	var cloth := Color(0.82, 0.79, 0.74)   # undyed cloth for legacy sides
	if HouseRegistry.has_house(house_id):
		var cols: Dictionary = HouseRegistry.get_colors(house_id)
		cloth = (cols["primary"] as Color).darkened(0.12)
	var img := Image.create(256, 384, false, Image.FORMAT_RGBA8)
	img.fill(cloth)
	# hem stripe in the house accent
	if HouseRegistry.has_house(house_id):
		var accent: Color = HouseRegistry.get_colors(house_id)["accent"]
		img.fill_rect(Rect2i(0, 360, 256, 24), accent.darkened(0.2))
	if HouseRegistry.has_house(house_id):
		var sigil_img := HouseRegistry.load_sigil(house_id).get_image()
		if sigil_img != null:
			if sigil_img.is_compressed():
				sigil_img.decompress()
			sigil_img.convert(Image.FORMAT_RGBA8)
			img.blend_rect(sigil_img,
					Rect2i(0, 0, sigil_img.get_width(), sigil_img.get_height()),
					Vector2i(0, 44))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_banner_tex_cache[house_id] = tex
	return tex


# -- tint pipeline ---------------------------------------------------------


## House-tinted variant of a pack material: desaturated albedo texture
## multiplied by the house tint, roughness pushed up. Cached and shared.
func tinted_material(src: StandardMaterial3D, tint: Color, saturation: float) -> StandardMaterial3D:
	var key := "%d|%s" % [src.get_rid().get_id(), tint.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tinted: StandardMaterial3D = src.duplicate()
	if tinted.albedo_texture != null:
		tinted.albedo_texture = _desaturated(tinted.albedo_texture, saturation)
	tinted.albedo_color = src.albedo_color * tint
	tinted.roughness = maxf(tinted.roughness, 0.88)
	tinted.metallic = minf(tinted.metallic, 0.05)
	_tint_cache[key] = tinted
	return tinted


## HOUSE layer — the knight's mount, dyed into the house palette.
##
## The tint pipeline above multiplies a DESATURATED ALBEDO TEXTURE by the
## house color; the Quaternius horse's pack materials carry no texture at
## all, so that multiply only darkens their flat browns — a brown horse
## stayed brown in Winterfang's steel-blue army (caught in the preview,
## 2026-08-08). So dye the mount instead: take the HOUSE hue and modulate it
## by each material's own luminance, which keeps hide/mane/hooves contrast
## while the whole animal reads house-colored at gameplay distance. Cached
## and shared like every other tinted material.
const MOUNT_DYE_FLOOR := 0.42   # darkest material still shows the hue
const MOUNT_DYE_GAIN := 1.05    # ...and the lightest reads near full tint


func dyed_mount_material(src: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var key := "mount|%d|%s" % [src.get_rid().get_id(), tint.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var dyed: StandardMaterial3D = src.duplicate()
	var lum := src.albedo_color.get_luminance()
	dyed.albedo_color = tint * (MOUNT_DYE_FLOOR + MOUNT_DYE_GAIN * lum)
	dyed.albedo_color.a = src.albedo_color.a
	dyed.roughness = maxf(dyed.roughness, 0.85)
	dyed.metallic = minf(dyed.metallic, 0.05)
	_tint_cache[key] = dyed
	return dyed


func _desaturated(tex: Texture2D, saturation: float) -> Texture2D:
	var key := tex.get_rid().get_id()
	if _desat_cache.has(key):
		return _desat_cache[key]
	var img := tex.get_image()
	if img == null:
		_desat_cache[key] = tex
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(1.0, 1.0, saturation)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_desat_cache[key] = out
	return out
