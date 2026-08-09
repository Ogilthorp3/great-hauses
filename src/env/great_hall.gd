class_name GreatHall
extends Node3D
## Builds the torch-lit great hall around the chess board: stone floor and
## perimeter walls (MultiMesh — 1 draw call each), corner pillars, two feast
## tables, eight flickering torches (src/env/torch.gd), TWENTY-TWO banner
## stations (src/env/banner.gd) awaiting the Great Hauses' colors, a further
## 26 sigil-less panels of cloth carried on two MultiMeshes, and the Throne of
## Blades (custom prop) against the far wall. `summon_champion_dragon()` /
## `dragon_wink()` stage the championship dragon above it — no extra lights.
##
## Cost of the whole dressing, measured against the same tree with the hall
## cut back to its original nine stations (1080p perf harness, both runs
## COTENANT count=0): draws 859 -> 885, primitives 466,346 -> 469,529 — +26
## draw calls and +0.68 % primitives for 9 -> 48 panels of cloth.
##
## Everything is KayKit Dungeon Remastered (CC0), copied with its license to
## res://assets/kaykit-dungeon/. Board center is world origin; the hall
## floor top sits at y = -0.3 (the board plinth rests on it).
##
## Integrator API (banners):
##   dress_for_match(player, rival)         THE DRESSING — colours AND sigils
##   dress_for_champion(house)              the throne shot: the hall falls
##   get_banner(i) -> HallBanner            i = 0..STATIONS.size()-1
##   set_banner_colors(colors)              dyes banners 0..n in index order
##                                          (colour only — sigils stay put)
##   banners                                the Array[HallBanner] itself
##
## THE INDEX MAP IS APPEND-ONLY. 0..8 are the original nine and MUST keep
## their meaning: the e2e boot scenario reads banner 3 (west wall centre =
## the player's primary) and the tournament scenario reads banner 6 (east
## wall centre = the rival's primary) every round. New stations are appended
## at 9+; nothing is ever renumbered.
##   0,1,2   far wall   (z=+12) at x = -4, 0, +4   (2 is screen-left)
##   3,4,5   west wall  (x=-12) at z = -4, 0, +4   (screen-right side)
##   6,7,8   east wall  (x=+12) at z = -4, 0, +4   (screen-left side)
##   9,10    far wall, the pair framing the throne, x = -2, +2
##   11,12   the FAR pillars' camera-facing shoulders  <- the gameplay heroes
##   13,14   the NEAR pillars' camera-facing shoulders (the black-side view)
##   15..18  side walls, far quarter, small low pennants (z = +6.3, +8.6)
##   19,20,21 near wall, behind the player's own army, x = -6.5, 0, +6.5
##
## THE HALL WEARS THE MATCHUP (ISSUES.md P12, 2026-08-09): the hall dresses
## ITSELF from Session at _ready — the player's house claims the west wall
## and the far-wall flank it faces, the rival claims the east wall and the
## opposite flank, each in its own heraldic colours AND its own sigil. Before
## this the nine banners were anonymous dyed rectangles: every
## Winterfang-vs-Goldclaw frame hung red and cream cloth and the room the war
## is actually fought in was the only place in the game that never said who
## was fighting.
##
## ── DRESSED WHERE THE PLAYER ACTUALLY LOOKS (2026-08-09) ───────────────────
## The nine original stations were hung for a camera nobody plays from. The
## gameplay rig is pitch -0.85 / distance 11.5 off a pivot at y 0.4, i.e. the
## eye sits at (0, 9.04, -7.59) and looks 48.7 deg DOWN; with a 50 deg
## vertical fov the top of the frame drops through the room as
##     y_top(z) = 9.04 - 0.439 * (z + 7.59)
## so at the far wall (z = 11.31, the cloth's front face) the frame stops at
## y = 0.74 — the far-wall banners hang from 0.23 to 3.43 and the player sees
## a 20 px hem of them, mostly behind the HUD title. Sideways it is worse:
## |x| <= 0.829 * depth, so the side walls do not enter the frame at all
## until z ~ +4, which is why exactly ONE of the nine (station 8) clipped the
## screen edge in 02_boot_lineup.png and the hall read as bare stone.
##
## What the gameplay camera CAN see of the room's dressing is the far pillars
## and the far quarter of the side walls, so that is where the new heroes go:
## stations 11/12 hang on the pillars' camera-facing shoulders at 0.75 scale
## (whole banner inside the frame, ~43 px sigil, top-left and top-right of
## every frame) and 15..18 are small low pennants on the side walls' far
## quarter (~36 px sigils in the corner wedges). The full-height wall stations
## stay full height because the wide/showcase/orbit/throne cameras — which do
## see the walls — are the ones they were tuned on.
## tests/test_cinematics.gd::_test_hall_banner_frame reproduces this
## projection against the REAL camera and fails if the heroes leave the frame.
##
## FPS probe (env verification, no game-code hooks): launch with user arg
## "--env-fps" to print one "ENV_FPS second=<n> fps=<v>" line per second for
## 10 s, then quit. Dormant otherwise.

const WALL_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/wall.gltf")
const FLOOR_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/floor_tile_large.gltf")
const PILLAR_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/pillar.gltf")
const TABLE_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/table_long.gltf")
const CANDLE_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/candle_triple.gltf")
const THRONE_SCENE: PackedScene = preload("res://assets/custom-props/throne.glb")
## The drape shapes the sigil-less dressing is cut from — same CC0 pack, same
## dungeon_texture.png, so they cost no new texture memory. banner_thin is one
## 1.1 u drop (83 tris); banner_triple is a 3.7 u three-panel swag in a SINGLE
## mesh (263 tris), which is why the corners are cheap.
const DRAPE_THIN_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/banner_thin_white.gltf")
const DRAPE_TRIPLE_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/banner_triple_white.gltf")

