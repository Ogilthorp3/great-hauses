extends Node3D
## TRIAL BY FIRE — everything you can SEE on the board, and nothing you can
## reason about. It owns no rules: it is handed cells and event dictionaries by
## trial_by_fire.gd and turns them into geometry.
##
## GREEN, BECAUSE IT IS NOT DRAGONFIRE. The wyrm's breath in this game is the
## dracarys kit's orange-to-white torrent, and the kings' jars must not be
## mistaken for it — one is the clock and the other is the weapon. So the jars
## burn WILDFIRE: an alchemical green that exists nowhere else in the hall, sits
## on the opposite side of the wheel from every torch, banner and haus in the
## game, and reads instantly against the grey stone the arena is made of.
##
## NO Light3D. NOT ONE. The hall's eight omnis are the eight torches and the
## suites count them, so the fire sells its light the way dracarys.gd and
## piece_view.gd already do: HDR emissive, unshaded, additive geometry, plus the
## WorldEnvironment's glow doing the bleed. An additive quad lying ON the stone
## does most of the work — firelight is mostly what it lands on.
##
## THE FLAME IS THREE LAYERS PER TILE, and it needs all three:
##   1. the POOL   — an additive disc on the tile face, the thing that actually
##                   makes the stone look lit
##   2. the COLUMN — a short upward burst of billboards, so the fire has volume
##                   from the low camera instead of being a decal
##   3. the CORE   — a small white-green hot spot, because a flame without a
##                   clipped centre reads as gel, not fire
## A single flat quad was tried first and read exactly like the "bare opaque
## square" a critic caught in this project's weapon trail: a shape, not a fire.

const RigScript := preload("res://src/cinematics/dragon_rig.gd")

## WILDFIRE. HDR on purpose — these go through tonemapping and glow, so the
## core is meant to clip and the pool is not.
## THE RED AND BLUE CHANNELS ARE THE WHOLE PROBLEM. First cut had the core at
## (1.55, 2.80, 1.70) — "white-green", by analogy with the way real flame has a
## white heart. Additive geometry over pale stone, through a filmic tonemap and
## a 0.62 glow, drove all three channels past 1.0 and the photographs came back
## with a WHITE blob on the board: at that point the fire was not green, it was
## a lamp. Green survives only if red and blue stay low in ABSOLUTE terms, so
## the heat is spent almost entirely on one channel. The core still clips —
## flame should — but it clips green.
## Trimmed AGAIN after the second re-shoot, and the arithmetic is the argument:
## the board's light stone sits near 0.5, these are ADDED to it, and anything
## that lands a channel over 1.0 gets clipped by the tonemap. With r at 0.50
## there was only 0.5 of headroom, the core cleared it, and the photograph came
## back with a white slab on a green smear. Keeping r and b down here means the
## brightest thing on the board can only clip toward GREEN.
const WILD_CORE := Color(0.22, 2.10, 0.42)    ## the hot heart
const WILD_BODY := Color(0.08, 1.45, 0.26)    ## the flame proper
const WILD_DEEP := Color(0.01, 0.55, 0.12)    ## the cooling edge
const WILD_SMOKE := Color(0.09, 0.16, 0.11)   ## acrid green-grey
## The jar itself: fired clay with a live glass belly.
const CLAY_DARK := Color(0.17, 0.145, 0.125)
const CLAY_RIM := Color(0.26, 0.22, 0.18)

const BOON_TINT := {
	1: Color(1.0, 0.42, 0.12),    # DRAUGHT — Ashwyrm's fire
	2: Color(0.42, 0.78, 1.0),    # CACHE   — alchemist's glass
	3: Color(1.0, 0.86, 0.30),    # SPURS   — Swiftcrest gold
}

## How many particle columns exist at once. A full chain can light a dozen tiles
## in a quarter second; beyond this the extra emitters buy nothing a human eye
## can find, and each one is 18 billboards.
const COLUMN_POOL := 22

var tile_size := 1.0
var tile_top := 0.22

