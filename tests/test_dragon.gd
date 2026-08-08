extends SceneTree

# Headless unit tests for the DRAGON SPECTATOR + ASHFALL module — focused on
# the module's hard contracts:
#   - reaction rate limit (max 1 per 2 moves) + the duel-cam gate
#   - ASHFALL Engine.time_scale hygiene on EVERY exit path (normal end,
#     skip, spectator freed mid-sequence)
#   - loser-piece cleanup is complete (explicit list AND duck-scan), and
#     the king / winners are never touched
#   - NO Light3D node is added by any module code path (asserted by
#     counting the whole tree before/after)
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_dragon.gd
# Exit code 0 = all green, 1 = failures.

const Spectator := preload("res://src/cinematics/dragon_spectator.gd")
const DD := preload("res://src/cinematics/duel_director.gd")

var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its await
## resumes as if it finished — the floor turns silent aborts into a loud
## failure (same guard as test_cinematics.gd).
const MIN_EXPECTED_CHECKS := 34


class Duck:
	extends Node3D
	## Minimal PieceView-shaped piece (the duck fields the module reads),
	## with a real material so the char path executes.
	var piece_type := 0
	var side := 0

	func _init(pt: int = 0, s: int = 0) -> void:
		piece_type = pt
		side = s
		var mi := MeshInstance3D.new()
		mi.mesh = CapsuleMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.4, 0.3)
		mi.material_override = mat
		add_child(mi)


class MockDD:
	extends Node
	var active := false
	func is_active() -> bool:
		return active


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Houses — dragon spectator/ashfall headless suite ===")
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	var lights_before := _light_count()
	_test_kill_lines()
	await _test_rate_limit_and_gate()
	await _test_ashfall_completion()
	await _test_ashfall_duck_scan()
	await _test_ashfall_skip()
	await _test_ashfall_free_restore()
	check("final: time_scale is 1.0", true, is_equal_approx(Engine.time_scale, 1.0))
	check("final: no Light3D added by any module path", lights_before, _light_count())
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	print("---")
	if failures == 0:
		print("DRAGON OK — all checks passed")
	else:
		print("DRAGON FAILED — %d check(s) failed" % failures)
	quit(0 if failures == 0 else 1)


## Helpers ##


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	print("%s %s (expected %s, got %s)" % ["PASS" if ok else "FAIL", test_name, expected, actual])


func _light_count() -> int:
	return root.find_children("*", "Light3D", true, false).size()


func _fast_spectator() -> DragonSpectator:
	var s: DragonSpectator = Spectator.new()
	s.ash_ramp_wall = 0.05
	s.ash_swoop_wall = 0.15
	s.ash_breath_wall = 0.3
	s.ash_return_wall = 0.1
	s.ash_char_wall = 0.05
	s.ash_crumble_wall = 0.05
	s.failsafe_wall_sec = 5.0
	root.add_child(s)
	return s


