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
## Every game scenario first navigates the Hall of Banners (house select) by
## synthesized clicks: crest -> opponent -> mode, then plays in game.tscn.
##
## Scenarios:
##   boot        select flows into the game, 32 pieces standing, banners
##               dyed to the chosen house, HUD carries the house names
##   move        click e2 pawn -> e4 via real clicks, AI replies within 30 s
##   duel        (needs --e2e-fen with an immediate white capture) executes
##               the capture by clicks; slow-mo duel plays out untouched;
##               asserts victim gone, death anim, attacker arrival, and
##               time_scale restored to 1.0
##   castle      (needs --e2e-fen with O-O available) castles by clicks
##   promote     (needs --e2e-fen with a promotion push) promotes by clicks
##   slowmo      capture triggers the DuelDirector; asserts activation, the
##               time dip, skip-on-click restore, and a clean final settle
##   tournament  Begin Tournament with a mate-in-1 FEN: three rounds of
##               scripted mates; asserts bracket advance, banner re-dress
##               each round, and the championship panel
##   oracle-mock DS4-Oracle (Pure Oracle) against an in-driver canned HTTP
##               mock; asserts a legal oracle move, llm source, thinking HUD
##   oracle-modes Counseled Oracle vs the mock LLM + REAL local stockfish:
##               (needs --e2e-fen with Black to move) the mock's first
##               proposal is a deliberate blunder; asserts the counsel's
##               reconsideration prompt was issued, the blunder was not
##               played, the revised move landed, and the HUD mode label
##   fullgame    complete scripted game (two-rook ladder mate) vs the engine;
##               asserts board/view sync every ply and time_scale hygiene
##   showcase    beauty run for Gate C: hall wide shot, select screen,
##               mid-duel caption frame, idles to the 45 s mark, then the
##               championship throne-room tableau (crowned king + throne +
##               dragon, camera parked on the frame — 09_throne_room.png)
##
## Output contract (consumed by run_e2e.sh):
##     "E2E PASS <step>" / "E2E FAIL <step> — <reason>" lines,
##     per-step PNGs in the artifacts dir, exit code 0/1, watchdog.

extends Node

const DEFAULT_HOUSE := "winterfang"
const MOCK_MODEL := "deepseek-v4-flash-mock"

var scenario: String = ""
var artifacts_dir: String = ""
var timeout_sec: float = 60.0

var _steps_passed: int = 0
var _shot_i: int = 0
var _done: bool = false
var _to_window: Transform2D = Transform2D.IDENTITY
var _last_input_pos := Vector2(-1e9, -1e9)
var _start_ms := 0

# -- mock oracle server state (oracle-mock scenario) --
var _mock_server: TCPServer
var _mock_port := 0
var _mock_running := false
var _mock_replies: Array = []    # queued chat contents; default "MOVE: e7e5"
var _mock_requests: Array = []   # parsed JSON bodies of every chat call

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
	if scenario == "oracle-mock" or scenario == "oracle-modes":
		# The env var must exist before main.gd/game.gd ever build an oracle;
		# autoload _ready runs before the main scene loads, so this is early
		# enough — and each e2e launch is its own process, nothing leaks.
		_start_mock_oracle()
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
		"slowmo":
			await _scenario_slowmo()
		"tournament":
			await _scenario_tournament()
		"oracle-mock":
			await _scenario_oracle_mock()
		"oracle-modes":
			await _scenario_oracle_modes()
		"fullgame":
			await _scenario_fullgame()
		"showcase":
			await _scenario_duel(true)
		_:
			await _fail("scenario", "unknown scenario '%s'" % scenario)

func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	_mock_running = false
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

func _colors_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

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

func _click_control(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center())

# ── Game accessors ─────────────────────────────────────────────────────────
func _game() -> Node:
	var cs := get_tree().current_scene
	if cs != null and cs.get("state") != null and cs.get("board") != null:
		return cs
	return null

func _select_screen() -> Control:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if cs is HouseSelect:
		return cs
	return cs.find_child("HouseSelect", true, false) as Control

func _find_button(root: Node, needle: String) -> Button:
	for b: Button in root.find_children("*", "Button", true, false):
		var label := str(b.get_meta("label")) if b.has_meta("label") else b.text
		if label.contains(needle):
			return b
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