var _pool_quads: Array[MeshInstance3D] = []    ## one ground pool per cell
var _pool_mats: Array[StandardMaterial3D] = []
var _pool_life: PackedFloat32Array = PackedFloat32Array()
var _pool_full: PackedFloat32Array = PackedFloat32Array()
var _columns: Array[GPUParticles3D] = []
var _column_next := 0
var _kegs := {}        ## cell index -> jar Node3D
var _boons := {}       ## cell index -> boon Node3D
var _stones := {}      ## cell index -> block Node3D
var _t := 0.0

var _pool_mesh: PlaneMesh
var _pool_tex: ImageTexture
var _core_tex: ImageTexture


func build(cells: int, size: float, top: float) -> void:
	tile_size = size
	tile_top = top
	_pool_tex = _fire_pool_texture()
	_core_tex = _hot_core_texture()
	_pool_mesh = PlaneMesh.new()
	_pool_mesh.size = Vector2(tile_size * 1.28, tile_size * 1.28)
	_pool_life.resize(cells)
	_pool_full.resize(cells)
	var pools := Node3D.new()
	pools.name = "FirePools"
	add_child(pools)
	for i in cells:
		var mi := MeshInstance3D.new()
		mi.name = "Pool%d" % i
		mi.mesh = _pool_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = _pool_tex
		m.albedo_color = WILD_BODY
		m.disable_receive_shadows = true
		m.disable_ambient_light = true
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.material_override = m
		mi.visible = false
		pools.add_child(mi)
		_pool_quads.append(mi)
		_pool_mats.append(m)
	var cols := Node3D.new()
	cols.name = "FireColumns"
	add_child(cols)
	for i in COLUMN_POOL:
		var p := RigScript.spawn_emitter(cols, "Column%d" % i, {
			"amount": 24, "lifetime": 0.62, "size": 0.55,
			"velocity": Vector2(2.6, 5.4), "spread": 22.0,
			"direction": Vector3(0.0, 1.0, 0.0),
			"gravity": Vector3(0.0, -1.4, 0.0), "grow": 2.4,
			"ramp": [
				[0.0, Color(WILD_CORE.r, WILD_CORE.g, WILD_CORE.b, 1.0)],
				[0.28, Color(WILD_BODY.r, WILD_BODY.g, WILD_BODY.b, 0.95)],
				[0.68, Color(WILD_DEEP.r, WILD_DEEP.g, WILD_DEEP.b, 0.5)],
				[1.0, Color(WILD_SMOKE.r, WILD_SMOKE.g, WILD_SMOKE.b, 0.0)],
			],
			"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 1.1,
		})
		p.one_shot = true
		p.explosiveness = 0.82
		p.visible = false
		_wildfire(p)
		_columns.append(p)


## DragonRig.spawn_emitter HARD-CODES ITS EMISSION COLOUR to Color(1.0, 0.45,
## 0.12) — dragon-orange, because every effect it was written for is the
## wyrm's. It is the right default for that lane and it quietly poisoned this
## one: the wildfire columns were being ADDED to in orange at energy 1.5, which
## is exactly why the first two rounds of photographs came back with a white-hot
## plume over a green pool and no amount of retuning the colour RAMP fixed it —
## the ramp was never the thing glowing. The factory is another lane's file and
## stays untouched; the material it hands back is ours to repaint.
static func _wildfire(p: GPUParticles3D, tint: Color = WILD_BODY) -> void:
	var quad := p.draw_pass_1 as QuadMesh
	if quad == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat != null and mat.emission_enabled:
		mat.emission = tint


# ── the fire ────────────────────────────────────────────────────────────────


## A tile just caught. `full` is how long the grid says it will burn — the pool
## is driven off that so the picture and the rules cannot drift.
func light(idx: int, world: Vector3, full: float) -> void:
	if idx < 0 or idx >= _pool_quads.size():
		return
	_pool_life[idx] = full
	_pool_full[idx] = maxf(full, 0.05)
	var q := _pool_quads[idx]
	q.position = Vector3(world.x, tile_top + 0.018, world.z)
	q.visible = true
	var col := _columns[_column_next]
	_column_next = (_column_next + 1) % _columns.size()
	col.position = Vector3(world.x, tile_top + 0.05, world.z)
	col.visible = true
	col.restart()
	col.emitting = true


