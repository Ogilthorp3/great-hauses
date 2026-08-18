extends Node3D
## Great Hauses — game root. The player's chosen Great Haus battles a rival
## house across a torch-lit hall: full rules via src/chess, capture duels in
## slow motion (DuelDirector), house-dyed armies and banners, SAN move list,
## tournament bracket between matches, an optional DS4-Oracle opponent,
## undo/take-back (HUD button + Cmd/Ctrl+Z — 3 per game in tournaments,
## unlimited in single matches), and hover-only type-glyph rings.
##
## PROMOTION IS A CHOICE (Albert's bug, closed 2026-08-09). A promoting pawn
## opens `PromotionPicker` — all four pieces as the real models in the
## promoting haus's kit — and the chosen ChessMove is what goes to the engine,
## to the AI's board, and onto the wire. See `_moves_for`/`_choose_promotion`.
##
## Flow: main.tscn boots the Hall of Banners; Session carries the choices
## here. Unconfigured launches (probes, --smoke, direct game.tscn runs) fall
## back to the legacy Frost-vs-Ember skin so every old hook keeps working.
##
## Command-line hooks (after "--"):
##   --difficulty=easy|medium|hard   AI strength when Session is unconfigured
##   --e2e-fen=<fen>                 start from a custom position
##   --smoke                         windowed: wait 3 s, screenshot, quit
##   --dump-tree                     headless-safe: print scene tree, quit
##   --debug-coords                  world-space file/rank/royal labels showing
##                                   the ENGINE'S OWN square beliefs (the
##                                   orientation tiebreaker — see e2e
##                                   'orientation' scenario)
##
## HEAD-TO-HEAD (Session.mode == "network", src/net/**). The same board, the
## same duels, one difference that reaches everywhere: THE PLAYER IS NOT
## ALWAYS WHITE. `player_color` (false = White) replaces every bare
## `state.turn` test, the camera sits behind whichever army is the player's,
## and the rival's plies arrive from the wire instead of from ChessAI.
## Take-backs are disabled outright in a network match — see `_request_undo`.

const PieceScene: PackedScene = preload("res://scenes/piece_view.tscn")
const MAIN_SCENE := "res://scenes/main.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

const CHAR_TO_TYPE := {
	"p": PieceView.Type.PAWN, "r": PieceView.Type.ROOK, "n": PieceView.Type.KNIGHT,
	"b": PieceView.Type.BISHOP, "q": PieceView.Type.QUEEN, "k": PieceView.Type.KING,
}

const PIECE_NAME := {
	"p": "pawn", "r": "rook", "n": "knight", "b": "bishop", "q": "queen", "k": "king",
}

const BLUNDER_CP := 150.0            # eval swing that counts as a player blunder
const BLUNDER_DEPTH := 8             # shallow probe — a signal, not counsel

const CaptureLedgerScript := preload("res://src/cinematics/capture_ledger.gd")
const MomentContextScript := preload("res://src/cinematics/moment_context.gd")
const MomentScoreScript := preload("res://src/cinematics/moment_score.gd")
const MomentGovernorScript := preload("res://src/cinematics/moment_governor.gd")
const ZeldaEasterEggsScript := preload("res://src/cinematics/zelda_easter_eggs.gd")
const HoloChessGamificationScript := preload("res://src/cinematics/holochess_gamification.gd")
const CoachEngineScript := preload("res://src/coach/coach_engine.gd")
const CoachOverlayScript := preload("res://src/coach/coach_overlay.gd")
const DevConsoleScript := preload("res://src/ui/dev_console.gd")
const JediCouncilOpponentScript := preload("res://src/ai/jedi_council.gd")
const CathedralCinematicIntroScript := preload("res://src/cinematics/cathedral_cinematic_intro.gd")

const TOURNAMENT_UNDO_LIMIT := 3     # take-backs per tournament game (single: unlimited)

const RESULT_TEXT := {
	ChessState.RESULT.STALEMATE: "Stalemate — the war ends in a draw",
	ChessState.RESULT.INSUFFICIENT: "Draw — neither haus can force mate",
	ChessState.RESULT.FIFTY_MOVE: "Draw — fifty quiet moves",
	ChessState.RESULT.THREEFOLD: "Draw — threefold repetition",
}

@onready var board: BoardView = $Board

var state: ChessState
var ai := ChessAI.new()
var ai_difficulty := ChessAI.Difficulty.MEDIUM

var duel_director: DuelDirector
var banter: BanterEngine = null      # non-null only with a registry rival (legacy skin skipped)
var spectator: DragonSpectator = null
var _easter_eggs = null
var _holochess = null
var _coach_overlay = null
var _dev_console = null
var _last_coach_analysis: Dictionary = {}
var oracle: Node = null       # non-null vs DS4-Oracle or Jedi Council
var oracle_thinking := false
var oracle_think_count := 0          # e2e evidence: thinking HUD fired
var oracle_stumble_count := 0        # e2e evidence: fallback was surfaced
var _oracle_think_start_ms := 0

var player_house_id := ""            # "" = legacy Frost/Ember skin
var rival_house_id := ""
var _player_display := "Haus Frost"
var _rival_display := "Haus Ember"

# -- which army is MINE ------------------------------------------------------
# Single player is always White, and for four months "the player's turn" was
# spelled `not state.turn` in a dozen places. Head-to-head broke that: the
# host may choose Black. `player_color` is the one fact those dozen places now
# ask, and it defaults to White so every single-player path is untouched.
var player_color := false            # false = White, true = Black
var net: NetMatch = null             # non-null only in a head-to-head match
var _net_disconnected := false
## The host owes us an answer and is past its deadline (verifier defect P1).
## NOT the same as _net_disconnected: the socket may be perfectly alive and the
## answer may still arrive, so this state is RECOVERABLE — the panel closes
## again by itself if the host wakes up.
var _net_stalled := false
var net_stalled_count := 0           # e2e evidence: the deadline actually fired
var _net_status: Label
var _net_panel: PanelContainer
var _net_panel_label: Label
## e2e evidence: one entry per ply that completed the full network round trip.
var net_plies: Array[String] = []    # "seq|uci|fen"
var net_rejections: Array[String] = []
signal net_ply_settled(seq: int, fen: String)

var views: Dictionary = {}          # Vector2i (board sq) -> PieceView
var selected: Variant = null        # Vector2i, or null
var busy := false                   # move/duel animation or AI turn in flight
var game_over := false
var death_log: Array[String] = []   # death anims played (e2e evidence)

# -- undo / take-back state (see the "undo" section below) --
var undo_count := 0                 # e2e evidence: take-backs executed
var _turn_gen := 0                  # bumped on every undo; a stale AI reply is void
var _ai_waiting := false            # inside choose_move await — the cancellable window
var _undo_checkpoints: Array = []   # one per player move: {stack, san, banter_ply}
var _undo_pending := false          # queued while a cinematic/animation owns the board
var _undos_left := -1               # -1 = unlimited (single match); tournament = 3
var _undo_btn: Button

var _hovered_view: PieceView = null # glyph ring currently hover-revealed

# -- promotion (Albert's bug: a pawn was forced to become a queen) -----------
## The modal while it is up — non-null means it owns the board and the
## keyboard. Read by the e2e harness.
var promo_picker: PromotionPicker = null
## Every piece the PLAYER chose, in order ("q"/"r"/"b"/"n") — e2e evidence.
var promo_picks: Array[String] = []
## Every promotion that actually landed on this board, either side, as
## "<uci>|<piece>|<mover>" — the AI's and the wire's included (e2e evidence).
var promotions_played: Array[String] = []

var _turn_moves: Array = []         # SAN-notated legal moves for side to move
var _san_log: Array[String] = []

var _turn_label: Label
var _casualty_label: RichTextLabel
var _move_list: RichTextLabel
var _oracle_flash: Label
var _oracle_caption: Label
var _banter_caption: Label
## Generation token for the banter caption: a newer taunt abandons the older
## one's fade / yield loop instead of racing it.
var _banter_token := 0
## How long a taunt will wait for the cinematic caption to clear before it
## gives up and speaks anyway (a caption must never be lost outright).
const BANTER_YIELD_MAX_SEC := 6.0

# shared blunder probe (one shallow Stockfish sample feeds banter + dragon)
var _blunder_engine: UciEngine = null
var _blunder_failed := false
var _blunder_busy := false
var blunder_count := 0               # e2e evidence: the blunder hook fired
var _victory_panel: PanelContainer
var _victory_label: Label
var _continue_btn: Button
var _concede_panel: PanelContainer
var _concede_btn: Button
var _victory_shown := false
var _next_action := "rematch"       # "rematch" | "next_round" | "hall"

# 3-Tier Cinematic VFX Moments System
var ledger = CaptureLedgerScript.new()
var governor = MomentGovernorScript.new()

# ── THE CEREMONY OWNS THE FRAME (critic defect P2, 2026-08-09) ─────────────
# Three separate pieces of UI were sitting ON TOP of the best shot in the
# game: the HUD title block lay across the dragon's neck and skull in the
# throne-room frame, and the checkmate modal opened over the wyrm while the
# ASHFALL ceremony was still playing behind it. A cinematic is a shot, not a
# background — so while one is running the chrome fades out and the verdict
# card waits its turn.
## Every HUD control that is CHROME (readouts, controls, scrim) — never the
## victory panel and never a caption, which have their own rules.
var _hud_chrome: Array[Control] = []
var _cine_depth := 0                # nested/chained cinematics: fade once
var _chrome_fade := 0               # generation token for the wall-clock fades
## The verdict card, queued while a ceremony is still on screen.
var _victory_pending := ""
var _victory_held := false
## What a drawn TOURNAMENT match did to the bracket, in the player's words —
## filled by the draw seam (`settle_tournament_draw`) before the card opens.
var _draw_bracket_lines: Array[String] = []


## ── THE MATCH-LOAD BREAKDOWN ───────────────────────────────────────────────
## The one stall a player of this game actually sees is at match load: a
## single frozen frame the moment the Hall hands over to the board, in every
## audited run, at both resolutions, in both scene versions.
##
## It measures ~180 ms on a warm load and ~550 ms on the first load of a
## process. (Thirteen earlier runs reported 113-152 ms; that was the harness
## discarding the real frame at a phase boundary — see perf_driver.gd's
## `_set_phase`. The stall was always worse than the number.)
##
## A per-second summary can say "match-load hitched"; it can never say WHICH
## part of `_ready()` did it, and "somewhere in match-load" is not a fix.
##
## So `_ready()` is bracketed step by step on the WALL clock. The lines only
## exist when the perf harness is in the tree (it sets the `perf_trace` meta
## before main.tscn boots) — a shipped launch never creates that node, so the
## player pays one `has_meta` per match load and nothing else.
var _perf_trace := false
var _perf_t0 := 0
var _perf_step_us := 0


func _lt(step: String) -> void:
	if not _perf_trace:
		return
	var now := Time.get_ticks_usec()
	print("PERF LOADSTEP step=%s ms=%.2f cum_ms=%.2f t_us=%d" % [
		step, float(now - _perf_step_us) / 1000.0,
		float(now - _perf_t0) / 1000.0, now])
	_perf_step_us = now


## THE THREE MARKS THAT SPLIT A SCENE SWAP. `_ready()` alone cannot see the
## work that happens BEFORE it: the PackedScene is parsed, every node is
## constructed, and every CHILD's `_ready()` runs (children are readied before
## their parent) — the Great Hall builds its whole room in there. Marking
## `_init` and `_enter_tree` turns "somewhere in the scene swap" into three
## named intervals:
##   load+construct   the swap frame up to _init  (ResourceLoader + node build)
##   construct->tree  _init -> _enter_tree
##   children-ready   _enter_tree -> _ready       (GreatHall, BoardView, camera)
var _perf_init_us := 0
var _perf_tree_us := 0


func _init() -> void:
	_perf_init_us = Time.get_ticks_usec()


func _apply_visual_profile() -> void:
	# Keep empty stub or default visual profile settings
	pass


# ── Developer Console Live 3D Testing Hooks ───────────────────────────────


func test_switch_house(new_hid: String) -> void:
	if not HouseRegistry.has_house(new_hid):
		return
	player_house_id = new_hid
	Session.player_house = new_hid
	_player_display = _house_name(player_house_id)
	_dress_hall()
	_update_turn_label()
	_spawn_from_state()


func test_stage_duel(attacker_type: int = -1, victim_type: int = -1) -> void:
	if duel_director == null:
		return
	var a_type := attacker_type if attacker_type >= 0 else 2 # default Knight
	var v_type := victim_type if victim_type >= 0 else 5  # default King

	# Spawn or locate combatants
	var attacker: PieceView = null
	var victim: PieceView = null

	for sq in views:
		var pv: PieceView = views[sq]
		if pv == null:
			continue
		if attacker == null and pv.house == PieceView.House.FROST and pv.piece_type == a_type:
			attacker = pv
		elif victim == null and pv.house == PieceView.House.EMBER and pv.piece_type == v_type:
			victim = pv

	if attacker == null:
		attacker = _spawn(a_type, PieceView.House.FROST, Vector2i(4, 3))
	if victim == null:
		victim = _spawn(v_type, PieceView.House.EMBER, Vector2i(4, 4))

	var d_meta := _duel_meta(false)
	d_meta["tier"] = 2
	await duel_director.play_duel(attacker, victim, d_meta, func():
		await attacker.play_capture(victim)
	)
	await get_tree().create_timer(0.4).timeout
	_spawn_from_state()


func test_piece_animation(piece_type: int = -1) -> void:
	for sq in views:
		var pv: PieceView = views[sq]
		if pv != null and (piece_type < 0 or pv.piece_type == piece_type):
			await pv.play_victory_flourish()
			return