const TorchScript := preload("res://src/env/torch.gd")
const BannerScript := preload("res://src/env/banner.gd")
## Shared dragon controller (loader + clips + emissive lift) — the single
## owner of the dragon.glb staging since the spectator/ashfall module.
const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")

const FLOOR_Y := -0.3         # hall floor top (plinth bottom)
const WALL_HALF := 12.0       # wall centerline distance from board center
const SEGMENT_XS := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]  # 6 x 4u = 24u side

## ── THE HALL HAD NO TOP (critic defect, 2026-08-09) ───────────────────────
## One wall course is 4 u, so the stone stopped at y 3.7 and above that the
## room was the Environment's background colour. Two frames were shipping that
## hole: `showcase/10_throne_room` is ~40 % black over the banners (its camera
## looks level at the far wall, whose frame top is y 7.20 — three and a half
## units of nothing), and `dragon-live/04_mid_ashfall` films the airborne wyrm
## from a low dolly, so every sightline behind it left the room entirely.
##
## Both are the same missing geometry, and the fix is the cheapest one there
## is: TWO more courses of the wall mesh — appended to the SAME MultiMesh, so
## the enclosure costs zero extra draw calls — plus a ceiling and a rafter
## band above the ceremony's flight ceiling.
const WALL_COURSE := 4.0      # one wall segment's height
const WALL_COURSES := 3       # 3 x 4 u: stone up to y 11.7
const CEILING_Y := FLOOR_Y + WALL_COURSE * WALL_COURSES
## The rafters hang under the ceiling, and they must clear EVERY airborne beat
## the ceremony has: the tableau dragon tops out near y 7.6 (root 4.04 at
## scale 1.6) and the ashfall bank flies at root 5.11 — 9.6 is above both with
## room to spare, and still inside the frame of any camera looking up.
const RAFTER_Y := 9.6
const RAFTER_ZS := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]

## Throne of Blades (custom prop): 1.5 m plinth against the far wall (inner
## face z = +11.5), base centered so the back edge nearly kisses the stone.
const THRONE_POS := Vector3(0.0, FLOOR_Y, 10.7)
## Championship dragon hover: above the throne, wings clearing the 4 u wall
## line (the hall is open-topped) but well under the y≈7 ceiling.
##
## THE ORIGIN MOVED (dragon-v2, 2026-08-09). The Quaternius rig hung its mesh
## around a MID-AIR root; the serpent-wyrm's `Root` sits ON THE GROUND
## between its feet, with the torso mass centre measured at
## DragonRig.BODY_RISE (0.95) × rig scale above it. Rule from the asset's
## author: new_root_y = old_root_y + 1.15 × rig_scale. At DRAGON_SCALE 1.6
## that is 2.2 + 1.84 = 4.04, and the body still reads at the same y 5.56 it
## always did — which is why throne_focus() below did NOT move.
const DRAGON_HOVER := Vector3(0.0, 4.04, 9.9)
## Ceremony sizing (2026-08-08): the tableau dragon reads at 1.6 — the same
## scale the DragonSpectator championship ceremony settles at, so the
## hand-off from ashfall to tableau never pops. (test_dragon.gd asserts
## both the scale and DRAGON_HOVER stay in sync with the spectator.)
const DRAGON_SCALE := 1.6

## Which house a piece of cloth belongs to. THE SEAM IS x = 0: everything on
## the player's side of the hall (x < 0, the west) flies the player, the
## rival owns the east, and the two meet over the throne — the far wall runs
## player, player, SEAM, rival, rival across the Throne of Blades.
const HOUSE_SELF := 0
const HOUSE_RIVAL := 1

## Pillar face (+-6.75 from the pillar's 1.5 u box at z = +-7.5) plus the
## drape's own 0.378 back offset at 0.75 scale — so the cloth kisses the stone.
const PILLAR_BANNER_Z := 7.0335