## THE IGNITION, at the jar's own tile: a bright ground ring that snaps outward.
## Distinct from the tiles the arms light, because a player has to be able to
## read WHERE a chain started at a glance.
func ignite(world: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(tile_size * 0.9, tile_size * 0.9)
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _core_tex
	# NOT WILD_CORE: additive over pale stone, the core texel already clips, and
	# clipping from WILD_CORE lands on white. The ignition is the one thing that
	# must never be mistaken for the dragon's fire.
	m.albedo_color = Color(WILD_BODY.r, WILD_BODY.g * 1.15, WILD_BODY.b)
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring.material_override = m
	ring.position = Vector3(world.x, tile_top + 0.03, world.z)
	add_child(ring)
	var grow := create_tween()
	grow.set_parallel(true)
	grow.tween_property(ring, "scale", Vector3(2.1, 1.0, 2.1), 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	grow.tween_property(m, "albedo_color", Color(WILD_DEEP.r, WILD_DEEP.g,
		WILD_DEEP.b, 0.0), 0.30)
	grow.chain().tween_callback(ring.queue_free)


func _process(delta: float) -> void:
	_t += delta
	for i in _pool_life.size():
		if _pool_life[i] <= 0.0:
			continue
		_pool_life[i] -= delta
		var q := _pool_quads[i]
		if _pool_life[i] <= 0.0:
			q.visible = false
			continue
		# u runs 1 -> 0 over the tile's burn. The pool flares WIDE and bright on
		# the first sixth and then sinks; a flame that fades linearly from full
		# looks like a dimmer switch, not a fire going out.
		var u: float = _pool_life[i] / _pool_full[i]
		var flare: float = clampf((1.0 - u) / 0.10, 0.0, 1.0)
		# It arrives at nearly full width on the FIRST frame (0.88) and punches
		# a little past the tile at the peak. It never grows from a dot: the
		# whole job of this layer is to say "this square is lethal NOW", and a
		# blossoming circle says it a third of a second late.
		var s: float = lerpf(0.88, 1.14, flare) * lerpf(0.78, 1.0, u)
		# a fast flicker, offset per tile so the field does not pulse as one
		s *= 1.0 + 0.09 * sin(_t * 26.0 + float(i) * 1.7)
		q.scale = Vector3(s, 1.0, s)
		var c: Color = WILD_CORE.lerp(WILD_DEEP, 1.0 - u)
		_pool_mats[i].albedo_color = Color(c.r, c.g, c.b, clampf(u * 1.5, 0.0, 0.84))
	for kidx in _kegs:
		var jar: Node3D = _kegs[kidx]
		if is_instance_valid(jar) and jar.has_method("tick_fuse"):
			jar.tick_fuse(delta)
	for bidx in _boons:
		var b: Node3D = _boons[bidx]
		if is_instance_valid(b):
			b.rotation.y += delta * 1.1
			b.position.y = tile_top + 0.30 + sin(_t * 2.2 + float(bidx)) * 0.055


# ── the furniture ───────────────────────────────────────────────────────────


## Indestructible blackstone. Deliberately LOW (0.46 of a tile): the arena is
## read from a raked camera and a full-height pillar would hide the very king
## the player is hunting. It is the board's own plinth stone, so it belongs to
## the hall rather than being dropped into it.
func add_stone(idx: int, world: Vector3, base: Color) -> void:
	var root := Node3D.new()
	root.name = "Blackstone%d" % idx
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size * 0.9, 0.46, tile_size * 0.9)
	block.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = base.lightened(0.10)
	m.roughness = 0.95
	block.mesh.material = m
	block.position = Vector3(0.0, 0.23, 0.0)
	root.add_child(block)
	# A lighter cap, so the top face separates from the side under the raked
	# key light instead of the whole block reading as one dark lump.
	var cap := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(tile_size * 0.78, 0.06, tile_size * 0.78)
	cap.mesh = cmesh
	var cm := StandardMaterial3D.new()
	cm.albedo_color = base.lightened(0.28)
	cm.roughness = 0.9
	cap.mesh.material = cm
	cap.position = Vector3(0.0, 0.47, 0.0)
	root.add_child(cap)
	root.position = Vector3(world.x, tile_top, world.z)
	add_child(root)
	_stones[idx] = root


func has_stone(idx: int) -> bool:
	return _stones.has(idx) and is_instance_valid(_stones[idx])


func stone_indices() -> Array:
	return _stones.keys()


## HOW FAR A PLINTH HAS COME OUT OF ITS SQUARE — 0 is buried inside the board,
## 1 is seated. Only the transmutation drives this; every other caller gets a
## seated block because `add_stone` builds it seated.
##
## The sink has to clear the whole block (0.46 + a 0.06 cap) or the transmutation
## opens on eight rows of black caps already sitting proud of the chessboard,
## which is the one thing the beat exists to hide.
const STONE_SINK := 0.62


func set_stone_rise(idx: int, u: float) -> void:
	if not has_stone(idx):
		return
	var root: Node3D = _stones[idx]
	root.position.y = tile_top - STONE_SINK * (1.0 - clampf(u, 0.0, 1.0))


## Grit thrown out of a square — the plinth breaking the surface, or a bannerman
## planting his feet.
##
## MIX-BLENDED AND UNLIT, alone among this file's effects. Everything else here
## is additive wildfire because it IS fire; dust that glows is a boon, and the
## one thing the transmutation must not say is "something magical happened to
## this square" when what happened is that a slab of rock came up through it.
func plant_dust(world: Vector3, power := 1.0) -> void:
	var p := RigScript.spawn_emitter(self, "PlantDust", {
		"amount": maxi(6, int(14.0 * power)), "lifetime": 0.9,
		"size": 0.30 * tile_size, "velocity": Vector2(0.5, 1.9 * power),
		"spread": 68.0, "direction": Vector3(0.0, 1.0, 0.0),
		"gravity": Vector3(0.0, -2.4, 0.0), "grow": 2.8,
		"emission_radius": tile_size * 0.34,
		"ramp": [
			[0.0, Color(0.40, 0.38, 0.35, 0.62)],
			[0.45, Color(0.29, 0.28, 0.25, 0.38)],
			[1.0, Color(0.18, 0.17, 0.15, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "emission_energy": 0.0,
	})
	p.position = Vector3(world.x, tile_top + 0.04, world.z)
	p.one_shot = true
	p.explosiveness = 0.88
	p.emitting = true
	# ignore_time_scale: the transmutation bends the clock, and a puff of dust
	# that outlives the beat that threw it is litter on the arena floor.
	get_tree().create_timer(1.8, true, false, true).timeout.connect(
		func() -> void:
			if is_instance_valid(p):
				p.queue_free())


# ── the wildfire jar ────────────────────────────────────────────────────────


## A squat clay jar with a glass belly full of green fire. The belly's pulse
## RATE is the fuse — it starts as a slow breath and ends as a stutter, which is
## the only warning a player gets and therefore has to be readable across the
## board without a number attached to it.
func add_keg(idx: int, world: Vector3, fuse: float) -> void:
	var jar := KegJar.new()
	jar.name = "Jar%d" % idx
	add_child(jar)
	jar.setup(fuse, tile_size)
	jar.position = Vector3(world.x, tile_top, world.z)
	_kegs[idx] = jar


func drop_keg(idx: int) -> void:
	if _kegs.has(idx):
		var jar = _kegs[idx]
		if is_instance_valid(jar):
			jar.queue_free()
		_kegs.erase(idx)


class KegJar:
	extends Node3D
	var _glass: StandardMaterial3D
	var _fuse := 2.0
	var _left := 2.0
	var _phase := 0.0

	func setup(fuse: float, tile: float) -> void:
		_fuse = maxf(fuse, 0.1)
		_left = _fuse
		var body := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = tile * 0.33
		bm.height = tile * 0.54
		body.mesh = bm
		var clay := StandardMaterial3D.new()
		clay.albedo_color = ArenaFxColors.CLAY
		clay.roughness = 0.88
		body.mesh.material = clay
		body.position = Vector3(0.0, tile * 0.22, 0.0)
		add_child(body)
		# the glass band: the live half of the jar
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = tile * 0.24
		tm.outer_radius = tile * 0.36
		band.mesh = tm
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.06, 0.30, 0.12)
		_glass.emission_enabled = true
		_glass.emission = ArenaFxColors.WILD
		_glass.emission_energy_multiplier = 2.2
		_glass.roughness = 0.3
		band.mesh.material = _glass
		band.position = Vector3(0.0, tile * 0.22, 0.0)
		add_child(band)
		var neck := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = tile * 0.075
		nm.bottom_radius = tile * 0.12
		nm.height = tile * 0.16
		neck.mesh = nm
		var rim := StandardMaterial3D.new()
		rim.albedo_color = ArenaFxColors.RIM
		rim.roughness = 0.85
		neck.mesh.material = rim
		neck.position = Vector3(0.0, tile * 0.48, 0.0)
		add_child(neck)
		var wisp := preload("res://src/cinematics/dragon_rig.gd").spawn_emitter(
			self, "FuseWisp", {
				"amount": 10, "lifetime": 0.9, "size": 0.11,
				"velocity": Vector2(0.5, 1.1), "spread": 14.0,
				"direction": Vector3(0.0, 1.0, 0.0),
				"gravity": Vector3(0.0, 0.4, 0.0), "grow": 1.5,
				"ramp": [
					[0.0, Color(0.6, 2.0, 0.8, 0.9)],
					[0.5, Color(0.1, 0.9, 0.3, 0.5)],
					[1.0, Color(0.08, 0.14, 0.1, 0.0)],
				],
				"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 1.8,
			})
		wisp.position = Vector3(0.0, tile * 0.58, 0.0)
		ArenaFxColors.repaint(wisp, ArenaFxColors.WILD)
		wisp.emitting = true

	func tick_fuse(delta: float) -> void:
		_left = maxf(_left - delta, 0.0)
		var urgency: float = 1.0 - _left / _fuse          # 0 -> 1
		# 1.6 Hz at rest, 11 Hz at the end. The exponent is what makes the last
		# half-second feel like a countdown rather than a metronome.
		_phase += delta * (1.6 + 9.4 * pow(urgency, 2.2)) * TAU
		var beat: float = 0.5 + 0.5 * sin(_phase)
		if _glass != null:
			_glass.emission_energy_multiplier = 1.2 + (2.4 + 6.5 * urgency) * beat
		var swell: float = 1.0 + 0.07 * beat * (0.4 + urgency)
		scale = Vector3(swell, 1.0 / swell, swell)   # it strains, it does not grow


class ArenaFxColors:
	## Constants (and the one helper) an inner class cannot reach through the
	## outer script.
	const CLAY := Color(0.17, 0.145, 0.125)
	const RIM := Color(0.26, 0.22, 0.18)
	const WILD := Color(0.10, 1.60, 0.30)

	## See ArenaFx._wildfire — spawn_emitter's emission is dragon-orange.
	static func repaint(p: GPUParticles3D, tint: Color) -> void:
		var quad := p.draw_pass_1 as QuadMesh
		if quad == null:
			return
		var mat := quad.material as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			mat.emission = tint


# ── boons ───────────────────────────────────────────────────────────────────


## A boon on the stone: a slowly turning rune plate, hovering a hand above the
## square. Emissive in its own colour so a player can tell across the board
## whether that flicker is worth walking into a corridor for.
func add_boon(idx: int, world: Vector3, kind: int) -> void:
	drop_boon(idx)
	var tint: Color = BOON_TINT.get(kind, Color.WHITE)
	var root := Node3D.new()
	root.name = "Boon%d" % idx
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size * 0.42, 0.07, tile_size * 0.42)
	plate.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = tint.darkened(0.55)
	m.emission_enabled = true
	m.emission = Color(tint.r * 1.7, tint.g * 1.7, tint.b * 1.7)
	m.emission_energy_multiplier = 1.7
	m.roughness = 0.5
	plate.mesh.material = m
	plate.rotation.x = 0.42
	root.add_child(plate)
	var halo := MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(tile_size * 1.1, tile_size * 1.1)
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_texture = _pool_tex
	hmat.albedo_color = Color(tint.r, tint.g, tint.b, 0.5)
	hmat.disable_receive_shadows = true
	hmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	halo.mesh.material = hmat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0.0, -0.26, 0.0)
	root.add_child(halo)
	root.position = Vector3(world.x, tile_top + 0.30, world.z)
	add_child(root)
	_boons[idx] = root


func drop_boon(idx: int) -> void:
	if _boons.has(idx):
		var b = _boons[idx]
		if is_instance_valid(b):
			b.queue_free()
		_boons.erase(idx)


## The boon a king picked up: it snaps up and out rather than blinking off, so
## the player sees WHICH tile paid him.
func claim_boon(idx: int, world: Vector3, kind: int) -> void:
	drop_boon(idx)
	var tint: Color = BOON_TINT.get(kind, Color.WHITE)
	var spark := RigScript.spawn_emitter(self, "BoonSpark", {
		"amount": 16, "lifetime": 0.6, "size": 0.16,
		"velocity": Vector2(1.4, 2.8), "spread": 40.0,
		"direction": Vector3(0.0, 1.0, 0.0),
		"gravity": Vector3(0.0, -1.0, 0.0), "grow": 0.8,
		"ramp": [
			[0.0, Color(tint.r * 2.0, tint.g * 2.0, tint.b * 2.0, 1.0)],
			[1.0, Color(tint.r, tint.g, tint.b, 0.0)],
		],
		"blend": BaseMaterial3D.BLEND_MODE_ADD, "emission_energy": 2.2,
	})
	spark.position = Vector3(world.x, tile_top + 0.3, world.z)
	spark.one_shot = true
	spark.explosiveness = 0.95
	_wildfire(spark, Color(tint.r * 1.3, tint.g * 1.3, tint.b * 1.3))
	spark.emitting = true
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if is_instance_valid(spark):
			spark.queue_free())


