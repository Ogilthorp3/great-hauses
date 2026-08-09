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
## ...and a THIRD axis, orthogonal to both, added 2026-08-09: MATERIAL ROLE.
## Type says what a piece is, house says whose it is, and role says what a
## surface is MADE OF — kit, natural, regalia or heraldry. The house colour is
## painted on the KIT and nowhere else, which is what turned nine monochrome
## armies into nine teams. See MATERIAL_ROLES below; it is the table the whole
## tint pipeline dispatches on.
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
var _tint_cache: Dictionary = {}    # "<kind>|<material id>|<color>" -> StandardMaterial3D
var _desat_cache: Dictionary = {}   # "<kind>|<texture id>" -> Texture2D
var _atlas_cache: Dictionary = {}   # texture id -> decompressed RGBA8 Image
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


# -- MATERIAL ROLES — what a surface IS, before what colour it takes --------
#
# THE RULE THAT REPLACED "DYE EVERYTHING" (owner critique, 2026-08-09):
#
#   "The figurines [are] too much mono color, should be like a hockey team
#    jersey — colors of the team/house, but NOT everywhere. Horse should be
#    brown, black or white, something majestic."
#
# He is right and the cause was ours. A critic found un-tinted marketplace
# props (a fluorescent magenta grimoire on every bishop) and the fix was made
# ABSOLUTE: a palette envelope that required EVERY rendered surface to sit on
# the house hue, with saturation ceilinged at 0.10 and then at 0.00 precisely
# because that hue had to be painted onto skin, steel, bone and horsehide too.
# Nine monochrome armies. The gate had become the defect.
#
# So the pipeline no longer asks "what colour is this house?" first. It asks
# WHAT IS THIS SURFACE MADE OF, and dispatches:
#
#   KIT       carries the house, and can now be CONFIDENTLY saturated because
#             it is no longer everywhere — tabard/surcoat, cloak, hood, shield
#             FACE, caparison and banner cloth, helm, crest/plume, pennant,
#             sash, the sigil charge.
#   NATURAL   never house-hued; each family stays inside its own material's
#             range — steel and iron (cold grey, at most a whisper of house in
#             the shadows), leather, wood, stone, skin, bone, and the horse's
#             COAT (bay/chestnut/black/grey/dun — never a blue horse).
#   REGALIA   gold and silver: the crown and the tiara are regalia, not kit.
#             They stay metal, and their contrast against the body IS the
#             royal read.
#   HERALDRY  carries its own artwork — the sigil plate, the banner/caparison
#             cloth texture, the type-glyph ring. Dyeing it would dye the
#             sigil.
#   MIXED     the KayKit casts paint a whole figure from ONE 1024² atlas, so a
#             mesh name cannot say what it is: `*_Body` is a tabard AND a
#             breastplate AND leather straps. These are split per TRIANGLE by
#             the colour the atlas paints them (see role_split_mesh) into a
#             KIT surface and a NATURAL one. tools/dump_uv_palette.gd is the
#             instrument that reads those palettes off disk.
#   EFFECT    transient VFX — owns its own light, takes no dye.
#
# UNCLASSIFIED IS A FAILURE, NEVER A DEFAULT. `classify()` push_error()s and
# the role gate fails on any surface no rule names — the old pipeline's silent
# fallback was "dye it", which is exactly how a magenta grimoire hid AND how
# nine armies later went monochrome.

enum Role { KIT, NATURAL, REGALIA, HERALDRY, MIXED, EFFECT, UNCLASSIFIED }
## What a NATURAL surface is made of — decides its legal colour range and how
## much (if any) house whisper it may take.
enum Stuff { NONE, STEEL, LEATHER, WOOD, STONE, SKIN, BONE, COAT, GLOW, ATLAS }

