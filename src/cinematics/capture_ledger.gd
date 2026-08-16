class_name CaptureLedger
extends RefCounted
## Lifetime capture and piece history ledger for Great Hauses.
## Pure RefCounted — no Node, no autoload, runs headless.
## Tracks piece age, kills counter, victims list, nemesis tracking, and streaks.

var plies: int = 0
var captures: Array = []
# square index -> record
# record: {uid: int, char: String, born_ply: int, moves: int, kills: int, victims: Array}
var _at: Dictionary = {}
var _undo_stack: Array = []
var _next_uid: int = 1


func _init() -> void:
	reset()


func reset() -> void:
	plies = 0
	captures.clear()
	_at.clear()
	_undo_stack.clear()
	_next_uid = 1


func reset_from(state: ChessState) -> void:
	reset()
	if state == null:
		return
	for idx in 64:
		var c = state.pieces[idx]
		if c != null:
			_at[idx] = {
				"uid": _next_uid,
				"char": str(c),
				"born_ply": 0,
				"moves": 0,
				"kills": 0,
				"victims": []
			}
			_next_uid += 1


func note_move(move, is_white_turn: bool) -> Dictionary:
	plies += 1
	var snapshot: Dictionary = {
		"plies": plies - 1,
		"at": _at.duplicate(true),
		"captures": captures.duplicate(true),
		"next_uid": _next_uid
	}
	_undo_stack.append(snapshot)

	var from_sq: int = move.from_square
	var to_sq: int = move.to_square
	var cap_sq: int = move.captured_square if move.is_capture() else -1

	var mover_rec: Dictionary = _at.get(from_sq, {
		"uid": _next_uid,
		"char": str(move.piece),
		"born_ply": plies - 1,
		"moves": 0,
		"kills": 0,
		"victims": []
	})
	if not _at.has(from_sq):
		_next_uid += 1

	mover_rec["moves"] += 1
	if move.promotion != null and not str(move.promotion).is_empty():
		# Preserve born_ply and kills across promotion!
		mover_rec["char"] = str(move.promotion) if is_white_turn else str(move.promotion).to_lower()

	_at.erase(from_sq)

	var victim_rec: Dictionary = {}
	if move.is_capture():
		var target_cap_sq: int = cap_sq if cap_sq >= 0 else to_sq
		if _at.has(target_cap_sq):
			victim_rec = _at[target_cap_sq]
			_at.erase(target_cap_sq)
		else:
			victim_rec = {
				"uid": _next_uid,
				"char": str(move.captured_piece) if move.captured_piece != null else ("p" if is_white_turn else "P"),
				"born_ply": 0,
				"moves": 0,
				"kills": 0,
				"victims": []
			}
			_next_uid += 1

		mover_rec["kills"] += 1
		mover_rec["victims"].append({
			"char": victim_rec.get("char", ""),
			"ply": plies,
			"uid": victim_rec.get("uid", 0)
		})
		captures.append({
			"ply": plies,
			"attacker": mover_rec.duplicate(true),
			"victim": victim_rec.duplicate(true),
			"white_attacker": is_white_turn
		})

	# Handle castling moving the rook
	if move.is_castling:
		var rook_from := -1
		var rook_to := -1
		if to_sq == ChessState.SQUARES.G1:
			rook_from = ChessState.SQUARES.H1
			rook_to = ChessState.SQUARES.F1
		elif to_sq == ChessState.SQUARES.C1:
			rook_from = ChessState.SQUARES.A1
			rook_to = ChessState.SQUARES.D1
		elif to_sq == ChessState.SQUARES.G8:
			rook_from = ChessState.SQUARES.H8
			rook_to = ChessState.SQUARES.F8
		elif to_sq == ChessState.SQUARES.C8:
			rook_from = ChessState.SQUARES.A8
			rook_to = ChessState.SQUARES.D8

		if rook_from >= 0 and _at.has(rook_from):
			var rook_rec = _at[rook_from]
			rook_rec["moves"] += 1
			_at.erase(rook_from)
			_at[rook_to] = rook_rec

	_at[to_sq] = mover_rec
	return victim_rec


func rewind_to(target_ply: int) -> void:
	while not _undo_stack.is_empty() and plies > target_ply:
		var snap: Dictionary = _undo_stack.pop_back()
		plies = snap["plies"]
		_at = snap["at"]
		captures = snap["captures"]
		_next_uid = snap["next_uid"]


func get_streak(is_white: bool) -> int:
	var s := 0
	for i in range(captures.size() - 1, -1, -1):
		if captures[i].get("white_attacker", false) == is_white:
			s += 1
		else:
			break
	return s