func test_dragon_action(action: String) -> void:
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall != null and is_instance_valid(hall):
		var cd = hall.get("cathedral_dragon")
		if cd != null and is_instance_valid(cd) and cd.has_method("swoop_over_altar"):
			cd.swoop_over_altar()
	if spectator == null:
		return
	match action.to_lower():
		"wake":
			spectator.react_brilliant()
		"roar":
			spectator.react_blunder()
		"breathe", "fire":
			spectator.react_capture(Vector2i(4, 4))
		"ashfall":
			spectator.play_ashfall(false, player_house_id)


func test_dragon_scale(scale_val: float) -> void:
	if spectator != null and spectator.rig != null:
		spectator.dragon_scale = scale_val
		spectator.rig.scale = Vector3.ONE * scale_val


func _enter_tree() -> void:
	_perf_tree_us = Time.get_ticks_usec()


func _ready() -> void:
	_perf_trace = Engine.has_meta("perf_trace")
	_perf_t0 = _perf_init_us
	_perf_step_us = _perf_init_us
	_lt("init->enter_tree")
	_perf_step_us = _perf_tree_us
	_lt("children-ready (GreatHall+Board+camera)")
	# visionOS XR bring-up, PHASE 2 (src/xr/visionos_boot.gd). PHASE 1 (the
	# XRSession start-up call) already ran in main.gd._ready(), before this
	# scene existed — this is the earliest point the rig (XROrigin3D/XRCamera3D,
	# tagged "xr_origin"/"xr_camera" in this very scene) can possibly be
	# resolved: it is a static child of Game, and Godot always finishes a
	# child's _ready() before its parent's, so it is already in the tree by
	# the time this line runs. On desktop (no visionOS interface, phase 1
	# never reached "done") this returns a clean, non-fatal
	# {ok: false, step: "not_active"} — never a crash, never a silent no-op.
	var xr_bind := XRSession.bind_rig(get_tree())
	if not xr_bind.ok and OS.get_name() == "visionOS":
		push_error("visionOS XR rig bind failed at '%s': %s" % [xr_bind.step, xr_bind.error])
	# ---- XR DIAGNOSTIC LOG PHASE 2 (2026-08-12 bring-up) ----
	var _xr_log := FileAccess.open("user://xr_debug.log", FileAccess.READ_WRITE)
	if _xr_log:
		_xr_log.seek_end()
		_xr_log.store_line("\n--- Phase 2: game.gd._ready() ---")
		_xr_log.store_line("xr_bind.ok: %s" % str(xr_bind.ok))
		_xr_log.store_line("xr_bind.step: %s" % str(xr_bind.step))
		_xr_log.store_line("xr_bind.error: %s" % str(xr_bind.get("error", "")))
		_xr_log.store_line("XRSession.is_immersive(): %s" % str(XRSession.is_immersive()))
		_xr_log.store_line("tree.root.use_xr: %s" % str(get_tree().root.use_xr))
		var vp_size = get_tree().root.size
		_xr_log.store_line("tree.root.size: %s" % str(vp_size))
		var primary_iface = XRServer.primary_interface
		_xr_log.store_line("XRServer.primary_interface: %s" % (primary_iface.name if primary_iface else "null"))
		if primary_iface:
			_xr_log.store_line("  initialized: %s" % str(primary_iface.is_initialized()))
			_xr_log.store_line("  play_area_mode: %s" % str(primary_iface.xr_play_area_mode))
		var xr_origin = get_tree().get_first_node_in_group("xr_origin")
		var xr_cam = get_tree().get_first_node_in_group("xr_camera")
		_xr_log.store_line("xr_origin: %s (current=%s, global_pos=%s)" % [
			xr_origin.name if xr_origin else "null",
			str(xr_origin.current) if xr_origin else "?",
			str(xr_origin.global_position) if xr_origin else "?"])
		_xr_log.store_line("xr_camera: %s (current=%s, global_pos=%s)" % [
			xr_cam.name if xr_cam else "null",
			str(xr_cam.current) if xr_cam else "?",
			str(xr_cam.global_position) if xr_cam else "?"])
		var orbit_cam = get_node_or_null("CameraRig/Camera3D")
		_xr_log.store_line("orbit_cam.current: %s" % (str(orbit_cam.current) if orbit_cam else "null"))
		_xr_log.store_line("--- end ---")
		_xr_log.close()
	# Camera setup: XR on visionOS, OrbitCamera on desktop
	if XRSession.is_immersive():
		var orbit_cam := get_node_or_null("CameraRig/Camera3D")
		if orbit_cam:
			orbit_cam.current = false
		var orbit_rig := get_node_or_null("CameraRig")
		if orbit_rig:
			orbit_rig.set_process(false)
			orbit_rig.set_process_unhandled_input(false)
		var xr_cam := get_tree().get_first_node_in_group("xr_camera")
		if xr_cam:
			xr_cam.current = true
	else:
		var orbit_cam := get_node_or_null("CameraRig/Camera3D") as Camera3D
		if orbit_cam:
			orbit_cam.current = true
		var xr_cam := get_tree().get_first_node_in_group("xr_camera") as Camera3D
		if xr_cam:
			xr_cam.current = false

	# Snapshot SubViewport for visual test tooling
	var snap_vp := SubViewport.new()
	snap_vp.name = "SnapViewport"
	snap_vp.size = Vector2i(1280, 720)
	snap_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	snap_vp.use_xr = false
	var snap_cam := Camera3D.new()
	snap_cam.name = "SnapCamera"
	snap_cam.fov = 50.0
	snap_cam.near = 0.1
	snap_cam.far = 100.0
	snap_vp.add_child(snap_cam)
	add_child(snap_vp)
	var fen := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--difficulty="):
			match arg.substr(13):
				"easy": ai_difficulty = ChessAI.Difficulty.EASY
				"medium": ai_difficulty = ChessAI.Difficulty.MEDIUM
				"hard": ai_difficulty = ChessAI.Difficulty.HARD
				_: push_warning("unknown difficulty '%s', using medium" % arg.substr(13))
		elif arg.begins_with("--e2e-fen="):
			fen = arg.substr(10)
	_resolve_identity()
	if Session.configured and Session.mode == "tournament":
		_undos_left = TOURNAMENT_UNDO_LIMIT
	if Session.is_network():
		# The HOST's position is the only position. Its --e2e-fen rode across
		# the wire in match_ready, so the joiner never reads its own flag.
		fen = Session.net_start_fen
		_undos_left = 0             # take-backs are off online (see _request_undo)
	_lt("args+identity")
	state = ChessState.new()
	if not fen.is_empty() and not state.set_fen(fen):
		push_error("invalid --e2e-fen '%s' — using the standard lineup" % fen)
	_lt("chess-state")
	duel_director = DuelDirector.new()
	duel_director.name = "DuelDirector"
	add_child(duel_director)
	duel_director.victory_panel_requested.connect(_on_victory_panel_requested)
	# Music rides the director's own cinematic signals: every cinematic ducks
	# the playlist −8 dB; only the duel also fires a stinger at the slow-mo.
	duel_director.cinematic_started.connect(_on_cinematic_started)
	duel_director.cinematic_finished.connect(func(_kind: String) -> void:
		Music.unduck()
		_chrome_for_cinematic(false))
	_lt("duel-director")
	_easter_eggs = ZeldaEasterEggsScript.new()
	_easter_eggs.name = "ZeldaEasterEggs"
	add_child(_easter_eggs)
	_holochess = HoloChessGamificationScript.new()
	_holochess.name = "HoloChessGamification"
	add_child(_holochess)
	_coach_overlay = CoachOverlayScript.new()
	_coach_overlay.name = "CoachOverlay"
	add_child(_coach_overlay)
	_coach_overlay.hint_requested.connect(_on_coach_hint_requested)
	_coach_overlay.stockfish_hint_requested.connect(_on_stockfish_hint_requested)
	_coach_overlay.leela_hint_requested.connect(_on_leela_hint_requested)
	_dev_console = DevConsoleScript.new()
	_dev_console.name = "DevConsole"
	_dev_console.set_game_ref(self)
	add_child(_dev_console)
	_setup_spectator()
	if Session.configured and (str(Session.opponent.get("kind", "")) == "ds4_oracle" or str(Session.opponent.get("kind", "")) == "jedi_council"):
		if str(Session.opponent.get("kind", "")) == "jedi_council":
			oracle = JediCouncilOpponentScript.new()
			oracle.name = "JediCouncil"
			oracle.mode = str(Session.opponent.get("council_mode", "jedi_council"))
		else:
			oracle = Ds4Opponent.new()
			oracle.name = "Oracle"
			oracle.mode = str(Session.opponent.get("oracle_mode", Ds4Opponent.MODE_PURE))
		add_child(oracle)
		oracle.thinking_started.connect(_on_oracle_thinking_started)
		oracle.thinking_finished.connect(_on_oracle_thinking_finished)
		oracle.oracle_stumbled.connect(_on_oracle_stumbled)
		oracle.retry_attempted.connect(_on_oracle_retry)
		oracle.oracle_reason.connect(_on_oracle_reason)
	_lt("oracle")
	_build_hud()
	_lt("hud")
	## ── WHY THIS IS STILL ONE FRAME, AND WHAT IT COSTS ────────────────────
	## Everything from here to the end of `_ready()` runs inside the SAME
	## frame as the scene swap, and that frame is the one stall a player of
	## this game actually feels. Measured at 1080p over four consecutive
	## loads in one process (`run_perf.sh load`, PERF LOADSTEP lines):
	##
	##   dress-hall        58 ms on EVERY load — it never warms up
	##   spawn-32-pieces  362 ms on the first load, 15 ms on every load after
	##                    (first use builds each type x house mesh/material
	##                    pair into the PieceAssets cache — CPU construction,
	##                    not shader compilation: it completes before any draw)
	##
	## Spreading this across frames was tried, measured, and REVERTED. It
	## works (worst frame 181 -> 153 ms warm, 550 -> 343 ms cold) but it
	## breaks a contract this game makes everywhere else: `e2e_driver.gd`'s
	## `_boot_game()` checks `views.size()` against the engine's piece count
	## the instant `_game()` is non-null, and eighteen scenarios depend on it.
	## A staggered board is empty for those frames. Deferring the spawn means
	## renegotiating "the board is complete when the scene exists", which is a
	## coordinated change to the harness, not a local one.
	##
	## The fix that does NOT break that contract is to warm `game.tscn` during
	## the Hall of Banners: `main.gd::_on_selection_complete` already waits
	## 0.75 s ("let the 'rides to war' banner breathe") before
	## `change_scene_to_file`, and a `ResourceLoader.load_threaded_request()`
	## fired into that dead time would take the load out of the swap frame for
	## free. See docs/PERF.md.
	_dress_hall()
	_lt("dress-hall")
	Music.play_game()   # idempotent; crossfades out whatever the menu left playing
	_lt("music")
	_setup_banter()     # after the HUD — the opening pool line arrives synchronously
	_lt("banter")
	_spawn_from_state()
	_lt("spawn-32-pieces")
	_refresh_turn_moves()
	_lt("turn-moves")
	_setup_network()    # after the state exists — the host hands it to NetMatch
	_update_turn_label()
	board.square_clicked.connect(_on_square_clicked)
	board.square_hovered.connect(_on_square_hovered)
	_lt("net+wiring")
	var args := OS.get_cmdline_user_args()
	if args.has("--debug-coords"):
		_build_debug_coords()
	if args.has("--smoke"):
		_smoke()
	elif args.has("--dump-tree"):
		_dump_tree()
	else:
		var game_cam := get_node_or_null("CameraRig/Camera3D") as Camera3D
		if game_cam != null and not Session.is_network():
			var intro := CathedralCinematicIntroScript.new()
			intro.name = "CathedralCinematicIntro"
			add_child(intro)
			intro.start_cinematic(game_cam)
	if net == null and state.turn != player_color and not game_over:
		_kick_ai_opening()
	_lt("ready-exit")


# -- head-to-head wiring ----------------------------------------------------


func _setup_network() -> void:
	## Bind the live connection (opened back in the Hall of Banners) to this
	## match. The HOST hands NetMatch its authoritative ChessState here — that
	## reference is what every incoming move request is validated against.
	if not Session.is_network():
		return
	net = NetMatch.get_active(get_tree())
	if net == null:
		push_error("network match with no live NetMatch — falling back to a local board")
		return
	if net.is_host:
		net.attach_state(state)
	net.move_applied.connect(_on_net_move_applied)
	net.move_rejected.connect(_on_net_move_rejected)
	net.opponent_left.connect(_on_net_opponent_left)
	net.desync.connect(_on_net_desync)
	# THE REQUEST DEADLINE (verifier defect P1). Without these three the board
	# sits on `busy = true` forever when the host never answers.
	net.request_slow.connect(_on_net_request_slow)
	net.request_stalled.connect(_on_net_request_stalled)
	net.request_recovered.connect(_on_net_request_recovered)
	# The camera sits behind the player's OWN army. yaw = PI is behind White
	# (the rig's default); a Black player looks down the board from the far end.
	if player_color:
		var rig: Node = get_node_or_null("CameraRig")
		if rig != null:
			rig.set("yaw", 0.0)
			rig.set("_target_yaw", 0.0)
			if rig.has_method("_apply"):
				rig.call("_apply", 1.0)   # snap, don't swing through the hall


# -- wave-3 module setup (spectator dragon + rival banter) ------------------


