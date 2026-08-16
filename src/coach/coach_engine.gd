class_name CoachEngine
extends RefCounted
## CoachEngine — Grandmaster Training & Dual-Engine Council Architecture.
## Provides real-time tactical pattern recognition, blunder radar,
## threat evaluation, opening master book coaching, and dual-perspective
## analysis from both Stockfish 18 NNUE (Tactics) and Leela Lc0 AlphaZero (Positional Strategy).

const StockfishBridgeScript := preload("res://src/coach/stockfish_bridge.gd")
const LeelaBridgeScript := preload("res://src/coach/leela_bridge.gd")

const OPENING_BOOK := {
	"e2e4": {
		"name": "King's Pawn Opening (1. e4)",
		"tip": "Controls the critical d5 and e5 central squares and opens diagonals for your Queen and Bishop.",
		"responses": {
			"e7e5": {
				"name": "Open Game (1. e4 e5)",
				"tip": "Symmetric control. Next: Develop Knights towards the center (Nf3) before Bishops!",
				"next": "g1f3"
			},
			"c7c5": {
				"name": "Sicilian Defense (1. e4 c5)",
				"tip": "Sharp asymmetrical fight for the d4 square. Play Nf3 then d4 to open lines.",
				"next": "g1f3"
			},
			"e7e6": {
				"name": "French Defense (1. e4 e6)",
				"tip": "Solid wall. Play d4 to establish a broad pawn center, then defend e4 with Nc3.",
				"next": "d2d4"
			}
		}
	},
	"d2d4": {
		"name": "Queen's Pawn Opening (1. d4)",
		"tip": "Rock-solid opening. Controls e5 and c5 squares. Safe and virtually unassailable!",
		"responses": {
			"d7d5": {
				"name": "London System / Queen's Gambit (1. d4 d5)",
				"tip": "Develop dark-squared Bishop to f4 early, followed by e3 and c3 for an impenetrable pyramid!",
				"next": "c1f4"
			},
			"g8f6": {
				"name": "Indian Defense (1. d4 Nf6)",
				"tip": "Fight for central control. Play c4 to gain space or Nf3 to develop safely.",
				"next": "c2c4"
			}
		}
	}
}


