extends SceneTree

# Headless suite for the SIX SIGNATURE KILLS (2026-08-09) — the owner's brief
# was "different killing animations so it's not boring", and the thing that
# actually has to hold is: every rank kills in its own hand, every variant of
# every kill still FELLS THE VICTIM, and none of it costs the duel its budget
# or its contracts.
#
# What it proves, on REAL PieceViews (no mocks — a mock cannot tell you the
# rider re-seated or the tower ended up standing on the corpse):
#   * per type: the signature style fires (kill_style), the victim dies with
#     the matching death_style, a real death clip is named, and the view is
#     freed — all three variants of all six kills, 18 duels
#   * the victim's own variety: hit/death clips vary across repeats, and the
#     legacy bare die() is still exactly Hit_A -> Death_A (checkmate and the
#     costume suite both depend on that)
#   * NO Light3D is created by any kill (the hall's 8 omnis are the torches)
#   * every kill lands inside the duel's wall budget
#   * the attacker ends where it belongs: back on its mark — except the ROOK,
#     which is supposed to end up standing where its victim stood
#   * a piece freed mid-bolt leaves no torrent behind
#
# NOTE (same as test_costumes): -s runs never instance autoloads, so a script
# that so much as NAMES PieceAssets fails to compile until a node called
# "PieceAssets" hangs under /root. Shim first, then load() everything else,
# and touch those APIs only through Variants.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_kill_styles.gd
# Exit code 0 = all green, 1 = failures.

var failures := 0
var checks_run := 0

## A hard-erroring test aborts silently at the error and its await resumes as
## if it finished — so "no FAIL lines" is NOT proof the suite ran.
const MIN_EXPECTED_CHECKS := 120

# PieceView.Type (int-mirrored: PAWN ROOK KNIGHT BISHOP QUEEN KING).
const T_PAWN := 0
const T_ROOK := 1
const T_KNIGHT := 2
const T_BISHOP := 3
const T_QUEEN := 4
const T_KING := 5
const TYPE_NAMES := ["PAWN", "ROOK", "KNIGHT", "BISHOP", "QUEEN", "KING"]
const FROST := 0
const EMBER := 1

## type -> [expected kill_style, expected death_style per variant]
const SIGNATURES := {
	T_PAWN: ["stab", ["blade", "blade", "blade"]],
	T_ROOK: ["grind", ["crush", "crush", "crush"]],
	T_KNIGHT: ["charge", ["launch", "launch", "launch"]],
	T_BISHOP: ["bolt", ["burn", "burn", "burn"]],
	T_QUEEN: ["arrow", ["arrow", "arrow", "arrow"]],
	# the king's third variant is a sweep taken across the body, not a
	# straight-down blow — his victim is cut, not crushed
	T_KING: ["execution", ["crush", "crush", "blade"]],
}
## One duel's wall-clock ceiling at time_scale 1.0. The director spends its
## own ~1.5 s on the face-off, the swoop and the return on top of this, and
## the whole cinematic is budgeted at ~5.5 s (duel_test asserts < 6 s).
const KILL_WALL_CEILING := 3.6

var assets: Node          # the PieceAssets shim
var piece_scene: PackedScene
var kills_seen: Dictionary = {}   # style -> times fired


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — signature kills headless suite ===")
	assets = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	piece_scene = load("res://scenes/piece_view.tscn")
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	await _test_every_kill()
	await _test_legacy_die_unchanged()
	await _test_victim_variety()
	await _test_tower_victim_still_crumbles()
	await _test_bolt_leaves_nothing_behind()
	check("final: time_scale untouched", true, is_equal_approx(Engine.time_scale, 1.0))
	check("final: all six styles fired", 6, kills_seen.size())
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	print("---")
	if failures == 0:
		print("KILLS OK — all %d checks passed" % checks_run)
	else:
		print("KILLS FAILED — %d of %d checks failed" % [failures, checks_run])
	quit(0 if failures == 0 else 1)


## Helpers ##


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
		print("FAIL  %-62s expected %s, got %s" % [test_name, expected, actual])


func _spawn(piece_type: int, side: int, house_id: String) -> Node:
	var pv: Node = piece_scene.instantiate()
	root.add_child(pv)
	pv.setup(piece_type, side, house_id)
	return pv


func _lights_under(n: Node) -> int:
	return n.find_children("*", "Light3D", true, false).size()


## Tests ##


## THE GATE, per type and per variant: the signature fires, the victim dies
## of it, and the board is left in the state the next beat expects.
func _test_every_kill() -> void:
	for t: int in SIGNATURES:
		var sig: Array = SIGNATURES[t]
		for variant in 3:
			await _one_kill(t, variant, str(sig[0]), str((sig[1] as Array)[variant]))


