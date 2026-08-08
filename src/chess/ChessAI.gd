extends RefCounted
class_name ChessAI

# Ported from "Stop Waiting For Godot" chess (https://github.com/thearst3rd/stopwaitingforgodot)
# Copyright (c) 2021 Terry Hearst, MIT License — see LICENSE-stopwaitingforgodot in this directory.
# Faithful port of the negamax + quiescence engine (ChessEngine.gd).
# Great Houses additions: difficulty tiers, and an async choose_move() that runs the
# search on WorkerThreadPool (replacing the source game's manual Thread + call_deferred
# pattern) so callers can simply `await` the move. No UI dependencies.

const ChessStateScript := preload("res://src/chess/ChessState.gd")
const MoveScript := preload("res://src/chess/ChessMove.gd")

enum Difficulty {
	EASY,
	MEDIUM,
	HARD,
}

const MATE_SCORE := 1_000_000_000
const MATE_THRESHOLD := 999_000_000

const INF_SCORE := 0xFFFF_FFFF_FFFF

var search_depth := 3
var quiescence_depth := 5

# Simplified Evaluation Function piece tables
var w_pawn_table = [
	 0,  0,  0,  0,  0,  0,  0,  0,
	50, 50, 50, 50, 50, 50, 50, 50,
	10, 10, 20, 30, 30, 20, 10, 10,
	 5,  5, 10, 25, 25, 10,  5,  5,
	 0,  0,  0, 20, 20,  0,  0,  0,
	 5, -5,-10,  0,  0,-10, -5,  5,
	 5, 10, 10,-20,-20, 10, 10,  5,
	 0,  0,  0,  0,  0,  0,  0,  0,
]
var w_knight_table = [
	-50,-40,-30,-30,-30,-30,-40,-50,
	-40,-20,  0,  0,  0,  0,-20,-40,
	-30,  0, 10, 15, 15, 10,  0,-30,
	-30,  5, 15, 20, 20, 15,  5,-30,
	-30,  0, 15, 20, 20, 15,  0,-30,
	-30,  5, 10, 15, 15, 10,  5,-30,
	-40,-20,  0,  5,  5,  0,-20,-40,
	-50,-40,-30,-30,-30,-30,-40,-50,
]
var w_bishop_table = [
	-20,-10,-10,-10,-10,-10,-10,-20,
	-10,  0,  0,  0,  0,  0,  0,-10,
	-10,  0,  5, 10, 10,  5,  0,-10,
	-10,  5,  5, 10, 10,  5,  5,-10,
	-10,  0, 10, 10, 10, 10,  0,-10,
	-10, 10, 10, 10, 10, 10, 10,-10,
	-10,  5,  0,  0,  0,  0,  5,-10,
	-20,-10,-10,-10,-10,-10,-10,-20,
]
var w_rook_table = [
	 0,  0,  0,  0,  0,  0,  0,  0,
	 5, 10, 10, 10, 10, 10, 10,  5,
	-5,  0,  0,  0,  0,  0,  0, -5,
	-5,  0,  0,  0,  0,  0,  0, -5,
	-5,  0,  0,  0,  0,  0,  0, -5,
	-5,  0,  0,  0,  0,  0,  0, -5,
	-5,  0,  0,  0,  0,  0,  0, -5,
	 0,  0,  0,  5,  5,  0,  0,  0,
]
var w_queen_table = [
	-20,-10,-10, -5, -5,-10,-10,-20,
	-10,  0,  0,  0,  0,  0,  0,-10,
	-10,  0,  5,  5,  5,  5,  0,-10,
	 -5,  0,  5,  5,  5,  5,  0, -5,
	  0,  0,  5,  5,  5,  5,  0, -5,
	-10,  5,  5,  5,  5,  5,  0,-10,
	-10,  0,  5,  0,  0,  0,  0,-10,
	-20,-10,-10, -5, -5,-10,-10,-20,
]
var w_king_middle_table = [
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-20,-30,-30,-40,-40,-30,-30,-20,
	-10,-20,-20,-20,-20,-20,-20,-10,
	 20, 20,  0,  0,  0,  0, 20, 20,
	 20, 30, 10,  0,  0, 10, 30, 20,
]
var w_king_end_table = [
	-50,-40,-30,-20,-20,-30,-40,-50,
	-30,-20,-10,  0,  0,-10,-20,-30,
	-30,-10, 20, 30, 30, 20,-10,-30,
	-30,-10, 30, 40, 40, 30,-10,-30,
	-30,-10, 30, 40, 40, 30,-10,-30,
	-30,-10, 20, 30, 30, 20,-10,-30,
	-30,-30,  0,  0,  0,  0,-30,-30,
	-50,-30,-30,-30,-30,-30,-30,-50,
]
var b_pawn_table = flip_table(w_pawn_table)
var b_knight_table = flip_table(w_knight_table)
var b_bishop_table = flip_table(w_bishop_table)
var b_rook_table = flip_table(w_rook_table)
var b_queen_table = flip_table(w_queen_table)
var b_king_middle_table = flip_table(w_king_middle_table)
var b_king_end_table = flip_table(w_king_end_table)

