## e2e_driver.gd — in-engine E2E driver (autoload "E2EDriver", LAST in order).
##
## Dormant unless the game is launched with user args:
##     Godot --path <proj> -- --e2e=<scenario> [--e2e-artifacts=<abs dir>]
##                            [--e2e-fen=<fen>] [--e2e-timeout=<sec>]
##
## Driver pattern ported from Duke's Gambit (our own test harness file — no
## game code shared): it drives the REAL running game by synthesizing
## InputEvents through Input.parse_input_event, with the empirical
## canvas->window transform calibration so stretch/HiDPI can never break the
## click math. Never calls handlers directly — the input path IS the test.
##
## Scenarios:
##   boot      scene loads, 32 pieces standing, engine agrees
##   move      click e2 pawn -> e4 via real clicks, AI replies within 30 s
##   duel      (needs --e2e-fen with an immediate white capture) executes the
##             capture by clicks; asserts victim gone from engine AND view,
##             a death animation played, attacker occupies the square
##   castle    (needs --e2e-fen with O-O available) castles by clicks;
##             asserts king AND rook views land on g1/f1 per move metadata
##   promote   (needs --e2e-fen with a promotion push) promotes by clicks;
##             asserts the pawn view was replaced by a queen view
##   showcase  beauty run for Gate C: overview + mid-duel screenshots, then
##             idles to the 30 s mark (shell greps the log for errors)
##
## Output contract (consumed by run_e2e.sh):
##     "E2E PASS <step>" / "E2E FAIL <step> — <reason>" lines,
##     per-step PNGs in the artifacts dir, exit code 0/1, watchdog.

extends Node

var scenario: String = ""
var artifacts_dir: String = ""
var timeout_sec: float = 60.0

var _steps_passed: int = 0
var _shot_i: int = 0
var _done: bool = false
var _to_window: Transform2D = Transform2D.IDENTITY
var _last_input_pos := Vector2(-1e9, -1e9)
var _start_ms := 0

## Observe every event that actually reaches the scene tree — proves
## synthesized events are delivered and learns the coordinate space
## parse_input_event expects.
func _input(event: InputEvent) -> void:
	if scenario != "" and event is InputEventMouse:
		_last_input_pos = (event as InputEventMouse).position

# ── Activation ─────────────────────────────────────────────────────────────
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e2e="):
			scenario = arg.substr(6)
		elif arg.begins_with("--e2e-artifacts="):
			artifacts_dir = arg.substr(16)
		elif arg.begins_with("--e2e-timeout="):
			timeout_sec = float(arg.substr(14))
	if scenario.is_empty():
		return   # dormant — normal gameplay is completely untouched
	if artifacts_dir.is_empty():
		artifacts_dir = ProjectSettings.globalize_path("res://test_e2e/artifacts") \
			+ "/" + scenario
	DirAccess.make_dir_recursive_absolute(artifacts_dir)
	_start_ms = Time.get_ticks_msec()
	print("E2E driver active — scenario=%s timeout=%.0fs artifacts=%s"
		% [scenario, timeout_sec, artifacts_dir])
	_watchdog()
	_run()

# ── Top-level flow ─────────────────────────────────────────────────────────
func _watchdog() -> void:
	await get_tree().create_timer(timeout_sec).timeout
	if _done:
		return
	print("E2E FAIL watchdog — scenario '%s' exceeded %.0fs" % [scenario, timeout_sec])
	await _shot("timeout")
	_finish(1)

func _run() -> void:
	await get_tree().process_frame
	var have_scene := await _wait_until(
		func(): return get_tree().current_scene != null, 20.0)
	if not have_scene:
		await _fail("boot", "no main scene appeared within 20s")
		return
	if not await _calibrate_input():
		await _fail("input-pipeline", "synthesized mouse events do not reach the viewport")
		return
	_pass("input-pipeline")
	match scenario:
		"boot":
			await _scenario_boot()
		"move":
			await _scenario_move()
		"duel":
			await _scenario_duel(false)
		"castle":
			await _scenario_castle()
		"promote":
			await _scenario_promote()
		"showcase":
			await _scenario_duel(true)
		_:
			await _fail("scenario", "unknown scenario '%s'" % scenario)

func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	print("E2E DONE scenario=%s exit=%d steps_passed=%d" % [scenario, code, _steps_passed])
	get_tree().quit(code)

