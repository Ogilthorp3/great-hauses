extends SceneTree

# Headless unit tests for DuelDirector — focused on Engine.time_scale
# hygiene: the restore MUST hold on every exit path (normal end, skip,
# failsafe overrun, director freed mid-cinematic) plus the kill-line pool.
#
# Since 2026-08-09 this suite also owns the DRACARYS RESTORE CONTRACT. The
# fire kit lifts the hall's WorldEnvironment (tonemap exposure, glow,
# ambient) and shakes the camera (h_offset / v_offset / fov) at ignition. A
# STUCK EXPOSURE IS A SHIPPING BUG — the whole hall would stay a stop
# brighter for the rest of the session — so the restore is asserted on every
# exit path there is: the normal end of the ceremony, the click/Esc skip
# mid-torrent, and the spectator being freed mid-torrent (the error path).
# The lift is also asserted to be REAL mid-shot, or the three restore
# assertions could all pass vacuously against an effect that never fired.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_cinematics.gd
# Exit code 0 = all green, 1 = failures.

const DD := preload("res://src/cinematics/duel_director.gd")
const Spectator := preload("res://src/cinematics/dragon_spectator.gd")
const LINES_PATH := "res://src/cinematics/kill_lines.json"

var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its await
## resumes as if it finished — so "no FAIL lines" is NOT proof the suite ran.
## This floor turns silently-aborted tests into a loud failure.
const MIN_EXPECTED_CHECKS := 95


class Duck:
	extends Node3D
	## Minimal PieceView-shaped fighter (duck fields DuelDirector reads).
	var piece_type := 2   # knight
	var side := 0         # FROST


func _initialize() -> void:
	_main()


func _main() -> void:
	print("=== Great Hauses — cinematics (DuelDirector) headless suite ===")
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
	var lights_before := _light_count()
	await _test_dracarys_lift_is_real()
	await _test_dracarys_restore_normal()
	await _test_dracarys_restore_skip()
	await _test_dracarys_restore_free()
	check("dracarys: no Light3D added by the fire on any path",
			lights_before, _light_count())
	_test_heraldic_tincture()
	_test_hall_banner_stations()
	await _test_hall_banner_frame()
	await _test_hall_dressing()
	await _test_caption_clears_its_subject()
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
		{"aa": "wolf", "ah": "Haus Frost", "vp": "queen"})
	check("lines: format_line substitutes", "The wolf of Haus Frost remembers, ser queen.", out)


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
	check("ctx: victim house resolved", "Haus Ember", ctx["vh"])
	# Canonical HouseRegistry resolution (id / display name / archetype)
	# Ask the ROSTER, not a file path. This used to test for
	# res://src/houses/houses.json; houses are discovered house PACKS now
	# (docs/HOUSE-PACK.md), and a guard naming a file that no longer exists
	# would have quietly skipped these three checks forever.
	if HouseRegistry.has_house("winterfang"):
		check("canon: id resolves", "Haus Winterfang", d.resolve_house_name("winterfang"))
		check("canon: archetype resolves", "Haus Winterfang", d.resolve_house_name("wolf"))
		var mctx := d.duel_context(a, v,
			{"attacker_house": "goldclaw", "victim_house": "winterfang"})
		check("canon: meta house override", "Haus Goldclaw", mctx["ah"])
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
	check("checkmate: victory hook fired", "Haus Ember", got["house"])
	check("checkmate: inactive after", false, d.is_active())
	d.free()
	king.free()


# ── DRACARYS RESTORE CONTRACT ──────────────────────────────────────────────
# The fire kit's only reach outside its own subtree is the WorldEnvironment
# lift and the camera shake. Both are recorded on first touch and must come
# back EXACTLY, on every exit path. These tests stage a real ceremony over a
# real Environment and a real Camera3D, then compare field by field.


class Duck3D:
	extends Node3D
	## Minimal PieceView-shaped loser (the duck fields DragonSpectator reads).
	var piece_type := 0
	var side := 1

	func _init() -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = CapsuleMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.4, 0.3)
		mi.material_override = mat
		add_child(mi)


