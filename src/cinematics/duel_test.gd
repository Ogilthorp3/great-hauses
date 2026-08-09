extends Node3D
## Standalone battle-cam test stage (scenes/cinematics/duel_test.tscn).
## Mocks two PieceView-shaped fighters (duck-typed `piece_type` / `side`
## ints — the same fields DuelDirector reads off real PieceViews) and runs
## the full cinematic suite: duel -> promotion -> checkmate.
##
## Run windowed (visual verification, click/Esc to skip):
##   Godot --path <proj> res://scenes/cinematics/duel_test.tscn -- --run-duel-test
## Run headless (self-checking, exits 0/1):
##   Godot --headless --path <proj> res://scenes/cinematics/duel_test.tscn -- --run-duel-test
## Without the arg the stage idles with an instructions label (headless-safe).

const DuelDirectorScript := preload("res://src/cinematics/duel_director.gd")

const SHOT_FACING := "res://test_e2e/artifacts/module-previews/facing.png"

## The mock fighters carry no house id, so DuelDirector used to fall back to
## the LEGACY FROST/EMBER table and the saved facing.png read "So falls the
## queen of House Ember" — a house that is not one of the shipped Nine
## (ISSUES.md #16). The fixture now names two real houses, and every frame it
## saves is stamped FIXTURE so a capsule stand-in can never be mistaken for a
## shipped gameplay frame.
const FIXTURE_HOUSES := {
	"attacker_house": "winterfang",
	"victim_house": "goldclaw",
}
const FIXTURE_STAMP := "MODULE TEST FIXTURE — DuelDirector stage\ncapsule stand-ins, not gameplay art"

var _director: DuelDirector
var _fails := 0
var _victory_house := ""
var _facing_shot_taken := false


