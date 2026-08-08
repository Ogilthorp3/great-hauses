extends SceneTree

# Headless unit tests for DuelDirector — focused on Engine.time_scale
# hygiene: the restore MUST hold on every exit path (normal end, skip,
# failsafe overrun, director freed mid-cinematic) plus the kill-line pool.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_cinematics.gd
# Exit code 0 = all green, 1 = failures.

const DD := preload("res://src/cinematics/duel_director.gd")
const LINES_PATH := "res://src/cinematics/kill_lines.json"

var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its await
## resumes as if it finished — so "no FAIL lines" is NOT proof the suite ran.
## This floor turns silently-aborted tests into a loud failure.
const MIN_EXPECTED_CHECKS := 30


class Duck:
	extends Node3D
	## Minimal PieceView-shaped fighter (duck fields DuelDirector reads).
	var piece_type := 2   # knight
	var side := 0         # FROST


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Houses — cinematics (DuelDirector) headless suite ===")
	await process_frame   # let the tree start: nodes added before the first
	await process_frame   # frame get no _ready/get_tree during _initialize
	Engine.time_scale = 1.0
	_test_lines_pool()
	await _test_duel_restore()
	await _test_skip_restore()
	await _test_free_restore()
	await _test_failsafe_restore()
	await _test_promotion_restore()
	await _test_checkmate_restore()
	check("final: time_scale is 1.0", true, is_equal_approx(Engine.time_scale, 1.0))
	check("final: no test silently aborted (checks >= %d)" % MIN_EXPECTED_CHECKS,
			true, checks_run >= MIN_EXPECTED_CHECKS)
	print("---")
	if failures == 0:
		print("CINEMATICS OK — all checks passed")
	else:
		print("CINEMATICS FAILED — %d check(s) failed" % failures)
	quit(0 if failures == 0 else 1)


## Helpers ##


func check(test_name: String, expected, actual) -> void:
	checks_run += 1
	var ok := str(expected) == str(actual)
	if not ok:
		failures += 1
	print("%s %s (expected %s, got %s)" % ["PASS" if ok else "FAIL", test_name, expected, actual])


func _fast_director() -> DuelDirector:
	var d: DuelDirector = DD.new()
	d.swoop_wall = 0.05
	d.return_wall = 0.05
	d.duel_ramp_down_wall = 0.05
	d.duel_slow_hold_wall = 0.1
	d.duel_ramp_up_wall = 0.05
	d.duel_tail_wall = 0.05
	d.promo_wall = 0.15
	d.checkmate_hold_wall = 0.15
	d.failsafe_wall_sec = 5.0
	root.add_child(d)
	return d