func _setup_spectator() -> void:
	## The perched watcher: reactions gate on the duel cam, ASHFALL fires at
	## checkmate. Configure BEFORE add_child — _ready parks it on the perch.
	spectator = DragonSpectator.new()
	spectator.name = "DragonSpectator"
	spectator.duel_director = duel_director   # reactions gate on is_active()
	spectator.board = board                   # lets react_capture take Vector2i squares
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall != null:
		spectator.perch_position = hall.spectator_perch()
		if hall.has_method("dragon_rest"):
			spectator.rest_position = hall.dragon_rest()
		# The ceremony caption may never land on the throne or on the champion
		# standing at its foot — it slides around them (CineCaption).
		spectator.ceremony_avoid = [
			hall.throne_dais() + Vector3.UP * 0.9,
			hall.throne_focus() - Vector3.UP * 2.4,
		]
	add_child(spectator)
	# The wyrm's own ceremony is a cinematic too: chrome out, verdict held.
	spectator.ashfall_started.connect(func() -> void: _chrome_for_cinematic(true))
	spectator.ashfall_finished.connect(func() -> void: _chrome_for_cinematic(false))


func _setup_banter() -> void:
	## The rival's voice. Legacy Frost/Ember matches have no registry id —
	## skip entirely; the registry houses are the only voices.
	if rival_house_id.is_empty() or not HouseRegistry.has_house(rival_house_id):
		return
	banter = BanterEngine.new()
	banter.name = "Banter"
	banter.house_id = rival_house_id          # the rival speaks
	add_child(banter)                          # BEFORE the first beat (HTTP needs the tree)
	banter.banter_line.connect(_on_banter_line)
	# The opening taunt fires on the pre-game clock (fullmove -1) so it never
	# consumes the in-game rate limit — first blood at move 1-2 still taunts.
	banter.on_beat(BanterEngine.BEAT_GAME_START, {"fullmove": -1})


func _on_cinematic_started(kind: String) -> void:
	Music.duck()
	_chrome_for_cinematic(true)
	if kind == "duel":
		Music.sting_duel()
	# Drop any hover-revealed glyph medallion before the camera takes over —
	# no new hover event arrives while the pointer sits still on the duel
	# square, so the ring would otherwise burn through the whole cinematic
	# as a black disc under the fighters (ISSUES.md #17).
	if _hovered_view != null and is_instance_valid(_hovered_view):
		_hovered_view.set_hovered(false)
	_hovered_view = null


# -- identity / hall dressing ----------------------------------------------


func _resolve_identity() -> void:
	if not Session.configured:
		return
	if Session.is_network():
		player_color = Session.net_my_color
	player_house_id = Session.player_house
	rival_house_id = Session.rival_house()
	if rival_house_id.is_empty():
		var rivals := Tournament.seeded_rivals(player_house_id)
		rival_house_id = rivals[0] if not rivals.is_empty() else player_house_id
	if Session.opponent.has("difficulty"):
		ai_difficulty = int(Session.opponent["difficulty"]) as ChessAI.Difficulty
	_player_display = _house_name(player_house_id)
	_rival_display = _house_name(rival_house_id)


func _house_name(id: String) -> String:
	var h := HouseRegistry.get_house(id)
	return str(h.get("name", "Haus " + id.capitalize()))


func _dress_hall() -> void:
	## THE DRESSING is the hall's own (great_hall.gd dress_for_match): cloth
	## AND sigil, per station, so the room says who is fighting.
	##
	## This used to be a colour-only set_banner_colors pass duplicating the
	## hall's station plan by hand — and it had drifted: it re-tinted station 5
	## to the player's primary and station 8 to the rival's primary, overriding
	## the accent the hall had deliberately chosen so a near-black primary
	## never leaves a whole wall invisible. Two owners of one plan, one of them
	## stale. There is one owner now.
	if player_house_id.is_empty():
		return
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall == null:
		return
	hall.dress_for_match(player_house_id, rival_house_id)


func _dress_hall_championship() -> void:
	## The throne shot: every banner in the hall falls to the champion —
	## sigils included (the colour-only pass left the rival's charge flying on
	## the east wall of the champion's own coronation).
	if player_house_id.is_empty():
		return
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall == null:
		return
	hall.dress_for_champion(player_house_id)


# -- square mapping (engine 0..63, a8=0 .. h1=63  <->  board Vector2i) ------
# Board sq.y=0 is the player's home rank (world -Z); the camera starts
# behind the player, so files run a..h from screen-left: sq.x = 7 - file.