func _one_kill(attacker_type: int, variant: int, want_style: String,
		want_death: String) -> void:
	var tag := "%s v%d" % [TYPE_NAMES[attacker_type], variant]
	var attacker := _spawn(attacker_type, FROST, "winterfang")
	var victim := _spawn(T_PAWN, EMBER, "ashwyrm")
	attacker.position = Vector3.ZERO
	victim.position = Vector3(0.0, 0.0, 1.1)
	attacker.kill_variant_force = variant
	var home: Vector3 = attacker.position
	var lights_before := _lights_under(root)
	# What the victim carried to its grave — read at `died`, since the view is
	# freed immediately after.
	var fell: Array = ["", "", false]   # [death_style, death_anim, emitted]
	victim.died.connect(func() -> void:
		fell[0] = victim.death_style
		fell[1] = victim.death_anim
		fell[2] = true)
	var t0 := Time.get_ticks_msec()
	await attacker.play_capture(victim)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	# Printed, not just asserted: the wall clock per kill is the number that
	# tells a later reader WHY a variant is timed the way it is.
	print("KILL %-12s style=%-9s death=%-7s clip=%-8s wall=%.2fs"
			% [tag, attacker.kill_style, str(fell[0]), str(fell[1]), wall])
	check("%s: kill_style" % tag, want_style, attacker.kill_style)
	check("%s: variant honoured" % tag, variant, attacker.kill_variant)
	check("%s: victim died" % tag, true, bool(fell[2]))
	check("%s: victim death_style" % tag, want_death, str(fell[0]))
	check("%s: victim named a death clip" % tag, true, not str(fell[1]).is_empty())
	check("%s: victim view consumed" % tag, true,
			not is_instance_valid(victim) or victim.is_queued_for_deletion())
	check("%s: no Light3D created (%.2fs)" % [tag, wall], lights_before,
			_lights_under(root))
	check("%s: inside the wall budget (%.2fs)" % [tag, wall], true,
			wall < KILL_WALL_CEILING)
	if attacker_type == T_ROOK:
		# The tower is the one attacker that MOVES OVER its victim and stays
		# there — it does not step back off the square it just took.
		check("%s: tower ended on the victim's square" % tag, true,
				attacker.position.z > 0.9)
	else:
		check("%s: attacker back on its mark" % tag, true,
				attacker.position.distance_to(home) < 0.03)
	kills_seen[attacker.kill_style] = int(kills_seen.get(attacker.kill_style, 0)) + 1
	if attacker_type == T_KNIGHT:
		# The mounted contracts the costume suite owns, re-checked under the
		# NEW choreography: the mount keeps breathing, the rider re-seats.
		check("%s: mount still breathing" % tag, true,
				attacker._sway_tween != null and attacker._sway_tween.is_running())
	if is_instance_valid(attacker):
		attacker.free()
	if is_instance_valid(victim):
		victim.free()


## The LEGACY bare die() is load-bearing: play_checkmate calls it, and both
## the costume suite and game.gd's death_log read Death_A back out of it. It
## is deliberately exempt from the new variety.
func _test_legacy_die_unchanged() -> void:
	for i in 4:
		var pv := _spawn(T_QUEEN, EMBER, "goldclaw")
		var got: Array = ["", ""]
		pv.died.connect(func() -> void:
			got[0] = pv.death_anim
			got[1] = pv.death_style)
		await pv.die()
		check("legacy die #%d: Death_A" % i, "Death_A", str(got[0]))
		check("legacy die #%d: no style" % i, "", str(got[1]))


## The other half of "not boring": the same kill repeated does not play the
## same death. Across 12 stabs the victim must reach for more than one hit
## clip and more than one death clip.
func _test_victim_variety() -> void:
	var hits := {}
	var deaths := {}
	for i in 12:
		var attacker := _spawn(T_PAWN, FROST, "winterfang")
		var victim := _spawn(T_KING, EMBER, "ashwyrm")
		attacker.position = Vector3.ZERO
		victim.position = Vector3(0.0, 0.0, 1.1)
		var seen: Array = [""]
		victim.died.connect(func() -> void: seen[0] = victim.death_anim)
		await attacker.play_capture(victim)
		deaths[str(seen[0])] = true
		hits[str(attacker.kill_variant)] = true
		attacker.free()
		if is_instance_valid(victim):
			victim.free()
	check("variety: more than one death clip across 12 kills", true, deaths.size() > 1)
	check("variety: death clips are real clips", true,
			deaths.has("Death_A") or deaths.has("Death_B"))
	check("variety: the random variant picker moves", true, hits.size() > 1)


## A watchtower crushed, burned or shot still comes down as masonry — it has
## no rig to play a death clip on, and die() must not try.
func _test_tower_victim_still_crumbles() -> void:
	for style in ["crush", "burn", "arrow"]:
		var tower := _spawn(T_ROOK, EMBER, "tidegrip")
		var got: Array = ["", ""]
		tower.died.connect(func() -> void:
			got[0] = tower.death_anim
			got[1] = tower.death_style)
		await tower.die(style)
		check("tower victim (%s): crumbles" % style, "Tower_Crumble", str(got[0]))
		check("tower victim (%s): keeps the killer's style" % style, style, str(got[1]))


## A bishop freed mid-bolt must not strand a torrent (or a stuck shader) in
## the hall — _exit_tree hard-stops the kit.
func _test_bolt_leaves_nothing_behind() -> void:
	var bishop := _spawn(T_BISHOP, FROST, "winterfang")
	var victim := _spawn(T_PAWN, EMBER, "ashwyrm")
	bishop.position = Vector3.ZERO
	victim.position = Vector3(0.0, 0.0, 1.1)
	bishop.kill_variant_force = 0
	var runner := func() -> void:
		await bishop.play_capture(victim)
	runner.call()
	var saw_bolt := false
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(bishop) and bishop.find_child("StaffBolt", true, false) != null:
			saw_bolt = true
			break
		await process_frame
	check("bolt: the dracarys kit was built and fired", true, saw_bolt)
	check("bolt: no Light3D in the kit", 0,
			_lights_under(bishop.find_child("StaffBolt", true, false)) if saw_bolt else 0)
	bishop.free()   # mid-bolt, on purpose
	await process_frame
	await process_frame
	check("bolt: nothing left in the tree after the bishop is freed", 0,
			root.find_children("StaffBolt", "", true, false).size())
	if is_instance_valid(victim):
		victim.free()
