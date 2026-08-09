class_name GreatHall
extends Node3D
## Builds the torch-lit great hall around the chess board: stone floor and
## perimeter walls (MultiMesh — 1 draw call each), corner pillars, two feast
## tables, eight flickering torches (src/env/torch.gd), NINE wall banners
## (src/env/banner.gd) awaiting the Great Houses' colors, and the Throne of
## Blades (custom prop) against the far wall. `summon_champion_dragon()` /
## `dragon_wink()` stage the championship dragon above it — no extra lights.
##
## Everything is KayKit Dungeon Remastered (CC0), copied with its license to
## res://assets/kaykit-dungeon/. Board center is world origin; the hall
## floor top sits at y = -0.3 (the board plinth rests on it).
##
## Integrator API (banners):
##   dress_for_match(player, rival)         THE DRESSING — colours AND sigils
##   dress_for_champion(house)              the throne shot: the hall falls
##   get_banner(i) -> HallBanner            i = 0..8
##   set_banner_colors(colors)              dyes banners 0..n in index order
##                                          (colour only — sigils stay put)
##   banners                                the Array[HallBanner] itself
## Banner index map (world positions, camera default looks toward +Z):
##   0,1,2  far wall   (z=+12) at x = -4, 0, +4   (2 is screen-left)
##   3,4,5  west wall  (x=-12) at z = -4, 0, +4   (screen-right side)
##   6,7,8  east wall  (x=+12) at z = -4, 0, +4   (screen-left side)
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
## FPS probe (env verification, no game-code hooks): launch with user arg
## "--env-fps" to print one "ENV_FPS second=<n> fps=<v>" line per second for
## 10 s, then quit. Dormant otherwise.

const WALL_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/wall.gltf")
const FLOOR_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/floor_tile_large.gltf")
const PILLAR_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/pillar.gltf")
const TABLE_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/table_long.gltf")
const CANDLE_SCENE: PackedScene = preload("res://assets/kaykit-dungeon/candle_triple.gltf")
const THRONE_SCENE: PackedScene = preload("res://assets/custom-props/throne.glb")

const TorchScript := preload("res://src/env/torch.gd")
const BannerScript := preload("res://src/env/banner.gd")
## Shared dragon controller (loader + clips + emissive lift) — the single
## owner of the dragon.glb staging since the spectator/ashfall module.
const DragonRigScript := preload("res://src/cinematics/dragon_rig.gd")

const FLOOR_Y := -0.3         # hall floor top (plinth bottom)
const WALL_HALF := 12.0       # wall centerline distance from board center
const SEGMENT_XS := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]  # 6 x 4u = 24u side

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

var banners: Array[HallBanner] = []
var throne: Node3D = null
var dragon: Node3D = null              # summoned for the championship only
var _dragon_anim: AnimationPlayer = null

var _fps_probe := false
var _fps_accum := 0.0
var _fps_seconds := 0


func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_pillars()
	_build_tables()
	_build_torches()
	_build_banners()
	_build_throne()
	_build_fill_lights()
	_dress_from_session()
	var args := OS.get_cmdline_user_args()
	if args.has("--env-fps"):
		_fps_probe = true
		print("ENV_FPS probe armed — 10 one-second samples then quit")
	if args.has("--env-banner-test"):
		# Nine original Great House colors (wolf/lion/stag/dragon/kraken/
		# rose/sun/falcon/trout archetypes) — proves per-banner recolor.
		set_banner_colors([
			Color(0.75, 0.78, 0.82),  # House Winterhowl — grey wolf
			Color(0.72, 0.15, 0.12),  # House Goldmane — crimson lion
			Color(0.85, 0.65, 0.1),   # House Hartcrown — golden stag
			Color(0.38, 0.08, 0.1),   # House Ashwing — dragon oxblood
			Color(0.1, 0.34, 0.3),    # House Deepgrasp — kraken sea-green
			Color(0.32, 0.5, 0.2),    # House Thornrose — rose green
			Color(0.9, 0.45, 0.1),    # House Dawnspear — burning sun
			Color(0.35, 0.55, 0.8),   # House Skyperch — falcon sky
			Color(0.5, 0.55, 0.65),   # House Silverleap — trout silver
		])


# -- integrator hooks ------------------------------------------------------


func get_banner(i: int) -> HallBanner:
	return banners[i] if i >= 0 and i < banners.size() else null


func set_banner_colors(colors: Array) -> void:
	## Dye banners 0..n-1 in index order (see the map in the header). COLOUR
	## ONLY — whichever house each banner flies (its sigil) is untouched, so
	## an integrator re-dye can never leave a lion's sigil on a wolf's wall.
	for i in mini(colors.size(), banners.size()):
		banners[i].set_house_color(colors[i])