static func sq_of(idx: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(7 - (idx % 8), 7 - (idx / 8))


static func idx_of(sq: Vector2i) -> int:
	return (7 - sq.y) * 8 + (7 - sq.x)


# -- setup -----------------------------------------------------------------


## SYNCHRONOUS, DELIBERATELY. This is the single most expensive call in a
## match load — 362 ms the first time, 15 ms after — and it stays on the swap
## frame on purpose: every caller of this game assumes a board that is either
## complete or absent, never half-raised. `e2e_driver.gd::_boot_game()` checks
## `views.size()` the instant the scene exists, and `_perform_undo()` rebuilds
## the board mid-game where a progressive reassembly under the player's hand
## would be a worse bug than the stall. See the note in `_ready()` and
## docs/PERF.md for the measured cost and the fix that does not need this to
## move.
func _spawn_from_state() -> void:
	_hovered_view = null   # the freed views take any hover reveal with them
	if ledger != null:
		ledger.reset_from(state)
	if governor != null:
		governor.reset_game()
	for sq in views:
		(views[sq] as PieceView).queue_free()
	views.clear()
	for idx in 64:
		var c = state.pieces[idx]
		if c == null:
			continue
		# FROST is always "my army", EMBER always the rival's — so a Black
		# player's own pieces still wear their own house's dye.
		var piece_side := PieceView.House.FROST \
			if ChessState.piece_color(c) == player_color else PieceView.House.EMBER
		_spawn(CHAR_TO_TYPE[str(c).to_lower()], piece_side, sq_of(idx))
	if board:
		board.set_occupied_squares(views.keys())


func _spawn(piece_type: PieceView.Type, piece_side: PieceView.House, sq: Vector2i) -> PieceView:
	var p: PieceView = PieceScene.instantiate()
	add_child(p)
	var hid := ""
	if not player_house_id.is_empty():
		hid = player_house_id if piece_side == PieceView.House.FROST else rival_house_id
	p.setup(piece_type, piece_side, hid)
	p.position = board.square_to_world(sq)
	p.died.connect(_on_piece_died.bind(p))
	views[sq] = p
	if _holochess != null:
		_holochess.register_piece(p)
	return p


func _on_piece_died(p: PieceView) -> void:
	death_log.append(p.death_anim)
	if _holochess != null:
		_holochess.unregister_piece(p)


func _kick_ai_opening() -> void:
	## FEN gave the rival the move — let the AI open.
	busy = true
	await _ai_ply()
	busy = false
	_update_turn_label()


# -- interaction -----------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_QUOTELEFT, KEY_F1, KEY_F12, KEY_SECTION]:
			if _dev_console != null:
				_dev_console.toggle_console()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_H:
			if _holochess != null:
				_holochess.toggle_holochess_mode(board)
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_C:
			if _coach_overlay != null:
				_coach_overlay.toggle_coach()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_T:
			_on_stockfish_hint_requested()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_L:
			_on_leela_hint_requested()
			get_viewport().set_input_as_handled()
			return
		if _easter_eggs != null:
			if _easter_eggs.handle_key_input(event, self):
				get_viewport().set_input_as_handled()
				return


func _on_square_clicked(sq: Vector2i) -> void:
	if busy or game_over or state == null or state.turn != player_color \
			or _net_disconnected or promo_picker != null \
			or (duel_director != null and duel_director.is_active()) \
			or (_dev_console != null and _dev_console.is_open()):
		return  # not interactive during animations/cinematics, after the end, or on the rival's turn
	var idx := idx_of(sq)
	var piece = state.pieces[idx]
	var is_own: bool = piece != null and ChessState.piece_color(piece) == player_color

	if _easter_eggs != null and piece != null:
		var is_king := (is_own and str(piece).to_lower() == "k")
		var p_type: int = CHAR_TO_TYPE.get(str(piece).to_lower(), 0)
		_easter_eggs.handle_piece_clicked(p_type, is_king, self)

	if selected == null:
		if is_own:
			_select(sq)
		return
	if sq == selected:
		if is_own and piece != null and str(piece).to_lower() == "k":
			_request_concede()
			return
		_clear_selection()
		return
	if is_own:
		_select(sq)
		return
	var options := _moves_for(idx_of(selected), idx)
	if options.is_empty():
		return
	_clear_selection()
	var move = options.get("")
	if move == null:
		# A PROMOTION. The player chooses the piece — all four of them, as the
		# real models, before anything moves (see _choose_promotion).
		move = await _choose_promotion(options)
		if move == null:
			return
	_play_turn(move)


func _select(sq: Vector2i) -> void:
	_set_selected_glow(false)
	selected = sq
	board.set_selected(sq)
	_set_selected_glow(true)
	var from_idx := idx_of(sq)
	var piece = state.pieces[from_idx]
	if _concede_btn != null:
		_concede_btn.visible = (piece != null and str(piece).to_lower() == "k")
	var targets: Array[Vector2i] = []
	var captures: Array[Vector2i] = []
	for m in _turn_moves:
		if m.from_square != from_idx:
			continue
		var to_sq := sq_of(m.to_square)
		if not targets.has(to_sq):
			targets.append(to_sq)
		if m.is_capture() and not captures.has(to_sq):
			captures.append(to_sq)
	# Captures wear the red target ring, quiet moves the steel rune dot.
	board.show_legal_moves(targets, captures)


func _clear_selection() -> void:
	_set_selected_glow(false)
	selected = null
	if _concede_btn != null:
		_concede_btn.visible = false
	board.clear_highlights()


func _set_selected_glow(on: bool) -> void:
	## Costumes hook: the glyph medallion warms beside the tile highlight.
	if selected == null:
		return
	var pv: PieceView = views.get(selected)
	if pv != null and is_instance_valid(pv):
		pv.set_selected(on)


func _on_square_hovered(sq: Variant) -> void:
	## Hover-only glyph rings (ISSUES.md #2): the type glyph fades in under
	## the piece standing on the hovered square — BOTH armies reveal, knowing
	## the rival's piece types matters too. Selection keeps its own ring lit
	## via set_selected; leaving the square fades a non-selected ring out.
	##
	## NOT during a cinematic (ISSUES.md #17): the glyph medallion is a dark
	## disc, and from the duel camera — inches off the floor — the ring under
	## a fighter read as a black hole punched in the stone. A mouse-hover
	## affordance has no business on screen while the camera is taken over,
	## and the pointer is parked on the duel square for the whole fight.
	var pv: PieceView = null
	if duel_director != null and is_instance_valid(duel_director) \
			and duel_director.is_active():
		pv = null
	elif sq != null:
		pv = views.get(sq)
	if pv != null and not is_instance_valid(pv):
		pv = null
	if pv == _hovered_view:
		return
	if _hovered_view != null and is_instance_valid(_hovered_view):
		_hovered_view.set_hovered(false)
	_hovered_view = pv
	if _hovered_view != null:
		_hovered_view.set_hovered(true)


func _moves_for(from_idx: int, to_idx: int) -> Dictionary:
	## Every legal move from->to, keyed by promotion char ("" for the ordinary
	## move). THE PICKER IS BUILT FROM THIS, so the UI can never offer a piece
	## the rules did not generate — and a promotion square yields four entries
	## instead of the one queen the old `_move_for` kept (Albert's bug).
	var out: Dictionary = {}
	for m in _turn_moves:
		if m.from_square != from_idx or m.to_square != to_idx:
			continue
		var key := "" if m.promotion == null else str(m.promotion).to_lower()
		if not out.has(key):
			out[key] = m
	return out


## THE PROMOTION MODAL. Returns the chosen ChessMove, or null when the board
## moved on underneath it (an undo, a disconnect, the scene going away).
##
## The board is held `busy` for the length of the panel: nothing may animate,
## no take-back may fire, no rival ply may land while a half-made move is
## sitting in the player's hand. Every exit from the picker produces a legal
## piece (Esc and its timeout take the queen), so this lock always lifts.
func _choose_promotion(options: Dictionary) -> Variant:
	var picker := PromotionPicker.new()
	picker.house_id = player_house_id
	picker.side = PieceView.House.FROST     # the promoting army here is always mine
	var offer: Array[String] = []
	for pc in PromotionPicker.ORDER:
		if options.has(pc):
			offer.append(pc)
	if offer.is_empty():
		# Nothing this modal could legally show. Never open a panel with no way
		# out — take whatever the engine did offer and play on.
		return options.values()[0] if not options.is_empty() else null
	picker.offered = offer
	promo_picker = picker
	var gen := _turn_gen
	busy = true
	_update_turn_label()
	add_child(picker)
	var pc: String = await picker.chosen
	promo_picker = null
	busy = false
	if gen != _turn_gen or game_over or _net_disconnected or state == null:
		_update_turn_label()
		return null
	var move = options.get(pc)
	if move == null:
		move = options.get(PromotionPicker.DEFAULT_PIECE)   # belt and braces
	if move != null:
		promo_picks.append(pc)
	return move


# -- turn flow -------------------------------------------------------------


func _play_turn(move) -> void:
	## One full round: the player's ply, then (if the game goes on) the rival's.
	## An undo mid-round bumps _turn_gen; every await below re-checks it and a
	## stale continuation drops out without touching busy (the undo owns it).
	if net != null and net.is_active():
		# HEAD-TO-HEAD: our own click is a REQUEST, exactly like the joiner's.
		# Nothing moves — not even on the host's own screen — until the host's
		# validated broadcast comes back through _on_net_move_applied. One code
		# path, one order of events, no "the host sees it first" class of bug.
		busy = true
		_net_stalled = false      # a fresh request gets a fresh deadline (P1)
		_hide_net_panel()
		_clear_selection()
		_update_turn_label()
		net.request_move(move)
		return
	busy = true
	_push_undo_checkpoint()
	var gen := _turn_gen
	await _execute_ply(move)
	if gen != _turn_gen:
		return
	if not game_over and state.turn != player_color:
		await _ai_ply()
		if gen != _turn_gen:
			return
	busy = false
	_update_turn_label()
	_update_undo_button()


# -- head-to-head turn flow -------------------------------------------------


func _on_net_move_applied(payload: Dictionary) -> void:
	## The host has spoken: this ply is law on both machines. Both sides
	## animate it locally from THIS data — same move, same metadata, same duel.
	var seq: int = int(payload.get("seq", -1))
	var move = NetProtocol.decode_move(payload.get("move", {}))
	if move == null:
		push_error("network: malformed move payload for ply %d" % seq)
		return
	_net_stalled = false      # an applied ply is the loudest possible answer
	_hide_net_panel()
	busy = true
	_clear_selection()
	var gen := _turn_gen
	await _execute_ply(move)
	if gen != _turn_gen:
		return
	# The host told us the FEN this ply MUST produce. A board that quietly
	# diverges is the one failure a chess client may never ship with.
	var fen_now := str(state.get_fen())
	var fen_want := str(payload.get("fen_after", fen_now))
	if fen_now != fen_want:
		if net != null and is_instance_valid(net):
			net.report_desync(fen_now, fen_want)
		return
	net_plies.append("%d|%s|%s" % [seq, move.to_uci(), fen_now])
	print("NET PLY seq=%d uci=%s fen=%s" % [seq, move.to_uci(), fen_now])
	# THE CINEMATIC BARRIER (see net_ply_gate.gd). A capture duel runs for
	# seconds; the turn may not advance while the other player is still
	# watching it. We report finished, then wait for the host to confirm both
	# sides are.
	if net != null and is_instance_valid(net):
		net.ack_ply(seq)
		await _await_net_gate(seq, gen)
	if gen != _turn_gen:
		return
	busy = false
	_update_turn_label()
	_update_undo_button()
	net_ply_settled.emit(seq, fen_now)


func _await_net_gate(seq: int, gen: int) -> void:
	## Block turn flow until BOTH sides have finished watching ply `seq`.
	## Bounded: the host's own failsafe opens the gate at GATE_TIMEOUT_SEC, and
	## this wait outlives that by a margin so a lost gate packet still releases
	## the board instead of freezing the match forever.
	var deadline := Time.get_ticks_msec() \
		+ int((NetProtocol.GATE_TIMEOUT_SEC + 10.0) * 1000.0)
	while net != null and is_instance_valid(net) and not net.gate_is_open(seq):
		if gen != _turn_gen or _net_disconnected:
			return
		if Time.get_ticks_msec() > deadline:
			push_warning("network: ply %d gate never opened — releasing the board" % seq)
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _on_net_request_slow(_seq: int) -> void:
	## The answer is late. The board stays held — the move may still land — but
	## the player is told, instead of watching a screen that looks dead.
	if _net_disconnected or game_over:
		return
	_flash_oracle(NetProtocol.request_slow_text(), NetProtocol.REQUEST_TIMEOUT_SEC)
	_update_turn_label()


func _on_net_request_stalled(seq: int) -> void:
	## THE FIX FOR THE FREEZE (verifier defect P1). The host never answered, so
	## the board comes back to the player and the way out is on screen: keep
	## waiting (the panel closes itself if the answer arrives), or go home. The
	## request is NOT re-sent — the host may still apply it, and NetMatch's seq
	## guard drops it if the position has moved on.
	if _net_disconnected or game_over:
		return
	_net_stalled = true
	net_stalled_count += 1
	busy = false                 # the one line the whole defect was about
	_clear_selection()
	print("NET STALLED seq=%d" % seq)
	_show_net_panel(NetProtocol.request_stalled_text())
	_update_turn_label()
	_update_undo_button()


func _on_net_request_recovered(_seq: int) -> void:
	## It answered after all. Take the notice down; the applied ply (or the
	## rejection) that follows drives the board from here.
	_net_stalled = false
	_hide_net_panel()
	_flash_oracle(NetProtocol.request_recovered_text(), 3.0)
	_update_turn_label()


func _on_net_move_rejected(reason: String) -> void:
	## The host refused our move. Say why, in the words it gave us, and hand
	## the board back — never leave the player staring at a frozen screen.
	_net_stalled = false
	_hide_net_panel()
	net_rejections.append(reason)
	print("NET REJECTED %s" % reason)
	_clear_selection()
	busy = false
	_flash_oracle("the host refused that move — %s" % reason, 4.0)
	_update_turn_label()


func _on_net_opponent_left(reason: String) -> void:
	if _net_disconnected:
		return
	_net_disconnected = true
	_turn_gen += 1          # every in-flight await for this match is now void
	busy = false
	_clear_selection()
	_show_net_panel("Your friend has left the field.\n%s" % reason)
	_update_turn_label()
	_update_undo_button()


func _on_net_desync(why: String) -> void:
	if _net_disconnected:
		return
	_net_disconnected = true
	_turn_gen += 1
	busy = false
	_show_net_panel("The two boards no longer agree — the match cannot go on.\n%s" % why)


func _ai_ply() -> void:
	_update_turn_label(true)
	var gen := _turn_gen
	var move = null
	_ai_waiting = true   # the cancellable window: an undo here voids the reply
	if oracle != null:
		move = await oracle.choose_move(state, ai_difficulty)  # MAX thinking, difficulty ignored
	else:
		move = await ai.choose_move(state, ai_difficulty)  # WorkerThreadPool search
	if gen != _turn_gen:
		return   # undone while thinking — the late reply is for a dead position
	_ai_waiting = false
	if move == null:
		_finish_game()
		return
	await _execute_ply(move)


func _execute_ply(move) -> void:
	## Engine first (authoritative), then the choreography catches up.
	var mover_is_ember: bool = state.turn != player_color   # the RIVAL is moving
	var is_white_mover: bool = (not mover_is_ember) if player_color == false else mover_is_ember
	var fen_before := "" if mover_is_ember else str(state.get_fen())
	_record_san(move)
	state.apply_move(move)
	if banter != null:
		banter.note_ply()                      # the rate limiter's clock
	var fen_after := "" if mover_is_ember else str(state.get_fen())
	_refresh_turn_moves()

	var moment_info: Dictionary = {}
	if move.is_capture():
		var victim_rec: Dictionary = ledger.note_move(move, is_white_mover)
		var sit: Dictionary = MomentContextScript.situation(state, move, _turn_moves, ledger, victim_rec)
		var scored: Dictionary = MomentScoreScript.score(sit)
		var gives_check: bool = bool(sit.get("gives_check", false))
		var is_mate: bool = (_turn_moves.is_empty() and gives_check)
		var decision: Dictionary = {"tier": 0, "reason": "mate"} if is_mate else governor.decide(float(scored["notability"]))
		moment_info = {
			"tier": int(decision.get("tier", 0)),
			"tag": str(scored.get("tag", "")),
			"notability": float(scored.get("notability", 0.0)),
			"lead": str(scored.get("lead", "")),
			"reason": str(decision.get("reason", ""))
		}
	else:
		ledger.note_move(move, is_white_mover)

	await _animate_move(move, mover_is_ember, moment_info)
	if spectator != null and is_instance_valid(spectator):
		spectator.notice_move(sq_of(move.to_square))   # glance target + rate limiter
	_fire_banter_beats(move, mover_is_ember)
	if not mover_is_ember and not fen_before.is_empty():
		_sample_blunder(fen_before, fen_after)   # detached: one probe feeds banter + dragon
	if state.get_result() != ChessState.RESULT.ONGOING:
		_finish_game()


func _record_san(move) -> void:
	var san: String = str(move.notation_san) if move.notation_san != null else move.to_uci()
	_san_log.append(san)
	_render_move_list()


func _render_move_list() -> void:
	var lines: Array[String] = []
	for i in range(0, _san_log.size(), 2):
		@warning_ignore("integer_division")
		var row := "%d. %s" % [i / 2 + 1, _san_log[i]]
		if i + 1 < _san_log.size():
			row += "  %s" % _san_log[i + 1]
		lines.append(row)
	if _move_list != null:
		_move_list.text = "\n".join(lines)


func _walk_time(from_pos: Vector3, to_pos: Vector3) -> float:
	return clampf(from_pos.distance_to(to_pos) * 0.3, 0.3, 1.1)


func _duel_meta(mover_is_ember: bool) -> Dictionary:
	if player_house_id.is_empty():
		return {}
	var atk := rival_house_id if mover_is_ember else player_house_id
	var vic := player_house_id if mover_is_ember else rival_house_id
	return {"attacker_house": atk, "victim_house": vic}


func _animate_move(move, mover_is_ember: bool, moment_info: Dictionary = {}) -> void:
	var from_sq := sq_of(move.from_square)
	var to_sq := sq_of(move.to_square)
	var mover: PieceView = views.get(from_sq)
	if mover == null:
		push_error("no piece view on %s for move %s" % [str(from_sq), move.to_uci()])
		return
	views.erase(from_sq)
	var target := board.square_to_world(to_sq)
	if move.is_castling:
		var r_from := sq_of(move.rook_from)
		var rook: PieceView = views.get(r_from)
		if rook != null:
			views.erase(r_from)
			var r_to := sq_of(move.rook_to)
			views[r_to] = rook
			rook.move_to(board.square_to_world(r_to), 0.9)  # glides while the king walks
	if move.is_capture():
		var victim: PieceView = views.get(sq_of(move.captured_square))
		if victim != null:
			views.erase(sq_of(move.captured_square))
			var dir := (target - mover.position).normalized()
			var edge := target - dir * 0.55
			await mover.move_to(edge, _walk_time(mover.position, edge))
			# The slow-mo duel: the strike callable IS the old choreography,
			# now running under the director's time curve, moments governor, and battle cam.
			var d_meta := _duel_meta(mover_is_ember)
			d_meta.merge(moment_info)
			await duel_director.play_duel(mover, victim, d_meta,
				func(): await mover.play_capture(victim))
			if _holochess != null and is_instance_valid(_holochess):
				var tier_val: int = d_meta.get("tier", 0)
				_holochess.record_capture(tier_val, str(mover.piece_type), str(victim.piece_type), target)
			if spectator != null and is_instance_valid(spectator):
				spectator.react_capture(sq_of(move.captured_square))  # flinch, self-rate-limited
	await mover.move_to(target, _walk_time(mover.position, target))
	views[to_sq] = mover
	if move.promotion != null:
		# WHICHEVER PIECE WAS CHOSEN. This path was always type-correct — the
		# picker is what finally lets a player reach it, and the AI, the
		# Oracle and the wire have always been able to. The flourish is fired
		# on the piece that actually arrived, with the promoting haus's own
		# banner (`_duel_meta`), so a knight's beam is a knight's beam.
		mover.queue_free()
		var promo_char := str(move.promotion).to_lower()
		var promo_side := PieceView.House.EMBER if mover_is_ember else PieceView.House.FROST
		var promoted := _spawn(CHAR_TO_TYPE[promo_char], promo_side, to_sq)
		promotions_played.append("%s|%s|%s" % [move.to_uci(),
			str(PIECE_NAME.get(promo_char, promo_char)),
			"rival" if mover_is_ember else "player"])
		print("PROMOTION PLAYED uci=%s piece=%s mover=%s" % [move.to_uci(),
			str(PIECE_NAME.get(promo_char, promo_char)),
			"rival" if mover_is_ember else "player"])
		promoted.spawn_flourish()  # overlaps the director's beam + banner
		await duel_director.play_promotion(promoted, _duel_meta(mover_is_ember))


func _refresh_turn_moves() -> void:
	_turn_moves = state.legal_moves(true)
	if board:
		board.set_occupied_squares(views.keys())
	if state != null and state.turn == player_color and _coach_overlay != null:
		var uci_history: Array = []
		if "move_stack" in state and state.move_stack != null:
			for m in state.move_stack:
				if m != null and m.has_method("to_uci"):
					uci_history.append(m.to_uci())
		_last_coach_analysis = CoachEngineScript.analyze_position(state, player_color, uci_history)
		_coach_overlay.update_analysis(_last_coach_analysis)


func _on_coach_hint_requested() -> void:
	_on_stockfish_hint_requested()


func _on_stockfish_hint_requested() -> void:
	if state == null or state.turn != player_color or _last_coach_analysis.is_empty():
		return
	var sf_dict = _last_coach_analysis.get("stockfish", {})
	var best_m = sf_dict.get("move")
	if best_m == null:
		best_m = _last_coach_analysis.get("recommended_move")
	if best_m != null:
		var from_sq := sq_of(best_m.from_square)
		var to_sq := sq_of(best_m.to_square)
		_select(from_sq)
		board.show_legal_moves([to_sq], [to_sq] if best_m.is_capture() else [])


func _on_leela_hint_requested() -> void:
	if state == null or state.turn != player_color or _last_coach_analysis.is_empty():
		return
	var leela_dict = _last_coach_analysis.get("leela", {})
	var best_m = leela_dict.get("move")
	if best_m == null:
		best_m = _last_coach_analysis.get("recommended_move")
	if best_m != null:
		var from_sq := sq_of(best_m.from_square)
		var to_sq := sq_of(best_m.to_square)
		_select(from_sq)
		board.show_legal_moves([to_sq], [to_sq] if best_m.is_capture() else [])


# -- undo / take-back (fat-finger insurance) --------------------------------
# One checkpoint per player move (pushed before the ply applies). Undo pops
# the newest checkpoint and rewinds the ENGINE with ChessState.undo() until
# the move stack matches — that reverts both plies when the rival already
# replied, or just the player's when the rival is still thinking (the late
# reply is voided by _turn_gen). Views rebuild from state, the SAN list
# truncates, banter/dragon ply clocks rewind, music is untouched. Requests
# made under a cinematic queue until DuelDirector releases the board.
# Limits: tournament 3/game (button shows remaining), single match unlimited.


func _push_undo_checkpoint() -> void:
	_undo_checkpoints.append({
		"stack": state.move_stack.size(),
		"san": _san_log.size(),
		"banter_ply": banter._ply if banter != null else 0,
	})
	_update_undo_button()


func _request_undo() -> void:
	## HUD button + Cmd/Ctrl+Z land here.
	##
	## TAKE-BACKS ARE OFF IN A NETWORK MATCH. There is no correct unilateral
	## answer to "rewind the board out from under my opponent's hand": the host
	## would have to rewind a position the joiner has already seen and may
	## already have replied to, and every capture duel both players just
	## watched would have to be un-watched. Consent-based take-backs are a real
	## feature and not this one; until then the honest thing is to disable the
	## control and SAY SO rather than let the button lie.
	if net != null and net.is_active():
		_flash_oracle("take-backs are off in a match against a friend", 3.0)
		return
	if promo_picker != null:
		return   # a half-made move is in the player's hand — finish it first
	if game_over or _undo_checkpoints.is_empty() or _undos_left == 0:
		return
	_undo_pending = true
	_try_undo()


func _try_undo() -> void:
	## Executes a pending take-back at the first safe frame (_process polls).
	if not _undo_pending:
		return
	if game_over:
		_undo_pending = false   # the war ended while the request waited
		return
	if duel_director != null and duel_director.is_active():
		return   # queued — executes when the cinematic releases the board
	var cancel_thinking := busy and _ai_waiting
	if busy and not cancel_thinking:
		return   # mid move animation — wait for the board to settle
	if not busy and state.turn != player_color:
		return   # defensive: settled but rival to move — nothing safe to pop
	_undo_pending = false
	_perform_undo()


func _perform_undo() -> void:
	var cp: Dictionary = _undo_checkpoints.pop_back()
	var undone := 0
	while state.move_stack.size() > int(cp["stack"]):
		state.undo()
		undone += 1
	_turn_gen += 1          # any in-flight rival reply is now void
	_ai_waiting = false
	busy = false
	oracle_thinking = false
	undo_count += 1
	if _undos_left > 0:
		_undos_left -= 1
	selected = null
	board.clear_highlights()
	_san_log.resize(int(cp["san"]))
	_render_move_list()
	if banter != null:
		banter.rewind_ply_clock(int(cp["banter_ply"]))
		banter.on_beat(BanterEngine.BEAT_PLAYER_UNDO)   # the rival mocks the take-back
	if spectator != null and is_instance_valid(spectator) \
			and spectator.has_method("rewind_moves"):
		spectator.rewind_moves(undone)   # ships with dragon_spectator.gd
	if ledger != null:
		ledger.rewind_to(state.move_stack.size())
	_spawn_from_state()     # captured pieces resurrect
	_refresh_turn_moves()
	_update_turn_label()
	_update_undo_button()


func _update_undo_button() -> void:
	if _undo_btn == null:
		return
	if Session.is_network():
		# Obvious, in the HUD, from the first frame: this control is not a
		# take-back you have run out of — it does not exist in this match.
		_undo_btn.text = "↶ no take-backs online"
		_undo_btn.tooltip_text = "Take-backs are disabled in a match against a friend"
		_undo_btn.disabled = true
		return
	var label := "↶ undo"
	if _undos_left >= 0:
		label += "  ·  %d left" % _undos_left
	_undo_btn.text = label
	_undo_btn.disabled = game_over or _undo_checkpoints.is_empty() or _undos_left == 0


# -- banter beats + the shared blunder probe --------------------------------


func _fire_banter_beats(move, mover_is_ember: bool) -> void:
	## After the animation, so the caption never fights the duel's kill line.
	if banter == null or game_over:
		return
	var san: String = str(move.notation_san) if move.notation_san != null else ""
	if move.is_capture():
		# captured_piece is null for en passant — the victim is always a pawn.
		var piece := "pawn" if move.en_passant \
			else str(PIECE_NAME.get(str(move.captured_piece).to_lower(), ""))
		var beat: String = BanterEngine.BEAT_PLAYER_CAPTURED if mover_is_ember \
			else BanterEngine.BEAT_RIVAL_CAPTURED
		banter.on_beat(beat, {"piece": piece})
		return   # capture outranks check; the module would drop the 2nd anyway
	if san.ends_with("+"):
		var beat := BanterEngine.BEAT_CHECK_GIVEN if mover_is_ember \
			else BanterEngine.BEAT_CHECK_RECEIVED
		banter.on_beat(beat)


func _sample_blunder(fen_before: String, fen_after: String) -> void:
	## Detached coroutine (never awaited by the turn flow): one shallow
	## Stockfish probe around the PLAYER's ply feeds BOTH the banter blunder
	## taunt and the dragon's head-shake. Evals read from the player's
	## perspective: before = side-to-move (the player), after = sign-flipped.
	if _blunder_busy or (banter == null and spectator == null):
		return
	_blunder_busy = true
	var gen := _turn_gen
	var before := await _blunder_eval(fen_before)
	var after_raw := await _blunder_eval(fen_after)
	_blunder_busy = false
	if gen != _turn_gen or is_nan(before) or is_nan(after_raw) or game_over:
		return   # undone / no engine / mated position (empty lines) / game over
	var swing := before + after_raw   # before − (−after_raw)
	if swing < BLUNDER_CP:
		return
	blunder_count += 1
	if banter != null:
		banter.on_beat(BanterEngine.BEAT_PLAYER_BLUNDER, {"eval_swing_cp": swing})
	if spectator != null and is_instance_valid(spectator):
		spectator.react_blunder()


func _blunder_eval(fen: String) -> float:
	## cp from the side-to-move's perspective; NAN when no engine/answer.
	## Mate scores dominate every cp swing (the _score_value convention).
	var eng := await _ensure_blunder_engine()
	if eng == null:
		return NAN
	var res := await eng.search(fen, {"depth": BLUNDER_DEPTH})
	var lines: Array = res.get("lines", [])
	if lines.is_empty():
		return NAN
	var line: Dictionary = lines[0]
	if line.get("mate") != null:
		var m := int(line["mate"])
		return 100000.0 - m if m > 0 else -100000.0 - m
	return float(line.get("cp") if line.get("cp") != null else 0)


func _ensure_blunder_engine() -> UciEngine:
	if _blunder_engine != null and _blunder_engine.is_ready():
		return _blunder_engine
	if _blunder_engine != null:
		_blunder_engine.queue_free()
		_blunder_engine = null
	if _blunder_failed:
		return null
	var path := UciEngine.find_stockfish()
	if path.is_empty():
		_blunder_failed = true
		return null
	var eng := UciEngine.new()
	eng.name = "BlunderScout"
	add_child(eng)
	if not eng.start(path) or not await eng.init(8.0):
		eng.queue_free()
		_blunder_failed = true
		return null
	_blunder_engine = eng
	return eng


# -- endgame ---------------------------------------------------------------


func _finish_game() -> void:
	game_over = true
	_undo_pending = false   # a take-back cannot outlive the war
	_update_undo_button()
	_clear_selection()
	var result: int = state.get_result()
	# The side TO MOVE is the mated one; the player won if that side is not his.
	var player_won := result == ChessState.RESULT.CHECKMATE and state.turn != player_color
	if result == ChessState.RESULT.CHECKMATE:
		if _in_tournament():
			Session.tournament.report_result(player_won)
		if banter != null:
			# Perspective flip: the module speaks for the rival.
			banter.on_beat(BanterEngine.BEAT_ENDGAME_LOSE if player_won \
				else BanterEngine.BEAT_ENDGAME_WIN)
	else:
		# A DRAW. The bracket answer is decided in `_end_sequence`, by the ONE
		# seam the Trial by Fire replaces (`settle_tournament_draw`) — never
		# here, because that seam may take as long as a cinematic.
		if banter != null:
			# Draws used to be SILENT ("silence beats a wrong-register line").
			# They have a pool now — a stalemate deserves a reaction.
			banter.on_beat(BanterEngine.BEAT_DRAW,
				{"draw": str(RESULT_TEXT.get(result, "a draw"))})
	_update_turn_label()
	_end_sequence.call_deferred(result, player_won)


func _in_tournament() -> bool:
	return Session.configured and Session.mode == "tournament" \
		and Session.tournament != null


# ── THE DRAW SEAM — THE TRIAL BY FIRE DROPS IN HERE, AND NOWHERE ELSE ──────
#
# A draw is not a loss, and until today a drawn tournament match quietly
# ELIMINATED the player: `report_result(player_won)` with `player_won == false`
# and a comment admitting it. The owner has since designed a king-vs-king
# "Trial by Fire" minigame to settle draws, which is built separately — so
# this is deliberately NOT an elaborate resolution. It is the minimum honest
# thing: one function that decides the bracket outcome AND supplies the words
# the verdict card says about it, so the player is never eliminated silently.
#
# TO DROP THE MINIGAME IN: replace THIS FUNCTION'S BODY. Nothing else moves.
# Every caller already `await`s it, so the trial may run as long as it likes,
# take over the camera, and play its own cinematic before answering.
#
#   in   result   the ChessState.RESULT that ended the war (STALEMATE,
#                 INSUFFICIENT, FIFTY_MOVE, THREEFOLD)
#   out  {"player_advances": bool, "lines": Array[String]}
#        player_advances  goes straight to Tournament.report_result()
#        lines            appended to the verdict card, in the player's words
#
# THE MINIGAME IS IN. A stalemate or an insufficient-material draw now drops
# both kings into the arena (src/minigame/) and the last one standing takes the
# round. Everything that makes that safe — harvesting the survivors, taking and
# returning the frame, the wall-clock deadline, the fallback — lives in
# TrialBridge, so this stays the four lines the banner above asked for.
#
# WHICH DRAWS: TrialBridge.BY_FIRE (stalemate + insufficient). A draw by
# bookkeeping — threefold, fifty-move — still takes the old card, and the trial
# is never run online (see TrialBridge._refuse_reason). In every refusal and
# every failure the answer is the one this function shipped with: the rival
# advances, and the `lines` say which of the two reasons it was.
func settle_tournament_draw(result: int) -> Dictionary:
	var bridge := TrialBridge.new()
	var verdict: Dictionary = await bridge.run(self, result)
	if bool(verdict.get("player_advances", false)):
		# THE CALLER HARD-CODES DEFEAT. `_end_sequence` calls
		# `_show_match_end(false, ...)` for every draw, which was right when a
		# draw could only ever eliminate you — but a trial the player WINS
		# advances the bracket while that card still offers "Return to the Hall
		# of Banners". The seam is the only thing allowed to move in this file,
		# so it repairs its own consequence: this runs deferred, i.e. after
		# `_show_match_end` has written the button, and re-points it at the next
		# round. The proper fix is one word in `_end_sequence` — pass the
		# advance through instead of `false` — and belongs to whoever owns it.
		var ride_on := func() -> void:
			if not _victory_shown or Session.tournament == null \
					or Session.tournament.is_champion():
				return   # the throne branch already wrote its own ending
			_next_action = "next_round"
			if _continue_btn != null and is_instance_valid(_continue_btn):
				_continue_btn.text = "Ride to the %s" % _next_round_name(Session.tournament)
		ride_on.call_deferred()
	return verdict


func _end_sequence(result: int, player_won: bool) -> void:
	if result != ChessState.RESULT.CHECKMATE:
		# A DRAW: no dragon, no ceremony — and, in a tournament, no silent
		# elimination. The seam decides and supplies its own words.
		if _in_tournament():
			var verdict: Dictionary = await settle_tournament_draw(result)
			var lines: Variant = verdict.get("lines", [])
			_draw_bracket_lines.clear()
			if lines is Array:
				for l in (lines as Array):
					_draw_bracket_lines.append(str(l))
			Session.tournament.report_result(bool(verdict.get("player_advances", false)))
		_show_match_end(false, RESULT_TEXT.get(result, "The war is over"))
		return
	# The mated king falls under the checkmate cinematic's slow orbit.
	var loser := PieceView.House.FROST if state.turn == player_color \
		else PieceView.House.EMBER
	var king_view: PieceView = null
	var king_sq := Vector2i.ZERO
	for sq in views:
		var pv: PieceView = views[sq]
		if is_instance_valid(pv) and pv.piece_type == PieceView.Type.KING and pv.side == loser:
			king_view = pv
			king_sq = sq
			break
	var winner_key := ""
	if player_house_id.is_empty():
		winner_key = "FROST" if player_won else "EMBER"
	else:
		winner_key = player_house_id if player_won else rival_house_id
	if king_view == null:
		_on_victory_panel_requested(duel_director.resolve_house_name(winner_key))
		return
	views.erase(king_sq)
	# Whether a ceremony follows is knowable BEFORE the checkmate cinematic —
	# and it has to be, because play_checkmate fires victory_panel_requested on
	# its way out. Until 2026-08-09 that opened the verdict modal on top of the
	# wyrm and the ceremony played out behind a UI card (critic defect P2c).
	var loser_pieces: Array = []
	for lsq in views:
		var lpv: PieceView = views[lsq]
		if is_instance_valid(lpv) and lpv.side == loser:
			loser_pieces.append(lpv)
	var will_burn: bool = spectator != null and is_instance_valid(spectator) \
		and not loser_pieces.is_empty()   # a bare king leaves nothing to burn
	if will_burn:
		_hold_victory_panel()
	await duel_director.play_checkmate(king_view, winner_key,
		func(): await king_view.die())
	# ── ASHFALL: king death → the wyrm burns the beaten army → victory flow ──
	if will_burn and spectator != null and is_instance_valid(spectator):
		var champ_tier := Session.configured and Session.mode == "tournament" \
				and Session.tournament != null and player_won \
				and Session.tournament.is_champion()
		await spectator.play_ashfall(loser,
			duel_director.resolve_house_name(winner_key), loser_pieces, champ_tier)
		for lsq in views.keys():      # ashfall freed those views
			if not is_instance_valid(views[lsq]):
				views.erase(lsq)
	if will_burn:
		_release_victory_panel()


## The championship ending (the real champion branch fires this, and the e2e
## showcase reuses it for the throne-room tableau): every banner falls to the
## champion, the dragon appears above the Throne of Blades with a slow nod
## toward the camera, the crowned champion king walks to the dais, and the
## camera move ends parked framing the throne.
func start_championship_tableau() -> void:
	if spectator != null and is_instance_valid(spectator):
		spectator.skip()      # snap any running ashfall to its end state
		spectator.dismiss()   # one dragon in the throne frame
		spectator = null
	_dress_hall_championship()
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall == null or hall.throne == null:
		return
	hall.summon_champion_dragon()
	hall.dragon_wink()   # the wink — fire and forget
	while duel_director.is_active():   # let the checkmate death tail release
		await get_tree().process_frame
	var king := _champion_king_view()
	if king != null:
		var dais := hall.throne_dais()
		await king.move_to(dais, clampf(king.position.distance_to(dais) * 0.28, 1.0, 3.0))
		# move_to's fire-and-forget _face_home tween (0.18 s) would fight an
		# immediate turn — let it finish, then face the hall for the tableau.
		await get_tree().create_timer(0.25).timeout
		king.face_attacker(dais + Vector3(0.0, 0.0, -6.0))
	# The caption may not stand on the champion: the plate slides clear of the
	# crowned king (head height) and of the throne he stands before.
	await duel_director.play_championship_tableau(hall.throne_focus(), [
		hall.throne_dais() + Vector3.UP * 0.9,
		hall.throne_focus() - Vector3.UP * 2.4,
	])


func _champion_king_view() -> PieceView:
	## The player's king (the champion is always the player when this runs).
	for sq in views:
		var pv: PieceView = views[sq]
		if is_instance_valid(pv) and pv.piece_type == PieceView.Type.KING \
				and pv.side == PieceView.House.FROST:
			return pv
	return null


## Hold the verdict card until the ceremony that follows the checkmate has
## finished. Armed with a wall-clock deadline so a ceremony that never returns
## can only ever DELAY the panel, never lose it.
func _hold_victory_panel() -> void:
	_victory_held = true
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(30.0, true, false, true)   # ignore_time_scale
	t.timeout.connect(func() -> void:
		if _victory_held:
			push_warning("ceremony overran its hold — releasing the victory panel")
			_release_victory_panel())


func _release_victory_panel() -> void:
	if not _victory_held:
		return
	_victory_held = false
	if _victory_pending.is_empty():
		return
	var h := _victory_pending
	_victory_pending = ""
	_on_victory_panel_requested(h)


func _on_victory_panel_requested(winning_house: String) -> void:
	if _victory_held:
		_victory_pending = winning_house   # the ceremony still owns the frame
		return
	var player_won := state.get_result() == ChessState.RESULT.CHECKMATE \
		and state.turn != player_color
	_show_match_end(player_won, "Checkmate — %s triumphs" % winning_house)


func _show_match_end(player_won: bool, base_text: String) -> void:
	# The verdict music: the single spot where win/loss AND the champion
	# branch are both known. Playlists fade out under the fanfare.
	var throne_won := Session.configured and Session.mode == "tournament" \
			and Session.tournament != null and Session.tournament.is_champion()
	if throne_won:
		Music.championship()          # Fanfare for Space — the throne is won
	else:
		Music.game_over(player_won)   # Medieval Victory Theme / Agnus Dei X
	var lines: Array[String] = [base_text]
	_next_action = "rematch"
	var btn_text := "Rematch"
	if Session.is_network():
		# No unilateral rematch online: reloading the scene on one machine
		# would leave the other holding a finished board. The way out of a
		# network match is the Hall of Banners, for both of you.
		lines.append("%s played %s." % [_rival_display,
			NetProtocol.color_name(not player_color)])
		_next_action = "hall"
		btn_text = "Return to the Hall of Banners"
	elif Session.configured and Session.mode == "tournament" and Session.tournament != null:
		var t: Tournament = Session.tournament
		if t.is_champion():
			var motto := str(HouseRegistry.get_house(player_house_id).get("motto", ""))
			lines = ["THE THRONE IS WON",
				"%s rules the Nine Hauses." % _player_display, "“%s”" % motto]
			_next_action = "hall"
			btn_text = "Return to the Hall of Banners"
			start_championship_tableau()   # fire-and-forget coronation
			Tournament.clear_saved()
		elif player_won:
			var round_name := _next_round_name(t)
			lines.append("%s awaits in the %s." % [_house_name(t.current_opponent()), round_name])
			_next_action = "next_round"
			btn_text = "Ride to the %s" % round_name
		else:
			var champ := str(t.bracket_state().get("champion", ""))
			if _draw_bracket_lines.is_empty():
				lines.append("%s has fallen from the war." % _player_display)
			else:
				# A DRAW, and the card says plainly what it did to the bracket
				# instead of headlining "draw" and quietly eliminating you.
				lines.append_array(_draw_bracket_lines)
			if not champ.is_empty():
				lines.append("%s takes the throne." % _house_name(champ))
			_next_action = "hall"
			btn_text = "Return to the Hall of Banners"
	else:
		lines.append("R — rematch · Esc — the Hall of Banners")
	_victory_label.text = "\n".join(lines)
	_continue_btn.text = btn_text
	_victory_panel.visible = true
	_victory_shown = true


func _next_round_name(t: Tournament) -> String:
	var bs := t.bracket_state()
	var rounds: Array = bs["rounds"]
	for r in rounds.size():
		for m in rounds[r]:
			if str(m["winner"]).is_empty() \
					and (str(m["a"]) == t.player_house or str(m["b"]) == t.player_house):
				return str(bs["round_names"][r])
	return "war"


func _continue_pressed() -> void:
	match _next_action:
		"next_round":
			get_tree().change_scene_to_file(GAME_SCENE)
		"hall":
			_return_to_hall()
		_:
			get_tree().reload_current_scene()


func _return_to_hall() -> void:
	if net != null and is_instance_valid(net):
		net.shutdown()   # hang up before the scene goes — no orphan socket
		net = null
	Session.reset()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _request_concede() -> void:
	if game_over or busy:
		return
	if _concede_panel != null:
		_concede_panel.visible = true


func _confirm_concede() -> void:
	if _concede_panel != null:
		_concede_panel.visible = false
	if game_over or busy:
		return
	busy = true
	game_over = true
	_clear_selection()

	# 1. Collect all of the resigning player's living pieces
	var loser_side: int = PieceView.House.FROST if not player_color else PieceView.House.EMBER
	var loser_pieces: Array = []
	var king_pv: PieceView = null

	for sq in views:
		var pv: PieceView = views[sq]
		if is_instance_valid(pv) and pv.side == loser_side:
			loser_pieces.append(pv)
			if pv.piece_type == PieceView.Type.KING:
				king_pv = pv

	# 2. The King dramatically falls upon his own blade
	if king_pv != null and is_instance_valid(king_pv):
		if king_pv._anim != null:
			king_pv._anim.play("Death_B" if king_pv._anim.has_animation("Death_B") else "Death_A", 0.08)
			king_pv._anim.speed_scale = 1.15
		var tw := king_pv.create_tween().set_parallel(true)
		if tw != null:
			tw.tween_property(king_pv, "rotation:x", king_pv.rotation.x - 0.72, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(king_pv, "position:y", king_pv.position.y - 0.15, 0.42)
			await tw.finished
		await get_tree().create_timer(0.35).timeout

	# 3. The Dragon awakens, roars, and scorches the whole defeated army in fire!
	if spectator != null and is_instance_valid(spectator) and not loser_pieces.is_empty():
		_chrome_for_cinematic(true)
		await spectator.play_ashfall(loser_side, _rival_display, loser_pieces, false)
		_chrome_for_cinematic(false)
		for lsq in views.keys():
			if not is_instance_valid(views[lsq]):
				views.erase(lsq)

	_show_match_end(false, "The King has fallen upon his sword!\nThe dragon consumes the fallen realm in fire — %s triumphs." % _rival_display)
	busy = false
	_update_turn_label()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if promo_picker != null:
		return   # the modal owns the keyboard (it swallows keys itself too)
	if event.keycode == KEY_Z and event.is_command_or_control_pressed():
		_request_undo()   # queued through cinematics — see _try_undo
		return
	if duel_director != null and duel_director.is_active():
		return  # the director owns input mid-cinematic (click/Esc = skip)
	match event.keycode:
		KEY_R:
			if Session.is_network():
				return   # a one-sided reload would strand the other player
			if _victory_shown and _next_action != "rematch":
				_continue_pressed()
			else:
				get_tree().reload_current_scene()
		KEY_ENTER, KEY_KP_ENTER:
			if _victory_shown:
				_continue_pressed()
		KEY_ESCAPE:
			# _net_stalled (P1) is the recoverable one: Esc is a WAY OUT of a
			# host that stopped answering, not the only way out — the panel's
			# own button does the same, and staying put still works if the
			# answer turns up.
			if game_over or _net_disconnected or _net_stalled:
				_return_to_hall()


# -- oracle HUD glue --------------------------------------------------------


func _on_oracle_thinking_started() -> void:
	oracle_thinking = true
	oracle_think_count += 1
	_oracle_think_start_ms = Time.get_ticks_msec()


func _on_oracle_thinking_finished(_elapsed_s: float) -> void:
	oracle_thinking = false
	_update_turn_label()


func _on_oracle_stumbled(reason: String) -> void:
	oracle_stumble_count += 1
	if spectator != null and is_instance_valid(spectator):
		spectator.react_blunder()   # the wyrm disapproves (self-rate-limited)
	# Counseled saves are strong moves — soften the HUD line for them.
	var line := Ds4Opponent.HEEDS_TEXT if reason.contains(Ds4Opponent.HEEDS_TEXT) \
		else Ds4Opponent.STUMBLE_TEXT
	_flash_oracle(line, 3.0)


func _on_oracle_retry(_attempt: int) -> void:
	_flash_oracle("the Oracle reconsiders…", 2.0)


func _on_oracle_reason(text: String) -> void:
	## Maester mode: the Oracle's in-character reason, captioned under the
	## move list for 6 s.
	if _oracle_caption == null:
		return
	_oracle_caption.text = "“%s”" % text
	_oracle_caption.visible = true
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(_oracle_caption) and _oracle_caption.text == "“%s”" % text:
			_oracle_caption.visible = false)


func _on_banter_line(house_id: String, text: String, _beat: String) -> void:
	## The rival's taunt: bottom-LEFT caption in the rival's accent color,
	## mirroring _oracle_caption (bottom-right) so the two voices never
	## overlap. Show-for-6s + only-hide-if-unchanged, per _on_oracle_reason.
	##
	## TWO captions may never share one frame (ISSUES.md #4): if the duel
	## director's kill line is on screen, the taunt WAITS for it — spatial
	## separation (different rows) plus temporal separation (this wait).
	if _banter_caption == null:
		return
	_banter_token += 1
	var my := _banter_token
	var waited := 0.0
	while duel_director != null and is_instance_valid(duel_director) \
			and duel_director.caption_visible() and waited < BANTER_YIELD_MAX_SEC:
		await get_tree().create_timer(0.2, true, false, true).timeout
		waited += 0.2
		if my != _banter_token or not is_instance_valid(_banter_caption):
			return   # a newer line (or teardown) superseded this one
	var accent: Color = HouseRegistry.get_colors(house_id)["accent"]
	# HUE = whose voice this is; VALUE = whether anyone can read it. Only the
	# second is negotiable (see legible_accent).
	_banter_caption.add_theme_color_override("font_color", legible_accent(accent))
	_banter_caption.text = "%s: “%s”" % [_house_name(house_id), text]
	_banter_caption.modulate = Color(1, 1, 1, 0)
	_banter_caption.visible = true
	_fade_control(_banter_caption, 1.0, 0.25, my, func() -> int: return _banter_token)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(_banter_caption) \
				and _banter_caption.text.ends_with("“%s”" % text) \
				and my == _banter_token:
			await _fade_control(_banter_caption, 0.0, 0.4, my,
				func() -> int: return _banter_token)
			if is_instance_valid(_banter_caption) and my == _banter_token:
				_banter_caption.visible = false)


