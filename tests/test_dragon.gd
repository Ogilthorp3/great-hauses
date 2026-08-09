extends SceneTree

# Headless unit tests for the DRAGON SPECTATOR + ASHFALL module — focused on
# the module's hard contracts:
#   - THE WYRM SLEEPS: it rests coiled on the ground, a stir never fully
#     wakes it, and only checkmate does (rest -> stir -> wake -> burn)
#   - reaction rate limit (max 1 per 2 moves) + the duel-cam gate
#   - ASHFALL Engine.time_scale hygiene on EVERY exit path (normal end,
#     skip, spectator freed mid-sequence)
#   - loser-piece cleanup is complete (explicit list AND duck-scan), and
#     the king / winners are never touched
#   - NO Light3D node is added by any module code path (asserted by
#     counting the whole tree before/after) — including the wake, whose
#     "the eyes light" is emissive coals and nothing else
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_dragon.gd
# Exit code 0 = all green, 1 = failures.

const Spectator := preload("res://src/cinematics/dragon_spectator.gd")
const Rig := preload("res://src/cinematics/dragon_rig.gd")
const DD := preload("res://src/cinematics/duel_director.gd")
const GH := preload("res://src/env/great_hall.gd")

var failures := 0
var checks_run := 0

## A hard-erroring test function aborts silently at the error and its await
## resumes as if it finished — the floor turns silent aborts into a loud
## failure (same guard as test_cinematics.gd).
const MIN_EXPECTED_CHECKS := 225

## THE SERPENT-WYRM CONTRACT (dragon-v2, installed 2026-08-09). Asserted
## against the names GODOT ends up with, never the ones the GLB was authored
## with: the importer silently strips a trailing _Cycle/_Loop, so the asset's
## `Flap_Cycle` arrives as `Flap`, and a suite that trusted the Blender-side
## name would pass while the game called a clip that does not exist.
const REQUIRED_CLIPS: Array[String] = [
	"Flying_Idle", "Fast_Flying", "Headbutt", "Rear_Breathe",
	"Perch_Idle", "Glide", "Land_Settle", "Roar", "HitReact", "Yes", "No",
]


class Duck:
	extends Node3D
	## Minimal PieceView-shaped piece (the duck fields the module reads),
	## with a real material so the char/incineration path executes.
	var piece_type := 0
	var side := 0
	var house_id := ""

	func _init(pt: int = 0, s: int = 0, house: String = "") -> void:
		piece_type = pt
		side = s
		house_id = house
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
	print("=== Great Hauses — dragon spectator/ashfall headless suite ===")
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	var lights_before := _light_count()
	_test_kill_lines()
	_test_ceremony_budgets()
	_test_origin_moved()
	await _test_slumber_pose()
	await _test_rest_and_stir()
	await _test_the_wake()
	await _test_rig_contract()
	await _test_fire_wiring()
	await _test_rate_limit_and_gate()
	await _test_ashfall_completion()
	await _test_ashfall_duck_scan()
	await _test_ashfall_skip()
	await _test_ashfall_free_restore()
	await _test_skeleton_swap()
	await _test_tidegrip_chars_in_place()
	await _test_ashfall_mounted_knight()
	await _test_skip_every_phase()
	await _test_championship_tier()
	await _test_match_defaults_budget()
	await _test_phase_and_jet_probes()
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
	s.ash_stir_wall = 0.08
	s.ash_rise_wall = 0.1
	s.ash_roar_wall = 0.12
	s.ash_ramp_wall = 0.05
	s.ash_bank_wall = 0.2
	s.ash_flare_wall = 0.08
	s.ash_inhale_wall = 0.06
	s.ash_swoop_wall = 0.15
	s.ash_breath_wall = 0.3
	s.ash_linger_wall = 0.12
	s.ash_return_wall = 0.1
	s.ash_settle_wall = 0.1
	s.ash_flash_wall = 0.03
	s.ash_smolder_wall = 0.08
	s.ash_collapse_wall = 0.08
	s.ash_char_wall = 0.05
	s.ash_crumble_wall = 0.05
	s.failsafe_wall_sec = 6.0
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


## ── THE WYRM SLEEPS ───────────────────────────────────────────────────────
## The dramatic fault this suite now guards: a dragon that spends the match
## already airborne has nowhere to escalate to at checkmate. These check the
## resting STATE (not just that some numbers exist) — the pose is measured
## out of the skeleton, and the rest spot is checked against the real
## gameplay camera's geometry rather than eyeballed.