# ── The Hall of Banners (house select) by clicks ───────────────────────────
func _navigate_select(house_id: String, opponent_needle: String, mode_needle: String) -> bool:
	if not await _wait_until(func(): return _select_screen() != null, 15.0):
		await _fail("select-screen", "the Hall of Banners never appeared")
		return false
	var sel: Control = _select_screen()
	await _sleep(0.4)   # deferred ring layout + first draw
	await _shot("house_select")
	var crest: Node = sel.find_child("Crest_%s" % house_id, true, false)
	if crest == null:
		await _fail("select-crest", "no crest for house '%s'" % house_id)
		return false
	await _click_control(crest.get_node("Sigil"))
	if not await _wait_until(func(): return int(sel.get("phase")) == 1, 3.0):
		await _fail("select-house", "crest click did not advance to the opponent phase")
		return false
	_pass("select-house (%s)" % house_id)
	var opp_btn := _find_button(sel, opponent_needle)
	if opp_btn == null:
		await _fail("select-opponent", "no opponent button matching '%s'" % opponent_needle)
		return false
	await _click_control(opp_btn)
	if not await _wait_until(func(): return int(sel.get("phase")) == 2, 3.0):
		await _fail("select-opponent", "opponent click did not advance to the mode phase")
		return false
	_pass("select-opponent (%s)" % opponent_needle)
	var mode_btn := _find_button(sel, mode_needle)
	if mode_btn == null:
		await _fail("select-mode", "no mode button matching '%s'" % mode_needle)
		return false
	await _click_control(mode_btn)
	if not await _wait_until(func(): return _game() != null, 15.0):
		await _fail("select-into-game", "the game scene never appeared after selection")
		return false
	_pass("select-into-game")
	return true

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

## Board/view sync: every engine piece has a live view on its square and no
## orphan views linger. `allow_missing_king` covers the post-checkmate state
## where the mated king's view died under the cinematic.
func _assert_sync(game: Node, step: String, allow_missing_king := false) -> bool:
	var state: Object = game.get("state")
	var views: Dictionary = game.get("views")
	var engine_count := 0
	var missing: Array[String] = []
	for i in 64:
		if state.pieces[i] == null:
			continue
		engine_count += 1
		var sq: Vector2i = game.sq_of(i)
		var pv = views.get(sq)
		if pv == null or not is_instance_valid(pv):
			missing.append("%s(%s)" % [ChessState.square_get_name(i), str(state.pieces[i])])
	if allow_missing_king and missing.size() == 1 \
			and (missing[0].contains("(k)") or missing[0].contains("(K)")):
		missing.clear()
		engine_count -= 1
	if not missing.is_empty() or views.size() != engine_count:
		await _fail(step, "desync: views=%d engine=%d missing=[%s]"
			% [views.size(), engine_count, ",".join(missing)])
		return false
	return true

# ── Scenario: boot ─────────────────────────────────────────────────────────
func _scenario_boot() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	# The hall wears the chosen house's dye (banner 3 = west wall, player).
	var hall: Node = game.get_node_or_null("GreatHall")
	var expect: Color = HouseRegistry.get_colors(DEFAULT_HOUSE)["primary"]
	var got: Color = hall.get_banner(3).house_color
	if not _colors_close(got, expect):
		await _fail("boot-banners-dressed", "west banner %s, expected %s" % [got, expect])
		return
	_pass("boot-banners-dressed")
	var title: Label = game.find_child("Title", true, false)
	if title == null or not title.text.contains(DEFAULT_HOUSE.to_upper()):
		await _fail("boot-hud-houses", "HUD title missing the chosen house: '%s'"
			% (title.text if title != null else "<no Title>"))
		return
	_pass("boot-hud-houses")
	await _sleep(1.0)   # let idles and torchlight settle for the screenshot
	await _shot("boot_lineup")
	_finish(0)

# ── Scenario: move ─────────────────────────────────────────────────────────
func _scenario_move() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("move-player-turn", "never became the player's turn")
		return
	_pass("move-player-turn")
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