## THE BANNER STATIONS — the sigil-bearing banners, one HallBanner each.
## [position, yaw, scale, side, tone]. APPEND-ONLY (see the index map up top):
## row 3 must stay the player's primary and row 6 the rival's primary or the
## boot and tournament e2e scenarios go red.
##
## Scale is per-station because the gameplay camera's frame is a wedge, not a
## room: a full-height banner reads on the walls the wide/orbit cameras see,
## while the pillar and side-wall stations are cut down so their whole cloth —
## sigil included — lands inside the -0.85 pitch frame.
const STATIONS := [
	# ── the original nine (0..8): do not renumber, do not re-tone ──────────
	[Vector3(-4.0, FLOOR_Y, WALL_HALF), PI, 1.0, HOUSE_SELF, "primary"],
	[Vector3(0.0, FLOOR_Y, WALL_HALF), PI, 1.0, HOUSE_SELF, "accent"],
	[Vector3(4.0, FLOOR_Y, WALL_HALF), PI, 1.0, HOUSE_RIVAL, "primary"],
	[Vector3(-WALL_HALF, FLOOR_Y, -4.0), PI * 0.5, 1.0, HOUSE_SELF, "primary"],
	[Vector3(-WALL_HALF, FLOOR_Y, 0.0), PI * 0.5, 1.0, HOUSE_SELF, "secondary"],
	[Vector3(-WALL_HALF, FLOOR_Y, 4.0), PI * 0.5, 1.0, HOUSE_SELF, "accent"],
	[Vector3(WALL_HALF, FLOOR_Y, -4.0), -PI * 0.5, 1.0, HOUSE_RIVAL, "primary"],
	[Vector3(WALL_HALF, FLOOR_Y, 0.0), -PI * 0.5, 1.0, HOUSE_RIVAL, "secondary"],
	[Vector3(WALL_HALF, FLOOR_Y, 4.0), -PI * 0.5, 1.0, HOUSE_RIVAL, "accent"],
	# ── 9,10: the pair framing the Throne of Blades ────────────────────────
	[Vector3(-2.0, FLOOR_Y, WALL_HALF), PI, 1.0, HOUSE_SELF, "secondary"],
	[Vector3(2.0, FLOOR_Y, WALL_HALF), PI, 1.0, HOUSE_RIVAL, "secondary"],
	# ── 11..14: the pillars' camera-facing shoulders ───────────────────────
	# The pillar is 1.5 u square, its face at z = +-6.75; the drape's back
	# vertex sits at local z 0.378, so the node stands 0.378 * scale proud of
	# the face and the cloth lies flat on the stone. 11/12 are THE banners the
	# gameplay camera sees (top-right / top-left of every frame); 13/14 are
	# their twins for the black-side camera, which yaws 180 deg.
	[Vector3(-7.5, FLOOR_Y, PILLAR_BANNER_Z), PI, 0.75, HOUSE_SELF, "primary"],
	[Vector3(7.5, FLOOR_Y, PILLAR_BANNER_Z), PI, 0.75, HOUSE_RIVAL, "primary"],
	[Vector3(-7.5, FLOOR_Y, -PILLAR_BANNER_Z), 0.0, 0.75, HOUSE_SELF, "accent"],
	[Vector3(7.5, FLOOR_Y, -PILLAR_BANNER_Z), 0.0, 0.75, HOUSE_RIVAL, "accent"],
	# ── 15..18: side walls, far quarter — small pennants hung LOW, the only
	# height the gameplay camera keeps in frame out at the corner wedges ────
	[Vector3(-WALL_HALF, FLOOR_Y, 6.3), PI * 0.5, 0.64, HOUSE_SELF, "secondary"],
	[Vector3(WALL_HALF, FLOOR_Y, 6.3), -PI * 0.5, 0.64, HOUSE_RIVAL, "secondary"],
	[Vector3(-WALL_HALF, FLOOR_Y, 8.6), PI * 0.5, 0.64, HOUSE_SELF, "accent"],
	[Vector3(WALL_HALF, FLOOR_Y, 8.6), -PI * 0.5, 0.64, HOUSE_RIVAL, "accent"],
	# ── 19..21: the near wall, behind the player's own army (was bare) ─────
	# Clear of the near-wall torch pair at x = +-4.
	[Vector3(-6.5, FLOOR_Y, -WALL_HALF), 0.0, 1.0, HOUSE_SELF, "primary"],
	[Vector3(0.0, FLOOR_Y, -WALL_HALF), 0.0, 1.0, HOUSE_SELF, "accent"],
	[Vector3(6.5, FLOOR_Y, -WALL_HALF), 0.0, 1.0, HOUSE_RIVAL, "primary"],
]

## THE SIGIL-LESS DRESSING. Every remaining stretch of wall, carried on two
## MultiMeshes (one per shape) so 26 more panels of cloth cost TWO draw calls
## instead of 26 — measured, not assumed: the perf harness reads 883 -> 885
## draws and +1425 primitives for the whole set (test_e2e/artifacts/perf/
## 20260809-144527 vs -144408, both COTENANT count=0). No sigils: at these
## positions a 256 px charge would be a smear, and the heraldry is already
## carried by the stations. Per-instance MultiMesh colors let the same two
## meshes fly both hauses.
## [position, yaw, side, tone]
const DRAPES_THIN := [
	# far wall, inboard of the corner swags and clear of the x = +-8 torches
	[Vector3(-6.0, FLOOR_Y, WALL_HALF), PI, HOUSE_SELF, "secondary"],
	[Vector3(6.0, FLOOR_Y, WALL_HALF), PI, HOUSE_RIVAL, "secondary"],
	# near wall, between the player's stations and the x = +-4 torches
	[Vector3(-2.0, FLOOR_Y, -WALL_HALF), 0.0, HOUSE_SELF, "secondary"],
	[Vector3(2.0, FLOOR_Y, -WALL_HALF), 0.0, HOUSE_RIVAL, "secondary"],
	# west wall (the player's), filling the gaps between the stations
	[Vector3(-WALL_HALF, FLOOR_Y, -10.4), PI * 0.5, HOUSE_SELF, "accent"],
	[Vector3(-WALL_HALF, FLOOR_Y, -7.0), PI * 0.5, HOUSE_SELF, "secondary"],
	[Vector3(-WALL_HALF, FLOOR_Y, -2.0), PI * 0.5, HOUSE_SELF, "accent"],
	[Vector3(-WALL_HALF, FLOOR_Y, 2.0), PI * 0.5, HOUSE_SELF, "secondary"],
	[Vector3(-WALL_HALF, FLOOR_Y, 10.4), PI * 0.5, HOUSE_SELF, "accent"],
	# east wall (the rival's), mirrored
	[Vector3(WALL_HALF, FLOOR_Y, -10.4), -PI * 0.5, HOUSE_RIVAL, "accent"],
	[Vector3(WALL_HALF, FLOOR_Y, -7.0), -PI * 0.5, HOUSE_RIVAL, "secondary"],
	[Vector3(WALL_HALF, FLOOR_Y, -2.0), -PI * 0.5, HOUSE_RIVAL, "accent"],
	[Vector3(WALL_HALF, FLOOR_Y, 2.0), -PI * 0.5, HOUSE_RIVAL, "secondary"],
	[Vector3(WALL_HALF, FLOOR_Y, 10.4), -PI * 0.5, HOUSE_RIVAL, "accent"],
]