func _light_count() -> int:
	return root.find_children("*", "Light3D", true, false).size()


## The stage: a WorldEnvironment with a torch-lit-hall-shaped Environment, a
## current Camera3D, a fast spectator and three warriors to burn.
func _fire_stage(breath: float) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.275, 0.265)
	env.ambient_light_energy = 0.66
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.current = true
	var s: DragonSpectator = Spectator.new()
	s.ash_ramp_wall = 0.05
	s.ash_bank_wall = 0.15
	s.ash_flare_wall = 0.06
	s.ash_inhale_wall = 0.06
	s.ash_breath_wall = breath
	s.ash_linger_wall = 0.12
	s.ash_return_wall = 0.08
	s.ash_flash_wall = 0.03
	s.ash_smolder_wall = 0.06
	s.ash_collapse_wall = 0.06
	s.ash_char_wall = 0.04
	s.ash_crumble_wall = 0.04
	s.failsafe_wall_sec = 12.0
	root.add_child(s)
	var losers: Array = []
	for i in 3:
		var d := Duck3D.new()
		root.add_child(d)
		d.position = Vector3(-1.5 + i * 1.5, 0.0, 1.5)
		losers.append(d)
	return {"env": env, "we": we, "cam": cam, "s": s, "losers": losers,
		"saved": _env_snapshot(env), "cam_saved": _cam_snapshot(cam)}


func _env_snapshot(env: Environment) -> Array:
	return [env.tonemap_exposure, env.glow_enabled, env.glow_intensity,
		env.glow_bloom, env.ambient_light_source, env.ambient_light_energy,
		env.ambient_light_color]


func _cam_snapshot(cam: Camera3D) -> Array:
	return [cam.h_offset, cam.v_offset, cam.fov]


func _env_restored(tag: String, stage: Dictionary) -> void:
	var env: Environment = stage["env"]
	check("%s: tonemap_exposure restored" % tag, stage["saved"][0], env.tonemap_exposure)
	check("%s: glow_enabled restored" % tag, stage["saved"][1], env.glow_enabled)
	check("%s: glow_intensity restored" % tag, stage["saved"][2], env.glow_intensity)
	check("%s: glow_bloom restored" % tag, stage["saved"][3], env.glow_bloom)
	check("%s: ambient_source restored" % tag, stage["saved"][4], env.ambient_light_source)
	check("%s: ambient_energy restored" % tag, stage["saved"][5], env.ambient_light_energy)
	check("%s: ambient_color restored" % tag, stage["saved"][6], env.ambient_light_color)


func _cam_restored(tag: String, stage: Dictionary) -> void:
	var cam: Camera3D = stage["cam"]
	if not is_instance_valid(cam):
		return
	check("%s: camera h_offset restored" % tag, stage["cam_saved"][0], cam.h_offset)
	check("%s: camera v_offset restored" % tag, stage["cam_saved"][1], cam.v_offset)
	check("%s: camera fov restored" % tag, stage["cam_saved"][2], cam.fov)


func _teardown_stage(stage: Dictionary) -> void:
	for n in [stage["s"], stage["cam"], stage["we"]]:
		if is_instance_valid(n):
			n.free()
	for l in stage["losers"]:
		if is_instance_valid(l):
			l.free()
	await process_frame


## The lift must be DEMONSTRABLY real mid-shot, or every restore assertion
## below could pass against an effect that never fired.
func _test_dracarys_lift_is_real() -> void:
	var stage := _fire_stage(1.6)
	var s: DragonSpectator = stage["s"]
	var env: Environment = stage["env"]
	var base: float = env.tonemap_exposure
	var peak := {"exp": base, "glow": env.glow_intensity}
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", stage["losers"])
	runner.call()
	var sampler := func() -> void:
		while is_instance_valid(s) and s.is_ashfall_active():
			peak["exp"] = maxf(peak["exp"], env.tonemap_exposure)
			peak["glow"] = maxf(peak["glow"], env.glow_intensity)
			await process_frame
	sampler.call()
	var done: bool = await _wait_until(
		func() -> bool: return not s.is_ashfall_active(), 15.0)
	check("lift: ceremony completed", true, done)
	check("lift: exposure demonstrably kicked mid-shot", true, peak["exp"] > base * 1.02)
	check("lift: glow demonstrably kicked mid-shot", true,
			peak["glow"] > stage["saved"][2] + 0.01)
	await _teardown_stage(stage)