# Search debug info

var num_positions_searched := 0
var num_positions_searched_q := 0
var num_positions_evaluated := 0
var search_time := 0	# usec
var last_score := 0


static func flip_table(table: Array) -> Array:
	var new_table := []
	new_table.resize(64)
	for i in range(64):
		var file := ChessStateScript.square_get_file(i)
		var rank := 9 - ChessStateScript.square_get_rank(i)
		var new_i := ChessStateScript.square_index(file, rank)
		new_table[new_i] = table[i]
	return new_table


## PUBLIC API ##

func set_difficulty(difficulty: int) -> void:
	match difficulty:
		Difficulty.EASY:
			search_depth = 1
			quiescence_depth = 2
		Difficulty.MEDIUM:
			search_depth = 2
			quiescence_depth = 4
		_:
			search_depth = 3
			quiescence_depth = 5


# Async: runs the search on WorkerThreadPool and returns the chosen move (awaitable).
# The search runs on a duplicate of `state`, so the caller's state is never touched
# by the worker thread. Returns null if the game is already over.
# Usage: var move = await ai.choose_move(state, ChessAI.Difficulty.HARD)
func choose_move(state: ChessStateScript, difficulty := Difficulty.MEDIUM) -> MoveScript:
	set_difficulty(difficulty)
	if state.generate_legal_moves(false).is_empty():
		return null
	var search_state: ChessStateScript = state.duplicate()
	var out := []
	var task_id := WorkerThreadPool.add_task(func() -> void: out.push_back(get_move(search_state)), true, "ChessAI search")
	var loop := Engine.get_main_loop()
	while not WorkerThreadPool.is_task_completed(task_id):
		if loop is SceneTree:
			await (loop as SceneTree).process_frame
		else:
			OS.delay_msec(5)
	WorkerThreadPool.wait_for_task_completion(task_id)
	var r: Array = out[0]
	last_score = r[0]
	if r[1] == null:
		return null
	return _match_on_state(state, r[1])


# Synchronous variant: searches on the calling thread (blocks). `state` is searched
# in place (play/undo leaves it unchanged on return, as in the source engine).
func choose_move_sync(state: ChessStateScript, difficulty := Difficulty.MEDIUM) -> MoveScript:
	set_difficulty(difficulty)
	if state.generate_legal_moves(false).is_empty():
		return null
	var r := get_move(state)
	last_score = r[0]
	return r[1]


# Returns a SAN-notated move belonging to `state`'s own legal move list that matches `move`
func _match_on_state(state: ChessStateScript, move: MoveScript) -> MoveScript:
	for m in state.generate_legal_moves():
		if m.from_square == move.from_square and m.to_square == move.to_square and m.promotion == move.promotion:
			return m
	return null


func get_move(chess: ChessStateScript) -> Array:
	num_positions_searched = 0
	num_positions_searched_q = 0
	num_positions_evaluated = 0
	var before_time := Time.get_ticks_usec()
	var r := negamax(chess, search_depth, -INF_SCORE, INF_SCORE)
	search_time = Time.get_ticks_usec() - before_time
	# We generate the moves without notating them, but we need the final move notated
	var moves := chess.generate_legal_moves()
	for m in moves:
		if m.from_square == r[1].from_square and m.to_square == r[1].to_square and m.promotion == r[1].promotion:
			r[1] = m
			break
	assert(r[1].notation_san != null)
	return r


## EVALUATION ##

static func get_piece_value(piece) -> int:
	match piece:
		null, "K", "k":
			pass
		"Q", "q":
			return 900
		"R", "r":
			return 500
		"B", "b":
			return 330
		"N", "n":
			return 320
		"P", "p":
			return 100
	return 0