# ── Shared: wait for the player's turn, find + click a scripted move ───────
func _ready_for_scripted_move(prefix: String) -> Node:
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return null
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail(prefix + "-player-turn", "never became the player's turn")
		return null
	_pass(prefix + "-player-turn")
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
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
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
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
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
## duel: assert-heavy capture via clicks (the slow-mo duel plays untouched).
## showcase: same duel plus beauty screenshots and a 45 s zero-error soak.
func _scenario_duel(showcase: bool) -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)   # custom FEN — piece count varies
	if game == null:
		return
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("duel-player-turn", "never became the player's turn")
		return
	_pass("duel-player-turn")
	if showcase:
		# Hero wide shot with the env module's framing note (pitch ~-0.55,
		# distance ~13 keeps the far-wall banners in frame).
		var rig: Node = game.get_node_or_null("CameraRig")
		if rig != null:
			rig.set("target_distance", 13.0)
			rig.set("_target_pitch", -0.55)
		await _sleep(1.5)
		await _shot("great_hall_wide")
		if rig != null:
			rig.set("target_distance", 11.5)
			rig.set("_target_pitch", -0.85)
		await _sleep(1.0)
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
	await _sleep(1.2)   # walk + swoop + slow-mo ramp
	await _shot("mid_duel")
	if showcase:
		await _sleep(0.5)
		await _shot("duel_caption")   # inside the caption hold window
	if not await _wait_until(func():
		return (game.get("death_log") as Array).size() > deaths_before, 12.0):
		await _fail("duel-death-anim", "no death animation was recorded")
		return
	var last_death: String = (game.get("death_log") as Array).back()
	_pass("duel-death-anim (%s)" % last_death)
	if not await _wait_until(func(): return not is_instance_valid(victim), 6.0):
		await _fail("duel-victim-removed", "victim view still alive on the board")
		return
	if state.pieces[victim_idx] != null and ChessState.piece_color(state.pieces[victim_idx]):
		await _fail("duel-victim-removed", "black piece still on the captured square (engine)")
		return
	_pass("duel-victim-removed")
	if not await _wait_until(func():
		var v: Dictionary = game.get("views")
		return v.get(to_sq) == attacker, 10.0):
		await _fail("duel-attacker-occupies", "attacker view never registered on %s" % str(to_sq))
		return
	_pass("duel-attacker-occupies")
	await _shot("post_duel")
	# Let the rival's reply (WorkerThreadPool search + animation + possibly
	# its own duel) finish before quitting — tearing the engine down mid-task
	# segfaults on shutdown.
	if not await _wait_until(func(): return game.get("busy") == false, 30.0):
		await _fail("duel-settled", "board never settled after the duel")
		return
	_pass("duel-settled")
	var dd: Node = game.get("duel_director")
	if not await _wait_until(func():
		return not dd.is_active() and is_equal_approx(Engine.time_scale, 1.0), 10.0):
		await _fail("duel-timescale-restored", "time_scale=%f after the duel" % Engine.time_scale)
		return
	_pass("duel-timescale-restored")
	if showcase:
		while Time.get_ticks_msec() - _start_ms < 45_000 and not _done:
			await _sleep(1.0)
		await _shot("closing_tableau")
		_pass("showcase-45s-soak")
		await _showcase_throne_room(game)
	_finish(0)


## Showcase closer: the championship tableau — champion-dyed banners, the
## Throne of Blades, the dragon hovering overhead, the crowned champion king
## on the dais, camera parked framing it all (09_throne_room.png).
func _showcase_throne_room(game: Node) -> void:
	var hall: Node = game.get_node_or_null("GreatHall")
	if hall == null or hall.get("throne") == null:
		await _fail("showcase-throne-present", "the great hall has no throne")
		return
	_pass("showcase-throne-present")
	var views: Dictionary = game.get("views")
	var crowned := false
	for sq in views:
		var pv = views[sq]
		if is_instance_valid(pv) and int(pv.get("piece_type")) == PieceView.Type.KING \
				and pv.find_child("Crown", true, false) != null:
			crowned = true
	if not crowned:
		await _fail("showcase-king-crowned", "no crowned king on the field")
		return
	_pass("showcase-king-crowned")
	var done := {"done": false}
	var runner := func() -> void:
		await game.start_championship_tableau()
		done["done"] = true
	runner.call()
	var dd: Node = game.get("duel_director")
	if not await _wait_until(func(): return dd.is_active(), 15.0):
		await _fail("showcase-tableau-started", "championship tableau never started")
		return
	_pass("showcase-tableau-started")
	if hall.get("dragon") == null:
		await _fail("showcase-dragon-summoned", "no dragon above the throne")
		return
	_pass("showcase-dragon-summoned")
	await _sleep(2.4)   # glide (1.5 s) done — inside the tableau hold
	await _shot("throne_room")
	if not await _wait_until(func(): return done["done"], 25.0):
		await _fail("showcase-tableau-finished", "championship tableau never finished")
		return
	if not await _wait_until(func():
		return not dd.is_active() and is_equal_approx(Engine.time_scale, 1.0), 10.0):
		await _fail("showcase-tableau-clean",
			"director active or time_scale=%f after the tableau" % Engine.time_scale)
		return
	_pass("showcase-throne-room-tableau")

