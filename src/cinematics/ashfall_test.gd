extends Node3D
## Standalone DRAGON SPECTATOR + ASHFALL test stage
## (scenes/cinematics/ashfall_test.tscn). Mocks two armies of PieceView-
## shaped pieces (duck `piece_type` / `side` ints) and runs the module's
## whole surface: perch idle, reaction rate limiting, the duel-cam gate,
## and the full ASHFALL execution.
##
## Run windowed (visual verification; click/Esc skips the running ashfall;
## saves a mid-fire frame to test_e2e/artifacts/module-previews/ashfall.png):
##   Godot --path <proj> res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test
## Run headless (self-checking, exits 0/1):
##   Godot --headless --path <proj> res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test
## Without the arg the stage idles with an instructions label (headless-safe).

const SpectatorScript := preload("res://src/cinematics/dragon_spectator.gd")

const SHOT_DIR := "res://test_e2e/artifacts/module-previews"
const SHOT_PATH := SHOT_DIR + "/ashfall.png"

var _spectator: DragonSpectator
var _fails := 0
var _shot_taken := false


class MockDuelDirector:
	extends Node
	var active := false
	func is_active() -> bool:
		return active


class MockPiece:
	extends Node3D
	var piece_type := 0
	var side := 0

	func setup_mock(pt: int, house: int, color: Color) -> void:
		piece_type = pt
		side = house
		var mi := MeshInstance3D.new()
		var caps := CapsuleMesh.new()
		caps.radius = 0.22
		caps.height = 0.95
		mi.mesh = caps
		mi.position.y = 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		mi.material_override = mat
		add_child(mi)


func _ready() -> void:
	_build_stage()
	_spectator = SpectatorScript.new()
	_spectator.name = "DragonSpectator"
	add_child(_spectator)
	if OS.get_cmdline_user_args().has("--run-ashfall-test"):
		_run()
	else:
		_show_hint("launch with:  -- --run-ashfall-test")


func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var lights_before := _light_count()
	var t_suite := Time.get_ticks_msec()

	# ── Act I: spectator reactions + rate limit + duel-cam gate ──
	var winners: Array = []
	var losers: Array = []
	for i in 3:
		winners.append(_spawn_mock(i, 0, Vector3(-2.0 + i * 1.2, 0.0, -1.6)))
	for i in 4:
		losers.append(_spawn_mock(i, 1, Vector3(-2.2 + i * 1.4, 0.0, 1.4)))
	await _pause(0.4)   # let the perch idle settle

	_check("react-first-allowed", _spectator.react_brilliant())
	_check("react-anim-is-yes", _anim_now() == "Yes")
	_check("react-rate-limited", not _spectator.react_blunder())
	_spectator.notice_move(Vector3.ZERO)
	_check("react-still-limited-after-1-move", not _spectator.react_blunder())
	_spectator.notice_move(Vector3.ZERO)
	# Let the Yes reaction tail release (clip length / 0.7 speed).
	var reopened := await _wait_until(func() -> bool: return _spectator.can_react(), 5.0)
	_check("react-window-reopens", reopened)
	var mock_dd := MockDuelDirector.new()
	add_child(mock_dd)
	mock_dd.active = true
	_spectator.duel_director = mock_dd
	_check("react-blocked-by-duel-cam", not _spectator.react_capture(Vector3.ZERO))
	mock_dd.active = false
	_check("react-capture-allowed", _spectator.react_capture(
		(losers[0] as Node3D).position))
	_check("react-anim-is-hitreact", _anim_now() == "HitReact")
	await _pause(1.2)

	# ── Act II: full ASHFALL over the losing army ──
	var finished := {"v": false}
	_spectator.ashfall_finished.connect(func() -> void: finished["v"] = true)
	var t0 := Time.get_ticks_msec()
	if not headless:
		_schedule_shot(2.4)   # mid-breath frame
	await _spectator.play_ashfall(1, "House Winterfang", losers)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	await _pause(0.1)   # let queue_free flush
	_check("ashfall-finished-signal", finished["v"])
	_check("ashfall-timescale-restored", is_equal_approx(Engine.time_scale, 1.0))
	_check("ashfall-under-7s", wall < 7.0)   # 6 s budget + frame slack
	var survivors := 0
	for l in losers:
		if is_instance_valid(l):
			survivors += 1
	_check("ashfall-losers-removed", survivors == 0)
	var winners_alive := true
	for w in winners:
		winners_alive = winners_alive and is_instance_valid(w)
	_check("ashfall-winners-untouched", winners_alive)
	_check("ashfall-inactive-after", not _spectator.is_ashfall_active())
	_check("no-light3d-added", _light_count() == lights_before)
	print("ASHFALLTEST ashfall wall=%.2fs suite=%.1fs" % [
		wall, float(Time.get_ticks_msec() - t_suite) / 1000.0])

	print("ASHFALLTEST DONE fails=%d" % _fails)
	if headless:
		get_tree().quit(1 if _fails > 0 else 0)
	else:
		_show_hint("done — fails=%d · closing in 2.5 s" % _fails)
		await _pause(2.5)   # hold the end state for the eye
		get_tree().quit(1 if _fails > 0 else 0)