func _fade_control(ctrl: Control, to_alpha: float, sec: float, token: int,
		token_now: Callable) -> void:
	## Wall-clock alpha fade (immune to Engine.time_scale — captions play
	## inside slow-mo), abandoned the moment a newer line takes the slot.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	var from_alpha: float = ctrl.modulate.a
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(ctrl) and int(token_now.call()) == token:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (sec * 1000.0), 0.0, 1.0)
		ctrl.modulate.a = lerpf(from_alpha, to_alpha, u)
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _flash_oracle(text: String, sec: float) -> void:
	if _oracle_flash == null:
		return
	_oracle_flash.text = text
	_oracle_flash.visible = true
	get_tree().create_timer(sec).timeout.connect(func() -> void:
		if is_instance_valid(_oracle_flash) and _oracle_flash.text == text:
			_oracle_flash.visible = false)


var _frame_diag_done := false
var _frame_diag_count := 0

func _process(_delta: float) -> void:
	# Periodic visual frame capture from SnapViewport for tools/visionos/snap.py
	_frame_diag_count += 1
	var snap_cam: Camera3D = get_node_or_null("SnapViewport/SnapCamera")
	var xr_cam := get_tree().get_first_node_in_group("xr_camera")
	if snap_cam:
		if xr_cam and is_instance_valid(xr_cam):
			snap_cam.global_transform = xr_cam.global_transform
		else:
			var xr_orig: Node3D = get_tree().get_first_node_in_group("xr_origin")
			if xr_orig and is_instance_valid(xr_orig):
				snap_cam.global_position = xr_orig.global_position + Vector3(0, 1.2, 0)
				snap_cam.look_at(Vector3(0, 0.22, 0), Vector3.UP)
	if _frame_diag_count % 30 == 0:
		var snap_vp: SubViewport = get_node_or_null("SnapViewport")
		if snap_vp:
			var img := snap_vp.get_texture().get_image()
			if img:
				img.save_png("user://screenshot_latest.png")
	## Oracle thinking shimmer + elapsed seconds counter.
	if oracle_thinking and _turn_label != null and not game_over:
		var elapsed := (Time.get_ticks_msec() - _oracle_think_start_ms) / 1000.0
		_turn_label.text = "%s  %ds" % [Ds4Opponent.THINKING_TEXT, int(elapsed)]
		_turn_label.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.001 * TAU * 1.4)
	if _undo_pending:
		_try_undo()   # a queued take-back fires at the first safe frame


