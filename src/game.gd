extends Node3D
## Great Houses — game root. Player commands House Frost (white) against a
## ChessAI-driven House Ember (black). Full rules via src/chess (castling,
## en passant, promotion, draw rules), capture duels choreographed by
## PieceView, SAN move list HUD, game-over banner, R to restart.
##
## Command-line hooks (after "--"):
##   --difficulty=easy|medium|hard   AI strength (default medium)
##   --e2e-fen=<fen>                 start from a custom position
##   --smoke                         windowed: wait 3 s, screenshot, quit
##   --dump-tree                     headless-safe: print scene tree, quit

const PieceScene: PackedScene = preload("res://scenes/piece_view.tscn")

const CHAR_TO_TYPE := {
	"p": PieceView.Type.PAWN, "r": PieceView.Type.ROOK, "n": PieceView.Type.KNIGHT,
	"b": PieceView.Type.BISHOP, "q": PieceView.Type.QUEEN, "k": PieceView.Type.KING,
}

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

var views: Dictionary = {}          # Vector2i (board sq) -> PieceView
var selected: Variant = null        # Vector2i, or null
var busy := false                   # move/duel animation or AI turn in flight
var game_over := false
var death_log: Array[String] = []   # death anims played (e2e evidence)

var _turn_moves: Array = []         # SAN-notated legal moves for side to move
var _san_log: Array[String] = []

var _turn_label: Label
var _move_list: RichTextLabel
var _banner: PanelContainer
var _banner_label: Label


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
	state = ChessState.new()
	if not fen.is_empty() and not state.set_fen(fen):
		push_error("invalid --e2e-fen '%s' — using the standard lineup" % fen)
	_build_hud()
	_spawn_from_state()
	_refresh_turn_moves()
	_update_turn_label()
	board.square_clicked.connect(_on_square_clicked)
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke"):
		_smoke()
	elif args.has("--dump-tree"):
		_dump_tree()
	if state.turn and not game_over:
		_kick_ai_opening()


# -- square mapping (engine 0..63, a8=0 .. h1=63  <->  board Vector2i) ------
# Board sq.y=0 is House Frost's home rank (world -Z); the camera starts
# behind Frost, so files run a..h from screen-left: sq.x = 7 - file.