## The coil must actually move bones, and it must move them the right way.
## Sampled from INSIDE the modifier stack: Godot restores the animation pose
## the moment the stack finishes, so a coil that never touched a vertex reads
## identically to one that did from _process (learned the hard way).
func _test_slumber_pose() -> void:
	var s := _fast_spectator()
	await process_frame
	await process_frame
	var coil = s.get("_slumber")
	check("slumber: the coil is attached to the skeleton", true, coil != null)
	check("slumber: it bends the neck, head, tail and legs", true,
			coil != null and coil.bend_count() >= 20)
	check("slumber: asleep at rest", true, s.is_asleep())
	check("slumber: full weight at rest", true,
			is_equal_approx(s.slumber_weight(), 1.0))
	# Measure the coiled pose against the standing clip pose.
	coil.sample_bones = ["Head", "Head_end", "Chest", "Tail6", "Toe.L"]
	await process_frame
	await process_frame
	var down: Dictionary = (coil.sampled as Dictionary).duplicate()
	coil.weight = 0.0
	await process_frame
	await process_frame
	var up: Dictionary = (coil.sampled as Dictionary).duplicate()
	coil.weight = 1.0
	check("slumber: sampled inside the stack (both poses read)", true,
			down.has("Head") and up.has("Head"))
	if down.has("Head") and up.has("Head"):
		check("slumber: the head comes DOWN a body's height", true,
				(up["Head"] as Vector3).y - (down["Head"] as Vector3).y > 1.0)
		check("slumber: the snout ends near the stone (y=%.2f)"
				% (down["Head_end"] as Vector3).y, true,
				(down["Head_end"] as Vector3).y < 0.55)
		# ── SLEEPING ANIMALS FOLD ──────────────────────────────────────────
		# This pair replaced "the snout stays FORWARD of the head", which was
		# the previous pose's contract and is exactly what an art critic
		# rejected: a level skull at the end of an EXTENDED neck reads as a
		# shed skin, not a sleeping animal ("a dead lizard", 2026-08-09). The
		# head measured 1.37 out from the chest — ~150 px of bare neck on the
		# shipped gameplay frame. It now folds back to the flank at 0.67, and
		# the guard is that distance: a future re-tune that straightens the
		# neck out again fails here instead of on somebody's eye.
		var fold: float = ((down["Head"] as Vector3)
				- (down["Chest"] as Vector3)).length()
		check("slumber: the head folds BACK to the flank (%.2f from the chest)"
				% fold, true, fold < 0.85)
		# …and the fold must not roll the skull under: the muzzle sits at or
		# below the head origin exactly as it does in the standing clip.
		check("slumber: the skull stays upright (muzzle below the head origin)",
				true, (down["Head_end"] as Vector3).y < (down["Head"] as Vector3).y)
		# THE JAWS ARE SHUT. `Perch_Idle` never writes the Jaw bone, so parted
		# jaws would stay parted for the whole match; the coil closes them,
		# and the closing direction is a POSITIVE local X (see slumber_table).
		var jaw_shut := false
		for e: Array in Rig.slumber_default():
			if str(e[0]) == Rig.JAW_BONE:
				jaw_shut = (e[1] as Vector3).x > 0.0
		check("slumber: the coil CLOSES the jaws", true, jaw_shut)
		check("slumber: the tail is curled around the flank, not trailing", true,
				absf((down["Tail6"] as Vector3).x) > 0.6)
		check("slumber: the tail lies on the floor", true,
				(down["Tail6"] as Vector3).y < 0.45)
		check("slumber: the haunches couch (the claws lift, so the node sinks)",
				true, (down["Toe.L"] as Vector3).y - (up["Toe.L"] as Vector3).y > 0.2)
		check("slumber: the node sinks by what the couch lifted", true,
				absf((down["Toe.L"] as Vector3).y - (up["Toe.L"] as Vector3).y
					- Rig.SLUMBER_ROOT_DROP) < 0.06)
	s.free()
	await process_frame