func _wait_wall(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _wait_until(pred: Callable, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await process_frame
	return false


func _spawn_army(side: int, n: int, z: float) -> Array:
	var out: Array = []
	for i in n:
		var d := Duck.new(i % 5, side)
		root.add_child(d)
		d.position = Vector3(-2.0 + i * 1.1, 0.0, z)
		out.append(d)
	return out


func _alive(arr: Array) -> int:
	var n := 0
	for p in arr:
		if is_instance_valid(p):
			n += 1
	return n


## Tests ##


func _test_kill_lines() -> void:
	check("lines: pool present", true, Spectator.ASHFALL_LINES.size() >= 3)
	var all_have_token := true
	for l in Spectator.ASHFALL_LINES:
		if not str(l).contains("{wh}"):
			all_have_token = false
	check("lines: every line carries {wh}", true, all_have_token)
	var out := DD.format_line("What {wh} cannot rule, it burns.", {"wh": "House Winterfang"})
	check("lines: format substitutes", "What House Winterfang cannot rule, it burns.", out)


func _test_rate_limit_and_gate() -> void:
	var s := _fast_spectator()
	await process_frame
	check("rig: dragon spawned", true, s.rig != null and s.rig.anim != null)
	check("rig: idles on Flying_Idle", "Flying_Idle", s.rig.anim.assigned_animation)

	check("rate: first reaction allowed", true, s.react_brilliant())
	check("rate: reaction plays Yes", "Yes", s.rig.anim.assigned_animation)
	check("rate: immediate second suppressed", false, s.react_blunder())
	s.notice_move(Vector3.ZERO)
	check("rate: still suppressed after 1 move", false, s.react_blunder())
	s.notice_move(Vector3.ZERO)
	var released: bool = await _wait_until(func() -> bool: return s.can_react(), 4.0)
	check("rate: reaction window reopens after 2 moves", true, released)

	var dd := MockDD.new()
	root.add_child(dd)
	dd.active = true
	s.duel_director = dd
	check("gate: blocked while duel-cam active", false, s.react_capture(Vector3.ZERO))
	dd.active = false
	check("gate: allowed when duel-cam idle", true, s.react_capture(Vector3(1.0, 0.0, 1.0)))
	check("gate: capture plays HitReact", "HitReact", s.rig.anim.assigned_animation)

	s.free()
	dd.free()


func _test_ashfall_completion() -> void:
	var s := _fast_spectator()
	await process_frame
	var winners := _spawn_army(0, 2, -1.5)
	var losers := _spawn_army(1, 4, 1.5)
	var probe := {"min_ts": 10.0, "started": false, "finished": false}
	s.ashfall_started.connect(func() -> void: probe["started"] = true)
	s.ashfall_finished.connect(func() -> void: probe["finished"] = true)
	var sampler := func() -> void:
		while is_instance_valid(s) and not probe["finished"]:
			probe["min_ts"] = minf(probe["min_ts"], Engine.time_scale)
			await process_frame
	sampler.call()
	var t0 := Time.get_ticks_msec()
	await s.play_ashfall(1, "House Winterfang", losers)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	await process_frame
	await process_frame
	check("ashfall: started signal", true, probe["started"])
	check("ashfall: finished signal", true, probe["finished"])
	check("ashfall: slow-mo dipped", true, probe["min_ts"] < 0.9)
	check("ashfall: time_scale restored on completion", true,
			is_equal_approx(Engine.time_scale, 1.0))
	check("ashfall: all losers removed", 0, _alive(losers))
	check("ashfall: winners untouched", 2, _alive(winners))
	check("ashfall: inactive after", false, s.is_ashfall_active())
	check("ashfall: wall under 2s at test speeds", true, wall < 2.0)
	s.free()
	for w in winners:
		if is_instance_valid(w):
			w.free()


func _test_ashfall_duck_scan() -> void:
	## No explicit list: the module must find the losing side itself and
	## must NOT burn the king (he fell to the checkmate cinematic already).
	var s := _fast_spectator()
	await process_frame
	var losers := _spawn_army(1, 3, 2.5)
	var king := Duck.new(5, 1)   # piece_type 5 = KING
	root.add_child(king)
	var winners := _spawn_army(0, 2, -2.5)
	await s.play_ashfall(1)
	await process_frame
	await process_frame
	check("duckscan: losers found and removed", 0, _alive(losers))
	check("duckscan: king spared", true, is_instance_valid(king))
	check("duckscan: winners untouched", 2, _alive(winners))
	check("duckscan: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	king.free()
	for w in winners:
		if is_instance_valid(w):
			w.free()


func _test_ashfall_skip() -> void:
	var s := _fast_spectator()
	s.ash_breath_wall = 5.0   # long breath so there is a window to skip in
	await process_frame
	var losers := _spawn_army(1, 4, 1.5)
	var done := {"v": false}
	var runner := func() -> void:
		await s.play_ashfall(1, "House Winterfang", losers)
		done["v"] = true
	runner.call()
	var slowed: bool = await _wait_until(
		func() -> bool: return s.is_ashfall_active() and Engine.time_scale < 0.9, 2.0)
	check("skip: ashfall entered slow-mo", true, slowed)
	s.skip()
	await process_frame
	await process_frame
	check("skip: time_scale snaps back", true, is_equal_approx(Engine.time_scale, 1.0))
	check("skip: all losers removed at once", 0, _alive(losers))
	check("skip: inactive after", false, s.is_ashfall_active())
	var finished: bool = await _wait_until(func() -> bool: return done["v"], 3.0)
	check("skip: awaited sequence completes", true, finished)
	s.free()


func _test_ashfall_free_restore() -> void:
	var s := _fast_spectator()
	s.ash_breath_wall = 5.0
	await process_frame
	var losers := _spawn_army(1, 2, 1.5)
	var runner := func() -> void:
		await s.play_ashfall(1, "", losers)
	runner.call()
	var slowed: bool = await _wait_until(
		func() -> bool: return s.is_ashfall_active() and Engine.time_scale < 0.9, 2.0)
	check("free: ashfall entered slow-mo", true, slowed)
	s.free()   # spectator dies mid-sequence — _exit_tree must restore
	await process_frame
	check("free: time_scale restored on exit-tree", true,
			is_equal_approx(Engine.time_scale, 1.0))
	for l in losers:
		if is_instance_valid(l):
			l.free()