class MockPiece:
	extends Node3D
	## PieceView stand-in: same duck fields DuelDirector reads.
	var piece_type := 0   # PieceView.Type-compatible index
	var side := 0         # PieceView.House-compatible index
	var died_flag := false

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

	## Duel choreography stand-in — scaled tweens, so slow-mo is visible.
	func mock_strike(victim: MockPiece) -> void:
		var start := position
		var tw := create_tween()
		tw.tween_property(self, "position", start.lerp(victim.position, 0.6), 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
		await victim.mock_die()
		var back := create_tween()
		back.tween_property(self, "position", start, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await back.finished

	func mock_die() -> void:
		var tw := create_tween()
		tw.tween_property(self, "rotation:z", PI * 0.45, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "position:y", position.y - 1.2, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
		died_flag = true
		visible = false


func _ready() -> void:
	_build_stage()
	_director = DuelDirectorScript.new()
	_director.name = "DuelDirector"
	add_child(_director)
	_director.victory_panel_requested.connect(_on_victory)
	if OS.get_cmdline_user_args().has("--run-duel-test"):
		_run()
	else:
		_show_hint("launch with:  -- --run-duel-test")


func _on_victory(house: String) -> void:
	_victory_house = house
	print("DUELTEST victory-panel-hook house=%s" % house)


func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	while true:
		_fails = 0
		_victory_house = ""
		await _run_acts()
		print("DUELTEST DONE fails=%d" % _fails)
		if headless:
			get_tree().quit(1 if _fails > 0 else 0)
			return
		_show_hint("replaying in 2 s…  (click/Esc skips a running cinematic)")
		await get_tree().create_timer(2.0, true, false, true).timeout


func _run_acts() -> void:
	# Act I — the capture duel, full cam takeover, ≤5.5 s wall clock.
	# Both mocks spawn facing +Z (NOT facing each other) — the director's
	# face-off must have them eye-to-eye by the time the strike lands.
	var attacker := _spawn_mock(2, 0, Vector3(-0.8, 0.0, 0.0))   # knight
	var victim := _spawn_mock(4, 1, Vector3(0.8, 0.0, 0.2))      # queen
	var t0 := Time.get_ticks_msec()
	if not _facing_shot_taken and DisplayServer.get_name() != "headless":
		_schedule_facing_shot(1.5)   # mid slow-mo hold: the faced-off frame
	var strike := func() -> void:
		var dir := (victim.global_position - attacker.global_position).normalized()
		var fa := attacker.global_transform.basis.z.normalized()
		var fv := victim.global_transform.basis.z.normalized()
		_check("duel-face-to-face-at-strike",
			fa.dot(fv) < -0.95 and fa.dot(dir) > 0.95)
		await attacker.mock_strike(victim)
	await _director.play_duel(attacker, victim, FIXTURE_HOUSES, strike)
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	_check("duel-restores-timescale", is_equal_approx(Engine.time_scale, 1.0))
	_check("duel-victim-died", victim.died_flag)
	_check("duel-resting-yaw-restored",
		absf(wrapf(attacker.rotation.y, -PI, PI)) < 0.06)   # FROST rest = 0.0
	_check("duel-inactive-after", not _director.is_active())
	_check("duel-wall-under-6s", wall < 6.0)   # 5.5 s budget + skip/frame slack
	print("DUELTEST duel wall=%.2fs" % wall)
	await _pause(0.4)

	# Act II — promotion flourish on the survivor.
	attacker.piece_type = 4   # "promoted" to queen
	await _director.play_promotion(attacker)
	_check("promotion-restores-timescale", is_equal_approx(Engine.time_scale, 1.0))
	_check("promotion-inactive-after", not _director.is_active())
	await _pause(0.4)

	# Act III — checkmate: slow orbit of the losing king, victory hook.
	var king := _spawn_mock(5, 1, Vector3(0.2, 0.0, -0.6))       # king
	var death := func() -> void:
		await king.mock_die()
	# Real house key, deliberately (ISSUES.md #16): the fixture used the
	# legacy "FROST" fallback, so its captions advertised houses that do not
	# ship. The expected name below moved WITH it — the check still proves
	# the victory hook fires with the director's resolved house name.
	await _director.play_checkmate(king, "winterfang", death)
	_check("checkmate-restores-timescale", is_equal_approx(Engine.time_scale, 1.0))
	_check("checkmate-victory-hook", _victory_house == "House Winterfang")
	_check("checkmate-king-died", king.died_flag)
	_check("checkmate-inactive-after", not _director.is_active())

	for m in [attacker, victim, king]:
		if is_instance_valid(m):
			m.queue_free()


func _schedule_facing_shot(delay_sec: float) -> void:
	var runner := func() -> void:
		await _pause(delay_sec)
		if _facing_shot_taken or not is_inside_tree():
			return
		_facing_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(SHOT_FACING.get_base_dir()))
		var err := img.save_png(ProjectSettings.globalize_path(SHOT_FACING))
		print("DUELTEST SHOT_SAVED path=%s err=%d" % [
			ProjectSettings.globalize_path(SHOT_FACING), err])
	runner.call()


func _spawn_mock(pt: int, house: int, pos: Vector3) -> MockPiece:
	var m := MockPiece.new()
	add_child(m)
	var colors := [Color(0.58, 0.7, 0.9), Color(0.85, 0.38, 0.22)]
	m.setup_mock(pt, house, colors[house])
	m.position = pos
	return m


func _check(step: String, ok: bool) -> void:
	if ok:
		print("DUELTEST PASS %s" % step)
	else:
		_fails += 1
		print("DUELTEST FAIL %s" % step)


func _pause(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


# ── stage ──────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.13, 0.15)
	mat.roughness = 1.0
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 30.0, 0.0)
	sun.light_energy = 0.9
	add_child(sun)

	var torch := OmniLight3D.new()
	torch.position = Vector3(-2.5, 1.8, 2.5)
	torch.light_color = Color(1.0, 0.6, 0.3)
	torch.light_energy = 2.0
	torch.omni_range = 8.0
	add_child(torch)

	# Stand-in for the game's orbit camera: the director swoops away from
	# and returns to whatever camera is current.
	var cam := Camera3D.new()
	cam.name = "MockOrbit"
	cam.position = Vector3(0.0, 4.6, 6.8)
	cam.fov = 50.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.3, 0.0))
	cam.current = true

	_build_fixture_stamp()


func _build_fixture_stamp() -> void:
	## Every frame this stage renders — including the saved facing.png — is
	## stamped as a fixture. The capsules are a deliberate internal stand-in;
	## the stamp is what keeps them from reading as shipped art (ISSUES.md #16).
	var layer := CanvasLayer.new()
	layer.name = "FixtureStamp"
	layer.layer = 95
	add_child(layer)
	var l := Label.new()
	l.name = "Stamp"
	l.text = FIXTURE_STAMP
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.offset_left = -460
	l.offset_top = 14
	l.offset_right = -18
	l.offset_bottom = 62
	layer.add_child(l)


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
	(layer.get_node("Hint") as Label).text = "Great Houses — battle-cam test stage\n" + text