func get_piece_placement(piece, square: int) -> int:
	match piece:
		null: pass
		"K": return w_king_middle_table[square]
		"k": return b_king_middle_table[square]
		"Q": return w_queen_table[square]
		"q": return b_queen_table[square]
		"R": return w_rook_table[square]
		"r": return b_rook_table[square]
		"B": return w_bishop_table[square]
		"b": return b_bishop_table[square]
		"N": return w_knight_table[square]
		"n": return b_knight_table[square]
		"P": return w_pawn_table[square]
		"p": return b_pawn_table[square]
	return 0


# Evaluates a position from the POV of whose turn it is
# Largely based on https://www.chessprogramming.org/Simplified_Evaluation_Function
func evaluate(chess: ChessStateScript) -> int:
	num_positions_evaluated += 1
	var eval := 0
	for i in range(64):
		var piece = chess.pieces[i]
		if piece == null:
			continue
		var mult := 1 if (ChessStateScript.piece_color(piece) == chess.turn) else -1
		eval += mult * (get_piece_value(piece) + get_piece_placement(piece, i))
	return eval


## GAME TREE SEARCH ##

func negamax(chess: ChessStateScript, depth: int, alpha: int, beta: int) -> Array:
	var moves: Array
	if depth <= 0:
		if chess.in_check():
			moves = chess.generate_legal_moves(false)
			if moves.size() == 0:
				return [-MATE_SCORE, null]
		return [negamax_quiescence(chess, quiescence_depth, alpha, beta), null]
	moves = order_moves(chess, chess.generate_legal_moves(false))
	if moves.size() == 0:
		return [-MATE_SCORE if chess.in_check() else 0, null]
	var value := -INF_SCORE
	var best_move = null
	for move in moves:
		num_positions_searched += 1
		chess.play_move(move)
		var curr_score: int
		if depth == search_depth and chess.is_threefold_repetition():
			curr_score = 0
		else:
			curr_score = -negamax(chess, depth - 1, -beta, -alpha)[0]
		if curr_score > MATE_THRESHOLD:
			curr_score -= 1
		elif curr_score < -MATE_THRESHOLD:
			curr_score += 1
		chess.undo()
		if curr_score > value:
			value = curr_score
			best_move = move
		alpha = alpha if alpha > value else value
		if curr_score >= beta:
			break
	return [value, best_move]


func negamax_quiescence(chess: ChessStateScript, depth: int, alpha: int, beta: int) -> int:
	var value := evaluate(chess)
	if value >= beta:
		return beta
	if depth == 0:
		return value
	alpha = alpha if alpha > value else value
	var moves := order_moves(chess, chess.generate_legal_moves(false, true))
	for move in moves:
		num_positions_searched_q += 1
		chess.play_move(move)
		value = -negamax_quiescence(chess, depth - 1, -beta, -alpha)
		chess.undo()
		if value >= beta:
			return beta
		if value > alpha:
			alpha = value
	return value


## MOVE ORDERING ##

func order_moves(chess: ChessStateScript, moves: Array) -> Array:
	var moves_and_bonuses := []
	for move in moves:
		var bonus := 0
		var moving_piece = chess.pieces[move.from_square]

		# Prefer capturing higher value pieces with lower value pieces
		if move.captured_piece:
			bonus += get_piece_value(move.captured_piece) - get_piece_value(moving_piece)

		# Prefer not moving pieces onto squares attacked by opponent pawns
		if not (moving_piece in ["P", "p", "K", "k"]):
			if move.to_square > ChessStateScript.SQUARES.H8 and move.to_square < ChessStateScript.SQUARES.A1:
				var delta := 8 if chess.turn else -8
				var file := ChessStateScript.square_get_file(move.to_square)
				var target := "P" if chess.turn else "p"
				if file > 1:
					if chess.pieces[move.to_square + delta - 1] == target:
						bonus -= 1000
				if file < 8:
					if chess.pieces[move.to_square + delta + 1] == target:
						bonus -= 1000

		# Prefer promotions
		if move.promotion:
			bonus += get_piece_value(move.promotion)

		moves_and_bonuses.push_back([move, bonus])

	# Sort array
	moves_and_bonuses.sort_custom(sort_comparison)

	var sorted_moves := []
	for move_and_bonus in moves_and_bonuses:
		sorted_moves.push_back(move_and_bonus[0])

	return sorted_moves


func sort_comparison(move_a: Array, move_b: Array) -> bool:
	return move_a[1] > move_b[1]
