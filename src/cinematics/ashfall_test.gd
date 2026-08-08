extends Node3D
## Standalone DRAGON SPECTATOR + ASHFALL test stage
## (scenes/cinematics/ashfall_test.tscn). Mocks two armies of PieceView-
## shaped pieces (duck `piece_type` / `side` ints) and runs the module's
## whole surface: perch idle, reaction rate limiting, the duel-cam gate,
## and the full ASHFALL execution.
##
## Run windowed (visual verification; click/Esc skips the running ashfall;
## saves the mid-fire frame to test_e2e/artifacts/module-previews/ashfall.png
## and the CEREMONY frames — mid-bank, wing-spread hover, smolder, and (with
## --champ) the throne crowning/tableau — to module-previews/finale/):
##   Godot --path <proj> res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test
##   Godot --path <proj> res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test --champ
## Run headless (self-checking, exits 0/1; --champ selects the throne tier):
##   Godot --headless --path <proj> res://scenes/cinematics/ashfall_test.tscn -- --run-ashfall-test
## Without the arg the stage idles with an instructions label (headless-safe).

const SpectatorScript := preload("res://src/cinematics/dragon_spectator.gd")

const SHOT_DIR := "res://test_e2e/artifacts/module-previews"
const SHOT_PATH := SHOT_DIR + "/ashfall.png"
const FINALE_DIR := SHOT_DIR + "/finale"

var _spectator: DragonSpectator
var _fails := 0


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

	# ── Act II: THE CEREMONY — full ashfall over the losing army ──
	var champ := OS.get_cmdline_user_args().has("--champ")
	var finished := {"v": false}
	_spectator.ashfall_finished.connect(func() -> void: finished["v"] = true)
	var t0 := Time.get_ticks_msec()
	if not headless:
		# Default-timing phase map: ramp .25 | bank -> 2.85 | flare -> 3.55
		# | inhale -> 4.15 | breath -> 6.95 | linger/smolder | champ: crown
		# bank ~8.6-9.9, settle -> ~11.3, captions -> ~13.
		_schedule_shot(1.15, FINALE_DIR + "/bank.png")     # profile crossing, west
		_schedule_shot(1.95, FINALE_DIR + "/bank2.png")    # profile crossing, east
		_schedule_shot(3.7, FINALE_DIR + "/hover.png")     # wing-spread + inhale
		_schedule_shot(5.6, SHOT_PATH)                     # mid-breath (legacy frame)
		_schedule_shot(7.9, FINALE_DIR + "/smolder.png")   # jet cut — skeletons smolder
		if champ:
			_schedule_shot(10.7, FINALE_DIR + "/crowning.png")  # wing-settle, throne
			_schedule_shot(12.6, FINALE_DIR + "/tableau.png")   # the caption beat
	await _spectator.play_ashfall(1, "House Winterfang", losers, champ)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	await _pause(0.1)   # let queue_free flush
	_check("ashfall-finished-signal", finished["v"])
	_check("ashfall-timescale-restored", is_equal_approx(Engine.time_scale, 1.0))
	if champ:
		_check("ashfall-under-17s", wall < 17.0)   # 16 s budget + frame slack
		_check("champ-throne-perch",
			(_spectator.position - SpectatorScript.THRONE_PERCH).length() < 0.3)
		_check("champ-scale-1p6",
			is_equal_approx(_spectator.rig.scale.x, _spectator.champ_scale))
	else:
		_check("ashfall-under-13s", wall < 13.0)   # 12 s budget + frame slack
		_check("match-scale-restored",
			is_equal_approx(_spectator.rig.scale.x, _spectator.dragon_scale))
	var survivors := 0
	for l in losers:
		if is_instance_valid(l):
			survivors += 1
	_check("ashfall-losers-removed", survivors == 0)
	_check("ashfall-remains-cleaned", _spectator.remains_count() == 0)
	var winners_alive := true
	for w in winners:
		winners_alive = winners_alive and is_instance_valid(w)
	_check("ashfall-winners-untouched", winners_alive)
	_check("ashfall-inactive-after", not _spectator.is_ashfall_active())
	_check("no-light3d-added", _light_count() == lights_before)
	print("ASHFALLTEST ashfall wall=%.2fs champ=%s suite=%.1fs" % [
		wall, champ, float(Time.get_ticks_msec() - t_suite) / 1000.0])

	print("ASHFALLTEST DONE fails=%d" % _fails)
	if headless:
		get_tree().quit(1 if _fails > 0 else 0)
	else:
		_show_hint("done — fails=%d · closing in 2.5 s" % _fails)
		await _pause(2.5)   # hold the end state for the eye
		get_tree().quit(1 if _fails > 0 else 0)


# ── screenshot (windowed only) ─────────────────────────────────────────────


func _schedule_shot(delay_sec: float, path: String) -> void:
	var runner := func() -> void:
		await _pause(delay_sec)
		if not is_inside_tree():
			return
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(path.get_base_dir()))
		var err := img.save_png(ProjectSettings.globalize_path(path))
		var cam := get_viewport().get_camera_3d()
		print("ASHFALLTEST SHOT_SAVED path=%s err=%d size=%dx%d dragon=%v cam=%v" % [
			ProjectSettings.globalize_path(path), err,
			img.get_width(), img.get_height(),
			_spectator.global_position,
			cam.global_position if cam != null else Vector3.INF])
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
	plane.size = Vector2(26.0, 26.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.11, 0.13)
	mat.roughness = 1.0
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	# A ring of stand-in pillars at hall radius — scale cues so the
	# ceremony's bank/hover silhouettes can be judged by eye (the real
	# hall provides walls/pillars/torches; the void provides nothing).
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.2, 0.19, 0.22)
	pillar_mat.roughness = 1.0
	for i in 8:
		var ang := float(i) * TAU / 8.0
		var col := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 4.5, 0.8)
		col.mesh = box
		col.material_override = pillar_mat
		col.position = Vector3(sin(ang) * 10.5, 2.25, cos(ang) * 10.5)
		add_child(col)

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