## The three-panel swags: one in each corner of the room, on the near and far
## walls where a 3.7 u run fits outboard of every torch. Their x span
## (+-8.15 .. +-11.85) is why no side-wall drape may sit past |z| = 10.6 —
## the two would intersect in the corner.
const DRAPES_TRIPLE := [
	[Vector3(-10.0, FLOOR_Y, WALL_HALF), PI, HOUSE_SELF, "primary"],
	[Vector3(10.0, FLOOR_Y, WALL_HALF), PI, HOUSE_RIVAL, "primary"],
	[Vector3(-10.0, FLOOR_Y, -WALL_HALF), 0.0, HOUSE_SELF, "primary"],
	[Vector3(10.0, FLOOR_Y, -WALL_HALF), 0.0, HOUSE_RIVAL, "primary"],
]

var banners: Array[HallBanner] = []
## The sigil-less drapes: one entry per MultiMesh, {mm, tints, colors}. `tints`
## is the parallel [side, tone] list the re-dye walks; `colors` is what the
## re-dye last WROTE. Cloth only — the API above never hands these out,
## because there is nothing per-banner to hand out.
##
## `colors` is not bookkeeping for its own sake: MultiMesh instance data lives
## in the RenderingServer, and under `--headless` (the dummy server) both
## get_instance_color and get_instance_transform read back empty. Without this
## record a headless test of the dressing can only ever assert black.
var _drapes: Array = []
var throne: Node3D = null
var dragon: Node3D = null              # summoned for the championship only
var _dragon_anim: AnimationPlayer = null

var _fps_probe := false
var _fps_accum := 0.0
var _fps_seconds := 0


func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_roof()
	_build_wainscot()
	_build_pillars()
	_build_tables()
	_build_torches()
	_build_banners()
	_build_banner_drapes()
	_build_throne()
	_build_fill_lights()
	_dress_from_session()
	var args := OS.get_cmdline_user_args()
	if args.has("--env-fps"):
		_fps_probe = true
		print("ENV_FPS probe armed — 10 one-second samples then quit")
	if args.has("--env-banner-test"):
		# Nine original Great Haus colors (wolf/lion/stag/dragon/kraken/
		# rose/sun/falcon/trout archetypes) — proves per-banner recolor.
		# Cycled across every station, so the probe frame shows the whole
		# hall repainted and not just the first nine of it.
		var wheel := [
			Color(0.75, 0.78, 0.82),  # House Winterhowl — grey wolf
			Color(0.72, 0.15, 0.12),  # House Goldmane — crimson lion
			Color(0.85, 0.65, 0.1),   # House Hartcrown — golden stag
			Color(0.38, 0.08, 0.1),   # House Ashwing — dragon oxblood
			Color(0.1, 0.34, 0.3),    # House Deepgrasp — kraken sea-green
			Color(0.32, 0.5, 0.2),    # House Thornrose — rose green
			Color(0.9, 0.45, 0.1),    # House Dawnspear — burning sun
			Color(0.35, 0.55, 0.8),   # House Skyperch — falcon sky
			Color(0.5, 0.55, 0.65),   # House Silverleap — trout silver
		]
		var wheeled: Array = []
		for i in banners.size():
			wheeled.append(wheel[i % wheel.size()])
		set_banner_colors(wheeled)


# -- integrator hooks ------------------------------------------------------


func get_banner(i: int) -> HallBanner:
	return banners[i] if i >= 0 and i < banners.size() else null


func set_banner_colors(colors: Array) -> void:
	## Dye banners 0..n-1 in index order (see the map in the header). COLOUR
	## ONLY — whichever house each banner flies (its sigil) is untouched, so
	## an integrator re-dye can never leave a lion's sigil on a wolf's wall.
	for i in mini(colors.size(), banners.size()):
		banners[i].set_house_color(colors[i])


## THE DRESSING. Hang the whole hall for the match actually being played: the
## player's house takes everything west of the throne, the rival everything
## east of it, and the two meet on the far wall over the Throne of Blades.
## Each STATION flies its house's SIGIL over its house's cloth; the drapes
## between them fly the cloth alone.
##
## Which of a house's three heraldic colours each station flies is deliberate
## and lives in the STATIONS table: stations 3 and 6 (the wall centres the
## e2e asserts read) fly the PRIMARY exactly, and the rest alternate through
## secondary/accent so a near-black primary (Hartcrown #1d1a17, Ashwyrm
## #171214) never leaves a whole wall invisible in a torch-lit room.
func dress_for_match(player_house: String, rival_house: String) -> void:
	if player_house.is_empty() or banners.is_empty():
		return
	var rival := rival_house if not rival_house.is_empty() else player_house
	var ids := [player_house, rival]
	var cols := [HouseRegistry.get_colors(player_house), HouseRegistry.get_colors(rival)]
	for i in mini(STATIONS.size(), banners.size()):
		var st: Array = STATIONS[i]
		var side := int(st[3])
		banners[i].set_house(str(ids[side]), (cols[side] as Dictionary)[st[4]] as Color)
	_dye_drapes(cols)