# ── Scenario: slowmo (duel director activation + skip contract) ────────────
func _scenario_slowmo() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var state: Object = game.get("state")
	var dd: Node = game.get("duel_director")
	if dd == null:
		await _fail("slowmo-director", "game has no DuelDirector")
		return
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("slowmo-player-turn", "never became the player's turn")
		return
	var capture = null
	for m in state.legal_moves():
		if m.is_capture():
			capture = m
			break
	if capture == null:
		await _fail("slowmo-capture-available", "the FEN offers no capture")
		return
	if not await _select_square(game, game.sq_of(capture.from_square)):
		await _fail("slowmo-select", "attacker never selected")
		return
	await _click_square(game, game.sq_of(capture.to_square))
	if not await _wait_until(func(): return dd.is_active(), 8.0):
		await _fail("slowmo-activated", "duel director never became active")
		return
	_pass("slowmo-activated")
	if not await _wait_until(func(): return Engine.time_scale < 0.9, 3.0):
		await _fail("slowmo-time-dipped", "time_scale never dipped (%.2f)" % Engine.time_scale)
		return
	_pass("slowmo-time-dipped (%.2f)" % Engine.time_scale)
	await _sleep(0.3)
	await _shot("mid_slowmo")
	# A click mid-cinematic = skip: presentation snaps, time restores fast,
	# gameplay still resolves at normal speed.
	await _click_at(get_viewport().get_visible_rect().size * 0.5)
	if not await _wait_until(func(): return absf(Engine.time_scale - 1.0) < 0.01, 2.0):
		await _fail("slowmo-skip-restores",
			"click-skip did not restore time_scale (%.2f)" % Engine.time_scale)
		return
	_pass("slowmo-skip-restores")
	if not await _wait_until(func(): return not dd.is_active(), 10.0):
		await _fail("slowmo-cinematic-ended", "director stayed active after skip")
		return
	_pass("slowmo-cinematic-ended")
	if not await _wait_until(func():
		return state.pieces[capture.to_square] != null \
			and not ChessState.piece_color(state.pieces[capture.to_square]), 10.0):
		await _fail("slowmo-capture-resolved", "capture never resolved on the engine")
		return
	_pass("slowmo-capture-resolved")
	# Let the rival reply (possibly its own un-skipped duel) fully settle.
	if not await _wait_until(func():
		return game.get("busy") == false and not dd.is_active(), 40.0):
		await _fail("slowmo-settled", "board never settled")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("slowmo-final-timescale", "time_scale=%f after settle" % Engine.time_scale)
		return
	_pass("slowmo-final-timescale-1.0")
	await _shot("post_slowmo")
	_finish(0)