func _wait_wall(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _wait_until(pred: Callable, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await process_frame
	return false


## Tests ##


func _test_lines_pool() -> void:
	var f := FileAccess.open(LINES_PATH, FileAccess.READ)
	check("lines: file opens", true, f != null)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	check("lines: parses to object", true, typeof(data) == TYPE_DICTIONARY)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var kl: Array = data.get("kill_lines", [])
	check("lines: >= 20 kill lines", true, kl.size() >= 20)
	var all_have_text := true
	for e in kl:
		if typeof(e) != TYPE_DICTIONARY or str(e.get("text", "")).is_empty():
			all_have_text = false
	check("lines: every entry has text", true, all_have_text)
	check("lines: FROST house present", true, data.get("houses", {}).has("FROST"))
	check("lines: EMBER house present", true, data.get("houses", {}).has("EMBER"))
	check("lines: promotion pool present", true, data.get("promotion_lines", []).size() >= 3)
	# Token formatting
	var out := DD.format_line("The {aa} of {ah} remembers, ser {vp}.",
		{"aa": "wolf", "ah": "House Frost", "vp": "queen"})
	check("lines: format_line substitutes", "The wolf of House Frost remembers, ser queen.", out)


func _test_duel_restore() -> void:
	var d := _fast_director()
	var a := Duck.new()
	var v := Duck.new()
	v.piece_type = 4
	v.side = 1
	root.add_child(a)
	root.add_child(v)

	# Kill-line picks are fully formatted (no leftover tokens), 30 samples.
	var ctx := d.duel_context(a, v, {})
	check("ctx: attacker resolved", "knight", ctx["ap"])
	check("ctx: victim house resolved", "House Ember", ctx["vh"])
	# Canonical HouseRegistry resolution (id / display name / archetype)
	if FileAccess.file_exists("res://src/houses/houses.json"):
		check("canon: id resolves", "House Winterfang", d.resolve_house_name("winterfang"))
		check("canon: archetype resolves", "House Winterfang", d.resolve_house_name("wolf"))
		var mctx := d.duel_context(a, v,
			{"attacker_house": "goldclaw", "victim_house": "winterfang"})
		check("canon: meta house override", "House Goldclaw", mctx["ah"])
	var clean := true
	for i in 30:
		var line := d.pick_kill_line(ctx)
		if line.is_empty() or line.contains("{a") or line.contains("{v"):
			clean = false
	check("ctx: 30 picked lines fully formatted", true, clean)

	# The duel itself: probe slow-mo + activity from inside the strike.
	var probe := {"min_ts": 10.0, "active_seen": false}
	var strike := func() -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 300:
			probe["min_ts"] = minf(probe["min_ts"], Engine.time_scale)
			probe["active_seen"] = probe["active_seen"] or d.is_active()
			await process_frame
	await d.play_duel(a, v, {}, strike)
	check("duel: slow-mo reached (<0.5)", true, probe["min_ts"] < 0.5)
	check("duel: is_active during", true, probe["active_seen"])
	check("duel: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("duel: inactive after", false, d.is_active())

	d.free()
	a.free()
	v.free()


func _test_skip_restore() -> void:
	var d := _fast_director()
	d.duel_slow_hold_wall = 3.0   # long hold so there is a window to skip in
	var a := Duck.new()
	var v := Duck.new()
	root.add_child(a)
	root.add_child(v)
	var done := {"v": false}
	var runner := func() -> void:
		await d.play_duel(a, v, {})
		done["v"] = true
	runner.call()
	var slowed: bool = await _wait_until(func(): return Engine.time_scale < 0.9, 2.0)
	check("skip: slow-mo entered", true, slowed)
	d.skip()
	await process_frame
	await process_frame
	check("skip: time_scale snaps back", true, is_equal_approx(Engine.time_scale, 1.0))
	var finished: bool = await _wait_until(func(): return done["v"], 3.0)
	check("skip: sequence completes", true, finished)
	check("skip: inactive after", false, d.is_active())
	d.free()
	a.free()
	v.free()


func _test_free_restore() -> void:
	var d := _fast_director()
	d.duel_slow_hold_wall = 5.0
	var a := Duck.new()
	var v := Duck.new()
	root.add_child(a)
	root.add_child(v)
	var runner := func() -> void:
		await d.play_duel(a, v, {})
	runner.call()
	var slowed: bool = await _wait_until(func(): return Engine.time_scale < 0.9, 2.0)
	check("free: slow-mo entered", true, slowed)
	d.free()   # director dies mid-cinematic — _exit_tree must restore
	await process_frame
	check("free: time_scale restored on exit-tree", true, is_equal_approx(Engine.time_scale, 1.0))
	a.free()
	v.free()


func _test_failsafe_restore() -> void:
	var d := _fast_director()
	d.failsafe_wall_sec = 0.3
	d.duel_slow_hold_wall = 10.0   # would strand slow-mo without the failsafe
	var a := Duck.new()
	var v := Duck.new()
	root.add_child(a)
	root.add_child(v)
	var hang := func() -> void:   # a strike that never finishes
		while is_instance_valid(d):
			await process_frame
	var runner := func() -> void:
		await d.play_duel(a, v, {}, hang)
	runner.call()
	await _wait_wall(0.8)   # > failsafe_wall_sec
	check("failsafe: time_scale force-restored", true, is_equal_approx(Engine.time_scale, 1.0))
	d.free()
	a.free()
	v.free()


func _test_promotion_restore() -> void:
	var d := _fast_director()
	var p := Duck.new()
	p.piece_type = 4
	root.add_child(p)
	await d.play_promotion(p)
	check("promotion: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("promotion: inactive after", false, d.is_active())
	d.free()
	p.free()


func _test_checkmate_restore() -> void:
	var d := _fast_director()
	var king := Duck.new()
	king.piece_type = 5
	king.side = 1
	root.add_child(king)
	var got := {"house": ""}
	d.victory_panel_requested.connect(func(h: String): got["house"] = h)
	var death := func() -> void:
		await create_timer(0.1, true, false, true).timeout
	await d.play_checkmate(king, "EMBER", death)
	check("checkmate: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	check("checkmate: victory hook fired", "House Ember", got["house"])
	check("checkmate: inactive after", false, d.is_active())
	d.free()
	king.free()