## THE THRONE SHOT: every banner in the hall falls to the champion — the
## whole room, sigils and drapes included, becomes one house. Alternates
## primary/accent so a wall of identical rectangles does not read as wallpaper.
func dress_for_champion(house: String) -> void:
	if house.is_empty() or banners.is_empty():
		return
	var c := HouseRegistry.get_colors(house)
	for i in banners.size():
		banners[i].set_house(house, (c["primary"] if i % 2 == 0 else c["accent"]) as Color)
	_dye_drapes([c, c])


## Repaint the sigil-less cloth. `cols` is [player_colors, rival_colors] — the
## same pair the stations were dressed from, so a drape can never end up
## flying a house its neighbouring station is not.
func _dye_drapes(cols: Array) -> void:
	for group in _drapes:
		var mm: MultiMesh = group["mm"]
		var tints: Array = group["tints"]
		var record: PackedColorArray = group["colors"]
		for i in tints.size():
			var t: Array = tints[i]
			var c := (cols[int(t[0])] as Dictionary)[t[1]] as Color
			mm.set_instance_color(i, c)
			record[i] = c


## Self-dressing: the hall reads the matchup off Session (statics survive
## change_scene, and GreatHall._ready runs before the game root's _ready that
## would otherwise have to push it in). Unconfigured launches — probes,
## --smoke, direct game.tscn runs — leave the neutral undyed cloth alone.
func _dress_from_session() -> void:
	if not Session.configured or Session.player_house.is_empty():
		return
	dress_for_match(Session.player_house, Session.rival_house())


# -- construction ----------------------------------------------------------


static func _extract_mesh(scene: PackedScene) -> Mesh:
	## The single Mesh inside an imported KayKit gltf (materials ride on the
	## mesh surfaces, so MultiMesh keeps the look for free).
	var inst := scene.instantiate()
	var mesh := _find_mesh(inst)
	var res: Mesh = mesh.mesh if mesh != null else null
	inst.free()
	return res


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


static func _tinted_mesh(mesh: Mesh, tint: Color) -> Mesh:
	## A duplicate whose materials are multiplied toward gritty stone — the
	## KayKit texture is showroom-bright; the hall should not be. Duplicates
	## keep the source (shared, cached) resources untouched.
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s).duplicate() as StandardMaterial3D
		mat.albedo_color = mat.albedo_color * tint
		mat.roughness = 1.0
		copy.surface_set_material(s, mat)
	return copy


func _multimesh_node(node_name: String, mesh: Mesh, xforms: Array[Transform3D],
		shadows := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_floor() -> void:
	## 6x6 grid of 4u tiles = 24x24 hall floor; deterministic 90-degree spins
	## break the tiling repetition without random screenshots.
	var xforms: Array[Transform3D] = []
	var i := 0
	for gx in 6:
		for gz in 6:
			var pos := Vector3(-10.0 + gx * 4.0, FLOOR_Y - 0.05, -10.0 + gz * 4.0)
			var spin := Basis(Vector3.UP, float((i * 7) % 4) * PI * 0.5)
			xforms.append(Transform3D(spin, pos))
			i += 1
	_multimesh_node("Floor", _tinted_mesh(_extract_mesh(FLOOR_SCENE), Color(0.5, 0.49, 0.54)), xforms)


func _build_walls() -> void:
	## 6 segments per side, +Z face turned into the room; ends overlap at the
	## corners so the perimeter reads sealed from every orbit angle. Stacked
	## WALL_COURSES high (see the constant block): the extra courses ride the
	## same MultiMesh, so the room gets a top for no extra draw call.
	var xforms: Array[Transform3D] = []
	for c in WALL_COURSES:
		var y := FLOOR_Y + WALL_COURSE * float(c)
		for x in SEGMENT_XS:
			xforms.append(Transform3D(Basis(), Vector3(x, y, -WALL_HALF)))
			xforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, WALL_HALF)))
		for z in SEGMENT_XS:
			xforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-WALL_HALF, y, z)))
			xforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(WALL_HALF, y, z)))
	_multimesh_node("Walls", _tinted_mesh(_extract_mesh(WALL_SCENE), Color(0.58, 0.56, 0.62)), xforms)