# ── Scenario: tournament (3 scripted mates to the throne) ──────────────────
func _scenario_tournament() -> void:
	if not await _navigate_select("goldclaw", "Casual", "Begin Tournament"):
		return
	var prev_rival := ""
	var prev_banner := Color.BLACK
	for round_i in 3:
		var game := await _boot_game(0)
		if game == null:
			return
		var rival := str(game.get("rival_house_id"))
		if rival.is_empty():
			await _fail("tourn-rival-%d" % round_i, "no rival house resolved")
			return
		if rival == prev_rival:
			await _fail("tourn-rival-advanced-%d" % round_i, "rival did not change (%s)" % rival)
			return
		var hall: Node = game.get_node_or_null("GreatHall")
		var expect: Color = HouseRegistry.get_colors(rival)["primary"]
		var got: Color = hall.get_banner(6).house_color
		if not _colors_close(got, expect):
			await _fail("tourn-banners-%d" % round_i,
				"east banner %s != rival primary %s" % [got, expect])
			return
		if round_i > 0 and _colors_close(got, prev_banner):
			await _fail("tourn-redress-%d" % round_i, "banner color unchanged between rounds")
			return
		prev_rival = rival
		prev_banner = got
		_pass("tourn-round%d-dressing (%s)" % [round_i, rival])
		var state: Object = game.get("state")
		if not await _wait_until(func():
			return game.get("busy") == false and state.turn == false, 15.0):
			await _fail("tourn-turn-%d" % round_i, "never became the player's turn")
			return
		# The FEN promises a mate-in-1 — find it in the SAN'd turn moves.
		var mate = null
		for m in game.get("_turn_moves"):
			if m.notation_san != null and str(m.notation_san).ends_with("#"):
				mate = m
				break
		if mate == null:
			await _fail("tourn-mate-available-%d" % round_i, "FEN offers no mate-in-1")
			return
		if not await _select_square(game, game.sq_of(mate.from_square)):
			await _fail("tourn-select-%d" % round_i, "mate mover never selected")
			return
		await _click_square(game, game.sq_of(mate.to_square))
		if not await _wait_until(func(): return bool(game.get("game_over")), 10.0):
			await _fail("tourn-mate-%d" % round_i, "game never ended after the mate")
			return
		_pass("tourn-round%d-mate" % round_i)
		# The checkmate cinematic (~5 s) ends in victory_panel_requested.
		if not await _wait_until(func():
			var vp = game.get("_victory_panel")
			return vp != null and vp.visible, 25.0):
			await _fail("tourn-victory-panel-%d" % round_i, "victory panel never appeared")
			return
		await _shot("round%d_victory" % round_i)
		# The panel fires before the death tail ends; while the director is
		# active it consumes every click as "skip" — wait for it to let go.
		var dd: Node = game.get("duel_director")
		if not await _wait_until(func(): return not dd.is_active(), 15.0):
			await _fail("tourn-cinematic-released-%d" % round_i,
				"duel director never released input after the checkmate")
			return
		var t = Session.tournament
		if t == null:
			await _fail("tourn-state-%d" % round_i, "Session.tournament is null")
			return
		if round_i < 2:
			if t.is_over():
				await _fail("tourn-bracket-%d" % round_i, "tournament ended early")
				return
			var nxt: String = t.current_opponent()
			if nxt.is_empty() or nxt == rival:
				await _fail("tourn-bracket-advanced-%d" % round_i,
					"bracket did not advance past %s" % rival)
				return
			_pass("tourn-round%d-bracket-advanced (next: %s)" % [round_i, nxt])
			var btn := _find_button(game, "Ride to")
			if btn == null:
				await _fail("tourn-continue-%d" % round_i, "no continue button on the panel")
				return
			await _click_control(btn)
			if not await _wait_until(func():
				var g := _game()
				return g != null and g != game, 15.0):
				await _fail("tourn-next-round-%d" % round_i, "next round scene never loaded")
				return
		else:
			if not t.is_champion():
				await _fail("tourn-champion", "player is not champion after 3 wins")
				return
			if not bool(t.bracket_state().get("complete", false)):
				await _fail("tourn-complete", "bracket not complete after the final")
				return
			_pass("tourn-champion")
			await _sleep(0.6)
			await _shot("championship_panel")
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("tourn-timescale", "time_scale=%f at the end" % Engine.time_scale)
		return
	_pass("tourn-timescale-1.0")
	_finish(0)