# -- HUD -------------------------------------------------------------------

const HUD_TEXT := Color(0.93, 0.89, 0.79)
const HUD_DIM := Color(0.75, 0.71, 0.62)
const HUD_GOLD := Color(0.88, 0.70, 0.35)
## Every HUD line crosses BOTH the black hall and a torch-lit pale surface
## somewhere in a match. One flat color can never clear both, so each line
## carries its own dark: a glyph outline (ISSUES.md P11 — "Haus Winterfang
## to move" vanished into the pale Winterfang banner behind the throne).
const HUD_OUTLINE := Color(0.02, 0.02, 0.03, 0.92)
## The top band also gets a scrim, because an outline alone leaves the text
## sitting IN the scene rather than on a title bar. A vertical gradient (not
## a filled bar) keeps it a cinematic vignette instead of one more rectangle.
const HUD_SCRIM_H := 118.0
const HUD_SCRIM := Color(0.02, 0.02, 0.03)
## The banter caption's accent, forced to a value that clears torch-lit
## stone. Hue is the rival's identity and is never touched.
const ACCENT_MIN_VALUE := 0.93
const ACCENT_MAX_SAT := 0.55


## The rival's accent color, made legible without losing whose voice it is:
## HUE is preserved exactly, saturation is capped so a deep dye cannot drag
## the value down with it, and the value is floored. Public so the e2e
## banter check can assert "same house, legible value" rather than an exact
## RGB triple (which is what used to pin the caption to an unreadable dye).
func legible_accent(accent: Color) -> Color:
	return Color.from_hsv(accent.h, minf(accent.s, ACCENT_MAX_SAT),
		maxf(accent.v, ACCENT_MIN_VALUE), 1.0)