func _pass(step: String) -> void:
	_steps_passed += 1
	print("E2E PASS %s" % step)

func _fail(step: String, why: String) -> void:
	print("E2E FAIL %s — %s" % [step, why])
	await _shot("FAIL_" + step)
	_finish(1)

# ── Generic helpers ────────────────────────────────────────────────────────
func _wait_until(pred: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _done:
			return false
		if pred.call():
			return true
		await get_tree().process_frame
	return false

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(step_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("E2E WARN no viewport image for screenshot '%s'" % step_name)
		return
	_shot_i += 1
	var path := "%s/%02d_%s.png" % [artifacts_dir, _shot_i, step_name]
	var err := img.save_png(path)
	if err != OK:
		print("E2E WARN screenshot save failed (err %d): %s" % [err, path])

# ── Input synthesis ────────────────────────────────────────────────────────
## parse_input_event feeds events as-if-from-the-OS, i.e. in window
## coordinates; unproject() is in canvas coordinates. Calibrate the
## canvas->window transform empirically so stretch/HiDPI differences can
## never break the click math.
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
		print("E2E DEBUG calib sent=%s seen=%s vp_mouse=%s final=%s win=%s" % [
			str(mm.position), str(_last_input_pos), str(vp.get_mouse_position()),
			str(vp.get_final_transform()), str(get_window().size)])
		if _last_input_pos.distance_to(probe) < 2.0:
			_to_window = cand
			return true
	return false

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

# ── Game accessors ─────────────────────────────────────────────────────────
func _game() -> Node:
	var cs := get_tree().current_scene
	if cs != null and cs.get("state") != null and cs.get("board") != null:
		return cs
	return null

func _black_snapshot(state: Object) -> String:
	var parts: PackedStringArray = []
	for i in 64:
		var p = state.pieces[i]
		if p != null and ChessState.piece_color(p):
			parts.append("%d%s" % [i, p])
	return ",".join(parts)

func _click_square(game: Node, sq: Vector2i) -> void:
	var board: Node = game.get("board")
	var world: Vector3 = board.square_to_world(sq)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("E2E WARN no active Camera3D for square click %s" % str(sq))
		return
	var canvas := cam.unproject_position(world)
	print("E2E DEBUG sq=%s world=%s canvas=%s pick_roundtrip=%s behind=%s" % [
		str(sq), str(world), str(canvas), str(board.pick_square(canvas)),
		str(cam.is_position_behind(world))])
	await _click_at(canvas)
	print("E2E DEBUG post-click seen=%s selected=%s busy=%s" % [
		str(_last_input_pos), str(game.get("selected")), str(game.get("busy"))])

## Click a square until it is the selected one (a human would re-click too).
func _select_square(game: Node, sq: Vector2i, attempts: int = 3) -> bool:
	for i in attempts:
		await _click_square(game, sq)
		if await _wait_until(func(): return game.get("selected") == sq, 1.5):
			return true
		print("E2E WARN select attempt %d/%d for %s failed (selected=%s) — retrying"
			% [i + 1, attempts, str(sq), str(game.get("selected"))])
		await _sleep(0.6)
	return false

# ── Shared boot steps ──────────────────────────────────────────────────────
func _boot_game(expected_pieces: int) -> Node:
	var got := await _wait_until(func(): return _game() != null, 20.0)
	if not got:
		await _fail("game-scene-loaded", "game root with state+board never appeared")
		return null
	var game := _game()
	_pass("game-scene-loaded")
	var state: Object = game.get("state")
	var engine_count := 0
	for i in 64:
		if state.pieces[i] != null:
			engine_count += 1
	if expected_pieces > 0 and engine_count != expected_pieces:
		await _fail("boot-engine-pieces",
			"engine holds %d pieces, expected %d" % [engine_count, expected_pieces])
		return null
	var views: Dictionary = game.get("views")
	if views.size() != engine_count:
		await _fail("boot-views-match",
			"%d piece views for %d engine pieces" % [views.size(), engine_count])
		return null
	var standing := 0
	for sq in views:
		var pv: Node = views[sq]
		if is_instance_valid(pv) and pv.get_child_count() > 0:
			standing += 1
	if standing != engine_count:
		await _fail("boot-pieces-standing",
			"only %d/%d piece views have a model" % [standing, engine_count])
		return null
	_pass("boot-pieces-standing (%d)" % standing)
	return game

# ── Scenario: boot ─────────────────────────────────────────────────────────
func _scenario_boot() -> void:
	var game := await _boot_game(32)
	if game == null:
		return
	await _sleep(1.0)   # let idles and torchlight settle for the screenshot
	await _shot("boot_lineup")
	_finish(0)

# ── Scenario: move ─────────────────────────────────────────────────────────
func _scenario_move() -> void:
	var game := await _boot_game(32)
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("move-frost-turn", "never became House Frost's turn")
		return
	_pass("move-frost-turn")
	var e2 := ChessState.square_index_from_name("e2")
	var e4 := ChessState.square_index_from_name("e4")
	if state.pieces[e2] != "P":
		await _fail("move-e2-white-pawn", "e2 holds '%s', not a white pawn" % str(state.pieces[e2]))
		return
	_pass("move-e2-white-pawn")
	var e2_sq: Vector2i = game.sq_of(e2)
	var e4_sq: Vector2i = game.sq_of(e4)
	if not await _select_square(game, e2_sq):
		await _fail("move-select-pawn", "e2 never became the selected square")
		return
	_pass("move-select-pawn")
	await _shot("pawn_selected")
	var black_before := _black_snapshot(state)
	await _click_square(game, e4_sq)
	if not await _wait_until(func():
		return state.pieces[e2] == null and state.pieces[e4] == "P", 5.0):
		await _fail("move-pawn-e4", "engine never showed the pawn on e4")
		return
	_pass("move-pawn-e4")
	await _shot("after_e4")
	if not await _wait_until(func():
		return state.turn == false and _black_snapshot(state) != black_before, 30.0):
		await _fail("move-ai-replied", "AI did not reply within 30s")
		return
	_pass("move-ai-replied")
	if not await _wait_until(func(): return game.get("busy") == false, 15.0):
		await _fail("move-anim-settled", "reply animation never finished")
		return
	_pass("move-anim-settled")
	await _shot("after_ai_reply")
	_finish(0)

# ── Shared: wait for Frost's turn, find + click a scripted move ────────────
func _ready_for_scripted_move(prefix: String) -> Node:
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return null
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail(prefix + "-frost-turn", "never became House Frost's turn")
		return null
	_pass(prefix + "-frost-turn")
	return game

## Click from->to for the first legal move matching pred. Returns the move.
func _click_first_matching(game: Node, pred: Callable, prefix: String) -> Variant:
	var state: Object = game.get("state")
	var move = null
	for m in state.legal_moves():
		if pred.call(m):
			move = m
			break
	if move == null:
		await _fail(prefix + "-move-available", "the FEN offers no matching move")
		return null
	_pass(prefix + "-move-available (%s)" % move.to_uci())
	if not await _select_square(game, game.sq_of(move.from_square)):
		await _fail(prefix + "-select", "%s never became the selected square"
			% str(game.sq_of(move.from_square)))
		return null
	_pass(prefix + "-select")
	await _click_square(game, game.sq_of(move.to_square))
	return move

func _settle(game: Node, step: String) -> bool:
	if not await _wait_until(func(): return game.get("busy") == false, 20.0):
		await _fail(step, "board never settled (busy stuck)")
		return false
	_pass(step)
	return true

# ── Scenario: castle ───────────────────────────────────────────────────────
func _scenario_castle() -> void:
	var game := await _ready_for_scripted_move("castle")
	if game == null:
		return
	var state: Object = game.get("state")
	var move = await _click_first_matching(game,
		func(m): return m.is_castling, "castle")
	if move == null:
		return
	var king_sq: Vector2i = game.sq_of(move.to_square)
	var rook_sq: Vector2i = game.sq_of(move.rook_to)
	if not await _wait_until(func():
		return state.pieces[move.to_square] == "K" \
			and state.pieces[move.rook_to] == "R", 5.0):
		await _fail("castle-engine-applied", "engine never applied %s" % move.to_uci())
		return
	_pass("castle-engine-applied")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.has(king_sq) and v.has(rook_sq) \
			and v[king_sq].piece_type == PieceView.Type.KING \
			and v[rook_sq].piece_type == PieceView.Type.ROOK, 8.0):
		await _fail("castle-views-landed", "king/rook views never landed on %s/%s"
			% [str(king_sq), str(rook_sq)])
		return
	_pass("castle-views-landed")
	await _shot("after_castle")
	if not await _settle(game, "castle-settled"):
		return
	_finish(0)

# ── Scenario: promote ──────────────────────────────────────────────────────
func _scenario_promote() -> void:
	var game := await _ready_for_scripted_move("promote")
	if game == null:
		return
	var state: Object = game.get("state")
	var move = await _click_first_matching(game,
		func(m): return m.promotion != null, "promote")
	if move == null:
		return
	var to_sq: Vector2i = game.sq_of(move.to_square)
	if not await _wait_until(func():
		return str(state.pieces[move.to_square]) == "Q", 5.0):
		await _fail("promote-engine-applied", "no white queen on the promotion square (engine)")
		return
	_pass("promote-engine-applied")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.has(to_sq) and is_instance_valid(v[to_sq]) \
			and v[to_sq].piece_type == PieceView.Type.QUEEN, 8.0):
		await _fail("promote-view-replaced", "no queen view on %s" % str(to_sq))
		return
	_pass("promote-view-replaced")
	await _shot("after_promotion")
	if not await _settle(game, "promote-settled"):
		return
	_finish(0)