## Rest geometry against the REAL gameplay camera (game.tscn: pivot
## (0, 0.4, 0), yaw PI, pitch -0.85, fov 50, 16:9) and the real hall.
## A resting spot is only "beside the board, clear of the orbit ring" if the
## numbers say so from the seat the player actually sits in.
func _test_rest_and_stir() -> void:
	var s: DragonSpectator = Spectator.new()
	var rest: Vector3 = s.rest_position
	check("rest: on the hall floor, not in the air", true,
			absf(rest.y - (-0.3)) < 0.01)
	check("rest: outside the 8-unit board", true, absf(rest.x) > 4.6)
	check("rest: inside the walls and clear of the feast table at x 9", true,
			absf(rest.x) < 8.2 and absf(rest.z) < 8.0)
	# THE ORBIT RING, solved rather than sampled. OrbitCamera puts the eye at
	# horizontal radius d*cos(pitch) and height 0.4 + d*sin|pitch|; the pitch
	# clamp is -1.35..-0.12 and the zoom is a 1.12 geometric ladder from 11.5
	# between 4 and 13. So for each REACHABLE zoom step, the moment the ring's
	# radius equals the wyrm's, the eye is exactly 0.4 + sqrt(d^2 - r^2) up —
	# and the coiled wyrm stands ~1.1 m. The tightest case is the 7.31 zoom
	# step at the shallowest pitch, and it still clears by over a metre.
	var radius: float = Vector2(rest.x, rest.z).length()
	var worst_cam_y := 99.0
	var dists: Array[float] = []
	for k in range(-6, 4):
		var d: float = 11.5 * pow(1.12, float(k))
		if d >= 4.0 and d <= 13.0:
			dists.append(d)
	for dist in dists:
		var c: float = radius / dist
		if c > cos(0.12) or c < cos(1.35):
			continue   # this zoom step can never sit at the wyrm's radius
		worst_cam_y = minf(worst_cam_y, 0.4 + sqrt(dist * dist - radius * radius))
	check("rest: the orbit ring always clears the sleeper (closest %.2f m up)"
			% worst_cam_y, true, worst_cam_y >= 2.2)
	# …and it is IN FRAME from the default camera, on the board's flank.
	var cam := Vector3(0.0, 0.4, 0.0) + Vector3(0.0, 8.638, -7.590)
	var fwd := Vector3(0.0, -0.7513, 0.6600)
	var right := Vector3(-1.0, 0.0, 0.0)
	var up := Vector3(0.0, 0.6600, 0.7513)
	var v: Vector3 = rest - cam
	var depth: float = v.dot(fwd)
	var sx: float = 0.5 * (1.0 + (v.dot(right) / depth) / 0.8290)
	var sy: float = 0.5 * (1.0 - (v.dot(up) / depth) / 0.4663)
	check("rest: in frame from the default camera", true,
			sx > 0.05 and sx < 0.95 and sy > 0.05 and sy < 0.95)
	check("rest: off the board's flank, not over it (screen x %.2f < 0.30)" % sx,
			true, sx < 0.30)
	check("rest: and it is not hiding in a corner (screen y %.2f mid-frame)" % sy,
			true, sy > 0.25 and sy < 0.75)
	s.free()

	# THE STIR: a capture disturbs the sleeper; it must NEVER wake it.
	var sp := _fast_spectator()
	await process_frame
	check("stir: asleep before anything happens", true, sp.is_asleep())
	check("stir: a capture is allowed", true, sp.react_capture(Vector3(1.0, 0.0, 1.0)))
	check("stir: it plays the flinch", "HitReact", sp.rig.anim.assigned_animation)
	var floor_w: float = sp.stir_slumber_floor
	var lowest := {"v": 1.0}
	var sampler := func() -> void:
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(sp) and Time.get_ticks_msec() - t0 < 2500:
			lowest["v"] = minf(lowest["v"], sp.slumber_weight())
			await process_frame
	sampler.call()
	await _wait_wall(2.6)
	check("stir: the coil DID ease (the head came up)", true, lowest["v"] < 0.95)
	check("stir: but it never fully woke for a capture", true,
			lowest["v"] >= floor_w - 0.02)
	check("stir: still asleep after", true, sp.is_asleep())
	var settled: bool = await _wait_until(
			func() -> bool: return sp.slumber_weight() > 0.9, 3.0)
	check("stir: it settles back into the coil", true, settled)
	check("stir: back on Perch_Idle", "Perch_Idle", sp.rig.anim.assigned_animation)
	sp.free()
	await process_frame


