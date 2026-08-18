extends SceneTree
## Headless suite for the Sanctum Cathedral shell (rebuilt 2026-08-17).
##
## Contract under test:
##  * the GLB exists and instantiates under GreatHall;
##  * the shell casts NO shadows (the Sun must reach the board exactly as it
##    did before the cathedral existed) and every mesh carries layer 10, the
##    channel the fly-in's cull-masked WyrmGlow paints;
##  * the Wyrm's Gallery anchor sits above the hall's 11.7 wall crest with a
##    clear sightline to the board over that crest (the perch the fly-in
##    lands on and the spectator's vigil rest);
##  * the ambient patrol dragon is GONE — one wyrm, the spectator;
##  * the hall's 22 banner stations survive the rebuild untouched.

var passed := 0
var failed := 0


func _initialize() -> void:
	_main()


func _main() -> void:
	print("\n=== Great Hauses Chess — Sanctum Cathedral Suite ===")
	_test_cathedral_model_exists()
	await _test_great_hall_cathedral()
	_test_flight_path()
	_test_flight_smoothness()
	_test_dragon_door()
	_test_coronas()
	await _test_coronas_actually_swing()
	print("---")
	if failed == 0:
		print("CATHEDRAL OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("CATHEDRAL FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s" % desc)
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_cathedral_model_exists() -> void:
	var path := "res://assets/environment/sanctum_cathedral.glb"
	check("cathedral: glb asset exists", true, ResourceLoader.exists(path))


func _test_great_hall_cathedral() -> void:
	var hall_script := load("res://src/env/great_hall.gd")
	var hall = hall_script.new()
	root.add_child(hall)
	await process_frame

	check("hall: cathedral instance created", true, hall.cathedral_instance != null)
	check("hall: ambient patrol dragon retired", false,
		hall.get("cathedral_dragon") != null)
	check("hall: 22 banner stations preserved", 22, hall.banners.size())

	var meshes: Array = []
	if hall.cathedral_instance != null:
		meshes = hall.cathedral_instance.find_children(
			"*", "MeshInstance3D", true, false)
	check("cathedral: shell has meshes", true, meshes.size() >= 10)
	var all_shadowless := true
	var all_layer10 := true
	for mi in meshes:
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			all_shadowless = false
		if (mi.layers & (1 << 9)) == 0:
			all_layer10 = false
	check("cathedral: casts no shadows (Sun reaches the board)", true,
		all_shadowless)
	check("cathedral: meshes carry layer 10 (WyrmGlow channel)", true,
		all_layer10)

	# The gallery anchor: above the hall wall crest (11.7), behind the far
	# wall plane (z > 12), and the board-to-perch sightline clears the crest.
	var g: Vector3 = hall.wyrm_gallery_rest()
	check("gallery: above the wall crest", true, g.y > 11.7)
	check("gallery: behind the far wall", true, g.z > 12.0)
	var body := g + Vector3.UP * 1.5   # the wyrm's mass centre on the ledge
	var crest_y: float = body.y * (12.0 / body.z)
	check("gallery: sightline to the board clears the crest", true,
		crest_y > 11.7)

	hall.queue_free()


## THE FLIGHT PATH IS GEOMETRY, AND GEOMETRY CAN BE CHECKED.
##
## Both faults Bert caught on 2026-08-18 were measurable before they were
## visible, and neither would have survived this test:
##   * the tower leg began 8.49 u from where the night leg ended — a teleport
##     at the beat seam, which also slammed the bank because the heading is
##     read from the frame's own displacement;
##   * that leg then passed 3.13 u from the north tower's centre, where the
##     masonry alone is 5.5 u and the wyrm is 12.4 u across.
##
## So: consecutive legs must share an endpoint exactly, and no sampled point
## of the flight may come within TOWER_CLEAR of either tower's axis, nor
## belly through the nave ridge cresting on the way over the roof.
const TOWER_X := 15.8
const TOWER_Z := -27.6
const TOWER_CLEAR := 11.7      ## 5.5 masonry + 6.2 half-wingspan at scale 2.2
const RIDGE_TOP := 39.65       ## ridge + cresting spikes
const RIDGE_HALF_W := 14.6
const BELLY := 1.2             ## how far under the root the body rides


static func _catmull(p: Array, t: float) -> Vector3:
	var n := p.size()
	var f := clampf(t, 0.0, 0.9999) * (n - 1)
	var i := int(f)
	var u := f - i
	var p0: Vector3 = p[maxi(i - 1, 0)]
	var p1: Vector3 = p[i]
	var p2: Vector3 = p[mini(i + 1, n - 1)]
	var p3: Vector3 = p[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


func _test_flight_path() -> void:
	var script: Script = load("res://src/cinematics/cathedral_cinematic_intro.gd")
	var consts := script.get_script_constant_map()
	var names := ["PATH_NIGHT", "PATH_APPROACH", "PATH_NEEDLE", "PATH_NAVE",
		"PATH_PERCH"]
	var legs: Array = []
	for n in names:
		legs.append(consts[n])

	# 1. the legs are ONE flight, not five
	var worst_seam := 0.0
	for i in range(legs.size() - 1):
		var gap: float = (legs[i][-1] as Vector3).distance_to(legs[i + 1][0] as Vector3)
		worst_seam = maxf(worst_seam, gap)
	check("flight: legs share their endpoints (worst gap %.3f)" % worst_seam,
		true, worst_seam < 0.01)

	# 2. nothing flies through the twin towers
	var worst_tower := INF
	var where := Vector3.ZERO
	for leg: Array in legs:
		for i in 801:
			var p := _catmull(leg, float(i) / 800.0)
			if p.y <= 20.0:
				continue   # below the belfries: the towers are not there yet
			for sx in [-1.0, 1.0]:
				var d := Vector2(p.x - sx * TOWER_X, p.z - TOWER_Z).length()
				if d < worst_tower:
					worst_tower = d
					where = p
	check("flight: clears the twin towers (min %.2f at %s)"
		% [worst_tower, str(where.round())], true, worst_tower >= TOWER_CLEAR)

	# 3. and rides OVER the nave ridge rather than through its cresting
	var worst_ridge := INF
	for leg: Array in legs:
		for i in 801:
			var p := _catmull(leg, float(i) / 800.0)
			if p.y < 32.0:
				continue   # inside the church, under its vault: not the roof
			if absf(p.x) <= RIDGE_HALF_W and p.z >= -26.0 and p.z <= 14.0:
				worst_ridge = minf(worst_ridge, p.y - BELLY - RIDGE_TOP)
	if worst_ridge == INF:
		check("flight: no exterior pass over the nave roof", true, true)
	else:
		check("flight: clears the nave ridge cresting (margin %.2f)" % worst_ridge,
			true, worst_ridge >= 0.0)


## SMOOTHNESS IS ALSO GEOMETRY (Bert, 2026-08-18: "make the approach into
## cathedral ouverture more smooth. Right now it's too sudden. A dragon is
## more like a b2 bomber, not a f35!").
##
## A flight can be continuous in POSITION and still lurch, because what the
## eye reads is the HEADING. The old cut dropped 20 u of altitude across one
## unit of ground to reach the rose — a falcon stoop — and then broke 74.9 deg
## the instant it was through, dodging a chandelier chain. Both are invisible
## to a seam-gap check and obvious in flight.
##
## So: the heading may not jump at a leg boundary. The landing flare is the
## one exemption, and it is a real one — the gallery sits behind the great
## hall's 11.7 u wall crest, so the wyrm must climb over the stone and settle
## onto the ledge. Birds pitch up hard to land.
const SEAM_TURN_MAX := 25.0     ## degrees, cruise seams
const FLARE_TURN_MAX := 60.0    ## …and the landing
const OUVERTURE_SLOPE_MAX := 18.0  ## degrees: a bomber's glideslope, not a dive


static func _tangent(p: Array, t: float) -> Vector3:
	var a := _catmull(p, maxf(t - 0.002, 0.0))
	var b := _catmull(p, minf(t + 0.002, 0.9999))
	var v := b - a
	return v.normalized() if v.length() > 1e-6 else Vector3(0, 0, 1)


func _test_flight_smoothness() -> void:
	var script: Script = load("res://src/cinematics/cathedral_cinematic_intro.gd")
	var consts := script.get_script_constant_map()
	var names := ["PATH_NIGHT", "PATH_APPROACH", "PATH_NEEDLE", "PATH_NAVE",
		"PATH_PERCH"]
	for i in range(names.size() - 1):
		var a: Array = consts[names[i]]
		var b: Array = consts[names[i + 1]]
		var turn := rad_to_deg(_tangent(a, 0.999).angle_to(_tangent(b, 0.001)))
		var limit := FLARE_TURN_MAX if names[i + 1] == "PATH_PERCH" else SEAM_TURN_MAX
		check("flight: %s -> %s heading holds (%.1f deg, max %.0f)"
			% [names[i].substr(5), names[i + 1].substr(5), turn, limit],
			true, turn <= limit)

	# THE OUVERTURE IS A GLIDESLOPE, NOT A DIVE: measure the run-in to the
	# rose from where the leg begins to where it crosses the facade plane.
	var ouv: Array = consts["PATH_NEEDLE"]
	var start: Vector3 = ouv[0]
	var rose := start
	for p: Vector3 in ouv:
		if absf(p.z + 26.0) < 0.5:
			rose = p
			break
	var run := absf(rose.z - start.z)
	var drop := start.y - rose.y
	var slope := rad_to_deg(atan2(drop, maxf(run, 0.001)))
	check("flight: the ouverture is a glideslope (%.1f deg over %.0f u, max %.0f)"
		% [slope, run, OUVERTURE_SLOPE_MAX], true, slope <= OUVERTURE_SLOPE_MAX)


## AND THE DOOR HAS TO FIT THE ANIMAL (Bert, 2026-08-18: "the hole is not big
## enough when he get in the cathedral... I know what would be more
## cinematic"). The wheel used to be r 6.0 with a CLEAR span of only r 3.0,
## because its tracery carried a stone hub ring straight across the opening.
## The wyrm is ~10.6 u across in its glide. So this asserts the two numbers
## against each other, and that the flight actually goes through the middle.
func _test_dragon_door() -> void:
	var script: Script = load("res://src/cinematics/cathedral_cinematic_intro.gd")
	var consts := script.get_script_constant_map()
	var centre: Vector3 = consts["ROSE_CENTRE"]
	var clear_r: float = consts["ROSE_CLEAR_R"]
	var span: float = consts["WYRM_SPAN"]
	check("door: the oculus is wider than the wyrm (%.1f u clear vs %.1f u span)"
		% [clear_r * 2.0, span], true, clear_r * 2.0 >= span * 1.1)

	# where does the flight actually cross the facade plane?
	var ouv: Array = consts["PATH_NEEDLE"]
	var crossing := Vector3.INF
	for i in 2001:
		var p := _catmull(ouv, float(i) / 2000.0)
		if absf(p.z - centre.z) < 0.02:
			crossing = p
			break
	check("door: the flight crosses the facade plane", true, crossing != Vector3.INF)
	if crossing == Vector3.INF:
		return
	var off := Vector2(crossing.x - centre.x, crossing.y - centre.y).length()
	check("door: the whole animal clears the stone (centre offset %.2f + half-span %.1f <= %.1f)"
		% [off, span * 0.5, clear_r], true, off + span * 0.5 <= clear_r)


## NOTHING HANGS IN THE CORRIDOR THE DRAGON FLIES DOWN.
##
## A corona is not just its ring — it is a column of iron from that ring up
## to the vault. Sweeping the flight against the fixtures as SOLIDS (the wyrm
## expanded by its half-span laterally and half-height vertically) is what
## caught all three of the originals; two were struck on the ring and one on
## the chain, and no amount of looking at stills had shown it.
func _corona_clear(fixtures: Array, radius: float, chain_top: float,
		legs: Array, label: String) -> void:
	var half := WYRM_SPAN_HALF
	var worst := ""
	for f: Vector3 in fixtures:
		for leg: Array in legs:
			for i in 1201:
				var p := _catmull(leg, float(i) / 1200.0)
				var horiz := Vector2(p.x - f.x, p.z - f.z).length()
				# the chain: a thin column from just above the ring upward
				if horiz < half + 0.2 and p.y + WYRM_H > f.y + 1.6 \
						and p.y - WYRM_H < chain_top:
					worst = "chain at %s, wyrm %s" % [str(f.round()), str(p.round())]
				# the ring itself
				if horiz < half + radius and absf(p.y - f.y) < WYRM_H + 0.2:
					worst = "ring at %s, wyrm %s" % [str(f.round()), str(p.round())]
	check("coronas: %s clear of the flight%s"
		% [label, "" if worst == "" else " — HIT " + worst], true, worst == "")


const WYRM_SPAN_HALF := 5.3
const WYRM_H := 1.2


func _test_coronas() -> void:
	var script: Script = load("res://src/cinematics/cathedral_cinematic_intro.gd")
	var c := script.get_script_constant_map()
	var legs: Array = []
	for n in ["PATH_NEEDLE", "PATH_NAVE", "PATH_PERCH"]:
		legs.append(c[n])
	_corona_clear(c["CORONA_NAVE"], c["CORONA_NAVE_R"],
		c["CORONA_NAVE_CHAIN_TOP"], legs, "the nave pair")
	var aisle: Array = []
	for sx in [-1.0, 1.0]:
		for z: float in c["CORONA_AISLE_ZS"]:
			aisle.append(Vector3(sx * float(c["CORONA_AISLE_X"]),
				float(c["CORONA_AISLE_Y"]), z))
	_corona_clear(aisle, c["CORONA_AISLE_R"], c["CORONA_AISLE_CHAIN_TOP"],
		legs, "the aisle eight")


## THE CHANDELIERS MUST MOVE WHILE THEY ARE BEING HIT (Bert, 2026-08-18: "the
## chandeliers didn't move like it should").
##
## The first sway evaluated a closed-form `amp * exp(-k t) * sin(w t)` and
## reset `t = 0` on every `strike()`. The cinematic strikes EVERY FRAME the
## wyrm is within reach — so t was zero on every one of those frames, sin(0)
## is zero, and the fixture hung dead still for exactly as long as the dragon
## was passing through it, then swung a second later with the camera already
## elsewhere. The one moment it had to sell was the one moment it could not.
##
## So the gate is not "a strike eventually produces motion" — the broken
## version passed that. It is "it is MOVING WHILE being struck every frame".
func _test_coronas_actually_swing() -> void:
	var SwayS: Script = load("res://src/env/corona_sway.gd")
	var scene: PackedScene = load("res://assets/environment/sanctum_cathedral.glb")
	if scene == null:
		check("coronas: cathedral loads", true, false)
		return
	var root := Node3D.new()
	get_root().add_child(root)
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var sway = SwayS.new()
	root.add_child(sway)
	var n: int = sway.adopt(inst)
	check("coronas: fixtures adopted from the GLB", true, n >= 3)
	if n < 1:
		root.queue_free()
		return
	sway.set_process(false)          # fixed clock: headless frames are ~0.4 ms
	var dt := 1.0 / 60.0
	var f = sway._fixtures[0]
	var pivot: Vector3 = sway.pivot(0)
	var peak_during := 0.0
	for i in int(0.45 / dt):         # a fly-by, struck on every single frame
		sway.strike_all_within(pivot, Vector3.FORWARD, 6.0, 0.9, dt)
		sway._process(dt)
		peak_during = maxf(peak_during, absf(rad_to_deg(f.ang)))
	check("coronas: swinging WHILE struck every frame (%.1f deg > 3)" % peak_during,
		true, peak_during > 3.0)
	# …and it rings on afterwards, because a hundred kilos of iron does not
	# stop in two seconds.
	var late := 0.0
	for i in int(8.0 / dt):
		sway._process(dt)
		late = maxf(late, absf(rad_to_deg(f.ang)))
	check("coronas: still ringing 8 s later (%.1f deg > 2)" % late, true, late > 2.0)
	root.queue_free()
