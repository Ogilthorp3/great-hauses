## perf_driver.gd — screenshot-free performance harness (Great Houses).
##
## THE INSTRUMENT LIES UNTIL PROVEN OTHERWISE. This file exists because this
## project already paid for that lesson once: an e2e run that takes
## screenshots does a SYNCHRONOUS framebuffer readback
## (`get_viewport().get_texture().get_image()`) every shot — at 6K that is a
## ~100 MB GPU→CPU copy that stalls the frame to single-digit FPS. Those
## numbers were read as a game defect and "fixed" by halving the render
## resolution. So:
##
##   1. This harness takes NO screenshots in its measuring modes. `--perf-shots=1`
##      exists ONLY to reproduce the contamination on demand, as evidence
##      (mode `shots`), never as a measurement.
##   2. It clocks frames on `Time.get_ticks_usec()`, NEVER on `_process(delta)`.
##      Every cinematic in this game bends `Engine.time_scale` (0.55 for the
##      duel, 0.15 for checkmate) — a `delta`-based FPS counter reports 1/0.55
##      of the truth exactly where the player complains about smoothness.
##   3. It reports the WORST frame in each second alongside the mean. A mean
##      hides the stutter a player actually feels.
##
## It drives the REAL game through the REAL input pipeline (synthesized
## InputEvents via Input.parse_input_event), like e2e_driver.gd — the click
## calibration below is the same empirical canvas→window probe, so HiDPI and
## window stretch can never break the click math.
##
## Launch (see run_perf.sh — it is the supported entry point):
##   Godot --path <proj> --scene res://test_e2e/perf_boot.tscn \
##         --resolution WxH --position X,Y \
##         -- --perf=<mode> [--perf-label=<tag>] [--perf-timeout=<sec>]
##            [--perf-shots=1] [--perf-artifacts=<abs dir>] [--e2e-fen=<fen>]
##
## Modes:
##   perf    the regression gate: boot → Hall of Banners → match → intro →
##           idle → hover sweep → CAPTURE (duel cinematic) → AI reply →
##           quiet move → AI reply → idle. Every second is phase-tagged.
##   ablate  the same run up to the first settle, then a controlled A/B
##           sweep: one cost is switched off at a time for a fixed window and
##           switched back on, so the ranked cost list is MEASURED, not
##           suspected. Nothing is persisted — this is an instrument, not an
##           optimization.
##   shots   `perf`, deliberately contaminated with screenshots, to document
##           the trap rather than merely avoid it.
##
## Output contract (consumed by run_perf.sh and by humans):
##   PERF ENV   ...   one line: window/framebuffer/scale/vsync/renderer
##   PERF phase=<p> ...  one line per wall-clock second
##   PERF CENSUS <tag> ...  scene-graph cost census (draw calls vs surfaces)
##   PERF SCRIPT <tag> ...  which GDScript actually runs every frame
##   PERF STEP <name>   milestone reached
##   PERF DONE mode=<m> exit=<n>

extends Node

const DEFAULT_HOUSE := "winterfang"

var mode: String = ""
var label: String = ""
var timeout_sec: float = 200.0
var shots: bool = false
var artifacts_dir: String = ""

var _done := false
var _to_window: Transform2D = Transform2D.IDENTITY
var _last_input_pos := Vector2(-1e9, -1e9)
var _shot_i := 0

# ── the sampler ────────────────────────────────────────────────────────────
var _phase := ""
var _phase_t := 0            # seconds elapsed inside the current phase
var _last_us := 0
var _bucket_us := 0          # wall-clock microseconds accumulated this bucket
var _frame_ms: Array[float] = []
var _scene_ms: Array[float] = []
var _draws_max := 0
var _objs_max := 0
var _prims_max := 0