## Fade the HUD chrome out for the length of a cinematic and back in after.
## Reference-counted (checkmate chains straight into ASHFALL, and a HUD that
## blinks back on for the one frame between them is worse than one that never
## left) and wall-clock driven, because every cinematic runs in slow-mo.
func _chrome_for_cinematic(entering: bool) -> void:
	_cine_depth = maxi(0, _cine_depth + (1 if entering else -1))
	_chrome_fade += 1
	var my := _chrome_fade
	if _cine_depth > 0:
		await _chrome_fade_to(my, 0.0, 0.4)
		return
	# Grace window: if another cinematic starts inside it, this restore is
	# superseded (the token check below) and the chrome never flashes.
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(0.55, true, false, true).timeout   # ignore_time_scale
	if _chrome_fade != my or _cine_depth > 0:
		return
	await _chrome_fade_to(my, 1.0, 0.55)


func _chrome_fade_to(my: int, target: float, dur: float) -> void:
	var from := 1.0
	for c in _hud_chrome:
		if is_instance_valid(c):
			from = c.modulate.a
			break
	var t0 := Time.get_ticks_msec()
	while _chrome_fade == my:
		var u := clampf(float(Time.get_ticks_msec() - t0) / (dur * 1000.0), 0.0, 1.0)
		var a := lerpf(from, target, u)
		for c in _hud_chrome:
			if is_instance_valid(c):
				c.modulate.a = a
		if u >= 1.0:
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _hud_scrim() -> TextureRect:
	## Top-of-frame gradient scrim: opaque-ish at the very top, gone by
	## HUD_SCRIM_H. Works over the dark hall (invisible there) AND over the
	## pale throne dais / house banners (where it buys the text its ground).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(HUD_SCRIM, 0.74), Color(HUD_SCRIM, 0.44), Color(HUD_SCRIM, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 128
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var scrim := TextureRect.new()
	scrim.name = "TopScrim"
	scrim.texture = tex
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scrim.offset_bottom = HUD_SCRIM_H
	return scrim


static func _outline(label: Label, px: int) -> void:
	label.add_theme_color_override("font_outline_color", HUD_OUTLINE)
	label.add_theme_constant_override("outline_size", px)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var scrim := _hud_scrim()
	hud.add_child(scrim)   # FIRST child — everything below draws over it
	_hud_chrome.append(scrim)

	var title := Label.new()
	title.name = "Title"
	title.text = "%s  vs  %s" % [_player_display.to_upper(), _rival_display.to_upper()]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HUD_TEXT)
	_outline(title, 6)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 14
	hud.add_child(title)

	var mottos := Label.new()
	mottos.name = "Mottos"
	if not player_house_id.is_empty():
		mottos.text = "“%s”   ·   “%s”" % [
			str(HouseRegistry.get_house(player_house_id).get("motto", "")),
			str(HouseRegistry.get_house(rival_house_id).get("motto", ""))]
	mottos.add_theme_font_size_override("font_size", 13)
	mottos.add_theme_color_override("font_color", HUD_DIM)
	_outline(mottos, 4)
	mottos.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mottos.anchor_left = 0.5
	mottos.anchor_right = 0.5
	mottos.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mottos.position.y = 44
	hud.add_child(mottos)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.add_theme_font_size_override("font_size", 15)
	_turn_label.add_theme_color_override("font_color", HUD_TEXT)
	_outline(_turn_label, 5)
	_turn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_turn_label.anchor_left = 0.5
	_turn_label.anchor_right = 0.5
	_turn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn_label.position.y = 66
	hud.add_child(_turn_label)

	_casualty_label = RichTextLabel.new()
	_casualty_label.name = "CasualtyLabel"
	_casualty_label.bbcode_enabled = true
	_casualty_label.fit_content = true
	_casualty_label.scroll_active = false
	_casualty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_casualty_label.add_theme_font_size_override("normal_font_size", 14)
	_casualty_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_casualty_label.anchor_left = 0.5
	_casualty_label.anchor_right = 0.5
	_casualty_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_casualty_label.position.y = 90
	_casualty_label.custom_minimum_size = Vector2(800, 24)
	hud.add_child(_casualty_label)

	var ctx := Label.new()
	ctx.name = "MatchContext"
	if Session.configured:
		var bits: Array[String] = []
		if Session.mode == "tournament" and Session.tournament != null:
			bits.append(_next_round_name(Session.tournament))
		bits.append(str(Session.opponent.get("label", "")))
		ctx.text = " · ".join(bits)
	ctx.add_theme_font_size_override("font_size", 14)
	ctx.add_theme_color_override("font_color", HUD_DIM)
	_outline(ctx, 4)
	ctx.position = Vector2(16, 14)
	hud.add_child(ctx)

	if Session.is_network():
		# The three things a player needs to know at a glance in a head-to-head
		# match: that it IS one, which army is theirs, and who they are facing.
		_net_status = Label.new()
		_net_status.name = "NetStatus"
		_net_status.text = "⚔ head-to-head · you play %s · %s vs %s" % [
			NetProtocol.color_name(player_color), _player_display, _rival_display]
		_net_status.add_theme_font_size_override("font_size", 12)
		_net_status.add_theme_color_override("font_color", HUD_GOLD)
		_outline(_net_status, 4)
		_net_status.position = Vector2(16, 34)
		hud.add_child(_net_status)

	if oracle != null:
		# The Oracle's mode, named under the opponent label.
		var mode_lbl := Label.new()
		mode_lbl.name = "OracleMode"
		mode_lbl.text = str(Ds4Opponent.MODE_LABELS.get(oracle.mode, oracle.mode))
		mode_lbl.add_theme_font_size_override("font_size", 12)
		mode_lbl.add_theme_color_override("font_color", HUD_GOLD)
		_outline(mode_lbl, 4)
		mode_lbl.position = Vector2(16, 34)
		hud.add_child(mode_lbl)

	_oracle_flash = Label.new()
	_oracle_flash.name = "OracleFlash"
	_oracle_flash.visible = false
	_oracle_flash.add_theme_font_size_override("font_size", 17)
	_oracle_flash.add_theme_color_override("font_color", HUD_GOLD)
	_outline(_oracle_flash, 5)
	_oracle_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_oracle_flash.anchor_left = 0.5
	_oracle_flash.anchor_right = 0.5
	_oracle_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_oracle_flash.position.y = 118
	hud.add_child(_oracle_flash)

	# The take-back control: subtle, parked just above the move list it edits.
	_undo_btn = Button.new()
	# Concede prompt button (shown when King is selected)
	_concede_btn = Button.new()
	_concede_btn.name = "ConcedeButton"
	_concede_btn.flat = true
	_concede_btn.focus_mode = Control.FOCUS_NONE
	_concede_btn.text = "🗡️ Fall Upon Thy Sword"
	_concede_btn.tooltip_text = "Surrender the crown and yield the match"
	_concede_btn.add_theme_font_size_override("font_size", 13)
	_concede_btn.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	_concede_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.65))
	_concede_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_concede_btn.offset_left = -200
	_concede_btn.offset_top = 18
	_concede_btn.offset_right = -16
	_concede_btn.visible = false
	_concede_btn.pressed.connect(_request_concede)
	hud.add_child(_concede_btn)

	_undo_btn.name = "UndoButton"
	_undo_btn.flat = true
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.add_theme_font_size_override("font_size", 13)
	_undo_btn.add_theme_color_override("font_color", HUD_DIM)
	_undo_btn.add_theme_color_override("font_hover_color", HUD_GOLD)
	_undo_btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.35, 0.3, 0.55))
	_undo_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_undo_btn.offset_left = -150
	_undo_btn.offset_top = 48
	_undo_btn.offset_right = -16
	_undo_btn.tooltip_text = "Take back your last move (Cmd/Ctrl+Z)"
	_undo_btn.pressed.connect(_request_undo)
	hud.add_child(_undo_btn)
	_update_undo_button()

	_concede_panel = PanelContainer.new()
	_concede_panel.name = "ConcedePanel"
	_concede_panel.visible = false
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.06, 0.04, 0.045, 0.96)
	c_style.border_color = Color(0.8, 0.28, 0.2)
	c_style.set_border_width_all(2)
	c_style.corner_radius_top_left = 8
	c_style.corner_radius_top_right = 8
	c_style.corner_radius_bottom_left = 8
	c_style.corner_radius_bottom_right = 8
	c_style.set_content_margin_all(24)
	_concede_panel.add_theme_stylebox_override("panel", c_style)
	_concede_panel.set_anchors_preset(Control.PRESET_CENTER)
	_concede_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_concede_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 14)

	var c_title := Label.new()
	c_title.text = "FALL UPON THY SWORD?"
	c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_title.add_theme_font_size_override("font_size", 20)
	c_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	_outline(c_title, 5)
	cvbox.add_child(c_title)

	var c_desc := Label.new()
	c_desc.text = "Will the King surrender the throne and drink the bitter draft of defeat?\nThe bards will sing of this craven surrender for a hundred winters."
	c_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_desc.add_theme_font_size_override("font_size", 14)
	c_desc.add_theme_color_override("font_color", HUD_DIM)
	_outline(c_desc, 3)
	cvbox.add_child(c_desc)

	var chbox := HBoxContainer.new()
	chbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chbox.add_theme_constant_override("separation", 20)

	var c_yes := Button.new()
	c_yes.text = "🗡️ I Yield the Crown (Resign)"
	c_yes.add_theme_font_size_override("font_size", 14)
	c_yes.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	c_yes.pressed.connect(_confirm_concede)
	chbox.add_child(c_yes)

	var c_no := Button.new()
	c_no.text = "🛡️ Fight to the Bitter End"
	c_no.add_theme_font_size_override("font_size", 14)
	c_no.add_theme_color_override("font_color", HUD_GOLD)
	c_no.pressed.connect(func(): _concede_panel.visible = false)
	chbox.add_child(c_no)

	cvbox.add_child(chbox)
	_concede_panel.add_child(cvbox)
	hud.add_child(_concede_panel)

	_move_list = RichTextLabel.new()
	_move_list.name = "MoveList"
	_move_list.scroll_following = true
	_move_list.add_theme_font_size_override("normal_font_size", 14)
	_move_list.add_theme_color_override("default_color", HUD_DIM)
	_move_list.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_move_list.offset_left = -150
	_move_list.offset_top = 80
	_move_list.offset_right = -16
	_move_list.offset_bottom = -44
	hud.add_child(_move_list)

	_oracle_caption = Label.new()
	_oracle_caption.name = "OracleCaption"
	_oracle_caption.visible = false
	_oracle_caption.add_theme_font_size_override("font_size", 13)
	_oracle_caption.add_theme_color_override("font_color", HUD_GOLD)
	_oracle_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_oracle_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_oracle_caption.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_oracle_caption.offset_left = -360
	_oracle_caption.offset_top = -38
	_oracle_caption.offset_right = -16
	_oracle_caption.offset_bottom = -10
	hud.add_child(_oracle_caption)

	# THE CHROME REGISTER. The title block ("HAUS X vs HAUS Y" + mottos +
	# turn line) lay exactly across the dragon's neck and skull in
	# showcase/10_throne_room.png — the best frame in the game had no readable
	# dragon head. Everything a cinematic must not have to draw around is
	# listed here; captions and the victory card are deliberately absent.
	_hud_chrome.append_array([title, mottos, _turn_label, _casualty_label, ctx,
		_oracle_flash, _undo_btn, _move_list, _oracle_caption])
	if _net_status != null:
		_hud_chrome.append(_net_status)
	if oracle != null:
		var ml := hud.get_node_or_null("OracleMode") as Control
		if ml != null:
			_hud_chrome.append(ml)

	_banter_caption = Label.new()
	_banter_caption.name = "BanterCaption"
	_banter_caption.visible = false
	_banter_caption.add_theme_font_size_override("font_size", 16)
	# Outline-only was the original call (ISSUES.md #4: "a filled panel there
	# would be one more rectangle on the frame"). Measured on the shipped
	# frame it lost: the taunt's glyphs came in at 0.086 relative luminance
	# against 0.071 of stone floor — 1.13:1, the same value as the flagstones
	# behind them, i.e. invisible. The rival's taunts are one of the best
	# things in this game and nobody could read them.
	#
	# So the taunt now wears the SAME clothes as the kill line — the shared
	# DuelDirector.caption_backing() plate — which is not "one more
	# rectangle" but the one caption look repeated in the other corner. The
	# plate HUGS its text (autowrap off + zero-width rect grown to the
	# label's minimum size), so it never becomes a slab across the frame,
	# and the outline stays for the glyph edges that overhang it.
	_banter_caption.add_theme_stylebox_override("normal",
		DuelDirector.caption_backing())
	_banter_caption.add_theme_color_override("font_outline_color", HUD_OUTLINE)
	_banter_caption.add_theme_constant_override("outline_size", 4)
	# BanterEngine clamps every line to 90 chars, so the widest possible
	# caption (house name + quotes + 90) fits inside half the frame without
	# wrapping — and only an un-wrapped label can size its plate to its text.
	_banter_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	_banter_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_banter_caption.anchor_right = 0.0
	_banter_caption.grow_horizontal = Control.GROW_DIRECTION_END
	_banter_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Bottom row, BELOW the cinematic caption's band (which occupies 96..160
	# px off the bottom edge) — the two voices can never share a screen row.
	_banter_caption.offset_left = 16
	_banter_caption.offset_right = 16
	_banter_caption.offset_top = -14
	_banter_caption.offset_bottom = -14
	hud.add_child(_banter_caption)

	_victory_panel = PanelContainer.new()
	_victory_panel.name = "VictoryPanel"
	_victory_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.045, 0.92)
	style.border_color = Color(0.55, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_content_margin_all(26)
	_victory_panel.add_theme_stylebox_override("panel", style)
	_victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	_victory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_victory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_victory_panel.add_child(vbox)
	_victory_label = Label.new()
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.add_theme_font_size_override("font_size", 26)
	_victory_label.add_theme_color_override("font_color", HUD_TEXT)
	vbox.add_child(_victory_label)
	_continue_btn = Button.new()
	_continue_btn.name = "ContinueButton"
	_continue_btn.flat = true
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.add_theme_font_size_override("font_size", 18)
	_continue_btn.add_theme_color_override("font_color", HUD_GOLD)
	_continue_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.45))
	_continue_btn.pressed.connect(_continue_pressed)
	vbox.add_child(_continue_btn)
	hud.add_child(_victory_panel)

	if Session.is_network():
		_build_net_panel(hud)


