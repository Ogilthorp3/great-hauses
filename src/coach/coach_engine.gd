class_name CoachEngine
extends RefCounted
## CoachEngine — The Grandmaster Rapid Improvement Engine.
## Provides real-time tactical pattern recognition, blunder radar,
## threat evaluation, opening master book coaching, and strategic move explanations.

const OPENING_BOOK := {
	"e2e4": {
		"name": "King's Pawn Opening",
		"tip": "Controls the critical d5 and e5 central squares and opens diagonals for your Queen and Bishop.",
		"responses": {
			"e7e5": {
				"name": "Open Game",
				"tip": "Symmetric control. Next: Develop Knights towards the center (Nf3) before Bishops!",
				"next": "g1f3"
			},
			"c7c5": {
				"name": "Sicilian Defense",
				"tip": "Sharp asymmetrical fight for the d4 square. Play Nf3 then d4 to open lines.",
				"next": "g1f3"
			},
			"e7e6": {
				"name": "French Defense",
				"tip": "Solid wall. Play d4 to establish a broad pawn center, then defend e4 with Nc3.",
				"next": "d2d4"
			}
		}
	},
	"d2d4": {
		"name": "Queen's Pawn Opening (London / Queen's Gambit)",
		"tip": "Rock-solid opening. Controls e5 and c5 squares. Safe and virtually unassailable!",
		"responses": {
			"d7d5": {
				"name": "London System / Queen's Gambit",
				"tip": "Develop dark-squared Bishop to f4 early, followed by e3 and c3 for an impenetrable pyramid!",
				"next": "c1f4"
			},
			"g8f6": {
				"name": "Indian Defense",
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
		"opportunities": [],     # Hanging or vulnerable enemy pieces
		"recommended_move": null,# ChessMove
		"explanation": "",       # Strategic/tactical explanation
		"opening_name": "",      # Current opening
		"opening_tip": "",       # Strategic opening guidance
		"eval_score": 0.0,       # Centipawn evaluation
		"threat_level": "SAFE"   # SAFE, CAUTION, DANGER
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

	# Find player pieces under attack
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

	# 3. Find Best Recommended Tactical Move
	var best_move = _find_best_move(state, legal_moves, player_color)
	if best_move != null:
		result["recommended_move"] = best_move
		result["explanation"] = _explain_move(state, best_move, player_color)

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

		# Captures
		if m.is_capture():
			var victim = state.pieces[m.captured_square]
			var mover = state.pieces[m.from_square]
			var gain = _piece_value(victim) - (_piece_value(mover) * 0.1)
			score += gain * 100.0

		# Central control bonus
		var to_sq = m.to_square
		var col = to_sq % 8
		var row = to_sq / 8
		if (col >= 3 and col <= 4) and (row >= 3 and row <= 4):
			score += 25.0
		elif (col >= 2 and col <= 5) and (row >= 2 and row <= 5):
			score += 12.0

		# Castling bonus
		if m.is_castling:
			score += 60.0

		# Development bonus in opening
		var mover_p = state.pieces[m.from_square]
		var p_lower = str(mover_p).to_lower()
		if p_lower == "n" or p_lower == "b":
			score += 18.0

		# Check penalty for hanging the piece
		var target_is_attacked := state.is_square_attacked(m.to_square, not player_color)
		var target_is_defended := state.is_square_attacked(m.to_square, player_color)
		if target_is_attacked and not target_is_defended:
			score -= _piece_value(mover_p) * 90.0

		if score > best_score or best_m == null:
			best_score = score
			best_m = m

	return best_m


static func _explain_move(state: ChessState, move, player_color: bool) -> String:
	var from_p = state.pieces[move.from_square]
	var p_name = _piece_full_name(from_p)
	var from_coord = _sq_to_coord(move.from_square)
	var to_coord = _sq_to_coord(move.to_square)

	if move.is_castling:
		return "👑 Castle King to safety! Connects your Rooks and tucks the sovereign behind a wall of pawns."

	if move.is_capture():
		var victim_p = state.pieces[move.captured_square]
		var victim_name = _piece_full_name(victim_p)
		return "⚔️ %s takes %s on %s! Wins material and weakens the opponent's defensive structure." % [p_name, victim_name, to_coord]

	var col = move.to_square % 8
	var row = move.to_square / 8
	var is_center = (col >= 3 and col <= 4) and (row >= 3 and row <= 4)

	var p_lower = str(from_p).to_lower()
	if is_center:
		return "🎯 Move %s from %s to %s to control the vital center squares (d4/d5/e4/e5)." % [p_name, from_coord, to_coord]
	elif p_lower == "n" or p_lower == "b":
		return "⚡ Develop %s to %s — activates your piece and prepares rapid kingside castling." % [p_name, to_coord]
	elif p_lower == "p":
		return "🛡️ Advance Pawn to %s — stakes territorial control and opens diagonals." % to_coord

	return "✨ Move %s to %s — improves piece positioning and tactical flexibility." % [p_name, to_coord]


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