## THE DRESSING. Hang the nine banners for the match actually being played:
## the player's house on the west wall plus the two far-wall stations it
## faces, the rival's on the east wall plus the far-wall station opposite.
## Each banner flies its house's SIGIL over its house's cloth.
##
## Which of a house's three heraldic colours each station flies is deliberate:
## stations 3 and 6 (the wall centres the e2e board-truth asserts read) fly
## the PRIMARY exactly, and the rest alternate through secondary/accent so a
## near-black primary (Hartcrown #1d1a17, Ashwyrm #171214) never leaves a
## whole wall invisible in a torch-lit room.
func dress_for_match(player_house: String, rival_house: String) -> void:
	if player_house.is_empty() or banners.is_empty():
		return
	var rival := rival_house if not rival_house.is_empty() else player_house
	var pc := HouseRegistry.get_colors(player_house)
	var rc := HouseRegistry.get_colors(rival)
	var plan := [
		[player_house, pc["primary"]],   # 0 far wall, player's flank
		[player_house, pc["accent"]],    # 1 far wall centre
		[rival, rc["primary"]],          # 2 far wall, rival's flank
		[player_house, pc["primary"]],   # 3 west wall — the player's
		[player_house, pc["secondary"]], # 4
		[player_house, pc["accent"]],    # 5
		[rival, rc["primary"]],          # 6 east wall — the rival's
		[rival, rc["secondary"]],        # 7
		[rival, rc["accent"]],           # 8
	]
	for i in mini(plan.size(), banners.size()):
		banners[i].set_house(str(plan[i][0]), plan[i][1] as Color)


## THE THRONE SHOT: every banner in the hall falls to the champion — the
## whole room, sigils included, becomes one house. Alternates primary/accent
## so nine identical rectangles do not read as wallpaper.
func dress_for_champion(house: String) -> void:
	if house.is_empty() or banners.is_empty():
		return
	var c := HouseRegistry.get_colors(house)
	for i in banners.size():
		banners[i].set_house(house, (c["primary"] if i % 2 == 0 else c["accent"]) as Color)


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


func _multimesh_node(node_name: String, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
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
	## corners so the perimeter reads sealed from every orbit angle.
	var xforms: Array[Transform3D] = []
	for x in SEGMENT_XS:
		xforms.append(Transform3D(Basis(), Vector3(x, FLOOR_Y, -WALL_HALF)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(x, FLOOR_Y, WALL_HALF)))
	for z in SEGMENT_XS:
		xforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-WALL_HALF, FLOOR_Y, z)))
		xforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(WALL_HALF, FLOOR_Y, z)))
	_multimesh_node("Walls", _tinted_mesh(_extract_mesh(WALL_SCENE), Color(0.58, 0.56, 0.62)), xforms)


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
	## Nine stations for the nine Great Houses — see the index map up top.
	var specs := [
		[Vector3(-4.0, FLOOR_Y, WALL_HALF), PI],        # 0 far wall
		[Vector3(0.0, FLOOR_Y, WALL_HALF), PI],         # 1 far wall center
		[Vector3(4.0, FLOOR_Y, WALL_HALF), PI],         # 2 far wall
		[Vector3(-WALL_HALF, FLOOR_Y, -4.0), PI * 0.5],  # 3 west
		[Vector3(-WALL_HALF, FLOOR_Y, 0.0), PI * 0.5],   # 4 west
		[Vector3(-WALL_HALF, FLOOR_Y, 4.0), PI * 0.5],   # 5 west
		[Vector3(WALL_HALF, FLOOR_Y, -4.0), -PI * 0.5],  # 6 east
		[Vector3(WALL_HALF, FLOOR_Y, 0.0), -PI * 0.5],   # 7 east
		[Vector3(WALL_HALF, FLOOR_Y, 4.0), -PI * 0.5],   # 8 east
	]
	for i in specs.size():
		var banner: HallBanner = BannerScript.new()
		banner.name = "Banner%d" % i
		banner.position = specs[i][0]
		banner.rotation.y = specs[i][1]
		add_child(banner)
		banners.append(banner)


func _build_throne() -> void:
	## The Throne of Blades stands against the far wall, seat opening turned
	## toward the board (the GLB front faces +Z as imported — rotate PI).
	## NO new lights: the 8-omni budget is full; the south-wall torch pair
	## (±8, z=11.48) already rakes the blade fan.
	throne = THRONE_SCENE.instantiate()
	throne.name = "ThroneOfBlades"
	throne.position = THRONE_POS
	throne.rotation.y = PI
	add_child(throne)


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