func _build_roof() -> void:
	## THE LID. A ceiling of the same floor tiles turned face-DOWN, plus a
	## band of rafters under it.
	##
	## Two properties this depends on, both deliberate:
	##   * it never casts a shadow — a 24x24 lid over the one shadow-casting
	##     Sun would put the whole hall in the dark;
	##   * its visible face points DOWN, so the default back-face cull makes it
	##     INVISIBLE from above. That matters because the gameplay orbit camera
	##     climbs to y ~9 (and to ~13 zoomed out at full pitch) — it looks into
	##     the room from over the roof line and must never see the lid it is
	##     standing on.
	var tiles: Array[Transform3D] = []
	var flip := Basis(Vector3.RIGHT, PI)
	for gx in 6:
		for gz in 6:
			tiles.append(Transform3D(flip,
				Vector3(-10.0 + gx * 4.0, CEILING_Y, -10.0 + gz * 4.0)))
	_multimesh_node("Ceiling",
		_tinted_mesh(_extract_mesh(FLOOR_SCENE), Color(0.30, 0.28, 0.33)), tiles,
		false)
	# The rafters: plain dark beams spanning the short way, plus the two wall
	# plates they land on. A box, not a KayKit prop — nothing in the pack is a
	# beam, and at this height and this light level it is a silhouette.
	var beam := BoxMesh.new()
	beam.size = Vector3(WALL_HALF * 2.0, 0.42, 0.62)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.155, 0.175)
	mat.roughness = 1.0
	beam.material = mat
	var beams: Array[Transform3D] = []
	for z in RAFTER_ZS:
		beams.append(Transform3D(Basis(), Vector3(0.0, RAFTER_Y, z)))
	for sx in [-1.0, 1.0]:
		beams.append(Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(11.6 * sx, RAFTER_Y + 0.3, 0.0)))
	_multimesh_node("Rafters", beam, beams, false)


## THE DARK BASE COURSE — and the reason it exists is the HUD, not the hall.
##
## The gameplay camera (pivot y 0.4, pitch -0.85, fov 50) stops at
## y_top(z) = 9.04 - 0.439 (z + 7.59), so at the far wall the frame's top edge
## is y 0.66: the TOP BAND OF EVERY FRAME is the bottom metre of the far wall,
## and that is exactly where the HUD hangs "HAUS X vs HAUS Y". Once the hall
## grew its full dressing, that metre filled with banner HEMS — and a champion
## dressing (dress_for_champion paints all 22 stations one house) put gold and
## crimson cloth directly behind pale title text. `tournament/
## 05_championship_panel` shipped with the matchup near-illegible.
##
## The HUD belongs to another module, so the hall keeps its own band quiet: a
## wainscot of dark stone standing PROUD OF THE CLOTH (front face z 11.10, the
## cloth's is 11.31) and exactly 1.0 u tall — the height that reaches y 0.70,
## a hair over the frame's top edge at that depth. Below the band the room is
## unchanged; above it every banner still flies its full drop.
const WAINSCOT_H := 1.0
const WAINSCOT_D := 0.5
const WAINSCOT_FACE := 11.10   # inner face; the wall's own is ~11.5


func _build_wainscot() -> void:
	var band := BoxMesh.new()
	band.size = Vector3(WALL_HALF * 2.0, WAINSCOT_H, WAINSCOT_D)
	var mat := StandardMaterial3D.new()
	# Dark enough that pale HUD text sits clear of it, light enough that the
	# duel and orbit cameras — which see this band edge-on across the whole
	# back of the frame — read STONE and not a black stripe.
	mat.albedo_color = Color(0.165, 0.155, 0.180)
	mat.roughness = 1.0
	band.material = mat
	var y := FLOOR_Y + WAINSCOT_H * 0.5
	var c := WAINSCOT_FACE + WAINSCOT_D * 0.5
	var xforms: Array[Transform3D] = []
	for spec: Array in [[Vector3(0.0, y, c), 0.0], [Vector3(0.0, y, -c), 0.0],
			[Vector3(c, y, 0.0), PI * 0.5], [Vector3(-c, y, 0.0), PI * 0.5]]:
		xforms.append(Transform3D(Basis(Vector3.UP, spec[1] as float),
			spec[0] as Vector3))
	_multimesh_node("Wainscot", band, xforms, false)


func _build_pillars() -> void:
	var mesh := _tinted_mesh(_extract_mesh(PILLAR_SCENE), Color(0.58, 0.56, 0.62))
	for corner in [Vector2(-7.5, -7.5), Vector2(7.5, -7.5), Vector2(-7.5, 7.5), Vector2(7.5, 7.5)]:
		var mi := MeshInstance3D.new()
		mi.name = "Pillar_%d_%d" % [int(corner.x), int(corner.y)]
		mi.mesh = mesh  # shared resource, 4 instances
		mi.position = Vector3(corner.x, FLOOR_Y, corner.y)
		add_child(mi)


func _build_tables() -> void:
	## Two feast tables along the side aisles (long axis runs Z), scaled to
	## the warriors' size, a pair of candle stands on each.
	var table_mesh := _extract_mesh(TABLE_SCENE)
	var candle_mesh := _extract_mesh(CANDLE_SCENE)
	for sx in [-1.0, 1.0]:
		var table := MeshInstance3D.new()
		table.name = "FeastTable_E" if sx > 0.0 else "FeastTable_W"
		table.mesh = table_mesh
		table.position = Vector3(9.0 * sx, FLOOR_Y, 0.0)
		table.scale = Vector3.ONE * 0.65
		add_child(table)
		for sz in [-1.1, 1.1]:
			var candle := MeshInstance3D.new()
			candle.name = "%s_Candle_%s" % [table.name, "N" if sz < 0.0 else "S"]
			candle.mesh = candle_mesh
			candle.position = Vector3(9.0 * sx, FLOOR_Y + 0.65, sz)
			candle.scale = Vector3.ONE * 0.5
			candle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(candle)