## THE WAKE — the beat the whole match builds to. Order is the contract:
## the head comes up and the coals kindle, it hauls itself up, it ROARS on
## the ground, and only THEN the wings move. A roar that lands after the
## wings is the same dramatic failure as a dragon that was already flying.
func _test_the_wake() -> void:
	var lights_before := _light_count()
	var s := _fast_spectator()
	s.ash_stir_wall = 0.25
	s.ash_rise_wall = 0.3
	s.ash_roar_wall = 0.4
	await process_frame
	var losers := _spawn_army(1, 3, 1.5)
	var seen: Array[String] = []
	var clips: Dictionary = {}
	var ember := {"lo": 99.0, "hi": 0.0}
	var awake_at := {"v": ""}
	check("wake: the coals are BANKED while it sleeps", true,
			is_equal_approx(float(s.get("_ember")), s.rest_ember_energy))
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", losers)
	runner.call()
	var sampler := func() -> void:
		while is_instance_valid(s) and s.is_ashfall_active():
			var ph: String = s.ashfall_phase()
			if not ph.is_empty() and (seen.is_empty() or seen[-1] != ph):
				seen.append(ph)
			if not clips.has(ph):
				clips[ph] = s.rig.anim.assigned_animation
			var e := float(s.get("_ember"))
			ember["lo"] = minf(ember["lo"], e)
			ember["hi"] = maxf(ember["hi"], e)
			if awake_at["v"].is_empty() and s.slumber_weight() < 0.02:
				awake_at["v"] = ph
			await process_frame
	sampler.call()
	var done: bool = await _wait_until(func() -> bool: return not s.is_ashfall_active(), 12.0)
	check("wake: ceremony completed", true, done)
	check("wake: the first beat of the ceremony IS the wake", "wake",
			seen[0] if not seen.is_empty() else "<none>")
	var i_roar := seen.find("roar")
	var i_bank := seen.find("bank")
	check("wake: it roars", true, i_roar >= 0)
	check("wake: THE ROAR LANDS BEFORE THE WINGS", true,
			i_roar >= 0 and i_bank > i_roar)
	check("wake: the roar phase plays the Roar clip", "Roar", clips.get("roar", "<none>"))
	check("wake: the wake phase does NOT flap", true,
			clips.get("wake", "") != "Fast_Flying")
	check("wake: the wings only come out for the bank", "Fast_Flying",
			clips.get("bank", "<none>"))
	check("wake: it was fully awake by the roar, not before the stir", true,
			awake_at["v"] == "wake" or awake_at["v"] == "roar")
	check("wake: the coals KINDLE (eyes light, emissive only)", true,
			ember["hi"] >= s.wake_ember_energy - 0.01)
	check("wake: and they were banked at the start", true,
			ember["lo"] <= s.rest_ember_energy + 0.01)
	check("wake: NO Light3D anywhere on the wake path", lights_before, _light_count())
	# …and afterwards it goes back to sleep on the same stone.
	await process_frame
	check("wake: back on the resting stone", true, _perched(s, s.rest_position))
	var recoiled: bool = await _wait_until(
			func() -> bool: return s.slumber_weight() > 0.9, 4.0)
	check("wake: it re-coils into slumber after the burn", true, recoiled)
	check("wake: asleep again", true, s.is_asleep())
	check("wake: the coals are banked again", true,
			float(s.get("_ember")) <= s.rest_ember_energy + 0.01)
	s.free()
	await process_frame


func _test_kill_lines() -> void:
	check("lines: pool present", true, Spectator.ASHFALL_LINES.size() >= 3)
	var all_have_token := true
	for l in Spectator.ASHFALL_LINES:
		if not str(l).contains("{wh}"):
			all_have_token = false
	check("lines: every line carries {wh}", true, all_have_token)
	var out := DD.format_line("What {wh} cannot rule, it burns.", {"wh": "Haus Winterfang"})
	check("lines: format substitutes", "What Haus Winterfang cannot rule, it burns.", out)


func _test_rate_limit_and_gate() -> void:
	var s := _fast_spectator()
	await process_frame
	check("rig: dragon spawned", true, s.rig != null and s.rig.anim != null)
	check("rig: idles on Perch_Idle (not a hover)", "Perch_Idle",
			s.rig.anim.assigned_animation)

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
	await s.play_ashfall(1, "Haus Winterfang", losers)
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
		await s.play_ashfall(1, "Haus Winterfang", losers)
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


func _perched(s: DragonSpectator, home: Vector3) -> bool:
	## The roost bob moves y each frame — compare xz exactly, y within bob.
	var dp: Vector3 = s.position - home
	return absf(dp.x) < 0.01 and absf(dp.z) < 0.01 \
		and absf(dp.y) <= s.bob_amplitude + 0.02


func _test_ceremony_budgets() -> void:
	## Static arithmetic on the DEFAULT exported phase walls; worst case
	## includes the linger's bounded +1.2 s wait and both caption beats.
	## The slow-mo dip is NOT in the sum: it rides the wake's stir beat.
	var s: DragonSpectator = Spectator.new()   # never enters the tree
	var wake: float = s.ash_stir_wall + s.ash_rise_wall + s.ash_roar_wall
	check("budget: the wake is a real beat, not a flourish (>= 2 s)", true, wake >= 2.0)
	check("budget: the wake fits inside 3 s", true, wake <= 3.0)
	check("budget: the roar owns its own phase before the wings", true,
			s.ash_roar_wall >= 1.0)
	check("budget: the slow-mo dip rides the stir (costs no phase)", true,
			s.ash_ramp_wall <= s.ash_stir_wall)
	var match_worst: float = wake + s.ash_bank_wall + s.ash_flare_wall \
		+ s.ash_inhale_wall + s.ash_breath_wall + s.ash_linger_wall + 1.2 \
		+ s.ash_return_wall
	check("budget: match ceremony defaults <= 13 s", true, match_worst <= 13.0)
	var champ_worst: float = match_worst - s.ash_return_wall + s.ash_swoop_wall \
		+ s.ash_settle_wall + 0.4 + 1.3
	check("budget: championship defaults <= 16 s", true, champ_worst <= 16.0)
	check("budget: the failsafe outlasts the championship worst case", true,
			s.failsafe_wall_sec > champ_worst)
	check("budget: throne perch synced with the hall", true,
			Spectator.THRONE_PERCH == GH.DRAGON_HOVER)
	check("budget: champ scale matches the hall dragon", true,
			is_equal_approx(s.champ_scale, GH.DRAGON_SCALE))
	s.free()