# ── Scenario: oracle-mock (DS4-Oracle vs the in-driver canned server) ──────
func _scenario_oracle_mock() -> void:
	if not _mock_running:
		await _fail("oracle-mock-server", "in-driver mock oracle failed to listen")
		return
	_pass("oracle-mock-server (port %d)" % _mock_port)
	if not await _navigate_select(DEFAULT_HOUSE, "Pure Oracle", "Single Match"):
		return
	var game := await _boot_game(32)
	if game == null:
		return
	if game.get("oracle") == null:
		await _fail("oracle-node", "game did not create the Ds4Opponent node")
		return
	_pass("oracle-node")
	var state: Object = game.get("state")
	if not await _wait_until(func():
		return game.get("busy") == false and state.turn == false, 15.0):
		await _fail("oracle-player-turn", "never became the player's turn")
		return
	_mock_replies = ["The pawn answers in kind.\nMOVE: e7e5"]
	var e2 := ChessState.square_index_from_name("e2")
	var e4 := ChessState.square_index_from_name("e4")
	if not await _select_square(game, game.sq_of(e2)):
		await _fail("oracle-select-pawn", "e2 never became the selected square")
		return
	await _click_square(game, game.sq_of(e4))
	if not await _wait_until(func(): return state.pieces[e4] == "P", 5.0):
		await _fail("oracle-e4", "engine never showed the pawn on e4")
		return
	_pass("oracle-e4")
	# The Oracle (mock) must answer with its scripted legal reply.
	var e5 := ChessState.square_index_from_name("e5")
	if not await _wait_until(func(): return str(state.pieces[e5]) == "p", 25.0):
		await _fail("oracle-legal-move",
			"the Oracle's e7e5 never landed (e5='%s')" % str(state.pieces[e5]))
		return
	_pass("oracle-legal-move (e7e5)")
	var oracle: Node = game.get("oracle")
	if str(oracle.last_source) != "llm":
		await _fail("oracle-source-llm", "last_source='%s', expected 'llm'" % str(oracle.last_source))
		return
	_pass("oracle-source-llm")
	if int(game.get("oracle_think_count")) < 1:
		await _fail("oracle-thinking-hud", "thinking_started never reached the HUD")
		return
	_pass("oracle-thinking-hud (%d)" % int(game.get("oracle_think_count")))
	if not await _wait_until(func(): return game.get("busy") == false, 15.0):
		await _fail("oracle-settled", "board never settled after the oracle move")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("oracle-timescale", "time_scale=%f after the oracle move" % Engine.time_scale)
		return
	_pass("oracle-settled")
	await _shot("after_oracle_move")
	_finish(0)

# ── Scenario: oracle-modes (Counseled Oracle: blunder caught by counsel) ───
## Launch with a Black-to-move FEN where d8d2 (Qxd2+??) trades queen for pawn
## and d8d7 is sound (run_e2e.sh's COUNSEL_FEN). The Oracle opens: mock
## proposes the blunder, real stockfish (depth 12) rejects it, the revised
## proposal plays. Covers mode selection clicks, Session->game wiring, the
## HUD mode label, and the reconsideration prompt.
func _scenario_oracle_modes() -> void:
	if not _mock_running:
		await _fail("oracle-modes-server", "in-driver mock oracle failed to listen")
		return
	_pass("oracle-modes-server (port %d)" % _mock_port)
	# Queue the canned proposals BEFORE the game scene boots the Oracle.
	_mock_replies = ["The queen strikes!\nMOVE: d8d2", "Wisdom prevails.\nMOVE: d8d7"]
	if not await _navigate_select(DEFAULT_HOUSE, "Counseled Oracle", "Single Match"):
		return
	var game := _game()
	var oracle: Node = game.get("oracle")
	if oracle == null:
		await _fail("oracle-modes-node", "game did not create the Ds4Opponent node")
		return
	if str(oracle.get("mode")) != "counseled":
		await _fail("oracle-modes-mode",
			"oracle mode '%s', expected 'counseled'" % str(oracle.get("mode")))
		return
	_pass("oracle-modes-mode (counseled)")
	var mode_lbl: Label = game.find_child("OracleMode", true, false)
	if mode_lbl == null or not mode_lbl.text.contains("Counseled"):
		await _fail("oracle-modes-hud", "HUD mode label missing/wrong: '%s'"
			% (mode_lbl.text if mode_lbl != null else "<none>"))
		return
	_pass("oracle-modes-hud (%s)" % mode_lbl.text)
	var state: Object = game.get("state")
	var d7 := ChessState.square_index_from_name("d7")
	var d2 := ChessState.square_index_from_name("d2")
	if not await _wait_until(func(): return str(state.pieces[d7]) == "q", 60.0):
		await _fail("oracle-modes-counseled-move",
			"the counseled d8d7 never landed (d7='%s')" % str(state.pieces[d7]))
		return
	_pass("oracle-modes-counseled-move (d8d7)")
	if str(state.pieces[d2]) != "P":
		await _fail("oracle-modes-blunder-avoided",
			"the d2 pawn is gone — the blunder was played")
		return
	_pass("oracle-modes-blunder-avoided")
	if _mock_requests.size() < 2:
		await _fail("oracle-modes-reconsidered",
			"only %d chat requests — no reconsideration issued" % _mock_requests.size())
		return
	var msgs: Array = _mock_requests[1].get("messages", [])
	var prompt2 := String((msgs.back() as Dictionary).get("content", "")) \
		if not msgs.is_empty() else ""
	if not prompt2.contains("Choose again"):
		await _fail("oracle-modes-reconsidered", "second request lacks the reconsideration prompt")
		return
	_pass("oracle-modes-reconsidered")
	if not str(oracle.get("last_source")).begins_with("counseled"):
		await _fail("oracle-modes-source", "last_source='%s'" % str(oracle.get("last_source")))
		return
	_pass("oracle-modes-source (%s)" % str(oracle.get("last_source")))
	if not await _wait_until(func(): return game.get("busy") == false, 20.0):
		await _fail("oracle-modes-settled", "board never settled after the counseled move")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		await _fail("oracle-modes-timescale", "time_scale=%f" % Engine.time_scale)
		return
	_pass("oracle-modes-settled")
	await _shot("after_counseled_move")
	_finish(0)