func _build_torches() -> void:
	## 8 torches / 8 shadowless omnis — at the Mobile renderer's 8-omni
	## per-mesh cap for the big MultiMeshes, so do not add a ninth light.
	var specs := [
		# north wall pair (behind the default camera)
		[Vector3(-4.0, 1.9, -11.48), 0.0],
		[Vector3(4.0, 1.9, -11.48), 0.0],
		# south wall pair (flanks the far banners)
		[Vector3(-8.0, 1.9, 11.48), PI],
		[Vector3(8.0, 1.9, 11.48), PI],
		# pillar torches, facing across the board
		[Vector3(-6.72, 1.7, -7.5), PI * 0.5],
		[Vector3(-6.72, 1.7, 7.5), PI * 0.5],
		[Vector3(6.72, 1.7, -7.5), -PI * 0.5],
		[Vector3(6.72, 1.7, 7.5), -PI * 0.5],
	]
	for i in specs.size():
		var torch: Torch = TorchScript.new()
		torch.name = "Torch%d" % i
		torch.position = specs[i][0]
		torch.rotation.y = specs[i][1]
		add_child(torch)


func _build_banners() -> void:
	## One HallBanner per row of STATIONS — see the index map up top.
	for i in STATIONS.size():
		var st: Array = STATIONS[i]
		var banner: HallBanner = BannerScript.new()
		banner.name = "Banner%d" % i
		banner.position = st[0] as Vector3
		banner.rotation.y = st[1] as float
		var s := st[2] as float
		if not is_equal_approx(s, 1.0):
			banner.scale = Vector3.ONE * s
		add_child(banner)
		banners.append(banner)


func _build_banner_drapes() -> void:
	## The rest of the cloth. Two MultiMeshes, per-instance colors, no sigils,
	## NO SHADOWS: every one of these hangs flat on a wall, so its shadow falls
	## on the stone it is already touching — pure submission cost for nothing.
	_drapes.append(_drape_group("DrapesThin", DRAPE_THIN_SCENE, DRAPES_THIN))
	_drapes.append(_drape_group("DrapesTriple", DRAPE_TRIPLE_SCENE, DRAPES_TRIPLE))


func _drape_group(node_name: String, scene: PackedScene, specs: Array) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# use_colors MUST be set before instance_count: the buffer format is fixed
	# the moment the count is assigned.
	mm.use_colors = true
	mm.mesh = _vertex_dyed_mesh(_extract_mesh(scene))
	mm.instance_count = specs.size()
	var tints: Array = []
	var colors := PackedColorArray()
	for i in specs.size():
		var spec: Array = specs[i]
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, spec[1] as float), spec[0] as Vector3))
		mm.set_instance_color(i, HallBanner.NEUTRAL)
		tints.append([spec[2], spec[3]])
		colors.append(HallBanner.NEUTRAL)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return {"mm": mm, "tints": tints, "colors": colors}


## Multiply every surface of an instanced prop toward `tint`, on DUPLICATED
## materials so the shared imported resource stays clean (the same discipline
## DragonRig._apply_emissive_lift uses).
static func _darken(node: Node, tint: Color) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				m.albedo_color = m.albedo_color * tint
				mi.set_surface_override_material(s, m)


static func _vertex_dyed_mesh(mesh: Mesh) -> Mesh:
	## A duplicate whose material takes its albedo from the MultiMesh instance
	## color, so one mesh + one material can fly both hauses' colours in a
	## single draw call. Duplicates keep the shared imported resource clean.
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s).duplicate() as StandardMaterial3D
		mat.albedo_color = Color.WHITE
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		copy.surface_set_material(s, mat)
	return copy


func _build_throne() -> void:
	## The Throne of Blades stands against the far wall, seat opening turned
	## toward the board (the GLB front faces +Z as imported — rotate PI).
	## NO new lights: the 8-omni budget is full; the south-wall torch pair
	## (±8, z=11.48) already rakes the blade fan.
	##
	## …and it is DARKENED. The throne stands at z 10.7, which is the one depth
	## whose top metre lands in the gameplay frame's top band — the same band
	## the HUD hangs the matchup title in. Shipped at the prop's own showroom
	## brightness its pale plinth was the lightest thing behind
	## "HAUS X vs HAUS Y". Blackened iron and dark stone is both the fix and
	## what a Throne of Blades should look like.
	throne = THRONE_SCENE.instantiate()
	throne.name = "ThroneOfBlades"
	throne.position = THRONE_POS
	throne.rotation.y = PI
	add_child(throne)
	_darken(throne, Color(0.46, 0.44, 0.50))