func _test_dracarys_restore_normal() -> void:
	var stage := _fire_stage(0.6)
	var s: DragonSpectator = stage["s"]
	await s.play_ashfall(1, "Haus Winterfang", stage["losers"])
	await process_frame
	await process_frame
	check("fire-normal: ceremony inactive", false, s.is_ashfall_active())
	_env_restored("fire-normal", stage)
	_cam_restored("fire-normal", stage)
	check("fire-normal: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	await _teardown_stage(stage)


func _test_dracarys_restore_skip() -> void:
	## THE SKIP: click/Esc mid-torrent must snap the environment back, not
	## leave the hall a stop brighter for the rest of the session.
	var stage := _fire_stage(4.0)   # long breath so there is a torrent to skip
	var s: DragonSpectator = stage["s"]
	var env: Environment = stage["env"]
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", stage["losers"])
	runner.call()
	var lifted: bool = await _wait_until(
		func() -> bool: return env.tonemap_exposure > stage["saved"][0] * 1.02, 8.0)
	check("fire-skip: torrent lifted the environment first", true, lifted)
	s.skip()
	await process_frame
	await process_frame
	check("fire-skip: ceremony inactive", false, s.is_ashfall_active())
	_env_restored("fire-skip", stage)
	_cam_restored("fire-skip", stage)
	check("fire-skip: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	await _teardown_stage(stage)


func _test_dracarys_restore_free() -> void:
	## THE ERROR PATH: the spectator is freed mid-torrent (scene change, a
	## crash in the caller, a rematch). _exit_tree must still restore.
	var stage := _fire_stage(4.0)
	var s: DragonSpectator = stage["s"]
	var env: Environment = stage["env"]
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", stage["losers"])
	runner.call()
	var lifted: bool = await _wait_until(
		func() -> bool: return env.tonemap_exposure > stage["saved"][0] * 1.02, 8.0)
	check("fire-free: torrent lifted the environment first", true, lifted)
	s.free()
	await process_frame
	await process_frame
	_env_restored("fire-free", stage)
	_cam_restored("fire-free", stage)
	check("fire-free: time_scale restored on exit-tree", true,
			is_equal_approx(Engine.time_scale, 1.0))
	await _teardown_stage(stage)


## ── HERALDIC TINCTURE (src/env/banner.gd) ─────────────────────────────────
## The sigil's field is re-dyed to contrast the cloth it flies on. Critic
## defect P5: Winterfang's white chevron measured 1.99:1 inside its own
## shield on its own cream banner and vanished at hall distance, while
## Goldclaw's gold sun read at 3.15:1 on crimson. These are the pure halves
## of that fix, so a future re-tune cannot silently invert the rule.
func _test_heraldic_tincture() -> void:
	const Banner := preload("res://src/env/banner.gd")
	var pale := Color("#8d99a6")        # Winterfang primary — light cloth
	var crimson := Color("#8e1f2c")     # Goldclaw primary — dark cloth
	var snow := Color("#eef2f5")        # Winterfang secondary — very light
	var pale_field: Color = Banner.field_tincture(pale)
	var crimson_field: Color = Banner.field_tincture(crimson)
	check("tincture: a light cloth takes a DEEP field", true,
			Banner.luminance(pale_field) < Banner.luminance(pale))
	check("tincture: a dark cloth takes a PALE field", true,
			Banner.luminance(crimson_field) > Banner.luminance(crimson))
	check("tincture: the deep field clears 2.5:1 on its own cloth", true,
			Banner.contrast_ratio(pale, pale_field) >= 2.5)
	check("tincture: the pale field clears 2.5:1 on its own cloth", true,
			Banner.contrast_ratio(crimson, crimson_field) >= 2.5)
	check("tincture: the whitest cloth in the registry still clears 2.5:1", true,
			Banner.contrast_ratio(snow, Banner.field_tincture(snow)) >= 2.5)
	# Hue is the house: a deepened field keeps the cloth's own colour.
	check("tincture: the deep field keeps the cloth's hue", true,
			absf(pale_field.h - pale.h) < 0.02)
	check("contrast_ratio: identical colours read 1.0", true,
			absf(Banner.contrast_ratio(pale, pale) - 1.0) < 0.001)
	check("contrast_ratio: black on white is the 21:1 maximum", true,
			absf(Banner.contrast_ratio(Color.BLACK, Color.WHITE) - 21.0) < 0.1)


## ── THE HALL'S BANNER STATIONS (src/env/great_hall.gd) ────────────────────
## THE INDEX MAP IS A CONTRACT, NOT A CONVENIENCE. The e2e boot scenario reads
## banner 3 as "the west wall centre flies the player's PRIMARY" and the
## tournament scenario reads banner 6 as the rival's primary, every round. The
## table may be appended to; rows 0..8 may never move. This is the literal
## guard on that, kept here rather than in the e2e so a renumber fails in
## two headless seconds instead of a windowed suite.
func _test_hall_banner_stations() -> void:
	const Hall := preload("res://src/env/great_hall.gd")
	var st: Array = Hall.STATIONS
	check("stations: the table is append-only (>= the original nine)", true,
			st.size() >= 9)
	# Rows 0..8, spelled out. If a future edit renumbers them this is the line
	# that goes red — not a screenshot three scenarios later.
	var original := [
		[Vector3(-4.0, -0.3, 12.0), PI, Hall.HOUSE_SELF, "primary"],
		[Vector3(0.0, -0.3, 12.0), PI, Hall.HOUSE_SELF, "accent"],
		[Vector3(4.0, -0.3, 12.0), PI, Hall.HOUSE_RIVAL, "primary"],
		[Vector3(-12.0, -0.3, -4.0), PI * 0.5, Hall.HOUSE_SELF, "primary"],
		[Vector3(-12.0, -0.3, 0.0), PI * 0.5, Hall.HOUSE_SELF, "secondary"],
		[Vector3(-12.0, -0.3, 4.0), PI * 0.5, Hall.HOUSE_SELF, "accent"],
		[Vector3(12.0, -0.3, -4.0), -PI * 0.5, Hall.HOUSE_RIVAL, "primary"],
		[Vector3(12.0, -0.3, 0.0), -PI * 0.5, Hall.HOUSE_RIVAL, "secondary"],
		[Vector3(12.0, -0.3, 4.0), -PI * 0.5, Hall.HOUSE_RIVAL, "accent"],
	]
	var moved := ""
	for i in original.size():
		var a: Array = original[i]
		var b: Array = st[i]
		if not ((a[0] as Vector3).is_equal_approx(b[0] as Vector3) \
				and is_equal_approx(a[1] as float, b[1] as float) \
				and is_equal_approx(b[2] as float, 1.0) \
				and int(a[2]) == int(b[3]) and str(a[3]) == str(b[4])):
			moved += " %d" % i
	check("stations: the original nine are exactly where they were", "", moved)
	check("stations: 3 is the player's PRIMARY (the boot e2e reads it)", true,
			int(st[3][3]) == Hall.HOUSE_SELF and str(st[3][4]) == "primary")
	check("stations: 6 is the rival's PRIMARY (the tournament e2e reads it)", true,
			int(st[6][3]) == Hall.HOUSE_RIVAL and str(st[6][4]) == "primary")
	# THE SEAM IS x = 0. Cloth west of the throne is the player's, east of it
	# the rival's; only the two centre stations sit on the line itself.
	var wrong_side := ""
	var tables: Array = [st, Hall.DRAPES_THIN, Hall.DRAPES_TRIPLE]
	var side_at: Array = [3, 2, 2]
	for t in tables.size():
		var rows: Array = tables[t]
		for i in rows.size():
			var row: Array = rows[i]
			var x: float = (row[0] as Vector3).x
			var side := int(row[side_at[t]])
			if absf(x) > 0.01 and (x < 0.0) != (side == Hall.HOUSE_SELF):
				wrong_side += " t%d:%d" % [t, i]
	check("stations: every banner is on its own house's side of the seam",
			"", wrong_side)
	var bad_tone := ""
	for t in tables.size():
		var rows: Array = tables[t]
		for i in rows.size():
			if not str((rows[i] as Array)[side_at[t] + 1]) in \
					["primary", "secondary", "accent"]:
				bad_tone += " t%d:%d" % [t, i]
	check("stations: every row names a real heraldic tone", "", bad_tone)


## ── THE HALL IS DRESSED WHERE THE PLAYER LOOKS ────────────────────────────
## Owner's report, 2026-08-09: "make sure that we see the banners all over the
## dungeon". The nine original stations were hung for a camera nobody plays
## from — reproduced below with the REAL gameplay rig (pivot y 0.4, pitch
## -0.85, distance 11.5, fov 50), exactly none of their nine sigils projected
## inside the frame, which is why 02_boot_lineup.png read as bare stone.
##
## This is that measurement, run in two headless seconds against
## Camera3D.unproject_position instead of against a screenshot. It fails if a
## future re-hang pushes the pillar heroes back out of the player's frame.
func _test_hall_banner_frame() -> void:
	const Hall := preload("res://src/env/great_hall.gd")
	const Banner := preload("res://src/env/banner.gd")
	# A SubViewport at the SHIPPED resolution, never `root`: headless gives the
	# root window a SQUARE 1920x1920 rect, and on a square frame the horizontal
	# half-angle collapses from 39.6 to 25 degrees — every side-wall banner
	# falls out of a frustum it is comfortably inside on a real 16:9 display.
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	root.add_child(vp)
	var rig := Node3D.new()
	vp.add_child(rig)
	rig.position = Vector3(0.0, 0.4, 0.0)      # game.tscn CameraRig
	rig.rotation = Vector3(-0.85, PI, 0.0)     # orbit_camera.gd defaults
	var cam := Camera3D.new()
	rig.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 11.5)
	cam.fov = 50.0
	cam.current = true
	await process_frame
	var size := Vector2(vp.size)
	check("frame: the probe camera really is the shipped 16:9 frame", true,
			absf(size.x / size.y - 16.0 / 9.0) < 0.001)
	var in_frame: Array = []
	for i in Hall.STATIONS.size():
		var st: Array = Hall.STATIONS[i]
		var s := st[2] as float
		# The sigil quad's own local offset, yawed onto the wall it hangs on.
		var local := Vector3(0.0, Banner.SIGIL_CENTER_Y * s, Banner.SIGIL_Z * s)
		var world: Vector3 = (st[0] as Vector3) \
				+ Basis(Vector3.UP, st[1] as float) * local
		if not cam.is_position_in_frustum(world):
			continue
		var p: Vector2 = cam.unproject_position(world)
		# Half a sigil of margin: a centre one pixel inside the edge is not a
		# banner the player can see.
		var margin: float = 0.5 * Banner.SIGIL_SIZE * s / (2.0 \
				* tan(deg_to_rad(cam.fov) * 0.5) \
				* cam.global_position.distance_to(world)) * size.y
		if p.x >= margin and p.x <= size.x - margin \
				and p.y >= margin and p.y <= size.y - margin:
			in_frame.append(i)
	print("    [banner-frame] stations whose whole sigil clears the gameplay "
			+ "frame: %s (of %d)" % [str(in_frame), Hall.STATIONS.size()])
	check("frame: the west pillar hero (11) is in the player's frame", true,
			in_frame.has(11))
	check("frame: the east pillar hero (12) is in the player's frame", true,
			in_frame.has(12))
	check("frame: the side-wall pennants (15,16) are in the player's frame",
			true, in_frame.has(15) and in_frame.has(16))
	check("frame: the hall shows the player at least four sigils", true,
			in_frame.size() >= 4)
	# The original nine were hung for a camera nobody plays from. Kept as a
	# measurement, not a wish: if a re-hang ever brings them into the gameplay
	# frame that is a WIN, and this line is the one to delete.
	var old_nine := 0
	for i in in_frame:
		if int(i) < 9:
			old_nine += 1
	print("    [banner-frame] of the original nine, %d are in the gameplay frame"
			% old_nine)
	vp.queue_free()
	await process_frame


## ── THE WHOLE HALL WEARS THE MATCHUP (live GreatHall) ─────────────────────
## Builds the real hall headless and dresses it, so the API the integrator
## calls is exercised end to end: stations get sigils AND cloth, the
## sigil-less drapes get the same two palettes, and — the hard one — the
## torch-lit hall still holds exactly EIGHT omni lights. The Mobile renderer
## caps a mesh at 8 omnis; a banner that ever "sells" itself with a Light3D
## silently drops a torch off the far wall instead.
func _test_hall_dressing() -> void:
	const Hall := preload("res://src/env/great_hall.gd")
	var hall = Hall.new()
	root.add_child(hall)
	await process_frame
	check("hall: one banner per station", Hall.STATIONS.size(), hall.banners.size())
	check("hall: the drapes are carried on 2 MultiMeshes, not 24 nodes", 2,
			_multimesh_drape_count(hall))
	check("hall: the hall's own Light3D census is 8 torches + 2 fills", 10,
			hall.find_children("*", "Light3D", true, false).size())
	check("hall: exactly 8 omni lights (the Mobile renderer's whole budget)",
			8, _omni_count(hall))
	hall.dress_for_match("winterfang", "goldclaw")
	var pc: Dictionary = HouseRegistry.get_colors("winterfang")
	var rc: Dictionary = HouseRegistry.get_colors("goldclaw")
	check("hall: banner 3 flies the player's primary (the boot e2e assert)",
			true, hall.get_banner(3).house_color.is_equal_approx(pc["primary"]))
	check("hall: banner 6 flies the rival's primary (the tournament assert)",
			true, hall.get_banner(6).house_color.is_equal_approx(rc["primary"]))
	check("hall: banner 3 flies the player's SIGIL too", "winterfang",
			hall.get_banner(3).house_id)
	check("hall: banner 6 flies the rival's SIGIL too", "goldclaw",
			hall.get_banner(6).house_id)
	var sigil_less := 0
	for b in hall.banners:
		if not b.has_sigil():
			sigil_less += 1
	check("hall: every station hangs a sigil after the dressing", 0, sigil_less)
	# The drapes are cloth-only, but they must wear the same two hauses.
	# Read from the hall's own record, NOT from MultiMesh.get_instance_color:
	# instance data lives in the RenderingServer and the headless dummy server
	# hands back an empty buffer — colours AND transforms alike — so an assert
	# taken off the MultiMesh here would be measuring the renderer's absence.
	var undyed := 0
	var seen := {}
	var drape_n := 0
	for group in hall.get("_drapes"):
		for c in (group["colors"] as PackedColorArray):
			drape_n += 1
			if c.is_equal_approx(HallBanner.NEUTRAL):
				undyed += 1
			seen[c.to_html(false)] = true
	check("hall: the dressing reaches every drape", 18, drape_n)
	check("hall: no drape is left undyed by the dressing", 0, undyed)
	check("hall: the drapes fly BOTH hauses, not one", true, seen.size() >= 2)
	# The throne shot: the whole room falls to one house, drapes included.
	hall.dress_for_champion("goldclaw")
	var not_champion := 0
	for b in hall.banners:
		if b.house_id != "goldclaw":
			not_champion += 1
	check("champion: every station falls to the champion", 0, not_champion)
	var champ_only := true
	for group in hall.get("_drapes"):
		for c in (group["colors"] as PackedColorArray):
			if not (c.is_equal_approx(rc["primary"]) \
					or c.is_equal_approx(rc["secondary"]) \
					or c.is_equal_approx(rc["accent"])):
				champ_only = false
	check("champion: every drape falls to the champion too", true, champ_only)
	# set_banner_colors is COLOUR ONLY — a re-dye may never strike a sigil.
	hall.set_banner_colors([Color.RED, Color.GREEN, Color.BLUE])
	check("set_banner_colors: dyes in index order", true,
			hall.get_banner(1).house_color.is_equal_approx(Color.GREEN))
	check("set_banner_colors: leaves the sigil flying", true,
			hall.get_banner(1).has_sigil() and hall.get_banner(1).house_id == "goldclaw")
	hall.queue_free()
	await process_frame


func _multimesh_drape_count(hall: Node) -> int:
	var n := 0
	for child in hall.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with("Drapes"):
			n += 1
	return n


func _omni_count(node: Node) -> int:
	var n := 1 if node is OmniLight3D else 0
	for child in node.get_children():
		n += _omni_count(child)
	return n


## ── THE CAPTION CLEARS ITS SUBJECT (src/cinematics/cine_caption.gd) ───────
## Critic defect P2b: the "ASHFALL." plate landed square on the crowned king
## on the dais in the throne-room frame. The plate now slides. This drives
## the solver with the EXACT geometry measured off that frame (subjects at
## screen x 918 and 958, a 228 px plate in a 1920 px frame) — the case a
## one-subject-at-a-time push could not solve, because clearing the second
## subject threw the plate back across the first.
func _test_caption_clears_its_subject() -> void:
	const Caption := preload("res://src/cinematics/cine_caption.gd")
	var vp := root
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.0, 1.0, -6.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var label := Label.new()
	label.text = "ASHFALL."
	label.add_theme_font_size_override("font_size", 34)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = -160.0
	label.offset_bottom = -96.0
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(label)
	await process_frame
	await process_frame
	var size := vp.get_visible_rect().size
	# A subject standing low and centred, right where the plate lives.
	var subject := Vector3(0.0, 0.0, 0.0)
	var s: Vector2 = cam.unproject_position(subject)
	var half: float = label.get_global_rect().size.x * 0.5 + 90.0 + 34.0
	var dx: float = Caption.clear_offset(label, 0.0, [subject], vp)
	var in_frame := s.y >= size.y * 0.5
	check("caption: the probe subject really is in the lower half", true, in_frame)
	check("caption: the plate slides clear of a subject under it", true,
			absf((size.x * 0.5 + dx) - s.x) >= half - 1.0)
	check("caption: it stays inside the frame", true,
			size.x * 0.5 + dx - label.get_global_rect().size.x * 0.5 >= 0.0 \
			and size.x * 0.5 + dx + label.get_global_rect().size.x * 0.5 <= size.x)
	# TWO subjects a little apart — the case the greedy push could not solve.
	var second := Vector3(0.55, 0.0, 0.6)
	var s2: Vector2 = cam.unproject_position(second)
	var dx2: float = Caption.clear_offset(label, 0.0, [subject, second], vp)
	var c2: float = size.x * 0.5 + dx2
	check("caption: two subjects at once — clears BOTH", true,
			absf(c2 - s.x) >= half - 1.0 and absf(c2 - s2.x) >= half - 1.0)
	# Nothing to avoid = dead centre, the default look.
	check("caption: no subject leaves it centred", true,
			absf(Caption.clear_offset(label, 40.0, [], vp)) < 0.001)
	# A subject high in the frame is not under a lower-third plate.
	var high := Vector3(0.0, 4.0, 0.0)
	check("caption: a subject in the upper half never moves it", true,
			absf(Caption.clear_offset(label, 0.0, [high], vp)) < 0.001)
	cam.queue_free()
	layer.queue_free()
	await process_frame