## THE SCENE-STEP BRACKET. `Performance.TIME_PROCESS` is not what its name
## suggests: Godot updates it once per second and it covers the whole idle
## step INCLUDING RenderingServer::sync/draw — under vsync it is just the
## frame time wearing a CPU costume, and it can never answer "how much of
## this frame is GDScript and animation?".
##
## So the harness brackets the SceneTree process group itself. `_ProcMark`
## runs at process_priority -100000 (first callback of the frame) and stamps
## the clock; this driver runs at +100000 (last callback) and subtracts. The
## difference is every `_process` and every internal process callback in the
## tree — scripts, AnimationPlayers, Tweens — and NOTHING else. Frame time
## minus that is render submit + sync + present.
class _ProcMark extends Node:
	var t_us := 0
	func _process(_delta: float) -> void:
		t_us = Time.get_ticks_usec()

var _mark: _ProcMark


func _input(event: InputEvent) -> void:
	if mode != "" and event is InputEventMouse:
		_last_input_pos = (event as InputEventMouse).position


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf="):
			mode = arg.substr(7)
		elif arg.begins_with("--perf-label="):
			label = arg.substr(13)
		elif arg.begins_with("--perf-timeout="):
			timeout_sec = float(arg.substr(15))
		elif arg.begins_with("--perf-artifacts="):
			artifacts_dir = arg.substr(17)
		elif arg.begins_with("--perf-shots="):
			shots = arg.substr(13) == "1"
	if mode.is_empty():
		return   # dormant — a normal launch never reaches this file at all
	if shots and artifacts_dir.is_empty():
		artifacts_dir = ProjectSettings.globalize_path("res://test_e2e/artifacts") \
			+ "/perf-contaminated"
	if shots:
		DirAccess.make_dir_recursive_absolute(artifacts_dir)
	# THE FRAME RATE MUST NOT BE CAPPED BY THE DISPLAY. With vsync on, every
	# frame cheaper than the refresh interval reads as "exactly the refresh
	# interval" and the headroom — the whole question — is invisible.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_priority = 100000          # last _process callback of the frame
	_mark = _ProcMark.new()
	_mark.name = "PerfProcMark"
	_mark.process_priority = -100000   # first _process callback of the frame
	get_tree().root.add_child.call_deferred(_mark)
	_last_us = Time.get_ticks_usec()
	_watchdog()
	_run()


## THE RESOLUTION TRAP, and why `px` is computed the hard way.
##
## `get_viewport().get_visible_rect()` reports 1920x1080 for BOTH a 960x540-pt
## window and a 3008x1692-pt one, because the project stretches on
## `canvas_items` and that rect is in CANVAS coordinates. Trusting it would
## have reported the 6K run as "1080p" and hidden the entire resolution axis.
## The device framebuffer is window points x the screen's backing scale, and
## it is corroborated on every run by RENDER_VIDEO_MEM_USED: 264 MB at
## 1920x1080 vs 432 MB at 6016x3384 — a 168 MB delta, which is exactly a
## 6016x3384 color+depth pair. Two independent signals, one conclusion.
func _env_line() -> void:
	var win := get_window()
	var vp := get_viewport()
	var scr := DisplayServer.window_get_current_screen()
	var sscale := DisplayServer.screen_get_scale(scr)
	var dev := Vector2i(int(round(win.size.x * sscale)), int(round(win.size.y * sscale)))
	var tex := Vector2i.ZERO
	var vt := vp.get_texture()
	if vt != null:
		tex = vt.get_size()
	print("PERF ENV label=%s mode=%s window_pts=%dx%d device_px=%dx%d " % [
			label, mode, win.size.x, win.size.y, dev.x, dev.y]
		+ "canvas_rect=%.0fx%.0f tex=%dx%d screen=%s screen_scale=%.1f " % [
			vp.get_visible_rect().size.x, vp.get_visible_rect().size.y,
			tex.x, tex.y, str(DisplayServer.screen_get_size(scr)), sscale]
		+ "px=%d renderer=%s driver=%s vsync=%d max_fps=%d shots=%s" % [
			dev.x * dev.y,
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
			str(RenderingServer.get_video_adapter_name()),
			DisplayServer.window_get_vsync_mode(), Engine.max_fps, str(shots)])


