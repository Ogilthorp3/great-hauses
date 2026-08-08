extends Node3D
## Great Houses — game root. The player's chosen Great House battles a rival
## house across a torch-lit hall: full rules via src/chess, capture duels in
## slow motion (DuelDirector), house-dyed armies and banners, SAN move list,
## tournament bracket between matches, an optional DS4-Oracle opponent,
## undo/take-back (HUD button + Cmd/Ctrl+Z — 3 per game in tournaments,
## unlimited in single matches), and hover-only type-glyph rings.
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

const TOURNAMENT_UNDO_LIMIT := 3     # take-backs per tournament game (single: unlimited)

const RESULT_TEXT := {
	ChessState.RESULT.STALEMATE: "Stalemate — the war ends in a draw",
	ChessState.RESULT.INSUFFICIENT: "Draw — neither house can force mate",
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
var oracle: Ds4Opponent = null       # non-null only vs DS4-Oracle
var oracle_thinking := false
var oracle_think_count := 0          # e2e evidence: thinking HUD fired
var oracle_stumble_count := 0        # e2e evidence: fallback was surfaced
var _oracle_think_start_ms := 0

var player_house_id := ""            # "" = legacy Frost/Ember skin
var rival_house_id := ""
var _player_display := "House Frost"
var _rival_display := "House Ember"

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

var _turn_moves: Array = []         # SAN-notated legal moves for side to move
var _san_log: Array[String] = []

var _turn_label: Label
var _move_list: RichTextLabel
var _oracle_flash: Label
var _oracle_caption: Label
var _banter_caption: Label

# shared blunder probe (one shallow Stockfish sample feeds banter + dragon)
var _blunder_engine: UciEngine = null
var _blunder_failed := false
var _blunder_busy := false
var blunder_count := 0               # e2e evidence: the blunder hook fired
var _victory_panel: PanelContainer
var _victory_label: Label
var _continue_btn: Button
var _victory_shown := false
var _next_action := "rematch"       # "rematch" | "next_round" | "hall"


func _ready() -> void:
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
	state = ChessState.new()
	if not fen.is_empty() and not state.set_fen(fen):
		push_error("invalid --e2e-fen '%s' — using the standard lineup" % fen)
	duel_director = DuelDirector.new()
	duel_director.name = "DuelDirector"
	add_child(duel_director)
	duel_director.victory_panel_requested.connect(_on_victory_panel_requested)
	# Music rides the director's own cinematic signals: every cinematic ducks
	# the playlist −8 dB; only the duel also fires a stinger at the slow-mo.
	duel_director.cinematic_started.connect(_on_cinematic_started)
	duel_director.cinematic_finished.connect(func(_kind: String) -> void:
		Music.unduck())
	_setup_spectator()
	if Session.configured and str(Session.opponent.get("kind", "")) == "ds4_oracle":
		oracle = Ds4Opponent.new()
		oracle.name = "Oracle"
		oracle.mode = str(Session.opponent.get("oracle_mode", Ds4Opponent.MODE_PURE))
		add_child(oracle)
		oracle.thinking_started.connect(_on_oracle_thinking_started)
		oracle.thinking_finished.connect(_on_oracle_thinking_finished)
		oracle.oracle_stumbled.connect(_on_oracle_stumbled)
		oracle.retry_attempted.connect(_on_oracle_retry)
		oracle.oracle_reason.connect(_on_oracle_reason)
	_build_hud()
	_dress_hall()
	Music.play_game()   # idempotent; crossfades out whatever the menu left playing
	_setup_banter()     # after the HUD — the opening pool line arrives synchronously
	_spawn_from_state()
	_refresh_turn_moves()
	_update_turn_label()
	board.square_clicked.connect(_on_square_clicked)
	board.square_hovered.connect(_on_square_hovered)
	var args := OS.get_cmdline_user_args()
	if args.has("--debug-coords"):
		_build_debug_coords()
	if args.has("--smoke"):
		_smoke()
	elif args.has("--dump-tree"):
		_dump_tree()
	if state.turn and not game_over:
		_kick_ai_opening()


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
	add_child(spectator)


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
	if kind == "duel":
		Music.sting_duel()


# -- identity / hall dressing ----------------------------------------------


func _resolve_identity() -> void:
	if not Session.configured:
		return
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
	return str(h.get("name", "House " + id.capitalize()))


func _dress_hall() -> void:
	## Banner index map (great_hall.gd): 0-2 far wall, 3-5 west, 6-8 east.
	if player_house_id.is_empty():
		return
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall == null:
		return
	var pc := HouseRegistry.get_colors(player_house_id)
	var rc := HouseRegistry.get_colors(rival_house_id)
	hall.set_banner_colors([
		pc["primary"], pc["accent"], rc["primary"],     # far wall — both claims
		pc["primary"], pc["secondary"], pc["primary"],  # west wall — the player
		rc["primary"], rc["secondary"], rc["primary"],  # east wall — the rival
	])


func _dress_hall_championship() -> void:
	## The throne shot: every banner in the hall falls to the champion.
	if player_house_id.is_empty():
		return
	var hall: GreatHall = get_node_or_null("GreatHall")
	if hall == null:
		return
	var pc := HouseRegistry.get_colors(player_house_id)
	var colors: Array = []
	for i in 9:
		colors.append(pc["primary"] if i % 2 == 0 else pc["accent"])
	hall.set_banner_colors(colors)


# -- square mapping (engine 0..63, a8=0 .. h1=63  <->  board Vector2i) ------
# Board sq.y=0 is the player's home rank (world -Z); the camera starts
# behind the player, so files run a..h from screen-left: sq.x = 7 - file.


static func sq_of(idx: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(7 - (idx % 8), 7 - (idx / 8))


static func idx_of(sq: Vector2i) -> int:
	return (7 - sq.y) * 8 + (7 - sq.x)


# -- setup -----------------------------------------------------------------


func _spawn_from_state() -> void:
	_hovered_view = null   # the freed views take any hover reveal with them
	for sq in views:
		(views[sq] as PieceView).queue_free()
	views.clear()
	for idx in 64:
		var c = state.pieces[idx]
		if c == null:
			continue
		var piece_side := PieceView.House.EMBER if ChessState.piece_color(c) \
			else PieceView.House.FROST
		_spawn(CHAR_TO_TYPE[str(c).to_lower()], piece_side, sq_of(idx))


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
	return p


func _on_piece_died(p: PieceView) -> void:
	death_log.append(p.death_anim)


func _kick_ai_opening() -> void:
	## FEN gave the rival the move — let the AI open.
	busy = true
	await _ai_ply()
	busy = false
	_update_turn_label()


# -- interaction -----------------------------------------------------------


func _on_square_clicked(sq: Vector2i) -> void:
	if busy or game_over or state == null or state.turn \
			or (duel_director != null and duel_director.is_active()):
		return  # not interactive during animations/cinematics, after the end, or on the rival's turn
	var idx := idx_of(sq)
	var piece = state.pieces[idx]
	var is_own: bool = piece != null and not ChessState.piece_color(piece)
	if selected == null:
		if is_own:
			_select(sq)
		return
	if sq == selected:
		_clear_selection()
		return
	if is_own:
		_select(sq)
		return
	var move = _move_for(idx_of(selected), idx)
	if move == null:
		return
	_clear_selection()
	_play_turn(move)


func _select(sq: Vector2i) -> void:
	_set_selected_glow(false)
	selected = sq
	board.set_selected(sq)
	_set_selected_glow(true)
	var targets: Array[Vector2i] = []
	var from_idx := idx_of(sq)
	for m in _turn_moves:
		if m.from_square == from_idx and not targets.has(sq_of(m.to_square)):
			targets.append(sq_of(m.to_square))
	board.show_legal_moves(targets)


func _clear_selection() -> void:
	_set_selected_glow(false)
	selected = null
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
	var pv: PieceView = null
	if sq != null:
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


func _move_for(from_idx: int, to_idx: int) -> Variant:
	## The matching legal move; promotions auto-pick the queen (v1).
	var found = null
	for m in _turn_moves:
		if m.from_square == from_idx and m.to_square == to_idx:
			found = m
			if m.promotion == null or str(m.promotion).to_lower() == "q":
				return m
	return found


# -- turn flow -------------------------------------------------------------


func _play_turn(move) -> void:
	## One full round: the player's ply, then (if the game goes on) the rival's.
	## An undo mid-round bumps _turn_gen; every await below re-checks it and a
	## stale continuation drops out without touching busy (the undo owns it).
	busy = true
	_push_undo_checkpoint()
	var gen := _turn_gen
	await _execute_ply(move)
	if gen != _turn_gen:
		return
	if not game_over and state.turn:
		await _ai_ply()
		if gen != _turn_gen:
			return
	busy = false
	_update_turn_label()
	_update_undo_button()


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
	var mover_is_ember: bool = state.turn
	var fen_before := "" if mover_is_ember else str(state.get_fen())
	_record_san(move)
	state.apply_move(move)
	if banter != null:
		banter.note_ply()                      # the rate limiter's clock
	var fen_after := "" if mover_is_ember else str(state.get_fen())
	_refresh_turn_moves()
	await _animate_move(move, mover_is_ember)
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


func _animate_move(move, mover_is_ember: bool) -> void:
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
			# now running under the director's time curve and battle cam.
			await duel_director.play_duel(mover, victim, _duel_meta(mover_is_ember),
				func(): await mover.play_capture(victim))
			if spectator != null and is_instance_valid(spectator):
				spectator.react_capture(sq_of(move.captured_square))  # flinch, self-rate-limited
	await mover.move_to(target, _walk_time(mover.position, target))
	views[to_sq] = mover
	if move.promotion != null:
		mover.queue_free()
		var promo_side := PieceView.House.EMBER if mover_is_ember else PieceView.House.FROST
		var promoted := _spawn(CHAR_TO_TYPE[str(move.promotion).to_lower()], promo_side, to_sq)
		promoted.spawn_flourish()  # overlaps the director's beam + banner
		await duel_director.play_promotion(promoted)


func _refresh_turn_moves() -> void:
	_turn_moves = state.legal_moves(true)


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
	if not busy and state.turn:
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
	_spawn_from_state()     # captured pieces resurrect
	_refresh_turn_moves()
	_update_turn_label()
	_update_undo_button()


func _update_undo_button() -> void:
	if _undo_btn == null:
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
	var player_won := result == ChessState.RESULT.CHECKMATE and state.turn
	if Session.configured and Session.mode == "tournament" and Session.tournament != null:
		Session.tournament.report_result(player_won)  # a draw eliminates the player
	if banter != null and result == ChessState.RESULT.CHECKMATE:
		# Perspective flip: the module speaks for the rival. Draws stay silent
		# (no draw pools — silence beats a wrong-register line).
		banter.on_beat(BanterEngine.BEAT_ENDGAME_LOSE if player_won \
			else BanterEngine.BEAT_ENDGAME_WIN)
	_update_turn_label()
	_end_sequence.call_deferred(result, player_won)


func _end_sequence(result: int, player_won: bool) -> void:
	if result != ChessState.RESULT.CHECKMATE:
		_show_match_end(false, RESULT_TEXT.get(result, "The war is over"))
		return
	# The mated king falls under the checkmate cinematic's slow orbit.
	var loser := PieceView.House.EMBER if state.turn else PieceView.House.FROST
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
	await duel_director.play_checkmate(king_view, winner_key,
		func(): await king_view.die())
	# ── ASHFALL: king death → the wyrm burns the beaten army → victory flow ──
	if spectator != null and is_instance_valid(spectator):
		var loser_pieces: Array = []
		for lsq in views:
			var lpv: PieceView = views[lsq]
			if is_instance_valid(lpv) and lpv.side == loser:
				loser_pieces.append(lpv)
		if not loser_pieces.is_empty():   # a bare king leaves nothing to burn
			await spectator.play_ashfall(loser,
				duel_director.resolve_house_name(winner_key), loser_pieces)
			for lsq in views.keys():      # ashfall freed those views
				if not is_instance_valid(views[lsq]):
					views.erase(lsq)


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
	await duel_director.play_championship_tableau(hall.throne_focus())


func _champion_king_view() -> PieceView:
	## The player's king (the champion is always the player when this runs).
	for sq in views:
		var pv: PieceView = views[sq]
		if is_instance_valid(pv) and pv.piece_type == PieceView.Type.KING \
				and pv.side == PieceView.House.FROST:
			return pv
	return null


func _on_victory_panel_requested(winning_house: String) -> void:
	var player_won := state.get_result() == ChessState.RESULT.CHECKMATE and state.turn
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
	if Session.configured and Session.mode == "tournament" and Session.tournament != null:
		var t: Tournament = Session.tournament
		if t.is_champion():
			var motto := str(HouseRegistry.get_house(player_house_id).get("motto", ""))
			lines = ["THE THRONE IS WON",
				"%s rules the Nine Houses." % _player_display, "“%s”" % motto]
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
			lines.append("%s has fallen from the war." % _player_display)
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
	Session.reset()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_Z and event.is_command_or_control_pressed():
		_request_undo()   # queued through cinematics — see _try_undo
		return
	if duel_director != null and duel_director.is_active():
		return  # the director owns input mid-cinematic (click/Esc = skip)
	match event.keycode:
		KEY_R:
			if _victory_shown and _next_action != "rematch":
				_continue_pressed()
			else:
				get_tree().reload_current_scene()
		KEY_ENTER, KEY_KP_ENTER:
			if _victory_shown:
				_continue_pressed()
		KEY_ESCAPE:
			if game_over:
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
	if _banter_caption == null:
		return
	var accent: Color = HouseRegistry.get_colors(house_id)["accent"]
	_banter_caption.add_theme_color_override("font_color", accent)
	_banter_caption.text = "%s: “%s”" % [_house_name(house_id), text]
	_banter_caption.visible = true
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(_banter_caption) \
				and _banter_caption.text.ends_with("“%s”" % text):
			_banter_caption.visible = false)


func _flash_oracle(text: String, sec: float) -> void:
	if _oracle_flash == null:
		return
	_oracle_flash.text = text
	_oracle_flash.visible = true
	get_tree().create_timer(sec).timeout.connect(func() -> void:
		if is_instance_valid(_oracle_flash) and _oracle_flash.text == text:
			_oracle_flash.visible = false)


func _process(_delta: float) -> void:
	## Oracle thinking shimmer + elapsed seconds counter.
	if oracle_thinking and _turn_label != null and not game_over:
		var elapsed := (Time.get_ticks_msec() - _oracle_think_start_ms) / 1000.0
		_turn_label.text = "%s  %ds" % [Ds4Opponent.THINKING_TEXT, int(elapsed)]
		_turn_label.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.001 * TAU * 1.4)
	if _undo_pending:
		_try_undo()   # a queued take-back fires at the first safe frame