## THE TABLE. Ordered — first match wins — and matched against the MESH node
## name first, then the material's resource_name, so authored props are named
## by their material and pack casts by their mesh. Read it top to bottom.
const MATERIAL_ROLES: Array = [
	# ── authored props: the material name IS the contract ──────────────────
	{"n": "crown_gold_worn", "role": Role.REGALIA},
	{"n": "crown_frost", "role": Role.REGALIA},
	{"n": "cape_cloth", "role": Role.KIT},          # the king's cloak
	{"n": "banner_cloth", "role": Role.HERALDRY},   # sigil composited in
	{"n": "pennant_cloth", "role": Role.HERALDRY},
	{"n": "caparison_cloth", "role": Role.HERALDRY},
	{"n": "crinet_cloth", "role": Role.KIT},        # neck barding, house cloth
	{"n": "chanfron_steel", "role": Role.NATURAL, "stuff": Stuff.STEEL},
	{"n": "saddle_leather", "role": Role.NATURAL, "stuff": Stuff.LEATHER},
	{"n": "tower_stone*", "role": Role.NATURAL, "stuff": Stuff.STONE},
	{"n": "tower_slit", "role": Role.NATURAL, "stuff": Stuff.STONE},
	{"n": "tower_wood", "role": Role.NATURAL, "stuff": Stuff.WOOD},
	# The pawn's half-helm is LIVERY, not bare plate: it exists only to say
	# which house a footman belongs to (ISSUES.md #3), and a painted helm is
	# what a real livery company put on a footman's head. Both its surfaces
	# carry the house — dome in the kit colour, rim + motif in the charge.
	{"n": "pawnhelm_iron", "role": Role.KIT},
	{"n": "pawnhelm_accent", "role": Role.KIT},
	{"n": "Crest_*", "role": Role.KIT},             # helm crest/plume
	{"n": "glyphring_*", "role": Role.HERALDRY},    # a TYPE marker, not house
	{"n": "SigilDecal", "role": Role.HERALDRY},
	{"n": "StrikeTrail", "role": Role.EFFECT},
	# ── the mount ──────────────────────────────────────────────────────────
	{"n": "Main", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Main_Light", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Main_Dark", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Muzzle", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Hair", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Hooves", "role": Role.NATURAL, "stuff": Stuff.COAT},
	{"n": "Eye_*", "role": Role.NATURAL, "stuff": Stuff.NONE},
	# ── the KayKit casts (one atlas per figure) ────────────────────────────
	{"n": "*BearHat*", "role": Role.NATURAL, "stuff": Stuff.LEATHER},
	{"n": "*_Cape", "role": Role.KIT},
	{"n": "*_Cloak", "role": Role.KIT},
	{"n": "*_Hood", "role": Role.KIT},
	{"n": "*_Mask", "role": Role.KIT},
	{"n": "*_Hat", "role": Role.KIT},               # the bishop's mitre
	{"n": "*_Helmet", "role": Role.NATURAL, "stuff": Stuff.STEEL},
	{"n": "*_HelmetVisor", "role": Role.NATURAL, "stuff": Stuff.STEEL},
	{"n": "*_Skull", "role": Role.NATURAL, "stuff": Stuff.BONE},
	{"n": "*_Jaw", "role": Role.NATURAL, "stuff": Stuff.BONE},
	{"n": "*_Eyes", "role": Role.NATURAL, "stuff": Stuff.GLOW},
	{"n": "Glow", "role": Role.NATURAL, "stuff": Stuff.GLOW},
	{"n": "*_Head", "role": Role.MIXED},            # skin, and the rogue's hood
	{"n": "*_Body", "role": Role.MIXED},            # tabard over plate
	{"n": "*_ArmLeft", "role": Role.MIXED},
	{"n": "*_ArmRight", "role": Role.MIXED},
	{"n": "*_LegLeft", "role": Role.MIXED},
	{"n": "*_LegRight", "role": Role.MIXED},
	{"n": "*_Quiver", "role": Role.MIXED},
	# ── the KayKit signature gear ──────────────────────────────────────────
	# A shield is a painted charge-board — the one piece of war gear that is
	# heraldry by trade, and the plate the sigil decal lands on.
	{"n": "shield_round", "role": Role.KIT},
	{"n": "shield_badge", "role": Role.KIT},
	# ...and a blade is a blade. Split: cold steel stays cold, the leather
	# grip stays leather, and only a prop's cloth/enamel takes the house.
	{"n": "sword_1handed", "role": Role.MIXED},
	{"n": "staff", "role": Role.MIXED},
	{"n": "spellbook_closed", "role": Role.MIXED},
	{"n": "bow_withString", "role": Role.MIXED},
	{"n": "quiver", "role": Role.MIXED},
]


## The role of one rendered surface. `mesh_name` is the MeshInstance3D's node
## name, `mat_name` the source material's resource_name. Returns
## {"role": Role, "stuff": Stuff}. An unnamed surface returns UNCLASSIFIED and
## shouts — it must never silently fall through to "dye it".
func classify(mesh_name: String, mat_name: String) -> Dictionary:
	for rule: Dictionary in MATERIAL_ROLES:
		var pattern: String = rule["n"]
		if mesh_name.matchn(pattern) or mat_name.matchn(pattern):
			return {"role": rule["role"], "stuff": rule.get("stuff", Stuff.NONE)}
	push_error("PieceAssets.classify: no MATERIAL_ROLES rule for mesh '%s' / material '%s' — add it to the table"
			% [mesh_name, mat_name])
	return {"role": Role.UNCLASSIFIED, "stuff": Stuff.NONE}


# -- the tint pipeline, dispatched on role ---------------------------------


## KIT — how loud the jersey is allowed to be.
##
## The old ceiling was 0.10 and then 0.00, and it was never about taste: the
## dye was painted on every surface, so any chroma at all leaked onto skin and
## steel. With the kit alone carrying it, the house colour is applied as the
## FLAT albedo (`tints.kit` in houses.json, saturation 0.45-0.85 per house) on
## top of a pure-luminance copy of the pack atlas — so a tabard keeps every
## fold the artist painted and takes the house's real colour on top of it.
##
## KIT_SHADE_FLOOR / KIT_SHADE_GAIN remap that luminance before the multiply:
## the pack's cloth patches sit anywhere between L 0.2 (the skeleton's crimson
## cloak) and L 0.8 (the ranger's blue cape), and un-remapped that spread turns
## the same house colour into two different houses. Floor 0.52 with gain 0.85
## lands every cast's cloth in the top half of the kit colour while keeping
## the shading ORDER intact (it is linear and monotonic, like the tone floor
## it replaces).
const KIT_SHADE_FLOOR := 0.52
const KIT_SHADE_GAIN := 0.85

## NATURAL — the whisper. A natural surface keeps its OWN atlas colours; this
## is the faint cast of the house tint it is allowed to take so an army still
## hangs together at board distance. Steel takes the most (real armour picks
## up the colour of what it stands next to), skin and bone take none, and a
## horse's coat takes none at all — that is the whole point of the coat table.
## The whisper is applied through a tint whose saturation is capped at
## NATURAL_WHISPER_SAT so it can only ever shift the hue a hair; the role gate
## measures what comes out and fails if a "natural" surface lands on the house.
const NATURAL_WHISPER := {
	Stuff.STEEL: 0.16,
	Stuff.STONE: 0.18,
	Stuff.LEATHER: 0.08,
	Stuff.WOOD: 0.08,
	Stuff.ATLAS: 0.10,
	Stuff.SKIN: 0.0,
	Stuff.BONE: 0.0,
	Stuff.COAT: 0.0,
	Stuff.GLOW: 0.0,
	Stuff.NONE: 0.0,
}
const NATURAL_WHISPER_SAT := 0.34
## ...and how much light each family carries. The old pipeline multiplied
## every body by the house tint, which dimmed it; naturals now keep their own
## albedo, so steel came back a full stop brighter and the near army turned
## into a bright mob that out-shone its own king. These are the trims that put
## the hierarchy back, measured on the boot frame (tools/frame_rank.py).
const NATURAL_VALUE := {
	Stuff.STEEL: 0.80,
	Stuff.STONE: 0.86,
	Stuff.LEATHER: 0.92,
	Stuff.WOOD: 0.92,
	Stuff.ATLAS: 0.88,
	Stuff.SKIN: 0.94,
	Stuff.BONE: 0.90,
	Stuff.COAT: 1.0,
	Stuff.GLOW: 1.0,
	Stuff.NONE: 1.0,
}


## THE TONE FLOOR — how a cast whose ATLAS is dark gets lifted (critic
## defect #2, 2026-08-09: "the far queen is a black hole in her own army").
##
## Measured on the shipped boot frame: Goldclaw's d8 queen at median value
## 0.212 against a back rank running 0.310-0.376 — the darkest piece in her own
## army by ~30 %. The Rogue_Hooded atlas paints her whole hooded robe near
## black, and a multiply-tint over a near-black texel can only ever return a
## near-black texel.
##
## Her ROBE is now KIT, so KIT_SHADE_FLOOR fixes that half structurally. This
## floor survives for her NATURAL half (the atlas's own leather and skin under
## the robe), where the pack texture is still what it always was:
##     L' = floor + (1 - floor) * L
## A linear black-point lift — monotonic, so every fold keeps its ordering (a
## hard `max(L, floor)` would flatten the hood into a paper cut-out), and it
## leaves L=1 exactly where it was so her highlights, and therefore her peak
## against the king's, do not move.
const QUEEN_TONE_FLOOR := 0.30


## KIT: the house jersey — a pure-luminance copy of the pack atlas multiplied
## by the house's kit colour. Cached and shared; the luminance copy is cached
## per SOURCE TEXTURE (it does not depend on the house), so nine armies share
## one desaturation pass instead of paying for nine.
func kit_material(src: StandardMaterial3D, kit: Color,
		value: float = 1.0) -> StandardMaterial3D:
	var col := Color(kit.r * value, kit.g * value, kit.b * value, kit.a)
	# Keyed on the resource's INSTANCE id, never its RID: a headless run has no
	# rendering server, so Resource.get_rid() hands every material the same
	# empty RID and one cache entry would be served to all of them (and a freed
	# RID id is recycled, which is the same bug with a timer on it).
	var key := "kit|%d|%s" % [src.get_instance_id(), col.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var mat: StandardMaterial3D = src.duplicate()
	if mat.albedo_texture != null:
		mat.albedo_texture = _kit_luminance(mat.albedo_texture)
	mat.albedo_color = Color(col.r, col.g, col.b, src.albedo_color.a)
	mat.roughness = maxf(mat.roughness, 0.88)
	mat.metallic = minf(mat.metallic, 0.05)
	_tint_cache[key] = mat
	return mat


## NATURAL: the surface keeps its OWN colours. It takes only its family's
## value trim and (for steel, stone, leather, wood and the split-atlas
## naturals) the faint house whisper — never the hue.
func natural_material(src: StandardMaterial3D, stuff: int, tint: Color,
		value: float = 1.0, tone_floor: float = 0.0) -> StandardMaterial3D:
	var whisper: float = NATURAL_WHISPER.get(stuff, 0.0)
	var trim: float = float(NATURAL_VALUE.get(stuff, 1.0)) * value
	var cast_col := Color.WHITE
	if whisper > 0.0:
		var soft := Color.from_hsv(tint.h, minf(tint.s, NATURAL_WHISPER_SAT), 1.0)
		cast_col = Color.WHITE.lerp(soft, whisper)
	var floor_v := clampf(tone_floor, 0.0, 0.9)
	var key := "nat|%d|%d|%s|%.3f|%.3f" % [src.get_instance_id(), stuff,
			cast_col.to_html(), trim, floor_v]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var mat: StandardMaterial3D = src.duplicate()
	if mat.albedo_texture != null and floor_v > 0.0:
		mat.albedo_texture = _black_point_lifted(mat.albedo_texture, floor_v)
	var base := src.albedo_color
	mat.albedo_color = Color(base.r * cast_col.r * trim, base.g * cast_col.g * trim,
			base.b * cast_col.b * trim, base.a)
	mat.roughness = maxf(mat.roughness, 0.82)
	mat.metallic = minf(mat.metallic, 0.05)
	_tint_cache[key] = mat
	return mat


## THE WEAPON TRAIL (critic defect #1, 2026-08-09 — "the mustard rectangle").
##
## PieceView._strike_flash used to spawn a BARE QuadMesh with a 90 %-alpha
## mustard albedo. A bare quad has no shape of its own, so at the instant the
## duel camera takes its frame the "weapon trail" was still a filled
## rectangle: measured 433x112 px at 99 % fill and value 0.741 in
## duel/03_mid_duel.png, 426x111 at 0.739 in showcase/05, and 427x110 at 0.940
## in slowmo/02 — a near-opaque slab across both fighters' heads at the moment
## of the kill. Three separate critics read it as an unfinished debug panel,
## which is exactly what it looked like.
##
## The fix is to give the quad SHAPE, in the only place a quad can have one:
## its alpha. This paints a tapered ARC — a curved core that thins to nothing
## at both ends and falls off with a gaussian across its width — so the mesh's
## rectangle is never visible at any opacity. The core is white-hot and the
## fringe amber, and the material draws it ADDITIVELY, so the trail can only
## ever ADD light to the frame: no alpha value of it can produce a flat plate,
## because there is no flat region to produce.
const TRAIL_TEX_W := 192
const TRAIL_TEX_H := 96
const TRAIL_ARC_TOP := 0.30      # v of the arc's crest (v=0 is the image top)
const TRAIL_ARC_DROP := 0.40     # ...and how far its ends fall below that
const TRAIL_CORE := 0.052        # half-thickness of the hot core, in v units

var _trail_tex: Texture2D


## The soft-edged blade-arc texture — built once, shared by every strike.
func strike_trail_texture() -> Texture2D:
	if _trail_tex != null:
		return _trail_tex
	var img := Image.create(TRAIL_TEX_W, TRAIL_TEX_H, false, Image.FORMAT_RGBA8)
	var edge := Color(1.0, 0.60, 0.20)   # amber fringe
	var core := Color(1.0, 0.96, 0.86)   # white-hot core
	for x in TRAIL_TEX_W:
		var u := (float(x) + 0.5) / TRAIL_TEX_W
		# Tapered ends: the ink reaches zero AT both ends, so the quad's left
		# and right edges can never draw a straight vertical cut.
		var taper := pow(sin(PI * u), 0.9)
		var arc := TRAIL_ARC_TOP + TRAIL_ARC_DROP * pow(2.0 * u - 1.0, 2.0)
		var half := TRAIL_CORE * maxf(taper, 0.05)
		for y in TRAIL_TEX_H:
			var v := (float(y) + 0.5) / TRAIL_TEX_H
			var d := (v - arc) / half
			var a := exp(-d * d * 1.6) * taper
			img.set_pixel(x, y, Color(
					lerpf(edge.r, core.r, a * a),
					lerpf(edge.g, core.g, a * a),
					lerpf(edge.b, core.b, a * a),
					clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_trail_tex = ImageTexture.create_from_image(img)
	return _trail_tex


## Every color a house is allowed to put on its KIT: the jersey colour plus
## its three heraldic colors (a jersey may carry a second colour as its
## charge — that is what a charge IS). The role gate measures every KIT
## surface against these hues; NATURAL surfaces are measured against their
## material's own range instead, and must stay OFF this list.
func house_palette(house_id: String) -> Array[Color]:
	if not HouseRegistry.has_house(house_id):
		return []
	var cols: Dictionary = HouseRegistry.get_colors(house_id)
	var out: Array[Color] = [HouseRegistry.get_house_tint(house_id, "kit"),
			cols["primary"], cols["secondary"], cols["accent"]]
	return out


## The house's one saturated jersey colour.
func kit_color(house_id: String) -> Color:
	return HouseRegistry.get_house_tint(house_id, "kit")


# -- THE HORSE'S COAT ------------------------------------------------------
#
# "Horse should be brown, black or white, something majestic." — the owner,
# 2026-08-09, looking at nine armies riding nine horses dyed in nine house
# colours (a steel-blue Winterfang charger, a gold Goldclaw one). He is right:
# a blue horse is a bug, not heraldry. The mount's house identity lives in its
# CAPARISON — the banner cloth over its flank, sigil and all — and the animal
# under that cloth is an animal.
#
# So a coat is a NATURAL palette, assigned per house for variety and majesty.
# The five real coats plus the three shade variants a nine-house field needs:
#
#   house         coat            reads as
#   winterfang    white_grey      the frost house rides a pale grey
#   goldclaw      chestnut        a red-gold lion's charger
#   hartcrown     dapple_grey     a storm-grey charger for the storm house
#   ashwyrm       black           the dragon's black destrier
#   tidegrip      drowned_grey    a cold, drowned dark grey
#   thornvale     dun             sandy gold with a dark mane and dorsal
#   duskfire      liver_chestnut  a darker, redder chestnut
#   swiftcrest    bay             classic red-brown with black points
#   silverbrook   dark_bay        near-black bay, distinct from Swiftcrest's
#
# The assignment is not arbitrary in one respect: a house's coat must stay
# clear of its own kit colour, or the role gate's "a natural surface may not
# wear the house kit" rule fires. Hartcrown's copper jersey is a bay's own
# colour, which is exactly why the stag rides a grey.
#
# Each palette names the horse's own material set (tools/props/convert_horse.py):
# Main is the hide, Main_Light the blaze/socks, Main_Dark the ears and
# shading, Muzzle the nose, Hair the mane and tail, Hooves the feet. The
# MANE is deliberately pushed off the hide's own value in every coat — a
# real chestnut's mane is the same colour as its body, and rendered at
# chess-piece scale that is a horse with no mane and no tail (the exact
# defect the pack's flat browns caused before). So the chestnut goes
# flaxen, the liver chestnut goes near-black, and the pale grey's mane
# drops a step: all four are real coats, chosen for the one that reads. Nothing
# here may be a house hue — tests/test_costumes.gd paints a horse blue and the
# role gate has to go red.
const COAT_PALETTES := {
	"bay": {
		"Main": "#6b4526", "Main_Light": "#8a5c33", "Main_Dark": "#4a2f19",
		"Muzzle": "#3a2515", "Hair": "#211a14", "Hooves": "#2b2724"},
	"dark_bay": {
		"Main": "#4a3320", "Main_Light": "#63452a", "Main_Dark": "#33220f",
		"Muzzle": "#2a1d12", "Hair": "#1a1512", "Hooves": "#262320"},
	"chestnut": {
		"Main": "#8f4a22", "Main_Light": "#b3663a", "Main_Dark": "#6b3517",
		"Muzzle": "#5a2d15", "Hair": "#d0a877", "Hooves": "#40342c"},
	"liver_chestnut": {
		"Main": "#6b3218", "Main_Light": "#8a4626", "Main_Dark": "#4d2210",
		"Muzzle": "#3d1c0e", "Hair": "#3a1a0c", "Hooves": "#38302a"},
	"black": {
		"Main": "#232120", "Main_Light": "#3a3634", "Main_Dark": "#171514",
		"Muzzle": "#141312", "Hair": "#121110", "Hooves": "#262422"},
	"white_grey": {
		"Main": "#b8b4ac", "Main_Light": "#d0ccc4", "Main_Dark": "#9a968e",
		"Muzzle": "#837f78", "Hair": "#8a867e", "Hooves": "#55514b"},
	"dapple_grey": {
		"Main": "#8e8d88", "Main_Light": "#ada9a2", "Main_Dark": "#6a6864",
		"Muzzle": "#575551", "Hair": "#4e4c49", "Hooves": "#3d3a36"},
	"drowned_grey": {
		"Main": "#4a4f4c", "Main_Light": "#626765", "Main_Dark": "#363a38",
		"Muzzle": "#2b2f2d", "Hair": "#242827", "Hooves": "#222523"},
	"dun": {
		"Main": "#b0956a", "Main_Light": "#cbb289", "Main_Dark": "#8a7350",
		"Muzzle": "#6e5c40", "Hair": "#3a3126", "Hooves": "#3a352e"},
}
## Legacy FROST/EMBER sides have no house entry, so they ride the default.
const COAT_DEFAULT := "bay"


## The coat palette a house's mount wears, as {material name -> Color}.
func coat_palette(house_id: String) -> Dictionary:
	var name := COAT_DEFAULT
	if HouseRegistry.has_house(house_id):
		name = HouseRegistry.get_house_coat(house_id)
	if not COAT_PALETTES.has(name):
		push_error("PieceAssets.coat_palette: house '%s' names coat '%s', which is not in COAT_PALETTES"
				% [house_id, name])
		name = COAT_DEFAULT
	var out := {}
	for key in COAT_PALETTES[name]:
		out[key] = Color.html(COAT_PALETTES[name][key])
	return out


## The coat's own colour for one horse material — NATURAL, never house-hued.
## `value` carries the rank's value trim (a mounted knight is trimmed as one
## ensemble, see PieceView.TYPE_VALUE_LIFT).
func coat_material(src: StandardMaterial3D, coat: Dictionary,
		value: float = 1.0) -> StandardMaterial3D:
	var name := str(src.resource_name)
	if not coat.has(name):
		push_error("PieceAssets.coat_material: no coat colour for horse material '%s'" % name)
		return src
	var c: Color = coat[name]
	return _flat_material("coat|%s" % name, src,
			Color(c.r * value, c.g * value, c.b * value, src.albedo_color.a))


## Flat house dye: the tint at a fixed weight, keeping the source's alpha.
## For UNTEXTURED authored materials (the pawn helm, the crest, the glyph
## ring's plate) where there is no atlas to modulate — the colour IS the
## surface.
func dyed_material(src: StandardMaterial3D, tint: Color,
		weight: float) -> StandardMaterial3D:
	return _flat_material("dye", src, Color(
			minf(tint.r * weight, 1.0),
			minf(tint.g * weight, 1.0),
			minf(tint.b * weight, 1.0), src.albedo_color.a))


## PAINT: a flat colour with the pack texture DROPPED entirely.
##
## For surfaces whose atlas patch carries no information worth keeping and
## whose luminance is actively in the way — the mage's mitre is one dark navy
## patch, so an ordinary multiply-tint can only make it darker, and the bishop
## shipped as the dimmest piece on the near back rank (measured mean value 0.34
## against a king at 0.55, critic P9). A painted surface takes the colour it is
## given, so a mitre can be lifted clear of the robe instead of inheriting the
## robe's gloom.
func painted_material(src: StandardMaterial3D, color: Color) -> StandardMaterial3D:
	var painted := _flat_material("paint", src,
			Color(color.r, color.g, color.b, src.albedo_color.a))
	painted.albedo_texture = null   # the cached instance is ours to strip
	return painted


## One flat-albedo material, cached and shared. Keyed on the resource's
## INSTANCE id, never its RID: a headless run has no rendering server, so
## Resource.get_rid() hands every material the same empty RID and one cache
## entry would be served to all of them (and a freed RID id is recycled, which
## is the same bug with a timer on it).
func _flat_material(kind: String, src: StandardMaterial3D,
		color: Color) -> StandardMaterial3D:
	var key := "%s|%d|%s" % [kind, src.get_instance_id(), color.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var mat: StandardMaterial3D = src.duplicate()
	mat.albedo_color = color
	mat.roughness = maxf(mat.roughness, 0.85)
	mat.metallic = minf(mat.metallic, 0.05)
	_tint_cache[key] = mat
	return mat


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
## THE LAW IS NOW VALUE-ONLY (role pass, 2026-08-09). The old law bought its
## separation with CHROMA — it ramped the winner's saturation until it stood
## off the dome — and that walked the charge clean off the house's palette:
## Thornvale's gold #d3b04a came out as #302300, a colour the house does not
## own and the role gate correctly refuses (a KIT surface must wear one of its
## house's four colours). So a charge is now one of the house's DECLARED
## colours — its jersey included — moved only along VALUE. Value-normalised,
## it is therefore always exactly a house colour.
##
## What survives of P8 is the part that was actually right: a PALE, LOW-CHROMA
## plate on the top of a silhouette flares and eats the head shape. That is now
## a rule about neutrals only — a near-colourless charge must be CUT INTO the
## dome (darker), while a chromatic one may be LAID ON it. Gold trim on a green
## helm is heraldry; a white plate on a pale-blue helm is a flare.
##
## ...and "maximise the distance" is a third trap, which cost one more render
## to find. The cheapest way to be far from a mid-value dome is to go BLACK, so
## a pure-distance rule elects the darkest cut of the darkest house colour every
## time: Winterfang's mitre band came out #2a2e32 (rendered value 0.20 against a
## 0.67 cone) and the near bishop was, from the top-down camera that matters, a
## black ring with a small blue nub in it — P9's dark thimble, wearing a new hat.
##
## So the search is ordered by INTENT, not by distance: try each house colour at
## its OWN value first and only cut it when nothing at that step separates. A
## charge is a colour a herald picked, not a shadow. Among the candidates that
## do separate, the winner is the one that separates most in HUE as well as in
## value — which is why Goldclaw's gold helm takes a crimson rim (its own
## primary) instead of a paler gold, and Thornvale's green takes gold.
##
## `tests/test_costumes.gd::_test_pawn_helms` asserts all three halves: the
## charge is a declared house colour, it separates from the dome, and a
## colourless one is cut into the dome rather than laid on it.
const CHARGE_UNDER := 0.95          # a neutral charge sits under its dome
const CHARGE_NEUTRAL_SAT := 0.25    # ...and this is what counts as neutral
const CHARGE_MIN_SEPARATION := 0.24
## Value steps a candidate is tried at — its OWN first, then progressively cut.
const CHARGE_VALUE_STEPS := [1.0, 0.78, 0.58, 0.42, 0.30]
## How much a hue difference is worth against a plain RGB one when several
## candidates already separate. A charge that differs in hue reads as heraldry;
## one that differs only in value reads as a shadow of the dome.
const CHARGE_HUE_BONUS := 0.5


func house_charge_color(house_id: String, body: Color) -> Color:
	if not HouseRegistry.has_house(house_id):
		return Color.WHITE
	var fallback := Color.WHITE
	var fallback_score := -1.0
	for step: float in CHARGE_VALUE_STEPS:
		var best := Color.WHITE
		var best_score := -1.0
		var separated := false
		for c: Color in house_palette(house_id):
			var cand := Color.from_hsv(c.h, c.s, clampf(c.v * step, 0.06, 1.0), c.a)
			# A colourless plate may only be CUT INTO the dome, never laid on it.
			if cand.s < CHARGE_NEUTRAL_SAT and cand.v > body.v * CHARGE_UNDER:
				continue
			var d := _charge_distance(cand, body)
			var score := d + CHARGE_HUE_BONUS * absf(wrapf(
					cand.h * 360.0 - body.h * 360.0, -180.0, 180.0)) / 180.0
			if d >= CHARGE_MIN_SEPARATION and score > best_score:
				separated = true
				best_score = score
				best = cand
			if score > fallback_score:
				fallback_score = score
				fallback = cand
		if separated:
			return best
	return fallback


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


# -- role-split meshes -----------------------------------------------------
#
# A KayKit figure is painted from ONE atlas, so `Mage_Body` is a navy robe AND
# leather boots AND skin, and `spellbook_closed` is a magenta cover on a brown
# leather spine. A mesh-level role cannot serve them, and a per-TEXEL dye of a
# 1024² atlas per house is 9M pixel operations nobody should pay for.
#
# So the surface is split by TRIANGLE, once, and cached on the source mesh:
# sample the atlas at each triangle's UV centroid, classify that colour, and
# emit one surface for the KIT triangles and one for the NATURAL ones. Each
# then takes a single material — the kit surface a luminance-and-house-colour
# one, the natural surface the pack atlas UNTOUCHED. It costs one pass over a
# few thousand triangles per cast and it is why a knight can wear a house
# tabard over steel that is still steel.
#
# The classifier reads the pack's own palette (verified against every atlas
# with tools/dump_uv_palette.gd):
#   * anything darker than NATURAL_V_FLOOR is shadow, not a garment;
#   * anything below KIT_TEXEL_SAT_MIN is steel, stone, bone or grey;
#   * anything inside the WARM band is skin, leather, wood or bone — the pack
#     paints all four from the same orange-brown ramp (h 6-52);
#   * everything else is dyed cloth or enamel, i.e. KIT: the rogue's teal
#     (h169 s0.92), the ranger's blue cape (h205 s0.83), the mage's navy robe
#     (h250 s0.43), the skeletons' crimson cloaks (h334-344 s0.6-0.78), the
#     grimoire's magenta cover (h333 s0.87) and the staff's lime orb (h145).
const KIT_TEXEL_SAT_MIN := 0.34
const NATURAL_WARM_LO := 6.0
const NATURAL_WARM_HI := 52.0
const NATURAL_V_FLOOR := 0.12

var _split_cache: Dictionary = {}       # source mesh id -> ArrayMesh
var _split_roles: Dictionary = {}       # source mesh id -> {surface: Role}
var _split_roles_out: Dictionary = {}   # SPLIT mesh id -> {surface: Role}


## Is this atlas colour a piece of KIT (dyed cloth/enamel) or NATURAL stuff?
func texel_role(c: Color) -> int:
	if c.a < 0.5 or c.v < NATURAL_V_FLOOR or c.s < KIT_TEXEL_SAT_MIN:
		return Role.NATURAL
	var h := c.h * 360.0
	if h >= NATURAL_WARM_LO and h <= NATURAL_WARM_HI:
		return Role.NATURAL
	return Role.KIT


## The role-split variant of a MIXED mesh: KIT triangles and NATURAL triangles
## on separate surfaces. Cached per source mesh; pair it with
## `split_surface_roles()`. Vertices are never moved, so the mesh's AABB — and
## therefore the height grading that measures it — is bit-identical.
func role_split_mesh(src: Mesh) -> ArrayMesh:
	var key := src.get_instance_id()
	if _split_cache.has(key):
		return _split_cache[key]
	var out := ArrayMesh.new()
	var roles := {}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var mat := src.surface_get_material(s) as StandardMaterial3D
		var img: Image = null
		if mat != null and mat.albedo_texture != null:
			img = _atlas_image(mat.albedo_texture)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] \
				if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		# Drop the compression flag: surface_get_arrays hands back plain data.
		var fmt: int = src.surface_get_format(s) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		var groups := _split_indices_by_texel(idx, uvs, img)
		for role in [Role.NATURAL, Role.KIT]:   # natural first, stable order
			var part: PackedInt32Array = groups[role]
			if part.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = part
			out.add_surface_from_arrays(src.surface_get_primitive_type(s),
					arrays, [], {}, fmt)
			var new_s := out.get_surface_count() - 1
			out.surface_set_material(new_s, mat)
			roles[new_s] = role
	_split_cache[key] = out
	_split_roles[key] = roles
	_split_roles_out[out.get_instance_id()] = roles
	return out


## Which surfaces of `role_split_mesh(src)` are KIT and which NATURAL, as
## {surface index -> Role}. Keyed on the SOURCE mesh, so callers may ask before
## or after the swap.
func split_surface_roles(src: Mesh) -> Dictionary:
	return _split_roles.get(src.get_instance_id(), {})


## The same map, asked the other way round: given a mesh a MeshInstance3D is
## already WEARING, was it a role split, and which of its surfaces are KIT?
## {} for every mesh that never went through the split — which is how the role
## gate tells a split surface from a plain one.
func split_roles_for_split_mesh(mesh: Mesh) -> Dictionary:
	return _split_roles_out.get(mesh.get_instance_id(), {})


func _split_indices_by_texel(idx: PackedInt32Array, uvs: PackedVector2Array,
		img: Image) -> Dictionary:
	var out := {Role.KIT: PackedInt32Array(), Role.NATURAL: PackedInt32Array()}
	if img == null or uvs.is_empty() or idx.size() < 3 or idx.size() % 3 != 0:
		out[Role.NATURAL] = idx   # nothing to sample: it is what it is
		return out
	var w := img.get_width()
	var h := img.get_height()
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var uv := (uvs[a] + uvs[b] + uvs[c]) / 3.0
		var px := img.get_pixel(
				clampi(int(uv.x * w), 0, w - 1),
				clampi(int(uv.y * h), 0, h - 1))
		var into: PackedInt32Array = out[texel_role(px)]
		into.append(a)
		into.append(b)
		into.append(c)
		out[texel_role(px)] = into
	return out


var _surface_mean_cache: Dictionary = {}   # "<mesh id>|<surface>|<tex id>" -> Color


## The mean colour of the texels ONE surface's UVs actually land on.
##
## The role gate needs to know what a surface renders, and on a pack where a
## single 1024² atlas paints skin, steel, leather AND cloth, the mean of the
## whole image is nobody's colour — it would call the knight's steel-blue
## breastplate "warm brown" because the same atlas holds his face. So the
## triangles are walked and the atlas sampled at each UV centroid, exactly the
## way role_split_mesh classifies them. Cached per (mesh, surface, texture).
func surface_mean_color(mesh: Mesh, s: int, tex: Texture2D) -> Color:
	if tex == null or s >= mesh.get_surface_count():
		return Color.WHITE
	var key := "%d|%d|%d" % [mesh.get_instance_id(), s, tex.get_instance_id()]
	if _surface_mean_cache.has(key):
		return _surface_mean_cache[key]
	var img := _atlas_image(tex)
	var out := Color.WHITE
	if img != null:
		var arrays := mesh.surface_get_arrays(s)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] \
				if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var w := img.get_width()
		var h := img.get_height()
		var sum := Color(0.0, 0.0, 0.0)
		var n := 0
		if not uvs.is_empty() and idx.size() >= 3:
			for t in idx.size() / 3:
				var uv := (uvs[idx[t * 3]] + uvs[idx[t * 3 + 1]]
						+ uvs[idx[t * 3 + 2]]) / 3.0
				var px := img.get_pixel(clampi(int(uv.x * w), 0, w - 1),
						clampi(int(uv.y * h), 0, h - 1))
				if px.a < 0.5:
					continue
				sum += px
				n += 1
		if n > 0:
			out = Color(sum.r / n, sum.g / n, sum.b / n)
	_surface_mean_cache[key] = out
	return out


## A decompressed RGBA copy of an atlas, cached. DUPLICATE before touching it:
## Texture2D.get_image() hands back the texture's OWN Image, and decompressing
## or converting in place silently edits the source atlas for every later
## caller (a scar from the desaturation pipeline this replaced).
func _atlas_image(tex: Texture2D) -> Image:
	var key := tex.get_instance_id()
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var src_img := tex.get_image()
	if src_img == null:
		return null
	var img := src_img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	_atlas_cache[key] = img
	return img


## THE JERSEY'S CLOTH: a pure-luminance copy of an atlas with its dark end
## remapped into the top half (KIT_SHADE_FLOOR/GAIN), so multiplying the house
## colour through it gives a garment that keeps every fold the artist painted
## and still lands ON the house colour. House-independent, so it is computed
## ONCE per atlas and shared by all nine armies.
func _kit_luminance(tex: Texture2D) -> Texture2D:
	var key := "kitlum|%d" % tex.get_instance_id()
	if _desat_cache.has(key):
		return _desat_cache[key]
	var src_img := _atlas_image(tex)
	if src_img == null:
		_desat_cache[key] = tex
		return tex
	var img := src_img.duplicate() as Image
	_remap_value(img, KIT_SHADE_FLOOR, KIT_SHADE_GAIN, 0.0)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_desat_cache[key] = out
	return out


## A NATURAL atlas with its black point lifted — see QUEEN_TONE_FLOOR. Colour
## is untouched; this is a value move and only a value move.
func _black_point_lifted(tex: Texture2D, floor_v: float) -> Texture2D:
	var key := "floor|%d|%.3f" % [tex.get_instance_id(), floor_v]
	if _desat_cache.has(key):
		return _desat_cache[key]
	var src_img := _atlas_image(tex)
	if src_img == null:
		_desat_cache[key] = tex
		return tex
	var img := src_img.duplicate() as Image
	_remap_value(img, floor_v, 1.0 - floor_v, 1.0)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_desat_cache[key] = out
	return out


## L' = floor + gain * L, per channel, in place, at the given saturation
## (0 = drive to pure luminance first, 1 = keep the atlas's own colours).
## Linear and monotonic, so every fold and seam keeps its ordering — a hard
## `max(L, floor)` would flatten a hood into a paper cut-out. Alpha untouched:
## a cut-out stays a cut-out.
##
## RUN IN ENGINE CODE, NEVER IN A LOOP. This used to be a get_pixel/set_pixel
## pass over the image; at 1024² that is a million GDScript iterations, and the
## role pipeline needs it on ~10 atlases — twenty-odd seconds of freeze at the
## first board setup. Image.adjust_bcs does the same affine in C++, but it is
## anchored at 0.5 (`out = 0.5 + contrast * (brightness * L - 0.5)`), so a floor
## above 0.5 is unreachable in one call. Two calls reach any of it:
##   A: adjust_bcs(1, 0.5, sat)  ->  L1 = 0.25 + 0.5*L   (range 0.25-0.75, so
##                                   the intermediate can never clamp)
##   B: L = 2*L1 - 0.5, so floor + gain*L = (0.5 - 0.5c) + c*b*L1 with
##      c = 1 - 2*floor + gain and b = 2*gain/c.
## tools/check_bcs.gd is the proof — it reproduces the identity to <0.009 over
## the range (two rounds of 8-bit quantisation), for every floor/gain we use.
func _remap_value(img: Image, floor_v: float, gain: float,
		saturation: float) -> void:
	img.adjust_bcs(1.0, 0.5, saturation)
	var c := 1.0 - 2.0 * floor_v + gain
	if c <= 0.001:
		push_error("PieceAssets._remap_value: floor %.2f / gain %.2f is not expressible"
				% [floor_v, gain])
		return
	img.adjust_bcs(2.0 * gain / c, c, 1.0)