# ── Scenario: duel / showcase ──────────────────────────────────────────────
## duel: assert-heavy capture via clicks. showcase: same duel plus beauty
## screenshots and a 30 s zero-error soak (asserted shell-side).
func _scenario_duel(showcase: bool) -> void:
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("duel-frost-turn", "never became House Frost's turn")
		return
	_pass("duel-frost-turn")
	if showcase:
		await _sleep(1.5)
		await _shot("board_overview")
	# Find the scripted capture from the engine itself — the FEN promises one.
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		await _fail("duel-capture-available", "the FEN offers White no capture move")
		return
	_pass("duel-capture-available (%s)" % capture.to_uci())
	var from_sq: Vector2i = game.sq_of(capture.from_square)
	var to_sq: Vector2i = game.sq_of(capture.to_square)
	var victim_sq: Vector2i = game.sq_of(capture.captured_square)
	var victim_idx: int = capture.captured_square
	var views: Dictionary = game.get("views")
	var attacker: Node = views.get(from_sq)
	var victim: Node = views.get(victim_sq)
	if attacker == null or victim == null:
		await _fail("duel-actors-present", "missing attacker/victim view on the board")
		return
	if not await _select_square(game, from_sq):
		await _fail("duel-select-attacker", "%s never became the selected square" % str(from_sq))
		return
	_pass("duel-select-attacker")
	await _shot("attacker_selected")
	var deaths_before: int = (game.get("death_log") as Array).size()
	await _click_square(game, to_sq)
	if not await _wait_until(func():
		return state.pieces[capture.to_square] != null \
			and not ChessState.piece_color(state.pieces[capture.to_square]) \
			and state.pieces[capture.from_square] == null, 5.0):
		await _fail("duel-engine-applied", "engine never applied the capture %s" % capture.to_uci())
		return
	_pass("duel-engine-applied")
	await _sleep(1.1)   # walk + throw wind-up
	await _shot("mid_duel")
	if not await _wait_until(func():
		return (game.get("death_log") as Array).size() > deaths_before, 10.0):
		await _fail("duel-death-anim", "no death animation was recorded")
		return
	var last_death: String = (game.get("death_log") as Array).back()
	_pass("duel-death-anim (%s)" % last_death)
	if not await _wait_until(func(): return not is_instance_valid(victim), 5.0):
		await _fail("duel-victim-removed", "victim view still alive on the board")
		return
	if state.pieces[victim_idx] != null and ChessState.piece_color(state.pieces[victim_idx]):
		await _fail("duel-victim-removed", "black piece still on the captured square (engine)")
		return
	_pass("duel-victim-removed")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.get(to_sq) == attacker, 8.0):
		await _fail("duel-attacker-occupies", "attacker view never registered on %s" % str(to_sq))
		return
	_pass("duel-attacker-occupies")
	await _shot("post_duel")
	# Let Ember's reply (WorkerThreadPool search + animation) finish before
	# quitting — tearing the engine down mid-task segfaults on shutdown.
	if not await _wait_until(func(): return game.get("busy") == false, 20.0):
		await _fail("duel-settled", "board never settled after the duel")
		return
	_pass("duel-settled")
	if showcase:
		while Time.get_ticks_msec() - _start_ms < 30_000 and not _done:
			await _sleep(1.0)
		await _shot("closing_tableau")
		_pass("showcase-30s-soak")
	_finish(0)