static func sq_of(idx: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(7 - (idx % 8), 7 - (idx / 8))


static func idx_of(sq: Vector2i) -> int:
	return (7 - sq.y) * 8 + (7 - sq.x)


# -- setup -----------------------------------------------------------------


func _spawn_from_state() -> void:
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
	p.setup(piece_type, piece_side)
	p.position = board.square_to_world(sq)
	p.died.connect(_on_piece_died.bind(p))
	views[sq] = p
	return p


func _on_piece_died(p: PieceView) -> void:
	death_log.append(p.death_anim)


func _kick_ai_opening() -> void:
	## FEN gave House Ember the move — let the AI open.
	busy = true
	await _ai_ply()
	busy = false
	_update_turn_label()


# -- interaction -----------------------------------------------------------


func _on_square_clicked(sq: Vector2i) -> void:
	if busy or game_over or state == null or state.turn:
		return  # not interactive during animations, after the end, or on Ember's turn
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
	selected = sq
	board.set_selected(sq)
	var targets: Array[Vector2i] = []
	var from_idx := idx_of(sq)
	for m in _turn_moves:
		if m.from_square == from_idx and not targets.has(sq_of(m.to_square)):
			targets.append(sq_of(m.to_square))
	board.show_legal_moves(targets)


func _clear_selection() -> void:
	selected = null
	board.clear_highlights()


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
	## One full round: the player's ply, then (if the game goes on) Ember's.
	busy = true
	await _execute_ply(move)
	if not game_over and state.turn:
		await _ai_ply()
	busy = false
	_update_turn_label()


func _ai_ply() -> void:
	_update_turn_label(true)
	var move = await ai.choose_move(state, ai_difficulty)  # WorkerThreadPool search
	if move == null:
		_finish_game()
		return
	await _execute_ply(move)


func _execute_ply(move) -> void:
	## Engine first (authoritative), then the choreography catches up.
	var mover_is_ember: bool = state.turn
	_record_san(move)
	state.apply_move(move)
	_refresh_turn_moves()
	await _animate_move(move, mover_is_ember)
	if state.get_result() != ChessState.RESULT.ONGOING:
		_finish_game()


func _record_san(move) -> void:
	var san: String = str(move.notation_san) if move.notation_san != null else move.to_uci()
	_san_log.append(san)
	var lines: Array[String] = []
	for i in range(0, _san_log.size(), 2):
		var row := "%d. %s" % [i / 2 + 1, _san_log[i]]
		if i + 1 < _san_log.size():
			row += "  %s" % _san_log[i + 1]
		lines.append(row)
	if _move_list != null:
		_move_list.text = "\n".join(lines)


func _walk_time(from_pos: Vector3, to_pos: Vector3) -> float:
	return clampf(from_pos.distance_to(to_pos) * 0.3, 0.3, 1.1)


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
			await mover.play_capture(victim)
	await mover.move_to(target, _walk_time(mover.position, target))
	views[to_sq] = mover
	if move.promotion != null:
		mover.queue_free()
		var promo_side := PieceView.House.EMBER if mover_is_ember else PieceView.House.FROST
		var promoted := _spawn(CHAR_TO_TYPE[str(move.promotion).to_lower()], promo_side, to_sq)
		await promoted.spawn_flourish()


func _refresh_turn_moves() -> void:
	_turn_moves = state.legal_moves(true)


func _finish_game() -> void:
	game_over = true
	_clear_selection()
	var result: int = state.get_result()
	var text: String
	if result == ChessState.RESULT.CHECKMATE:
		var frost_wins: bool = state.turn  # the side to move is the one mated
		text = "Checkmate — House %s triumphs" % ("Frost" if frost_wins else "Ember")
	else:
		text = RESULT_TEXT.get(result, "The war is over")
	_banner_label.text = text + "\nPress R to restart"
	_banner.visible = true
	_update_turn_label()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_R:
		get_tree().reload_current_scene()


# -- HUD -------------------------------------------------------------------

const HUD_TEXT := Color(0.85, 0.8, 0.7)
const HUD_DIM := Color(0.62, 0.58, 0.5)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var title := Label.new()
	title.name = "Title"
	title.text = "HOUSE FROST  vs  HOUSE EMBER"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HUD_TEXT)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 14
	hud.add_child(title)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.add_theme_font_size_override("font_size", 15)
	_turn_label.add_theme_color_override("font_color", HUD_DIM)
	_turn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_turn_label.anchor_left = 0.5
	_turn_label.anchor_right = 0.5
	_turn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn_label.position.y = 44
	hud.add_child(_turn_label)

	_move_list = RichTextLabel.new()
	_move_list.name = "MoveList"
	_move_list.scroll_following = true
	_move_list.add_theme_font_size_override("normal_font_size", 14)
	_move_list.add_theme_color_override("default_color", HUD_DIM)
	_move_list.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_move_list.offset_left = -150
	_move_list.offset_top = 80
	_move_list.offset_right = -16
	_move_list.offset_bottom = -20
	hud.add_child(_move_list)

	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.045, 0.92)
	style.border_color = Color(0.55, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_content_margin_all(26)
	_banner.add_theme_stylebox_override("panel", style)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 26)
	_banner_label.add_theme_color_override("font_color", HUD_TEXT)
	_banner.add_child(_banner_label)
	hud.add_child(_banner)


func _update_turn_label(ai_thinking := false) -> void:
	if _turn_label == null:
		return
	if game_over:
		_turn_label.text = "the field falls silent"
	elif ai_thinking or state.turn:
		_turn_label.text = "House Ember is thinking..."
	else:
		_turn_label.text = "House Frost to move"


# -- e2e hooks -------------------------------------------------------------


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