func _test_skeleton_swap() -> void:
	## MORTAL-KOMBAT incineration: mid-sequence a charred skeleton stands
	## in for each burned warrior; the field is fully cleaned by the end.
	var s := _fast_spectator()
	s.ash_smolder_wall = 0.5   # widen the smolder window for the probe
	await process_frame
	var losers := _spawn_army(1, 3, 1.5)
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", losers)
	runner.call()
	var seen: bool = await _wait_until(func() -> bool: return s.remains_count() > 0, 4.0)
	check("mk: skeletons stand in mid-sequence", true, seen)
	check("mk: remains nodes live in the tree", true,
			root.find_children("AshRemains", "", true, false).size() > 0)
	var done: bool = await _wait_until(func() -> bool: return not s.is_ashfall_active(), 8.0)
	check("mk: ceremony completed", true, done)
	await process_frame
	await process_frame
	check("mk: field fully cleaned (remains_count 0)", 0, s.remains_count())
	check("mk: no AshRemains left in the tree", 0,
			root.find_children("AshRemains", "", true, false).size())
	check("mk: all losers removed", 0, _alive(losers))
	check("mk: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	await process_frame


func _test_tidegrip_chars_in_place() -> void:
	## The Drowned Legion is already bones: no skeleton swap — they just
	## char darker and crumble (the intended joke).
	var s := _fast_spectator()
	await process_frame
	var losers: Array = []
	for i in 2:
		var d := Duck.new(i, 1, "tidegrip")
		root.add_child(d)
		d.position = Vector3(-1.0 + i * 1.2, 0.0, 1.8)
		losers.append(d)
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Tidegrip", losers)
	runner.call()
	var started: bool = await _wait_until(func() -> bool: return s.is_ashfall_active(), 2.0)
	check("tidegrip: ceremony started", true, started)
	var max_remains := 0
	var deadline := Time.get_ticks_msec() + 8000
	while s.is_ashfall_active() and Time.get_ticks_msec() < deadline:
		max_remains = maxi(max_remains, s.remains_count())
		await process_frame
	await process_frame
	await process_frame
	check("tidegrip: no skeleton swap for the bone cast", 0, max_remains)
	check("tidegrip: the legion still burns away", 0, _alive(losers))
	check("tidegrip: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	await process_frame


## ASHFALL vs the MOUNTED knight (ISSUES.md #1). The mounted knight is ONE
## PieceView carrying a whole ensemble (horse + tack + rider), so the burn
## has a failure mode no duck can expose: the rider is swapped for a foot
## warrior and his horse is left standing in the ashes. Asserted on REAL
## PieceViews, at the moment the charred bones stand AND after the sweep.
func _test_ashfall_mounted_knight() -> void:
	# piece_view.gd names the PieceAssets autoload, which a -s run never
	# instances — shim it under /root first, then load the scene.
	var assets: Node = (load("res://src/board/piece_assets.gd") as GDScript).new()
	assets.name = "PieceAssets"
	root.add_child(assets)
	var piece_scene: PackedScene = load("res://scenes/piece_view.tscn")
	var s := _fast_spectator()
	s.ash_smolder_wall = 0.6   # widen the standing-bones window for the probe
	await process_frame
	var losers: Array = []
	# a mounted knight, a foot pawn, and the Drowned Legion's mounted knight
	# (the already-bones path, which chars the ensemble in place instead)
	for spec: Array in [[2, "goldclaw"], [0, "goldclaw"], [2, "tidegrip"]]:
		var pv: Node3D = piece_scene.instantiate()
		root.add_child(pv)
		pv.setup(int(spec[0]), 1, str(spec[1]))
		pv.position = Vector3(-1.2 + losers.size() * 1.2, 0.0, 1.6)
		losers.append(pv)
	check("mounted burn: both knights ride in mounted", 2, _mount_count())
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Goldclaw", losers)
	runner.call()
	var seen: bool = await _wait_until(func() -> bool: return s.remains_count() > 0, 6.0)
	check("mounted burn: charred bones stand in mid-sequence", true, seen)
	var mounted_remains := 0
	for shell: Node in root.find_children("AshRemains", "", true, false):
		mounted_remains += shell.find_children("Horse", "MeshInstance3D", true, false).size()
	check("mounted burn: the charred stand-in walks on foot", 0, mounted_remains)
	var done: bool = await _wait_until(func() -> bool: return not s.is_ashfall_active(), 14.0)
	check("mounted burn: ceremony completed", true, done)
	await process_frame
	await process_frame
	check("mounted burn: all losers removed", 0, _alive(losers))
	check("mounted burn: NO orphan horse left in the ashes", 0, _mount_count())
	check("mounted burn: no AshRemains left in the tree", 0,
			root.find_children("AshRemains", "", true, false).size())
	check("mounted burn: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	assets.free()
	await process_frame


## Horses standing anywhere in the tree (the hide mesh — one per mount).
func _mount_count() -> int:
	return root.find_children("Horse", "MeshInstance3D", true, false).size()


func _test_skip_every_phase() -> void:
	## Click-skip from EVERY phase of both tiers: clock restored, field
	## clean (smoking skeletons included), tier end pose and scale.
	for delay: float in [0.02, 0.15, 0.35, 0.55, 0.8]:
		var s := _fast_spectator()
		s.ash_smolder_wall = 0.5   # keep skeletons alive into the skip window
		await process_frame
		var losers := _spawn_army(1, 3, 1.5)
		var runner := func() -> void:
			await s.play_ashfall(1, "Haus Winterfang", losers)
		runner.call()
		await _wait_wall(delay)
		s.skip()
		await process_frame
		await process_frame
		check("skip@%.2f: time_scale restored" % delay, true,
				is_equal_approx(Engine.time_scale, 1.0))
		check("skip@%.2f: losers removed" % delay, 0, _alive(losers))
		check("skip@%.2f: remains cleaned" % delay, 0, s.remains_count())
		check("skip@%.2f: match end scale" % delay, true,
				is_equal_approx(s.rig.scale.x, s.dragon_scale))
		check("skip@%.2f: back on the resting stone" % delay, true,
				_perched(s, s.rest_position))
		check("skip@%.2f: snapped straight back into the coil" % delay, true,
				is_equal_approx(s.slumber_weight(), 1.0))
		check("skip@%.2f: inactive" % delay, false, s.is_ashfall_active())
		s.free()
		await process_frame
	for delay: float in [0.3, 0.7, 1.1, 1.9]:
		var s2 := _fast_spectator()
		await process_frame
		var losers2 := _spawn_army(1, 2, 1.5)
		var runner2 := func() -> void:
			await s2.play_ashfall(1, "Haus Winterfang", losers2, true)
		runner2.call()
		await _wait_wall(delay)
		s2.skip()
		await process_frame
		await process_frame
		check("champ-skip@%.1f: time_scale restored" % delay, true,
				is_equal_approx(Engine.time_scale, 1.0))
		check("champ-skip@%.1f: losers removed" % delay, 0, _alive(losers2))
		check("champ-skip@%.1f: remains cleaned" % delay, 0, s2.remains_count())
		check("champ-skip@%.1f: throne end pose" % delay, true,
				_perched(s2, Spectator.THRONE_PERCH))
		check("champ-skip@%.1f: champ scale 1.6" % delay, true,
				is_equal_approx(s2.rig.scale.x, s2.champ_scale))
		check("champ-skip@%.1f: awake on the throne, not coiled" % delay, true,
				is_equal_approx(s2.slumber_weight(), 0.0))
		s2.free()
		await process_frame


func _test_championship_tier() -> void:
	var s := _fast_spectator()
	await process_frame
	var losers := _spawn_army(1, 3, 1.5)
	var t0 := Time.get_ticks_msec()
	await s.play_ashfall(1, "Haus Winterfang", losers, true)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	await process_frame
	await process_frame
	check("champ: completed under 6 s at test speeds", true, wall < 6.0)
	check("champ: throne perch pose", true, _perched(s, Spectator.THRONE_PERCH))
	check("champ: stays awake on the throne (no coil)", true,
			is_equal_approx(s.slumber_weight(), 0.0))
	check("champ: not asleep after a crowning", false, s.is_asleep())
	check("champ: settles at scale 1.6", true, is_equal_approx(s.rig.scale.x, s.champ_scale))
	check("champ: ember drift over the tableau", true,
			s.rig.get_node_or_null("TableauEmberDrift") != null)
	check("champ: losers removed", 0, _alive(losers))
	check("champ: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	await process_frame


func _test_match_defaults_budget() -> void:
	## The honest wall-clock gate: one full MATCH ceremony at DEFAULT
	## timings (headless — the camera phases no-op, the clock is the same).
	var s: DragonSpectator = Spectator.new()
	s.failsafe_wall_sec = 20.0
	root.add_child(s)
	await process_frame
	var losers := _spawn_army(1, 5, 1.5)
	var t0 := Time.get_ticks_msec()
	await s.play_ashfall(1, "Haus Winterfang", losers)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	print("  (default-timing match ceremony wall=%.2fs)" % wall)
	check("defaults: match ceremony <= 13 s wall", true, wall <= 13.0)
	check("defaults: scale returns to perch size", true,
			is_equal_approx(s.rig.scale.x, s.dragon_scale))
	check("defaults: time_scale restored", true, is_equal_approx(Engine.time_scale, 1.0))
	s.free()
	await process_frame


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


## THE ORIGIN MOVED (dragon-v2). Pure arithmetic on the shipped constants:
## the serpent-wyrm's Root sits ON THE GROUND between its feet instead of in
## mid-air, so every hardcoded dragon height moved by +1.15 x rig_scale. The
## invariant worth locking is not the raw numbers — it is that the BODY still
## reads at the height the ceremony was staged for. Getting this wrong buries
## the beast in the floor or parks it in the rafters, and neither shows up as
## a failing assertion anywhere else.
func _test_origin_moved() -> void:
	check("origin: BODY_RISE is the measured mass centre", true,
			is_equal_approx(Rig.BODY_RISE, 0.95))
	var s: DragonSpectator = Spectator.new()   # never enters the tree
	# body height = root + BODY_RISE * scale, per pose, vs the old rig's
	# (old_root + 2.10 * scale). Same screen height on both sides.
	var pairs := [
		["perch", s.perch_position.y, s.dragon_scale, 4.70],
		["breath hover", s.ash_hover_height, s.ceremony_scale, 0.00],
		["bank", s.bank_height, s.ceremony_scale, 3.50],
		["throne", Spectator.THRONE_PERCH.y, s.champ_scale, 2.20],
	]
	for p: Array in pairs:
		var now: float = float(p[1]) + Rig.BODY_RISE * float(p[2])
		var was: float = float(p[3]) + 2.10 * float(p[2])
		check("origin: %s body height unchanged (%.2f)" % [p[0], now], true,
				absf(now - was) < 0.02)
	check("origin: throne perch still equals the hall's hover", true,
			Spectator.THRONE_PERCH == GH.DRAGON_HOVER)
	# The hall's own perch anchor is what game.gd feeds the spectator; if the
	# two drift, the module lifts and the hall does not.
	var hall: GreatHall = GH.new()
	check("origin: spectator default matches the hall anchor", true,
			absf(hall.spectator_perch().y - s.perch_position.y) < 0.02)
	hall.free()
	# The breath playhead map: monotonic, starts at 0, and spends the whole
	# fire sweep inside the authored HELD BLAST window.
	var mono := true
	var prev := -1.0
	for i in 21:
		var t: float = Spectator._breath_clip_time(float(i) / 20.0)
		if t < prev - 0.0001:
			mono = false
		prev = t
	check("breath: clip time is monotonic", true, mono)
	check("breath: starts at the top of the clip", true,
			is_equal_approx(Spectator._breath_clip_time(0.0), 0.0))
	check("breath: jaws open exactly at the lunge hand-off", true,
			is_equal_approx(Spectator._breath_clip_time(Spectator.BREATH_LUNGE_FRAC),
				Spectator.BREATH_LUNGE_END))
	check("breath: the sweep ends on the held blast, not past it", true,
			is_equal_approx(Spectator._breath_clip_time(1.0), Spectator.BREATH_HOLD_END))
	s.free()


## The rig contract, read out of the LIVE AnimationPlayer and Skeleton3D.
func _test_rig_contract() -> void:
	var s := _fast_spectator()
	await process_frame
	check("rig: AnimationPlayer found", true, s.rig != null and s.rig.anim != null)
	for clip: String in REQUIRED_CLIPS:
		check("rig: clip '%s' exists Godot-side" % clip, true, s.rig.has_clip(clip))
	# The three deliberate aliases must stay interchangeable, or the incumbent
	# call sites silently no-op (play_once/play_loop swallow a missing clip).
	check("rig: Hover == Flying_Idle length", true,
			is_equal_approx(s.rig.clip_length("Hover"), s.rig.clip_length("Flying_Idle")))
	check("rig: Flap == Fast_Flying length", true,
			is_equal_approx(s.rig.clip_length("Flap"), s.rig.clip_length("Fast_Flying")))
	check("rig: Headbutt == Rear_Breathe length", true,
			is_equal_approx(s.rig.clip_length("Headbutt"), s.rig.clip_length("Rear_Breathe")))
	check("rig: the blast hold fits inside Rear_Breathe", true,
			s.rig.clip_length("Rear_Breathe") >= Spectator.BREATH_CLIP_END - 0.01)
	# Skeleton + the fire mount.
	check("rig: skeleton found", true, s.rig.skeleton != null)
	check("rig: Head bone", true, s.rig.skeleton.find_bone("Head") != -1)
	check("rig: Head_end bone", true, s.rig.skeleton.find_bone("Head_end") != -1)
	var mouth := s.rig.mouth_node()
	check("rig: mouth mount resolves", true, mouth != null)
	check("rig: mouth mount is offset down the head bone (not at the origin)",
			true, mouth != null and mouth.position.length() > 0.05)
	check("rig: hand-driven playhead accepted", true, s.rig.play_manual("Rear_Breathe"))
	s.rig.seek_clip(Spectator.BREATH_LUNGE_END)
	check("rig: seek parks the playhead on the blast", true,
			absf(s.rig.anim.current_animation_position - Spectator.BREATH_LUNGE_END) < 0.05)
	s.free()
	await process_frame


## The DRACARYS wiring: the kit is built lazily, mounted on the mouth, fired
## by the ceremony, and left INACTIVE with no Light3D behind it.
func _test_fire_wiring() -> void:
	var lights_before := _light_count()
	var s := _fast_spectator()
	await process_frame
	check("fire: not built before a ceremony needs it", true, s.get("_fx") == null)
	var losers := _spawn_army(1, 3, 1.5)
	var saw_fire := {"v": false}
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", losers)
	runner.call()
	var sampler := func() -> void:
		while is_instance_valid(s) and s.is_ashfall_active():
			var fx = s.get("_fx")
			if fx != null and is_instance_valid(fx) and fx.is_active():
				saw_fire["v"] = true
			await process_frame
	sampler.call()
	var done: bool = await _wait_until(func() -> bool: return not s.is_ashfall_active(), 10.0)
	check("fire: ceremony completed", true, done)
	check("fire: the torrent actually ignited", true, saw_fire["v"])
	var fx = s.get("_fx")
	check("fire: kit built and mounted", true, fx != null and is_instance_valid(fx))
	check("fire: inactive once the ceremony ends", false,
			fx != null and is_instance_valid(fx) and fx.is_active())
	check("fire: no Light3D anywhere in the kit", 0,
			(fx as Node).find_children("*", "Light3D", true, false).size() if fx != null else 0)
	s.free()
	await process_frame
	check("fire: no Light3D added by the whole fire path", lights_before, _light_count())


## ── THE INSTRUMENT HOOKS (critic defect P1, 2026-08-09) ───────────────────
## The dracarys torrent shipped, passed every unit test above, and no frame
## anywhere on disk contained one pixel of it: the e2e slept on the ENGINE
## clock the ceremony bends to 0.55, so its "mid-fire" shot landed at ~2.8 s,
## the tail of the bank, while the jet does not light until ~4.85 s. The fix
## is that a test never guesses WHEN — it asks. These are the probes it asks,
## so they can never quietly stop reporting the truth.
func _test_phase_and_jet_probes() -> void:
	var s := _fast_spectator()
	await process_frame
	check("probe: no phase before a ceremony", "", s.ashfall_phase())
	check("probe: no jet before a ceremony", false, s.is_jet_burning())
	check("probe: no tail before a ceremony", false, s.is_fire_tail_alive())
	var losers := _spawn_army(1, 3, 1.5)
	var seen := {}
	var jet_phase := {"v": ""}
	var runner := func() -> void:
		await s.play_ashfall(1, "Haus Winterfang", losers)
	runner.call()
	var sampler := func() -> void:
		while is_instance_valid(s) and s.is_ashfall_active():
			seen[s.ashfall_phase()] = true
			if s.is_jet_burning() and jet_phase["v"].is_empty():
				jet_phase["v"] = s.ashfall_phase()
			await process_frame
	sampler.call()
	var done: bool = await _wait_until(func() -> bool: return not s.is_ashfall_active(), 10.0)
	check("probe: ceremony completed", true, done)
	for beat in ["bank", "flare", "inhale", "breath", "linger"]:
		check("probe: phase '%s' was reported" % beat, true, seen.has(beat))
	check("probe: the jet only burns in the breath", "breath", jet_phase["v"])
	check("probe: phase cleared at the end", "", s.ashfall_phase())
	check("probe: the jet is out at the end", false, s.is_jet_burning())
	s.free()
	await process_frame