func _build_net_panel(hud: CanvasLayer) -> void:
	## The "something went wrong with the connection" card. Never a code, never
	## an error number: a plain sentence and the one action that still works.
	_net_panel = PanelContainer.new()
	_net_panel.name = "NetPanel"
	_net_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.03, 0.03, 0.94)
	style.border_color = Color(0.72, 0.32, 0.22)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	_net_panel.add_theme_stylebox_override("panel", style)
	_net_panel.set_anchors_preset(Control.PRESET_CENTER)
	_net_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_net_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_net_panel.add_child(vbox)
	_net_panel_label = Label.new()
	_net_panel_label.name = "NetPanelText"
	_net_panel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_panel_label.custom_minimum_size = Vector2(520, 0)
	_net_panel_label.add_theme_font_size_override("font_size", 20)
	_net_panel_label.add_theme_color_override("font_color", HUD_TEXT)
	vbox.add_child(_net_panel_label)
	var back := Button.new()
	back.name = "NetPanelButton"
	back.text = "Return to the Hall of Banners"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", HUD_GOLD)
	back.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.45))
	back.pressed.connect(_return_to_hall)
	vbox.add_child(back)
	hud.add_child(_net_panel)


func _show_net_panel(text: String) -> void:
	print("NET PANEL %s" % text.replace("\n", " · "))
	if _net_panel == null or _net_panel_label == null:
		return
	_net_panel_label.text = "%s\n\nPress Esc, or use the button below." % text
	_net_panel.visible = true


func _hide_net_panel() -> void:
	## Only the RECOVERABLE notice (the stalled request, P1) ever takes this
	## door back out — a lost opponent and a desync are terminal and leave the
	## card up until the player goes home.
	if _net_panel != null and _net_panel.visible and not _net_disconnected:
		_net_panel.visible = false


func _update_turn_label(ai_thinking := false) -> void:
	if _turn_label == null:
		return
	_turn_label.modulate.a = 1.0
	if _net_disconnected:
		_turn_label.text = "the connection is gone"
	elif promo_picker != null:
		_turn_label.text = "choose the crown"
	elif game_over:
		_turn_label.text = "the field falls silent"
	elif _net_stalled:
		# P1: the state that used to be an unlabelled frozen board.
		_turn_label.text = "your friend's game stopped answering"
	elif ai_thinking or state.turn != player_color:
		if net != null:
			_turn_label.text = "%s is deciding..." % _rival_display
		elif oracle != null:
			_turn_label.text = Ds4Opponent.THINKING_TEXT
		else:
			_turn_label.text = "%s is thinking..." % _rival_display
	elif busy and net != null:
		_turn_label.text = NetProtocol.request_slow_text() \
			if (is_instance_valid(net) and net.is_active() and net.request_is_slow()) \
			else "sending your move..."
	else:
		_turn_label.text = "%s to move" % _player_display
	_update_casualties_hud()


const PIECE_GLYPHS := {
	"p": "♟",
	"n": "♞",
	"b": "♝",
	"r": "♜",
	"q": "♛",
}


func _compute_casualties() -> Dictionary:
	var initial_w := {"p": 8, "n": 2, "b": 2, "r": 2, "q": 1}
	var initial_b := {"p": 8, "n": 2, "b": 2, "r": 2, "q": 1}
	var current_w := {"p": 0, "n": 0, "b": 0, "r": 0, "q": 0}
	var current_b := {"p": 0, "n": 0, "b": 0, "r": 0, "q": 0}

	if state != null and state.pieces != null:
		for p in state.pieces:
			if p == null:
				continue
			var p_str := str(p)
			var p_lower := p_str.to_lower()
			if p_lower == "k":
				continue
			if p_str == p_lower:
				current_b[p_lower] = current_b.get(p_lower, 0) + 1
			else:
				current_w[p_lower] = current_w.get(p_lower, 0) + 1

	var lost_w: Dictionary = {}
	var lost_b: Dictionary = {}
	var val_w := 0
	var val_b := 0
	var piece_values := {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9}

	for k in ["p", "n", "b", "r", "q"]:
		var diff_w = maxi(0, initial_w[k] - current_w[k])
		if diff_w > 0:
			lost_w[k] = diff_w
			val_w += diff_w * piece_values[k]
		var diff_b = maxi(0, initial_b[k] - current_b[k])
		if diff_b > 0:
			lost_b[k] = diff_b
			val_b += diff_b * piece_values[k]

	return {
		"lost_white": lost_w,
		"lost_black": lost_b,
		"val_white_lost": val_w,
		"val_black_lost": val_b,
		"advantage_white": val_b - val_w,
	}


func _format_casualty_side(lost: Dictionary) -> String:
	if lost.is_empty():
		return "[color=#666]none[/color]"
	var parts: Array[String] = []
	for k in ["q", "r", "b", "n", "p"]:
		if lost.has(k) and lost[k] > 0:
			var count: int = lost[k]
			if count == 1:
				parts.append(PIECE_GLYPHS[k])
			else:
				parts.append("%s×%d" % [PIECE_GLYPHS[k], count])
	return " ".join(parts)


func _update_casualties_hud() -> void:
	if _casualty_label == null or state == null:
		return
	var cas := _compute_casualties()
	var white_str := _format_casualty_side(cas["lost_white"])
	var black_str := _format_casualty_side(cas["lost_black"])

	var is_player_white: bool = not player_color
	var player_losses := white_str if is_player_white else black_str
	var rival_losses := black_str if is_player_white else white_str
	var player_adv: int = int(cas["advantage_white"]) if is_player_white else -int(cas["advantage_white"])

	var adv_str := ""
	if player_adv > 0:
		adv_str = "  [b][color=#ffd700]+%d[/color][/b]" % player_adv
	elif player_adv < 0:
		adv_str = "  [b][color=#e57373]-%d[/color][/b]" % abs(player_adv)

	_casualty_label.text = "[center][color=#94a3b8]%s losses:[/color] %s%s   [color=#555]│[/color]   [color=#f59e0b]%s losses:[/color] %s[/center]" % [
		_player_display, player_losses, adv_str, _rival_display, rival_losses
	]


# -- e2e hooks -------------------------------------------------------------


## --debug-coords: the orientation tiebreaker. Renders the ENGINE'S OWN belief
## of every file, rank, and royal square as world-space Label3Ds — every
## position below derives from square_index_from_name -> sq_of ->
## square_to_world, the exact chain gameplay uses, and NOTHING derives from
## the camera. If the mapping is mirrored, the labels render mirrored: the
## overlay makes the engine's claim visible so a human (or a screenshot
## reader) can diff it against chess truth in absolute terms.
func _build_debug_coords() -> void:
	var root := Node3D.new()
	root.name = "DebugCoords"
	add_child(root)
	# File letters a..h along the rank-1 (White home) edge, each at the world
	# X the engine believes that file occupies.
	for f in 8:
		var letter := char("a".unicode_at(0) + f)
		var pos := board.square_to_world(
			sq_of(ChessState.square_index_from_name(letter + "1")))
		var out_z := pos.z + (1.0 if pos.z > 0.0 else -1.0)
		_debug_label(root, letter, Vector3(pos.x, 0.45, out_z),
			Color(1.0, 0.85, 0.25))
	# Rank numbers 1..8 along the a-file edge, each at the world Z the engine
	# believes that rank occupies.
	for r in 8:
		var pos := board.square_to_world(
			sq_of(ChessState.square_index_from_name("a%d" % (r + 1))))
		var out_x := pos.x + (1.0 if pos.x > 0.0 else -1.0)
		_debug_label(root, str(r + 1), Vector3(out_x, 0.45, pos.z),
			Color(0.35, 0.9, 1.0))
	# Floating type labels over the 4 royal squares, as the engine believes
	# them. Under a correct mapping "Qd1" floats over the 4th-from-left near
	# square and the model beneath it is the uncrowned queen.
	#
	# d and e are ADJACENT files, so two same-height 3-glyph labels one world
	# unit apart collided into unreadable mush ("QdKe1", ISSUES.md #16). The
	# overlay is our permanent human-audit instrument, so legibility is a
	# hard requirement: the queen's plate rides high, the king's low, both
	# smaller, and each drops a leader stem to the head of the piece it
	# names — no two plates can share a screen row again.
	for royal in [["Qd1", "d1", 3.25], ["Ke1", "e1", 2.15],
			["Qd8", "d8", 3.25], ["Ke8", "e8", 2.15]]:
		var pos := board.square_to_world(
			sq_of(ChessState.square_index_from_name(str(royal[1]))))
		var y := float(royal[2])
		_debug_label(root, str(royal[0]), Vector3(pos.x, y, pos.z),
			Color(1.0, 0.45, 0.9), 104)
		_debug_stem(root, Vector3(pos.x, 0.0, pos.z), 1.65, y - 0.22,
			Color(1.0, 0.45, 0.9))


func _debug_label(parent: Node3D, text: String, pos: Vector3, color: Color,
		size: int = 150) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.modulate = color
	l.outline_size = int(size * 0.2)
	l.outline_modulate = Color(0, 0, 0, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)


func _debug_stem(parent: Node3D, base: Vector3, y0: float, y1: float,
		color: Color) -> void:
	## Leader line from a floating royal plate down to the head of the piece
	## it names — starts above the tallest crest so it never veils a model.
	if y1 <= y0:
		return
	var stem := MeshInstance3D.new()
	stem.name = "Stem"
	var box := BoxMesh.new()
	box.size = Vector3(0.035, y1 - y0, 0.035)
	stem.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.75)
	m.no_depth_test = true
	stem.material_override = m
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stem.position = Vector3(base.x, (y0 + y1) * 0.5, base.z)
	parent.add_child(stem)


func _smoke() -> void:
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("GH_SMOKE_OUT")
	if out.is_empty():
		out = "user://smoke.png"
	var err := img.save_png(out)
	print("SMOKE_SAVED path=%s err=%d size=%dx%d" % [out, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)


func _dump_tree() -> void:
	await get_tree().process_frame
	print_tree_pretty()
	print("TREE_PIECES=%d" % views.size())
	get_tree().quit()