# ── Scenario: fullgame (two-rook ladder mate, Gate D) ──────────────────────
func _scenario_fullgame() -> void:
	if not await _navigate_select(DEFAULT_HOUSE, "Casual", "Single Match"):
		return
	var game := await _boot_game(0)
	if game == null:
		return
	var state: Object = game.get("state")
	var dd: Node = game.get("duel_director")
	var white_plies := 0
	while white_plies < 40:
		if not await _wait_until(func():
			return bool(game.get("game_over")) \
				or (game.get("busy") == false and state.turn == false and not dd.is_active()), 40.0):
			await _fail("fullgame-turn", "board never settled for White ply %d" % (white_plies + 1))
			return
		if bool(game.get("game_over")):
			break
		if not is_equal_approx(Engine.time_scale, 1.0):
			await _fail("fullgame-timescale", "time_scale=%f between moves" % Engine.time_scale)
			return
		if not await _assert_sync(game, "fullgame-sync-ply%d" % white_plies):
			return
		var mv = _ladder_pick(state, game)
		if mv == null:
			await _fail("fullgame-plan", "ladder found no move at ply %d" % white_plies)
			return
		if not await _select_square(game, game.sq_of(mv.from_square)):
			await _fail("fullgame-select", "could not select the mover for %s" % mv.to_uci())
			return
		await _click_square(game, game.sq_of(mv.to_square))
		if not await _wait_until(func():
			return state.turn == true or bool(game.get("game_over")), 6.0):
			await _fail("fullgame-applied", "engine never applied %s" % mv.to_uci())
			return
		white_plies += 1
	if white_plies >= 40:
		await _fail("fullgame-mate", "no mate within 40 White moves")
		return
	_pass("fullgame-mate-reached (%d white moves)" % white_plies)
	if state.get_result() != ChessState.RESULT.CHECKMATE or state.turn != true:
		await _fail("fullgame-result", "expected Black checkmated, result=%d" % state.get_result())
		return
	_pass("fullgame-checkmate")
	if not await _wait_until(func():
		var vp = game.get("_victory_panel")
		return vp != null and vp.visible, 25.0):
		await _fail("fullgame-victory-panel", "victory panel never appeared")
		return
	_pass("fullgame-victory-panel")
	if not await _wait_until(func():
		return is_equal_approx(Engine.time_scale, 1.0) and not dd.is_active(), 10.0):
		await _fail("fullgame-timescale-restored",
			"time_scale=%f after the end" % Engine.time_scale)
		return
	_pass("fullgame-timescale-restored")
	if not await _assert_sync(game, "fullgame-final-sync", true):
		return
	_pass("fullgame-final-sync")
	await _shot("fullgame_end")
	_finish(0)

## Two-rook ladder policy: mate-in-1 if available, else fence the row below
## the black king, else check on the king's row from a safe distance,
## sliding the fence away when the king hunts it. Falls back to any
## non-drawing move (never needed on a clean ladder).
func _ladder_pick(state: Object, game: Node) -> Variant:
	var moves: Array = game.get("_turn_moves")
	for m in moves:
		if m.notation_san != null and str(m.notation_san).ends_with("#"):
			return m
	var bk: int = state.get_king(true)
	@warning_ignore("integer_division")
	var kr: int = bk / 8
	var kc: int = bk % 8
	var rooks: Array[int] = []
	for i in 64:
		if str(state.pieces[i]) == "R":
			rooks.append(i)
	var fence := -1
	for r in rooks:
		@warning_ignore("integer_division")
		if r / 8 == kr + 1:
			fence = r
	if fence >= 0 and absi(fence % 8 - kc) <= 1:
		var flee = _rook_to_row(moves, fence, kr + 1, kc, 3)
		if flee != null:
			return flee
	if fence < 0:
		for r in rooks:
			var build = _rook_to_row(moves, r, kr + 1, kc, 2)
			if build != null:
				return build
	else:
		for r in rooks:
			if r == fence:
				continue
			var chk = _rook_to_row(moves, r, kr, kc, 2)
			if chk != null:
				return chk
	for m in moves:
		var probe = state.duplicate(false)
		var pm = probe.move_from_uci(m.to_uci())
		if pm == null:
			continue
		probe.apply_move(pm)
		var res: int = probe.get_result()
		if res == ChessState.RESULT.ONGOING or res == ChessState.RESULT.CHECKMATE:
			return m
	return null