# -- HUD -------------------------------------------------------------------

const HUD_TEXT := Color(0.85, 0.8, 0.7)
const HUD_DIM := Color(0.62, 0.58, 0.5)
const HUD_GOLD := Color(0.8, 0.62, 0.3)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var title := Label.new()
	title.name = "Title"
	title.text = "%s  vs  %s" % [_player_display.to_upper(), _rival_display.to_upper()]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HUD_TEXT)
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
	mottos.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mottos.anchor_left = 0.5
	mottos.anchor_right = 0.5
	mottos.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mottos.position.y = 44
	hud.add_child(mottos)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.add_theme_font_size_override("font_size", 15)
	_turn_label.add_theme_color_override("font_color", HUD_DIM)
	_turn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_turn_label.anchor_left = 0.5
	_turn_label.anchor_right = 0.5
	_turn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn_label.position.y = 66
	hud.add_child(_turn_label)

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
	ctx.position = Vector2(16, 14)
	hud.add_child(ctx)

	if oracle != null:
		# The Oracle's mode, named under the opponent label.
		var mode_lbl := Label.new()
		mode_lbl.name = "OracleMode"
		mode_lbl.text = str(Ds4Opponent.MODE_LABELS.get(oracle.mode, oracle.mode))
		mode_lbl.add_theme_font_size_override("font_size", 12)
		mode_lbl.add_theme_color_override("font_color", HUD_GOLD)
		mode_lbl.position = Vector2(16, 34)
		hud.add_child(mode_lbl)

	_oracle_flash = Label.new()
	_oracle_flash.name = "OracleFlash"
	_oracle_flash.visible = false
	_oracle_flash.add_theme_font_size_override("font_size", 17)
	_oracle_flash.add_theme_color_override("font_color", HUD_GOLD)
	_oracle_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_oracle_flash.anchor_left = 0.5
	_oracle_flash.anchor_right = 0.5
	_oracle_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_oracle_flash.position.y = 96
	hud.add_child(_oracle_flash)

	# The take-back control: subtle, parked just above the move list it edits.
	_undo_btn = Button.new()
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

	_banter_caption = Label.new()
	_banter_caption.name = "BanterCaption"
	_banter_caption.visible = false
	_banter_caption.add_theme_font_size_override("font_size", 14)
	_banter_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banter_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_banter_caption.offset_left = 16
	_banter_caption.offset_top = -64
	_banter_caption.offset_right = 420
	_banter_caption.offset_bottom = -10
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


func _update_turn_label(ai_thinking := false) -> void:
	if _turn_label == null:
		return
	_turn_label.modulate.a = 1.0
	if game_over:
		_turn_label.text = "the field falls silent"
	elif ai_thinking or state.turn:
		if oracle != null:
			_turn_label.text = Ds4Opponent.THINKING_TEXT
		else:
			_turn_label.text = "%s is thinking..." % _rival_display
	else:
		_turn_label.text = "%s to move" % _player_display


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
	for royal in [["Qd1", "d1"], ["Ke1", "e1"], ["Qd8", "d8"], ["Ke8", "e8"]]:
		var pos := board.square_to_world(
			sq_of(ChessState.square_index_from_name(str(royal[1]))))
		_debug_label(root, str(royal[0]), Vector3(pos.x, 2.4, pos.z),
			Color(1.0, 0.45, 0.9))


func _debug_label(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 150
	l.modulate = color
	l.outline_size = 30
	l.outline_modulate = Color(0, 0, 0, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)


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