# ── screenshot (windowed only) ─────────────────────────────────────────────


func _schedule_shot(delay_sec: float) -> void:
	var runner := func() -> void:
		await _pause(delay_sec)
		if _shot_taken or not is_inside_tree():
			return
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
		var err := img.save_png(ProjectSettings.globalize_path(SHOT_PATH))
		print("ASHFALLTEST SHOT_SAVED path=%s err=%d size=%dx%d" % [
			ProjectSettings.globalize_path(SHOT_PATH), err,
			img.get_width(), img.get_height()])
	runner.call()


# ── helpers ────────────────────────────────────────────────────────────────


func _anim_now() -> String:
	if _spectator.rig == null or _spectator.rig.anim == null:
		return ""
	return _spectator.rig.anim.assigned_animation


func _light_count() -> int:
	return get_tree().root.find_children("*", "Light3D", true, false).size()


func _spawn_mock(pt: int, house: int, pos: Vector3) -> MockPiece:
	var m := MockPiece.new()
	add_child(m)
	var colors := [Color(0.58, 0.7, 0.9), Color(0.85, 0.38, 0.22)]
	m.setup_mock(pt, house, colors[house])
	m.position = pos
	return m


func _check(step: String, ok: bool) -> void:
	if ok:
		print("ASHFALLTEST PASS %s" % step)
	else:
		_fails += 1
		print("ASHFALLTEST FAIL %s" % step)


func _pause(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _wait_until(pred: Callable, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return false


# ── stage ──────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.13, 0.15)
	mat.roughness = 1.0
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	# Stage lights are scene furniture — the no-Light3D check counts the
	# DELTA across module calls, so these two are fine.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	sun.light_energy = 0.8
	add_child(sun)
	var torch := OmniLight3D.new()
	torch.position = Vector3(-3.0, 2.2, 3.0)
	torch.light_color = Color(1.0, 0.6, 0.3)
	torch.light_energy = 2.0
	torch.omni_range = 9.0
	add_child(torch)

	# Frames both the perch (high, +Z) and the armies near the origin.
	var cam := Camera3D.new()
	cam.name = "StageCam"
	cam.position = Vector3(6.4, 3.6, -6.2)
	cam.fov = 55.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.4, 2.0))
	cam.current = true


func _show_hint(text: String) -> void:
	var layer := get_node_or_null("HintLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "HintLayer"
		add_child(layer)
		var l := Label.new()
		l.name = "Hint"
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.8, 0.76, 0.66))
		l.position = Vector2(18, 14)
		layer.add_child(l)
	(layer.get_node("Hint") as Label).text = \
		"Great Houses — dragon spectator / ashfall test stage\n" + text