## Championship staging: the dragon takes its perch above the throne with a
## slow wing-settle (spawned slightly high and large-of-motion, easing onto
## DRAGON_HOVER at scale 1.6 — a tween, never a pop) and a gentle ember
## drift over the tableau. Idempotent — returns the live dragon. Adds NO
## lights (the rig's emissive lift + emissive particles cover the glow; the
## 8-omni budget stays full). Loader lives in DragonRig (shared with the
## spectator/ashfall module) — do not duplicate it here again.
func summon_champion_dragon() -> Node3D:
	if dragon != null:
		return dragon
	# The championship staging is also where the hall falls to the champion:
	# the tournament only reaches this throne when the player's house wins
	# the final, so Session.player_house IS the champion. Runs after the
	# integrator's own colour pass, so the sigils have the last word.
	if Session.configured and not Session.player_house.is_empty():
		dress_for_champion(Session.player_house)
	var rig: DragonRig = DragonRigScript.spawn(
		self, "ChampionDragon", DRAGON_HOVER + Vector3.UP * 0.55, PI,
		DRAGON_SCALE * 0.92)
	# yaw PI: face the hall (toward -Z / the camera side)
	dragon = rig
	_dragon_anim = rig.anim
	rig.play_loop("Flying_Idle", 0.5, 0.8)   # slow flap: the wing-settle
	var settle := create_tween().set_parallel(true)
	settle.tween_property(rig, "position", DRAGON_HOVER, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle.tween_property(rig, "scale", Vector3.ONE * DRAGON_SCALE, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle.chain().tween_callback(func() -> void:
		if is_instance_valid(rig):
			rig.play_loop("Flying_Idle", 0.6, 0.6))   # the mighty hover
	# Gentle ember drift over the throne — emissive billboards, no lights.
	var drift := DragonRigScript.spawn_emitter(rig, "ThroneEmberDrift", {
		"amount": 26, "lifetime": 3.2, "size": 0.06,
		"velocity": Vector2(0.2, 0.7), "spread": 70.0,
		"direction": Vector3(0.0, -1.0, 0.0),
		"gravity": Vector3(0.0, -0.35, 0.0), "grow": 0.8,
		"emission_radius": 1.7,
		"ramp": [
			[0.0, Color(1.0, 0.7, 0.3, 0.0)],
			[0.2, Color(1.0, 0.55, 0.15, 0.9)],
			[1.0, Color(0.5, 0.12, 0.03, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 2.2,
	})
	# Rig-local: the wyrm's mass centre sits at BODY_RISE (0.95); the drift
	# hangs a little over its back. (Was 3.2, tuned against the old mid-air
	# root — with the ground-origin rig that would have parked the embers in
	# the rafters, a whole body length above the beast.)
	drift.position = Vector3.UP * (DragonRigScript.BODY_RISE + 1.10)
	drift.emitting = true
	return dragon


## The wink: one slow Yes nod toward the camera, then back to the hover loop.
func dragon_wink() -> void:
	if _dragon_anim == null or not _dragon_anim.has_animation("Yes"):
		return
	_dragon_anim.speed_scale = 0.55
	_dragon_anim.play("Yes", 0.3)
	await get_tree().create_timer(_dragon_anim.get_animation("Yes").length / 0.55).timeout
	if not is_instance_valid(_dragon_anim):
		return
	_dragon_anim.speed_scale = 0.6   # settle back into the mighty hover
	if _dragon_anim.has_animation("Flying_Idle"):
		_dragon_anim.play("Flying_Idle", 0.4)


## Framing anchor for the championship tableau (throne + dragon + dais). The
## tableau camera sits at this point + its offset and LOOKS AT this point, so
## the anchor is the frame's centre.
##
## Raised 2026-08-09. At +2.2 the frame centred on the throne's back and the
## dragon was simply off the top — the old chibi showed a strip of wing, the
## serpent-wyrm shows two feet. The wyrm spans DRAGON_HOVER.y (4.04, its feet
## — the root is ON THE GROUND now) up to ~7.6, and the champion stands at
## FLOOR_Y; +3.4 is the centre that holds BOTH, checked on the rendered
## showcase frame, not computed and hoped for.
func throne_focus() -> Vector3:
	return THRONE_POS + Vector3(0.0, 3.4, 0.0)


## Where the champion stands: on the hall floor at the foot of the throne,
## a step to the side so the blade fan stays unobstructed in the tableau.
func throne_dais() -> Vector3:
	return Vector3(0.55, FLOOR_Y, 9.6)


## Perch anchor for the DragonSpectator module: high above the far wall,
## above the default camera's frame (pitch -0.85 keeps it out of shot) but
## in view the moment the player orbits up. Wall top sits at FLOOR_Y + 4.
## The serpent-wyrm's root is ON THE GROUND between its feet, so the root
## rides 1.15 × spectator scale (1.15) higher than the old mid-air-root rig
## did — 5.0 + 1.3225 — and the body still reads at the same y 7.11.
func spectator_perch() -> Vector3:
	return Vector3(0.0, FLOOR_Y + 6.3225, WALL_HALF - 0.8)


func _build_fill_lights() -> void:
	## Readability pass, part 2 (part 1 is the Environment in game.tscn).
	## Cool fill from the camera side lifts House Frost's back rank; a rim
	## from beyond the far wall silhouettes House Ember against the dark.
	## Both shadowless — the Sun stays the only shadow caster.
	##
	## ISSUES.md #15: the FAR army reads as mud because it faces the camera
	## (-Z) while the Sun rakes from the near-left and the torches are wall
	## fixtures. CoolFill is the only light that hits a far fighter's FACE,
	## and at 0.24 it barely did — more than doubled. Adding a light is not
	## an option (the Mobile renderer's 8-omni budget is full with the hall
	## torches), so the two existing fill directionals carry it.
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFill"
	fill.light_color = Color(0.6, 0.68, 0.86)
	fill.light_energy = 0.5
	fill.basis = Basis.looking_at(Vector3(-0.45, -0.7, 0.55).normalized())
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(0.7, 0.75, 0.9)
	rim.light_energy = 0.55
	rim.basis = Basis.looking_at(Vector3(0.1, -0.5, -1.0).normalized())
	add_child(rim)


# -- fps probe -------------------------------------------------------------


func _process(delta: float) -> void:
	if not _fps_probe:
		return
	_fps_accum += delta
	if _fps_accum >= 1.0:
		_fps_accum -= 1.0
		_fps_seconds += 1
		print("ENV_FPS second=%d fps=%.1f" % [_fps_seconds, Performance.get_monitor(Performance.TIME_FPS)])
		if _fps_seconds >= 10:
			get_tree().quit(0)