# ── procedural art ──────────────────────────────────────────────────────────


const TEX := 96


static func _tex_from(alphas: PackedFloat32Array) -> ImageTexture:
	var img := Image.create(TEX, TEX, true, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0,
				clampf(alphas[y * TEX + x], 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## THE FLAME IS THE SHAPE OF ITS TILE. This started as a soft radial gradient,
## which is the obvious way to draw fire on a floor and is wrong for this genre:
## photographed, it read as a green SPOTLIGHT sitting on the board, and a player
## could not tell which squares were lethal — which is the only question the
## flame layer exists to answer. In this family of games the fire occupies exact
## squares, and it has to LOOK like it does.
##
## So the body is a superellipse (p-norm 4.2) that fills most of the tile with a
## near-flat top and falls off hard at the edge — the same p-norm trick
## board_view.gd's selection frame uses, for the same reason. The ragged bit is
## kept, as a small angular chew on the falloff radius only: enough that the
## edge is fire and not a decal, never enough to lose the square.
static func _fire_pool_texture() -> ImageTexture:
	var a := PackedFloat32Array()
	a.resize(TEX * TEX)
	for y in TEX:
		for x in TEX:
			var u := absf((float(x) + 0.5) / TEX - 0.5) * 2.0
			var v := absf((float(y) + 0.5) / TEX - 0.5) * 2.0
			var m: float = pow(pow(u, 4.2) + pow(v, 4.2), 1.0 / 4.2)
			var th: float = atan2((float(y) + 0.5) / TEX - 0.5,
				(float(x) + 0.5) / TEX - 0.5)
			var chew: float = 1.0 + 0.07 * sin(th * 6.0) + 0.05 * sin(th * 11.0 + 1.3)
			var e: float = m / maxf(chew * 0.86, 0.01)
			# A bright interior that does NOT reach 1.0, and a small hot heart.
			# Both matter: an interior at full alpha is a slab of paint, and a
			# heart covering most of the tile is the same slab with a name.
			var body: float = (1.0 - smoothstep(0.70, 1.04, e)) * 0.72
			var heart: float = (1.0 - smoothstep(0.0, 0.30, e)) * 0.22
			a[y * TEX + x] = clampf(body + heart, 0.0, 1.0)
	return _tex_from(a)


## The core: a tight hot spot with a thin shock ring, for the ignition frame.
static func _hot_core_texture() -> ImageTexture:
	var a := PackedFloat32Array()
	a.resize(TEX * TEX)
	for y in TEX:
		for x in TEX:
			var u := (float(x) + 0.5) / TEX - 0.5
			var v := (float(y) + 0.5) / TEX - 0.5
			var r: float = sqrt(u * u + v * v) * 2.0
			var core: float = pow(clampf(1.0 - r / 0.42, 0.0, 1.0), 1.4)
			var ring: float = exp(-pow((r - 0.80) / 0.10, 2.0)) * 0.85
			a[y * TEX + x] = maxf(core, ring)
	return _tex_from(a)