## Analyze board state and return comprehensive coach tactical intelligence
static func analyze_position(state: ChessState, player_color: bool, move_history: Array = []) -> Dictionary:
	var result := {
		"threats": [],           # Hanging or attacked player pieces
		"recommended_move": null,# Primary ChessMove
		"explanation": "",       # Combined summary explanation
		"opening_name": "",      # Current opening
		"opening_tip": "",       # Strategic opening guidance
		"eval_score": 0.0,       # Centipawn evaluation
		"is_consensus": false,   # True when Stockfish + Leela pick the same move
		"engine_name": "Stockfish 18 NNUE + Leela Lc0",
		"threat_level": "SAFE",  # SAFE, CAUTION, DANGER
		"stockfish": {
			"move": null,
			"san": "",
			"eval": 0.0,
			"uci": "",
			"pv": "",
			"plan": ""
		},
		"leela": {
			"move": null,
			"san": "",
			"eval": 0.0,
			"uci": "",
			"pv": "",
			"plan": ""
		}
	}

	if state == null:
		return result

	var opp_color: bool = not player_color

	# 1. Identify Opening & Strategic Advice
	if move_history.size() <= 4:
		var op_info = _get_opening_info(move_history)
		result["opening_name"] = op_info.get("name", "Opening Phase")
		result["opening_tip"] = op_info.get("tip", "Golden Rules: 1. Control the center. 2. Develop Knights before Bishops. 3. Castle early!")

	# 2. Evaluate Hanging Pieces & Blunder Radar
	var legal_moves := state.generate_legal_moves()

	for sq in range(64):
		var p_char = state.pieces[sq]
		if p_char != null and ChessState.piece_color(p_char) == player_color:
			var is_attacked := state.is_square_attacked(sq, opp_color)
			if is_attacked:
				var is_defended := state.is_square_attacked(sq, player_color)
				var val := _piece_value(p_char)
				if not is_defended or val >= 3.0:
					var p_name = _piece_full_name(p_char)
					var sq_name = _sq_to_coord(sq)
					result["threats"].append({
						"square": sq,
						"name": p_name,
						"coord": sq_name,
						"hanging": not is_defended
					})

	if not result["threats"].is_empty():
		result["threat_level"] = "DANGER"

	# 3. Dual-Engine Analysis: Stockfish 18 (Tactics) + Leela Lc0 (Positional)
	var sf_move = null
	var leela_move = null
	var sf_eval := 0.0
	var leela_eval := 0.0
	var sf_pv := ""
	var leela_pv := ""

	if state.has_method("get_fen"):
		var fen_str := state.get_fen()

		# Stockfish 18 NNUE
		var sf_info = StockfishBridgeScript.analyze_fen(fen_str, 120)
		if sf_info.get("available", false) and not sf_info.get("bestmove_uci", "").is_empty():
			var sf_uci: String = sf_info["bestmove_uci"]
			for m in legal_moves:
				if m.to_uci() == sf_uci:
					sf_move = m
					break
			sf_eval = sf_info.get("eval_cp", 0.0)
			var sf_arr: Array = sf_info.get("pv", [])
			sf_pv = " ".join(sf_arr.slice(0, 4))
			if sf_move != null:
				var sf_san := _format_san(state, sf_move)
				result["stockfish"]["move"] = sf_move
				result["stockfish"]["san"] = sf_san
				result["stockfish"]["eval"] = sf_eval
				result["stockfish"]["uci"] = sf_uci
				result["stockfish"]["pv"] = sf_pv
				result["stockfish"]["plan"] = _explain_stockfish_tactical(state, sf_move, player_color)

		# Leela Lc0 AlphaZero
		var leela_info = LeelaBridgeScript.analyze_fen(fen_str, 60)
		if leela_info.get("available", false) and not leela_info.get("bestmove_uci", "").is_empty():
			var leela_uci: String = leela_info["bestmove_uci"]
			for m in legal_moves:
				if m.to_uci() == leela_uci:
					leela_move = m
					break
			leela_eval = leela_info.get("eval_cp", 0.0)
			var leela_arr: Array = leela_info.get("pv", [])
			leela_pv = " ".join(leela_arr.slice(0, 4))
			if leela_move != null:
				var leela_san := _format_san(state, leela_move)
				result["leela"]["move"] = leela_move
				result["leela"]["san"] = leela_san
				result["leela"]["eval"] = leela_eval
				result["leela"]["uci"] = leela_uci
				result["leela"]["pv"] = leela_pv
				result["leela"]["plan"] = _explain_leela_positional(state, leela_move, player_color)

	# Check for Grandmaster Consensus
	if sf_move != null and leela_move != null and sf_move.to_uci() == leela_move.to_uci():
		result["is_consensus"] = true
		result["recommended_move"] = sf_move
		result["eval_score"] = sf_eval
		var sign := "+" if sf_eval >= 0 else ""
		var san := _format_san(state, sf_move)
		result["explanation"] = "🌟 GRANDMASTER CONSENSUS (%s | Eval %s%.2f):\nStockfish & Leela both select %s!\n%s" % [
			san, sign, sf_eval, san, result["stockfish"]["plan"]
		]
	elif sf_move != null and leela_move != null:
		result["recommended_move"] = sf_move
		result["eval_score"] = sf_eval
		var sf_sign := "+" if sf_eval >= 0 else ""
		var leela_sign := "+" if leela_eval >= 0 else ""
		result["explanation"] = "⚔️ Stockfish (%s | %s%.2f): %s\n🧠 Leela (%s | %s%.2f): %s" % [
			result["stockfish"]["san"], sf_sign, sf_eval, result["stockfish"]["plan"],
			result["leela"]["san"], leela_sign, leela_eval, result["leela"]["plan"]
		]
	elif sf_move != null:
		result["recommended_move"] = sf_move
		result["eval_score"] = sf_eval
		var sf_sign := "+" if sf_eval >= 0 else ""
		result["explanation"] = "⚔️ Stockfish (%s | %s%.2f): %s" % [
			result["stockfish"]["san"], sf_sign, sf_eval, result["stockfish"]["plan"]
		]
	elif leela_move != null:
		result["recommended_move"] = leela_move
		result["eval_score"] = leela_eval
		var leela_sign := "+" if leela_eval >= 0 else ""
		result["explanation"] = "🧠 Leela (%s | %s%.2f): %s" % [
			result["leela"]["san"], leela_sign, leela_eval, result["leela"]["plan"]
		]
	else:
		# Fallback to internal minimax
		var fallback_m = _find_best_move(state, legal_moves, player_color)
		result["recommended_move"] = fallback_m
		if fallback_m != null:
			var san := _format_san(state, fallback_m)
			result["explanation"] = "✨ Master Move (%s): %s" % [san, _explain_stockfish_tactical(state, fallback_m, player_color)]

	return result