# ── per-second sampling, on the WALL clock ─────────────────────────────────
func _process(_delta: float) -> void:
	if _phase.is_empty():
		return
	var now := Time.get_ticks_usec()
	var dt_us := now - _last_us
	_last_us = now
	var dt_ms := float(dt_us) / 1000.0
	_frame_ms.append(dt_ms)
	_bucket_us += dt_us
	if _mark != null and _mark.t_us > 0:
		_scene_ms.append(float(now - _mark.t_us) / 1000.0)
	_draws_max = maxi(_draws_max,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_objs_max = maxi(_objs_max,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	_prims_max = maxi(_prims_max,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if _bucket_us >= 1_000_000:
		_emit_bucket()


func _emit_bucket() -> void:
	var n := _frame_ms.size()
	if n == 0:
		return
	var secs := float(_bucket_us) / 1_000_000.0
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var worst: float = sorted[n - 1]
	var p95: float = sorted[mini(n - 1, int(floor(n * 0.95)))]
	var median: float = sorted[n / 2]
	# THE CONTENTION-ROBUST ESTIMATOR. This Mac is not a lab bench: the owner's
	# live game, another agent's e2e suite and the 6K compositor all share the
	# GPU, and interference can only ever ADD time to a frame. The mean and the
	# worst therefore measure the machine; the FASTEST frames measure the game.
	# p5 is the cost of a frame that ran unmolested — the number to compare
	# across ablations. Mean/worst stay in the line because they are what the
	# player feels.
	var p5: float = sorted[mini(n - 1, int(floor(n * 0.05)))]
	var fastest: float = sorted[0]
	var mean: float = (secs * 1000.0) / float(n)
	# scene-step (all _process + internal process callbacks in the tree)
	var scene_mean := 0.0
	var scene_worst := 0.0
	if not _scene_ms.is_empty():
		for v in _scene_ms:
			scene_mean += v
			scene_worst = maxf(scene_worst, v)
		scene_mean /= float(_scene_ms.size())
	# TIME_PROCESS / TIME_PHYSICS_PROCESS are engine-side ONE-PER-SECOND
	# MAXIMA (Main::iteration resets them each second), and TIME_PROCESS
	# includes RenderingServer sync+draw — so they are read once per bucket
	# and reported as what they are: worst whole-idle-step and worst physics
	# step in the interval.
	_phase_t += 1
	print(("PERF phase=%s t=%d fps=%.1f frames=%d min_ms=%.2f p5_ms=%.2f "
		+ "mean_ms=%.2f median_ms=%.2f "
		+ "p95_ms=%.2f WORST_ms=%.2f scene_ms_mean=%.3f scene_ms_worst=%.3f "
		+ "TIME_PROCESS_ms=%.2f TIME_PHYSICS_ms=%.2f "
		+ "objs=%d draws=%d prims=%d vram_mb=%.1f "
		+ "nodes=%d mem_mb=%.1f ts=%.2f") % [
		_phase, _phase_t, float(n) / secs, n, fastest, p5,
		mean, median, p95, worst,
		scene_mean, scene_worst,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		_objs_max, _draws_max, _prims_max,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Engine.time_scale])
	_frame_ms.clear()
	_scene_ms.clear()
	_bucket_us = 0
	_draws_max = 0
	_objs_max = 0
	_prims_max = 0
	# THE TRAP, ON PURPOSE. In `shots` mode one screenshot is taken per sampled
	# second — the same `get_viewport().get_texture().get_image()` an e2e step
	# does. At 6K that is a ~81 MB synchronous GPU→CPU readback plus a PNG
	# encode, on the main thread, inside the frame. The files rotate through
	# five names so the disk does not fill: the cost being demonstrated is the
	# readback and the encode, not the filename.
	if shots:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			_shot_i += 1
			img.save_png("%s/rot_%02d.png" % [artifacts_dir, _shot_i % 5])


func _set_phase(p: String) -> void:
	## Flush whatever is in the bucket under the OLD tag, then start clean —
	## a phase boundary must never smear two phases into one line.
	if not _phase.is_empty() and _bucket_us > 100_000:
		_emit_bucket()
	_phase = p
	_phase_t = 0
	_frame_ms.clear()
	_scene_ms.clear()
	_bucket_us = 0
	_draws_max = 0
	_objs_max = 0
	_prims_max = 0
	_last_us = Time.get_ticks_usec()


# ── the census: what the frame is actually made of ─────────────────────────
## Draw calls come from SURFACES, not from nodes, and batching only happens
## when instances share a material. So the census counts both, and prints the
## ratio: unique materials ÷ visible surfaces is the direct falsification test
## for "material duplication kills batching".
func _census(tag: String) -> void:
	var mi_total := 0
	var mi_visible := 0
	var surf_visible := 0
	var mat_ids := {}
	var mesh_ids := {}
	var shadow_casters := 0
	var shadow_surfaces := 0
	var skinned := 0
	var skinned_shadow := 0
	var anim_total := 0
	var anim_playing := 0
	var anim_active := 0
	var particles := 0
	var particles_emitting := 0
	var particles_visible := 0
	var omni := 0
	var omni_shadow := 0
	var dirlight := 0
	var dir_shadow := 0
	var skeletons := 0
	var nodes := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			mi_total += 1
			var vis := m.is_visible_in_tree()
			var mesh := m.mesh
			var nsurf := mesh.get_surface_count() if mesh != null else 0
			if mesh != null:
				mesh_ids[mesh.get_instance_id()] = true
			if vis:
				mi_visible += 1
				surf_visible += nsurf
				for s in nsurf:
					var mat := m.get_active_material(s)
					if mat != null:
						mat_ids[mat.get_instance_id()] = true
				if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_casters += 1
					shadow_surfaces += nsurf
				if m.skin != null or not m.skeleton.is_empty():
					skinned += 1
					if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						skinned_shadow += 1
		elif n is AnimationPlayer:
			anim_total += 1
			if (n as AnimationPlayer).is_playing():
				anim_playing += 1
			if (n as AnimationPlayer).active:
				anim_active += 1
		elif n is GPUParticles3D:
			particles += 1
			if (n as GPUParticles3D).emitting:
				particles_emitting += 1
			if (n as GPUParticles3D).is_visible_in_tree():
				particles_visible += 1
		elif n is OmniLight3D:
			omni += 1
			if (n as OmniLight3D).shadow_enabled:
				omni_shadow += 1
		elif n is DirectionalLight3D:
			dirlight += 1
			if (n as DirectionalLight3D).shadow_enabled:
				dir_shadow += 1
		elif n is Skeleton3D:
			skeletons += 1
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var share := 0.0
	if surf_visible > 0:
		share = float(mat_ids.size()) / float(surf_visible)
	print(("PERF CENSUS %s nodes=%d meshinst=%d meshinst_visible=%d "
		+ "surfaces_visible=%d unique_materials=%d unique_meshes=%d "
		+ "mat_per_surface=%.2f draws_now=%d skeletons=%d skinned_mi=%d "
		+ "skinned_shadow=%d shadow_casters=%d shadow_surfaces=%d "
		+ "animplayers=%d anim_active=%d anim_playing=%d particles=%d "
		+ "particles_visible=%d particles_emitting=%d omni=%d omni_shadow=%d "
		+ "dirlight=%d dir_shadow=%d") % [
		tag, nodes, mi_total, mi_visible, surf_visible, mat_ids.size(),
		mesh_ids.size(), share, draws, skeletons, skinned, skinned_shadow,
		shadow_casters, shadow_surfaces, anim_total, anim_active, anim_playing,
		particles, particles_visible, particles_emitting, omni, omni_shadow,
		dirlight, dir_shadow])


## Which GDScript actually runs every frame — tallied by script path, so
## "32 AnimationPlayers ticking" and "8 torch flicker scripts" become counts
## instead of suspicions.
func _script_census(tag: String) -> void:
	var proc := {}
	var phys := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var key: String = "<builtin:%s>" % n.get_class()
		var sc: Variant = n.get_script()
		if sc != null and (sc as Script).resource_path != "":
			key = (sc as Script).resource_path.get_file()
		if n.is_processing():
			proc[key] = int(proc.get(key, 0)) + 1
		if n.is_physics_processing():
			phys[key] = int(phys.get(key, 0)) + 1
	print("PERF SCRIPT %s process=%s physics=%s" % [tag,
		_fmt_tally(proc), _fmt_tally(phys)])


func _fmt_tally(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s:%d" % [k, int(d[k])])
	return "[" + ",".join(parts) + "]"


# ── generic helpers (same input path as e2e_driver.gd) ─────────────────────
func _watchdog() -> void:
	await get_tree().create_timer(timeout_sec, true, false, true).timeout
	if _done:
		return
	print("PERF FAIL watchdog — mode '%s' exceeded %.0fs (phase=%s)"
		% [mode, timeout_sec, _phase])
	_finish(1)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	if not _phase.is_empty() and _bucket_us > 100_000:
		_emit_bucket()
	print("PERF DONE mode=%s label=%s exit=%d" % [mode, label, code])
	get_tree().quit(code)


func _fail(step: String, why: String) -> void:
	print("PERF FAIL %s — %s" % [step, why])
	_finish(1)


func _step(name: String) -> void:
	print("PERF STEP %s" % name)


## WALL-CLOCK sleep. Never `create_timer(sec)` — the duel bends
## Engine.time_scale to 0.55 and a scaled timer would silently stretch every
## measurement window taken during a cinematic.
func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _wait_until(pred: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _done:
			return false
		if pred.call():
			return true
		await get_tree().process_frame
	return false


func _calibrate_input() -> bool:
	var vp := get_viewport()
	get_window().grab_focus()
	await get_tree().process_frame
	var probe := Vector2(41.0, 57.0)
	for cand in [vp.get_final_transform(), Transform2D.IDENTITY]:
		_last_input_pos = Vector2(-1e9, -1e9)
		var mm := InputEventMouseMotion.new()
		mm.position = (cand as Transform2D) * probe
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame
		await get_tree().process_frame
		if _last_input_pos.distance_to(probe) < 2.0:
			_to_window = cand
			return true
	return false


func _move_mouse(canvas_pos: Vector2) -> void:
	var wpos := _to_window * canvas_pos
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	Input.parse_input_event(mm)
	await get_tree().process_frame


func _click_at(canvas_pos: Vector2) -> void:
	var wpos := _to_window * canvas_pos
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	Input.parse_input_event(mm)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = wpos
	down.global_position = wpos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = wpos
	up.global_position = wpos
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _click_control(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center())


func _click_until(c: Control, pred: Callable, what: String, attempts := 4) -> bool:
	for i in attempts:
		await _click_control(c)
		if await _wait_until(pred, 3.0):
			return true
		print("PERF WARN %s click %d/%d did not land — retrying" % [what, i + 1, attempts])
		await _sleep(0.5)
	return false


func _game() -> Node:
	var cs := get_tree().current_scene
	if cs != null and cs.get("state") != null and cs.get("board") != null:
		return cs
	return null


func _select_screen() -> Control:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if cs.get("phase") != null and cs.find_child("Crest_%s" % DEFAULT_HOUSE, true, false) != null:
		return cs as Control
	return cs.find_child("HouseSelect", true, false) as Control


func _find_button(root: Node, needle: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		var lbl := str(b.get_meta("label")) if b.has_meta("label") else b.text
		if lbl.contains(needle):
			return b
	return null


func _square_canvas(game: Node, sq: Vector2i) -> Vector2:
	var board: Node = game.get("board")
	var cam := get_viewport().get_camera_3d()
	return cam.unproject_position(board.square_to_world(sq))


func _click_square(game: Node, sq: Vector2i) -> void:
	await _click_at(_square_canvas(game, sq))


func _select_square(game: Node, sq: Vector2i, attempts := 4) -> bool:
	for i in attempts:
		await _click_square(game, sq)
		if await _wait_until(func(): return game.get("selected") == sq, 1.5):
			return true
		await _sleep(0.4)
	return false


## THE CONTAMINATION ITSELF. Only ever called in mode `shots`.
func _shot(step_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_shot_i += 1
	img.save_png("%s/%02d_%s.png" % [artifacts_dir, _shot_i, step_name])


# ── the run ────────────────────────────────────────────────────────────────
func _run() -> void:
	await get_tree().process_frame
	if not await _wait_until(func(): return get_tree().current_scene != null, 20.0):
		_fail("boot", "no scene appeared within 20s")
		return
	_env_line()
	_set_phase("boot")
	await _sleep(1.0)
	if not await _calibrate_input():
		_fail("input-pipeline", "synthesized mouse events do not reach the viewport")
		return
	_step("input-pipeline")

	# -- Hall of Banners ----------------------------------------------------
	_set_phase("hall")
	if not await _wait_until(func(): return _select_screen() != null, 20.0):
		_fail("hall", "the Hall of Banners never appeared")
		return
	await _sleep(1.5)          # deferred ring layout + first draws, measured
	_census("hall")
	if shots:
		_shot("hall")
	var sel: Control = _select_screen()
	var crest: Node = sel.find_child("Crest_%s" % DEFAULT_HOUSE, true, false)
	if crest == null:
		_fail("hall-crest", "no crest for house '%s'" % DEFAULT_HOUSE)
		return
	_set_phase("hall-select")
	if not await _click_until(crest.get_node("Sigil"),
			func(): return int(sel.get("phase")) == 1, "crest"):
		_fail("hall-house", "crest clicks never advanced")
		return
	var opp := _find_button(sel, "Casual")
	if opp == null:
		_fail("hall-opponent", "no 'Casual' opponent button")
		return
	if not await _click_until(opp, func(): return int(sel.get("phase")) == 2, "opponent"):
		_fail("hall-opponent", "opponent clicks never advanced")
		return
	var modebtn := _find_button(sel, "Single Match")
	if modebtn == null:
		_fail("hall-mode", "no 'Single Match' button")
		return
	_set_phase("match-load")
	await _click_control(modebtn)
	if not await _wait_until(func(): return _game() != null, 25.0):
		_fail("match-load", "the game scene never appeared")
		return
	var game := _game()
	_step("match-loaded")

	# -- intro --------------------------------------------------------------
	_set_phase("intro")
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 40.0):
		_fail("intro", "never became the player's turn")
		return
	_step("intro-done")
	_set_phase("settle")
	await _sleep(2.0)
	_census("settled")
	_script_census("settled")
	if shots:
		_shot("settled")

	if mode == "ablate":
		await _ablation_sweep(game)
		_finish(0)
		return

	# -- steady-state idle (the baseline the player stares at) ---------------
	_set_phase("idle-a")
	await _sleep(5.0)

	# -- hover sweep (hypothesis f: the hover raycast on mouse motion) ------
	_set_phase("hover-sweep")
	var t0 := Time.get_ticks_msec()
	var i := 0
	while Time.get_ticks_msec() - t0 < 5000 and not _done:
		# A real mouse drags a CONTINUOUS stream of motion events. Sweep the
		# board diagonally, one event per frame — the worst case the hover
		# path can ever be asked to serve.
		var sq := Vector2i(i % 8, (i / 8) % 8)
		await _move_mouse(_square_canvas(game, sq))
		i += 1
	_step("hover-sweep (%d motion events)" % i)

	# -- the capture: select, then the duel cinematic ------------------------
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		_fail("capture", "the position offers White no capture")
		return
	var from_sq: Vector2i = game.sq_of(capture.from_square)
	var to_sq: Vector2i = game.sq_of(capture.to_square)
	_set_phase("select-attacker")
	if not await _select_square(game, from_sq):
		_fail("select-attacker", "%s never became selected" % str(from_sq))
		return
	await _sleep(2.0)
	var deaths_before: int = (game.get("death_log") as Array).size()
	_set_phase("duel-capture")
	await _click_square(game, to_sq)
	if not await _wait_until(func():
		return (game.get("death_log") as Array).size() > deaths_before, 20.0):
		_fail("duel-capture", "no death animation was recorded")
		return
	_step("duel-death (%s)" % (game.get("death_log") as Array).back())
	# Hypothesis (e) is about particles LINGERING, so it has to be measured
	# while the cinematic is still on screen as well as after it.
	_census("mid-duel")
	if shots:
		_shot("mid_duel")
	_set_phase("duel-tail")
	if not await _wait_until(func():
		return game.get("busy") == false or state.turn == true, 25.0):
		_fail("duel-tail", "the board never handed the turn over")
		return

	# -- the AI's reply (which may bring its own duel) -----------------------
	_set_phase("ai-reply")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 60.0):
		_fail("ai-reply", "the rival never replied")
		return
	_step("ai-replied")
	_set_phase("idle-b")
	await _sleep(4.0)
	_census("post-duel")

	# -- a quiet move (no cinematic) — the cost of a plain animation ---------
	var quiet = null
	for m in state.legal_moves():
		if not m.is_capture():
			quiet = m
			break
	if quiet != null:
		var q_from: Vector2i = game.sq_of(quiet.from_square)
		var q_to: Vector2i = game.sq_of(quiet.to_square)
		_set_phase("quiet-move")
		if await _select_square(game, q_from):
			await _click_square(game, q_to)
			await _wait_until(func(): return game.get("busy") == true, 3.0)
			await _wait_until(func(): return game.get("busy") == false, 20.0)
		_set_phase("ai-reply-2")
		await _wait_until(func():
			return game.get("busy") == false and state.turn == false, 60.0)
		_step("quiet-round-done")

	_set_phase("idle-final")
	await _sleep(5.0)
	_census("final")
	_script_census("final")
	if shots:
		_shot("final")
	_set_phase("")
	_finish(0)


# ── the ablation sweep: measured cost, not suspected cost ──────────────────
## Each entry switches ONE thing off at runtime, holds it for MEASURE_SEC, and
## switches it back on. Nothing here is a fix and nothing survives the process
## — it is a controlled A/B (diff the working twin) whose only product is a
## number. `base-N` bracket lines between ablations catch drift, so a cost is
## only credited when the baselines either side of it agree.
## INTERLEAVED, NOT SEQUENTIAL. The first version of this sweep measured each
## ablation as one long block between two baselines, and the BASELINES
## disagreed with each other by more than any ablation moved the number
## (38 → 60 fps on identical scene content, draws=855 every time). On a
## machine whose GPU is shared with a live game and a 6K compositor, a block
## design measures the neighbours' schedule. So each ablation is now A/B/A/B
## interleaved on a few-second period: slow drift lands on BOTH arms equally,
## and the comparison is between medians of samples taken seconds apart
## instead of minutes apart.
const ABL_WARM := 1.0       # discarded after every toggle (atlas/pipeline churn)
const ABL_MEASURE := 2.0    # sampled window
const ABL_CYCLES := 3

func _ablation_sweep(game: Node) -> void:
	var names: Array[String] = [
		# THE CONTROLLED RESOLUTION EXPERIMENT. A small 1080p WINDOW is not a
		# valid 1080p measurement on this machine: it leaves the owner's live
		# game visible, and a visible Godot window is a GPU co-tenant, while a
		# screen-sized window occludes it. So the resolution axis is swept
		# INSIDE one screen-sized window by scaling the 3D render target —
		# same window, same compositor, same neighbours, one variable.
		"res1080",        # 3D render target forced to exactly 1920x1080
		"res50",          # 3D render scale 0.5 → 25 % of the pixels: FILL test
		"res25",          # 3D render scale 0.25 → 6 % of the pixels: FILL test
		"sun-shadow",     # the hall's single shadow-casting light
		"anim",           # every AnimationPlayer switched inactive
		"torch",          # the 8 torch flicker scripts stop processing
		"hud",            # the CanvasLayer HUD hidden
		"pieces",         # all 32 piece views hidden (whole-army upper bound)
		"hall",           # the Great Hall environment hidden
		"glow",           # the Environment's glow post-process off
	]
	for nm in names:
		for cycle in ABL_CYCLES:
			_set_phase("warm")
			await _sleep(ABL_WARM)
			_set_phase("BASE-" + nm)
			await _sleep(ABL_MEASURE)
			var undo := _ablate(game, nm)
			if undo.is_empty():
				print("PERF WARN ablation '%s' had nothing to switch off" % nm)
				break
			_set_phase("warm")
			await _sleep(ABL_WARM)
			_set_phase("ABL-" + nm)
			await _sleep(ABL_MEASURE)
			for c in undo:
				(c as Callable).call()
	_set_phase("")


## Returns the list of restore callables (empty when nothing matched).
func _ablate(game: Node, what: String) -> Array:
	var undo: Array = []
	var vp := get_viewport()
	match what:
		"res1080", "res50", "res25":
			var old_mode := vp.scaling_3d_mode
			var old_scale := vp.scaling_3d_scale
			var want := 0.5
			if what == "res25":
				want = 0.25
			elif what == "res1080":
				var scr := DisplayServer.window_get_current_screen()
				var dev_w := float(get_window().size.x) \
					* DisplayServer.screen_get_scale(scr)
				want = clampf(1920.0 / maxf(dev_w, 1.0), 0.1, 1.0)
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = want
			print("PERF ABLINFO %s scaling_3d_scale=%.4f" % [what, want])
			undo.append(func():
				vp.scaling_3d_mode = old_mode
				vp.scaling_3d_scale = old_scale)
		"sun-shadow":
			for n in _all_of_type(DirectionalLight3D):
				var d := n as DirectionalLight3D
				if d.shadow_enabled:
					d.shadow_enabled = false
					undo.append(func(): d.shadow_enabled = true)
		"anim":
			for n in _all_of_type(AnimationPlayer):
				var a := n as AnimationPlayer
				if a.active:
					a.active = false
					undo.append(func(): a.active = true)
		"torch":
			for n in _all_of_type(Node3D):
				var tsc: Variant = n.get_script()
				if tsc != null and str((tsc as Script).resource_path).ends_with("torch.gd"):
					var old: int = n.process_mode
					n.process_mode = Node.PROCESS_MODE_DISABLED
					undo.append(func(): n.process_mode = old)
		"particles":
			for n in _all_of_type(GPUParticles3D):
				var p := n as GPUParticles3D
				var was_e := p.emitting
				var was_v := p.visible
				p.emitting = false
				p.visible = false
				undo.append(func():
					p.emitting = was_e
					p.visible = was_v)
		"hud":
			for n in _all_of_type(CanvasLayer):
				var cl := n as CanvasLayer
				if cl.visible:
					cl.visible = false
					undo.append(func(): cl.visible = true)
		"pieces":
			var views: Dictionary = game.get("views")
			for sq in views:
				var pv = views[sq]
				if is_instance_valid(pv) and (pv as Node3D).visible:
					(pv as Node3D).visible = false
					undo.append(func(): (pv as Node3D).visible = true)
		"hall":
			var hall: Node = game.get_node_or_null("GreatHall")
			if hall != null and (hall as Node3D).visible:
				(hall as Node3D).visible = false
				undo.append(func(): (hall as Node3D).visible = true)
		"glow":
			for n in _all_of_type(WorldEnvironment):
				var env := (n as WorldEnvironment).environment
				if env != null and env.glow_enabled:
					env.glow_enabled = false
					undo.append(func(): env.glow_enabled = true)
	return undo


func _all_of_type(t) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, t):
			out.append(n)
	return out