func _rook_to_row(moves: Array, from_idx: int, want_row: int, king_col: int,
		min_dist: int) -> Variant:
	var best = null
	var best_d := -1
	for m in moves:
		if m.from_square != from_idx:
			continue
		@warning_ignore("integer_division")
		var tr: int = m.to_square / 8
		var tc: int = m.to_square % 8
		if tr != want_row:
			continue
		var d := absi(tc - king_col)
		if d < min_dist:
			continue
		if d > best_d:
			best_d = d
			best = m
	return best

# ── Canned OpenAI-style HTTP mock (oracle-mock scenario) ───────────────────
func _start_mock_oracle() -> bool:
	_mock_server = TCPServer.new()
	if _mock_server.listen(0, "127.0.0.1") != OK:
		return false
	_mock_port = _mock_server.get_local_port()
	OS.set_environment(Ds4Opponent.ENV_URL, "http://127.0.0.1:%d" % _mock_port)
	_mock_running = true
	_pump_mock.call_deferred()
	print("E2E mock oracle listening on 127.0.0.1:%d" % _mock_port)
	return true

func _pump_mock() -> void:
	while _mock_running:
		if _mock_server.is_connection_available():
			var peer := _mock_server.take_connection()
			await _handle_mock_conn(peer)
		await get_tree().process_frame

func _handle_mock_conn(peer: StreamPeerTCP) -> void:
	peer.set_no_delay(true)
	var raw := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 5000
	var header_end := -1
	var content_len := 0
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var chunk: Array = peer.get_data(n)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		if header_end < 0:
			header_end = _find_header_end(raw)
			if header_end >= 0:
				content_len = _parse_content_length(
					raw.slice(0, header_end).get_string_from_utf8())
		if header_end >= 0 and raw.size() >= header_end + content_len:
			break
		await get_tree().process_frame
	if header_end < 0:
		peer.disconnect_from_host()
		return
	var request_line := raw.slice(0, header_end).get_string_from_utf8().get_slice("\r\n", 0)
	var path := request_line.get_slice(" ", 1)
	var response_body: String
	if path.ends_with("/models"):
		response_body = JSON.stringify({
			"object": "list",
			"data": [{"id": MOCK_MODEL, "object": "model"}],
		})
	else:
		var body_text := raw.slice(header_end, header_end + content_len).get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(body_text)
		_mock_requests.append(parsed if parsed is Dictionary else {})
		var content := "MOVE: e7e5"
		if not _mock_replies.is_empty():
			content = _mock_replies.pop_front()
		response_body = JSON.stringify({
			"id": "chatcmpl-e2e-mock",
			"object": "chat.completion",
			"model": MOCK_MODEL,
			"choices": [{
				"index": 0,
				"message": {"role": "assistant", "content": content},
				"finish_reason": "stop",
			}],
			"usage": {"prompt_tokens": 0, "completion_tokens": 0},
		})
	var body_bytes := response_body.to_utf8_buffer()
	var head := ("HTTP/1.1 200 OK\r\n" +
		"Content-Type: application/json\r\n" +
		"Content-Length: %d\r\n" % body_bytes.size() +
		"Connection: close\r\n\r\n")
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body_bytes)
	for i in 8:  # let the client drain before we hang up
		peer.poll()
		await get_tree().process_frame
	peer.disconnect_from_host()

func _find_header_end(raw: PackedByteArray) -> int:
	for i in range(0, raw.size() - 3):
		if raw[i] == 13 and raw[i + 1] == 10 and raw[i + 2] == 13 and raw[i + 3] == 10:
			return i + 4
	return -1

func _parse_content_length(headers: String) -> int:
	for line in headers.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.get_slice(":", 1).strip_edges())
	return 0