static func _get_opening_info(move_history: Array) -> Dictionary:
	if move_history.is_empty():
		return {
			"name": "Opening Move",
			"tip": "Recommendation: Open with e4 (King's Pawn) or d4 (Queen's Pawn) to seize the center!"
		}
	var first = str(move_history[0])
	if OPENING_BOOK.has(first):
		var book_entry = OPENING_BOOK[first]
		if move_history.size() > 1:
			var second = str(move_history[1])
			if book_entry.get("responses", {}).has(second):
				return book_entry["responses"][second]
		return book_entry
	return {
		"name": "Standard Development",
		"tip": "Focus on central control, piece harmony, and king safety (early castling)."
	}


static func _find_best_move(state: ChessState, legal_moves: Array, player_color: bool):
	if legal_moves.is_empty():
		return null

	var best_score := -999999.0
	var best_m = null

	for m in legal_moves:
		var score := 0.0

		if m.is_capture():
			var victim = state.pieces[m.captured_square]
			var mover = state.pieces[m.from_square]
			var gain = _piece_value(victim) - (_piece_value(mover) * 0.1)
			score += gain * 100.0

		var to_sq = m.to_square
		var col = to_sq % 8
		var row = to_sq / 8
		if (col >= 3 and col <= 4) and (row >= 3 and row <= 4):
			score += 25.0
		elif (col >= 2 and col <= 5) and (row >= 2 and row <= 5):
			score += 12.0

		if m.is_castling:
			score += 60.0

		var mover_p = state.pieces[m.from_square]
		var p_lower = str(mover_p).to_lower()
		if p_lower == "n" or p_lower == "b":
			score += 18.0

		var target_is_attacked := state.is_square_attacked(m.to_square, not player_color)
		var target_is_defended := state.is_square_attacked(m.to_square, player_color)
		if target_is_attacked and not target_is_defended:
			score -= _piece_value(mover_p) * 90.0

		if score > best_score or best_m == null:
			best_score = score
			best_m = m

	return best_m


static func _format_san(state: ChessState, move: ChessMove) -> String:
	if move == null:
		return ""
	if move.notation_san != null and not str(move.notation_san).is_empty():
		return str(move.notation_san)
	if move.is_castling:
		return "O-O" if move.castle_kingside else "O-O-O"
	var p = state.pieces[move.from_square]
	var p_name = str(p).to_upper()
	var to_coord = _sq_to_coord(move.to_square)
	if p_name == "P":
		if move.is_capture():
			var from_file = char(ord("a") + (move.from_square % 8))
			return "%sx%s" % [from_file, to_coord]
		return to_coord
	var cap = "x" if move.is_capture() else ""
	return "%s%s%s" % [p_name, cap, to_coord]


