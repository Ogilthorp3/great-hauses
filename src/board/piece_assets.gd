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
## pawn < bishop < rook < queen < KNIGHT < king, tuned so a full army reads at
## a glance from the default gameplay camera. The rook's reference is its
## TowerBody stone (the pennant pole is an accent allowed to poke above); the
## knight's is the seated rider's helm (his crest is an accent above it).
##
## THE KNIGHT'S SLOT MOVED, DELIBERATELY (critic defect #1, 2026-08-08).
## It used to be 0.98, one notch over the bishop — and that single number was
## the whole cavalry-legibility bug. The ENSEMBLE is normalized to this value,
## so a horse added under the rider does not add height, it STEALS it: at 0.98
## the rider was scaled to 0.58 world units tall — a head SHORTER than a pawn
## — and the horse under him shrank to dog size. A mounted knight cannot be
## graded like a foot soldier. So the slot is now sized on the RIDER first
## (~0.68 world, a full-size figure) with the horse adding its mass BELOW him,
## which lands the ensemble at 1.22 — over the queen, under the king, exactly
## where a man on a warhorse belongs. tests/test_costumes.gd asserts the new
## order; GRADE_ORDER there carries the same reasoning.
const TYPE_HEIGHT := {
	0: 0.78,   # PAWN
	1: 1.02,   # ROOK (TowerBody stone height)
	2: 1.22,   # KNIGHT (mounted: rider's helm atop the destrier)
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

## THE SWORD GRIP (critic defect #12). The blade's long axis is the prop's
## local +Y and its ORIGIN sits at the guard, so mounting it at Vector3.ZERO
## put the guard exactly inside the fist: "the blade passes through the fist
## and forearm and the guard sits BELOW the gripping hand" — plainly visible
## in the marquee duel close-up. Sliding the prop +0.17 along its own blade
## axis lands the fist mid-grip (the grip runs local y -0.366..0) and lifts
## the guard clear of the knuckles, where a guard belongs.
const SWORD_GRIP := Vector3(0.0, 0.17, 0.0)

const GEAR_SPECS := {
	0: [   # PAWN — footman: sword + round shield
		{"key": "sword", "scene": GEAR_SWORD, "bone": "handslot.r",
			"pos": SWORD_GRIP, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
		{"key": "shield", "scene": GEAR_SHIELD_ROUND, "bone": "handslot.l",
			"pos": Vector3.ZERO, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": true,
			"decal_pos": Vector3(0.0, 0.0, 0.21), "decal_size": 0.52},
	],
	1: [],  # ROOK — the watchtower carries the banner instead
	2: [   # KNIGHT — sword + kite shield
		{"key": "sword", "scene": GEAR_SWORD, "bone": "handslot.r",
			"pos": SWORD_GRIP, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
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
			"pos": SWORD_GRIP, "rot_deg": Vector3.ZERO, "scl": 1.0, "decal": false},
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
## The ring's OTHER three materials, which used to ship as authored (critic
## P7, 2026-08-09): stone #0b0a08, inlay #060504 and the medallion plate
## #1a1712 are all near-black, and the medallion is the one the eye lands on
## because hover and selection happen together — "the darkest object on the
## selection tile, a near-black disc sitting on the bright amber squircle
## directly under the selected piece". A glyph is a UI ICON drawn in world
## space; it has to read on dark stone AND on the amber highlight, and a plate
## that is darker than either ground can only read on one of them.
##
## So the ring is dressed like everything else the piece wears: the plate takes
## the house body color at MEDAL_WEIGHT (mid value — lighter than the dark
## stone, darker than the amber wash, so it separates from both), the disc and
## inlay take it darker so the plate still reads as an inset coin, and the
## glyph keeps its emissive house accent on top. All four are exempted from
## receiving shadows, because a marker lying inside its own piece's contact
## shadow is the defect this ring already had once (#17).
const RING_STONE_MATERIAL := "glyphring_stone"
const RING_INLAY_MATERIAL := "glyphring_inlay"
const RING_MEDAL_MATERIAL := "glyphring_medal"
const RING_MEDAL_WEIGHT := 0.62
const RING_STONE_WEIGHT := 0.34
const RING_INLAY_WEIGHT := 0.24

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


## Crown-variant mapping (kings and their queens' tiaras).
##
## THE MAPPING IS INVERTED (critic P3, 2026-08-09). It used to match the crown
## to its wearer — cold houses in frost steel, warm houses in worn gold — and
## matching temperature is the one thing a crown must never do. A regalia
## piece exists to be found on a body, and it is exempt from the house dye
## (costume_preview.PALETTE_EXEMPT) precisely so it can contrast; handing a
## steel-blue army a steel-blue crown throws that exemption away and leaves the
## king's silhouette to be carried by geometry alone — which failed exactly
## where geometry is weakest, from the player's own side, where the camera
## looks down the crown's axis and the head occludes the band.
##
## So a crown now takes the OPPOSITE temperature to its army: the four cold
## houses (Winterfang, Tidegrip, Swiftcrest, Silverbrook, and legacy FROST)
## crown in warm gold, the five warm ones in cold steel. Hue contrast survives
## every camera angle, unlike a highlight.
func crown_scene(tint: Color) -> PackedScene:
	return CROWN_GOLD if tint.b > tint.r else CROWN_FROST


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


## THE PALETTE ENVELOPE (critic pass 2026-08-08, defects #6/#7).
##
## The dye is a MULTIPLY over a desaturated pack texture, so whatever chroma
## survives `saturation` survives into the frame. At the shipped 0.25 the
## survivors were loud enough to break the house read in all nine armies: the
## mage's grimoire stayed fluorescent MAGENTA, his staff orb LIME, the queen's
## hood FOREST GREEN over Goldclaw's gold. A stock pack color has no business
## being the brightest thing in a house's frame.
##
## THE CEILING IS NOW ZERO (third-pass critic regression, 2026-08-09). A
## 0.10 residual looked like a harmless "narrow chroma band" and was not: the
## Rogue_Hooded atlas paints the queen's hood in a SATURATED TEAL (#228993,
## HSV sat 0.77 — measured, and the single most chromatic large patch on any
## body in the pack). Ten percent of that is still enough to drag the surface
## off the house hue, and how far depends on how much chroma the house tint
## itself brings: Goldclaw's queen measured OLIVE (hood hue ~52 against an
## army at ~40) and Hartcrown's — whose tint was then a near-achromatic mud —
## measured TEAL, because once the albedo is that grey the hall's cool fill
## light owns the hue outright. Residual chroma is not material identity, it
## is a hue leak that scales with how weak the house colour is.
##
## So the texture is now driven to pure LUMINANCE and the house tint supplies
## the ONLY hue on the piece — the flat dye the gear (GEAR_SATURATION) and the
## knight's mount already use, applied to the bodies too. Material identity
## survives where it always actually lived: in the texture's luminance.
## `tests/test_costumes.gd::_test_palette_envelope` is the gate that fails if
## a rendered surface ever escapes the house's hue again.
const PALETTE_SATURATION_CEILING := 0.0
## Signature gear (sword, shield, staff, grimoire, bow, quiver) is dyed FLAT:
## the pack props are single-texture atlases whose stock colors are pure
## fantasy-loot candy, and they are the pieces a player's eye lands on. Full
## desaturation makes the prop's own luminance the only thing that survives,
## so the house hue is exact — the mount's dye doctrine, applied to tack.
const GEAR_SATURATION := 0.0


## House-tinted variant of a pack material: desaturated albedo texture
## multiplied by the house tint, roughness pushed up. Cached and shared.
## `saturation` is clamped to PALETTE_SATURATION_CEILING — see above.
func tinted_material(src: StandardMaterial3D, tint: Color, saturation: float) -> StandardMaterial3D:
	var sat := minf(saturation, PALETTE_SATURATION_CEILING)
	# Keyed on the resource's INSTANCE id, never its RID: a headless run has
	# no rendering server, so Resource.get_rid() hands every material the same
	# empty RID and one cache entry would be served to all of them (and a
	# freed RID id is recycled, which is the same bug with a timer on it).
	var key := "%d|%s|%.3f" % [src.get_instance_id(), tint.to_html(), sat]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tinted: StandardMaterial3D = src.duplicate()
	if tinted.albedo_texture != null:
		tinted.albedo_texture = _desaturated(tinted.albedo_texture, sat)
	tinted.albedo_color = src.albedo_color * tint
	tinted.roughness = maxf(tinted.roughness, 0.88)
	tinted.metallic = minf(tinted.metallic, 0.05)
	_tint_cache[key] = tinted
	return tinted


## Every color a house is allowed to put on the board: its three heraldic
## colors plus the two multiply tints. The palette-envelope test measures
## rendered surfaces against these hues.
func house_palette(house_id: String) -> Array[Color]:
	if not HouseRegistry.has_house(house_id):
		return []
	var cols: Dictionary = HouseRegistry.get_colors(house_id)
	var out: Array[Color] = [cols["primary"], cols["secondary"], cols["accent"],
			HouseRegistry.get_house_tint(house_id, "piece"),
			HouseRegistry.get_house_tint(house_id, "tower")]
	return out


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

## The pack's own albedos are all dark browns within 0.11 of each other, so a
## pure luminance dye flattened the animal into one silhouette-less blob at
## board distance (critic defect #1: "spindly, mane-less, tail-less"). The
## mount's parts are dyed on AUTHORED weights instead — a bright blaze, a dark
## mane, darker hooves — so the destrier keeps internal contrast and its mane,
## tail and legs stay separately readable while the whole animal still reads
## house-colored. Unknown materials fall back to the luminance formula.
## The BARDING (crinet + chanfron, critic P6 — tools/props/convert_horse.py)
## is deliberately the BRIGHTEST thing on the mount. Its whole job is to carry
## the neck and the head at values the near-side top-down camera can find, so
## the ensemble reads as a rider ON something rather than as a rider with
## debris around him. Anything dimmer than the hide would simply join the blob
## the barding exists to break up.
const MOUNT_DYE_WEIGHTS := {
	"Main": 1.00,          # the hide
	"Main_Light": 1.32,    # blaze / socks — the bright accent
	"Main_Dark": 0.60,     # ears, shading
	"Muzzle": 0.50,
	"Hair": 0.54,          # mane + tail: darker than the hide, not black
	"Hooves": 0.32,
	"saddle_leather": 0.44,
	"crinet_cloth": 1.06,  # neck barding — the plan-view band
	"chanfron_steel": 1.24,  # face plate — the brightest mark, ON the head
}


func dyed_mount_material(src: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var lum := src.albedo_color.get_luminance()
	var weight: float = MOUNT_DYE_WEIGHTS.get(str(src.resource_name),
			MOUNT_DYE_FLOOR + MOUNT_DYE_GAIN * lum)
	return dyed_material(src, tint, weight)


## Flat house dye: the tint at a fixed weight, keeping the source's alpha.
## For UNTEXTURED pack/authored materials, where the ordinary multiply-tint
## only darkens a stock color instead of replacing it (the brown-horse scar).
func dyed_material(src: StandardMaterial3D, tint: Color,
		weight: float) -> StandardMaterial3D:
	var key := "dye|%d|%s|%.3f" % [src.get_instance_id(), tint.to_html(), weight]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var dyed: StandardMaterial3D = src.duplicate()
	dyed.albedo_color = Color(
			minf(tint.r * weight, 1.0),
			minf(tint.g * weight, 1.0),
			minf(tint.b * weight, 1.0))
	dyed.albedo_color.a = src.albedo_color.a
	dyed.roughness = maxf(dyed.roughness, 0.85)
	dyed.metallic = minf(dyed.metallic, 0.05)
	_tint_cache[key] = dyed
	return dyed


## PAINT: a flat house color with the pack texture DROPPED entirely.
##
## For surfaces whose atlas patch carries no information worth keeping and
## whose luminance is actively in the way — the mage's mitre is one dark navy
## patch, so the ordinary multiply-tint can only make it darker, and the
## bishop shipped as the dimmest piece on the near back rank (measured mean
## value 0.34 against a king at 0.55, critic P9). A painted surface takes the
## color it is given, so a mitre can be lifted clear of the robe instead of
## inheriting the robe's gloom. Texture-free also means the palette gate's
## texel-loudness term is trivially satisfied — there is no texel.
func painted_material(src: StandardMaterial3D, color: Color) -> StandardMaterial3D:
	var key := "paint|%d|%s" % [src.get_instance_id(), color.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var painted: StandardMaterial3D = src.duplicate()
	painted.albedo_texture = null
	painted.albedo_color = Color(color.r, color.g, color.b, src.albedo_color.a)
	painted.roughness = maxf(painted.roughness, 0.85)
	painted.metallic = minf(painted.metallic, 0.05)
	_tint_cache[key] = painted
	return painted


## THE HOUSE CHARGE (critic defects #9/#10/#11, value law added 2026-08-09).
## The color a house paints its small marks in — helm rim and motif, the
## bishop's mitre band — chosen as whichever of its three heraldic colors sits
## FURTHEST from the color the surface it sits on is dyed in.
##
## Picking `accent` unconditionally is what made Thornvale's rose invisible: a
## #8fbf6a rose on a #79a04a helm is the same green twice, and the critic
## could not find it at 5x zoom. Contrast is a relationship, so it has to be
## computed against the body, not declared in the palette.
##
## ...and then "furthest" alone shipped the OPPOSITE failure (third-pass
## critic, P8). Furthest-from-a-mid-dome is reliably the house's palest
## heraldic color — Winterfang's #eef2f5 — so every near piece wore a
## near-WHITE plate at the TOP of its silhouette, measured on the boot frame
## at value 0.78 (peak 0.93) against a dome at 0.59, and less saturated than
## the dome besides. A small, pale, low-chroma shape on the skyline does not
## read as heraldry; it flares and eats the head shape.
##
## So a charge now obeys a VALUE LAW as well as a distance one. It is CUT INTO
## a helm bright enough to carry it (darker than the dome, like real blackened
## iron on a painted shell) and LAID ON one that is not — the Drowned Legion's
## charred dome renders at 0.22 and would swallow anything darker. Where the
## heraldic colors cannot separate on their own the winner is brought under the
## ceiling and pays for the lost distance in CHROMA first, value second, so a
## charge is never dimmed into the dome it is supposed to mark.
##
## `tests/test_costumes.gd::_test_pawn_helms` asserts both halves: separation
## from the dome (> 0.20) and the value relationship this law creates.
const CHARGE_DARK_DOME := 0.34    # below this a dome cannot carry a darker mark
const CHARGE_UNDER := 0.95        # bright dome: the charge sits just under it
const CHARGE_OVER := 0.24         # dark dome: ...and just over it instead
const CHARGE_MIN_SEPARATION := 0.24


func house_charge_color(house_id: String, body: Color) -> Color:
	if not HouseRegistry.has_house(house_id):
		return Color.WHITE
	var cols: Dictionary = HouseRegistry.get_colors(house_id)
	var ceiling := body.v * CHARGE_UNDER if body.v >= CHARGE_DARK_DOME \
			else body.v + CHARGE_OVER
	# 1. the furthest heraldic color that ALREADY obeys the ceiling, if it
	#    also separates on its own — no adjustment beats no adjustment.
	var best := Color.WHITE
	var best_d := -1.0
	var far := Color.WHITE
	var far_d := -1.0
	for key in ["primary", "secondary", "accent"]:
		var c: Color = cols[key]
		var d := _charge_distance(c, body)
		if d > far_d:
			far_d = d
			far = c
		if c.v <= ceiling and d > best_d:
			best_d = d
			best = c
	if best_d >= CHARGE_MIN_SEPARATION:
		return best
	# 2. nothing qualified: take the furthest, bring it under the ceiling, and
	#    buy the separation back with saturation before value.
	var out := Color.from_hsv(far.h, far.s, minf(far.v, ceiling), far.a)
	for _i in 10:
		if _charge_distance(out, body) >= CHARGE_MIN_SEPARATION:
			break
		out = Color.from_hsv(out.h, minf(1.0, out.s + 0.09),
				out.v * 0.93 if body.v >= CHARGE_DARK_DOME \
						else minf(1.0, out.v * 1.07), out.a)
	return out


func _charge_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# -- the bishop's hat (critic defect #2) -----------------------------------
#
# Both mage casts ship a witch hat whose BRIM IS TWICE THE BODY WIDTH. Seen
# from the near-side top-down gameplay camera that brim is the entire piece:
# "a navy saucer with a small cone in the middle — no face, no staff, no body.
# A sombrero seen from above." Nothing about the material, the tint or the
# lighting could rescue it; the shape was wrong.
#
# So the brim is narrowed and the crown lifted, on the MESH — not by scaling
# the node (a skinned MeshInstance3D ignores its own transform) and not by
# hiding the hat (it is the model's tallest mesh, i.e. the bishop's entire
# height reference: hiding it would silently rescale every bishop, the exact
# trap the Barbarian's bear hood already taught us). Rebuilding the surface
# keeps the hat real, keeps it skinned, and keeps the height law honest.
##  Outer brim radius is kept at CORE + (r - CORE) * BRIM_KEEP: a brim at the
##  full radius comes in ~38%, the crown and its taper are untouched.
##
## THE MITRE IS ALSO SPLIT IN TWO (critic P9, 2026-08-09). Narrower was not
## enough: from the high rear gameplay camera the near bishop measured the
## LOWEST value on its own back rank (mean 0.34 / 0.38 against 0.44-0.55 for
## every other piece) and the narrowed cone silhouetted as one dark thimble.
## So the rebuild now emits the CROWN and the BRIM as separate surfaces —
## classified per triangle by the vertex radius the narrowing already
## computes — and PieceView paints them apart (bright house cone, house-charge
## band). One dark oval becomes a lit cone inside a contrasting ring, which is
## a shape a player can name from directly above.
const HAT_BRIM_CORE := 0.42     # fraction of max radius that is "crown"
const HAT_BRIM_KEEP := 0.34     # how much of the overhang survives
const HAT_CROWN_LIFT := 0.22    # ...and the cone grows back what the brim lost

var _hat_cache: Dictionary = {}   # source mesh instance id -> ArrayMesh
var _hat_brim_cache: Dictionary = {}  # source mesh instance id -> {surface: true}


## The narrowed-brim variant of a wizard-hat mesh, crown and brim on separate
## surfaces. Cached per source mesh; pair it with `hat_brim_surfaces()`.
func narrowed_hat_mesh(src: Mesh) -> ArrayMesh:
	var key := src.get_instance_id()
	if _hat_cache.has(key):
		return _hat_cache[key]
	var box := src.get_aabb()
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var base_y := box.position.y
	var span_y := maxf(box.size.y, 0.0001)
	var max_r := maxf(maxf(box.size.x, box.size.z) * 0.5, 0.0001)
	var core := max_r * HAT_BRIM_CORE
	var out := ArrayMesh.new()
	var brim_surfaces := {}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var overhang := PackedFloat32Array()
		overhang.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var dx := v.x - cx
			var dz := v.z - cz
			var r := sqrt(dx * dx + dz * dz)
			overhang[i] = r / max_r
			if r > core:
				var f := (core + (r - core) * HAT_BRIM_KEEP) / r
				v.x = cx + dx * f
				v.z = cz + dz * f
			var t := clampf((v.y - base_y) / span_y, 0.0, 1.0)
			v.y = base_y + (v.y - base_y) * (1.0 + HAT_CROWN_LIFT * t)
			verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		# Drop the compression flag: surface_get_arrays hands back plain data.
		var fmt: int = src.surface_get_format(s) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var groups := _split_hat_indices(idx, overhang)
		for g in groups.size():   # [crown indices, brim indices] — crown first
			var part: PackedInt32Array = groups[g]
			if part.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = part
			out.add_surface_from_arrays(src.surface_get_primitive_type(s),
					arrays, [], {}, fmt)
			var new_s := out.get_surface_count() - 1
			out.surface_set_material(new_s, src.surface_get_material(s))
			if g == 1:
				brim_surfaces[new_s] = true
	_hat_cache[key] = out
	_hat_brim_cache[key] = brim_surfaces
	return out


## Which surfaces of `narrowed_hat_mesh(src)` are the BRIM (the rest are the
## cone). Keyed on the SOURCE mesh, so callers ask before or after the swap.
func hat_brim_surfaces(src: Mesh) -> Dictionary:
	return _hat_brim_cache.get(src.get_instance_id(), {})


## Triangles whose vertices sit mostly beyond the brim core are the BRIM.
## Returns [crown indices, brim indices]; an unindexed surface stays whole.
func _split_hat_indices(idx: PackedInt32Array,
		overhang: PackedFloat32Array) -> Array:
	if idx.size() < 3 or idx.size() % 3 != 0:
		return [idx, PackedInt32Array()]
	var crown := PackedInt32Array()
	var brim := PackedInt32Array()
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var mean := (overhang[a] + overhang[b] + overhang[c]) / 3.0
		var into: PackedInt32Array = brim if mean > HAT_BRIM_CORE else crown
		into.append(a)
		into.append(b)
		into.append(c)
	return [crown, brim]


func _desaturated(tex: Texture2D, saturation: float) -> Texture2D:
	# The saturation belongs in the key: body and gear pull the SAME pack
	# atlas at different saturations, and a texture-only key silently served
	# whichever one asked first to both.
	var key := "%d|%.3f" % [tex.get_instance_id(), saturation]
	if _desat_cache.has(key):
		return _desat_cache[key]
	# DUPLICATE before touching it: Texture2D.get_image() hands back the
	# texture's OWN Image, so decompress/convert/adjust_bcs edited the source
	# atlas in place. Consequences, all silent: the first saturation to ask
	# won for every later caller, a second pass compounded onto an already
	# desaturated image, and every "is this material dyed?" check was
	# comparing against a source that had been dyed behind its back.
	var src_img := tex.get_image()
	if src_img == null:
		_desat_cache[key] = tex
		return tex
	var img := src_img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(1.0, 1.0, saturation)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_desat_cache[key] = out
	return out