static func _explain_stockfish_tactical(state: ChessState, move: ChessMove, player_color: bool) -> String:
	var from_p = state.pieces[move.from_square]
	var p_name = _piece_full_name(from_p)
	var from_coord = _sq_to_coord(move.from_square)
	var to_coord = _sq_to_coord(move.to_square)
	var san := _format_san(state, move)

	if move.is_castling:
		return "Castle %s to safety! Connects Rooks and shields the King behind pawns." % san

	if move.is_capture():
		var victim_p = state.pieces[move.captured_square]
		return "%s takes %s on %s! Wins material and gains tactical tempo." % [p_name, _piece_full_name(victim_p), to_coord]

	var col = move.to_square % 8
	var row = move.to_square / 8
	var is_center = (col >= 3 and col <= 4) and (row >= 3 and row <= 4)
	var p_lower = str(from_p).to_lower()

	if is_center:
		return "Move %s to %s to control vital center squares (d4/d5/e4/e5)." % [p_name, to_coord]
	elif p_lower == "n" or p_lower == "b":
		return "Develop %s to %s — activates your piece and prepares rapid castling." % [p_name, to_coord]
	elif p_lower == "p":
		return "Advance Pawn to %s — claims territorial space and opens lines." % to_coord

	return "Move %s to %s — improves tactical flexibility and mobility." % [p_name, to_coord]


static func _explain_leela_positional(state: ChessState, move: ChessMove, player_color: bool) -> String:
	var from_p = state.pieces[move.from_square]
	var p_name = _piece_full_name(from_p)
	var from_coord = _sq_to_coord(move.from_square)
	var to_coord = _sq_to_coord(move.to_square)
	var san := _format_san(state, move)

	if move.is_castling:
		return "Castle %s — unifies your army and brings the rook to active play." % san

	if move.is_capture():
		var victim_p = state.pieces[move.captured_square]
		return "%s takes %s on %s — simplifies into a dominant positional squeeze." % [p_name, _piece_full_name(victim_p), to_coord]

	var p_lower = str(from_p).to_lower()
	if p_lower == "p":
		if to_coord in ["e4", "d4", "e5", "d5"]:
			return "Advance %s to %s — establishes an unbreakable central anchor." % [p_name, to_coord]
		elif to_coord in ["c4", "f4", "c5", "f5"]:
			return "Advance %s to %s — challenges the enemy pawn chain and creates active open files." % [p_name, to_coord]
		elif to_coord in ["h4", "h5", "a4", "a5"]:
			return "Advance %s to %s (AlphaZero Flank Storm) — gains territory and pressures enemy king shelter." % [p_name, to_coord]
		return "Advance %s to %s — reinforces pawn harmony and unlocks bishop diagonals." % [p_name, to_coord]
	elif p_lower == "n":
		return "Manoeuvre %s to %s — plants an outpost knight dominating critical crossing squares." % [p_name, to_coord]
	elif p_lower == "b":
		return "Develop %s to %s — controls the long diagonal with enduring board harmony." % [p_name, to_coord]
	elif p_lower == "r":
		return "Activate %s to %s — seizes the vertical open file for back-rank pressure." % [p_name, to_coord]
	elif p_lower == "q":
		return "Centralize %s to %s — maximises piece coordination across both wings." % [p_name, to_coord]

	return "Move %s to %s — maximises overall army coordination and harmony." % [p_name, to_coord]


static func _piece_value(p) -> float:
	if p == null:
		return 0.0
	match str(p).to_lower():
		"p": return 1.0
		"n": return 3.05
		"b": return 3.3
		"r": return 5.0
		"q": return 9.5
		"k": return 100.0
		_: return 0.0


static func _piece_full_name(p) -> String:
	if p == null:
		return "Piece"
	match str(p).to_lower():
		"p": return "Pawn"
		"n": return "Knight"
		"b": return "Bishop"
		"r": return "Rook"
		"q": return "Queen"
		"k": return "King"
		_: return "Piece"


static func _sq_to_coord(sq: int) -> String:
	var file_ch = char(ord("a") + (sq % 8))
	var rank_num = (sq / 8) + 1
	return "%s%d" % [file_ch, rank_num]
