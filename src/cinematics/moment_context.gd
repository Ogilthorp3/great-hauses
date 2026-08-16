class_name MomentContext
extends RefCounted
## Pure context analyzer for Great Hauses capture moments.
## Gathers situational facts into a standardized Dictionary for scoring.

const VALUE: Dictionary = {
	"p": 100,
	"n": 320,
	"b": 330,
	"r": 500,
	"q": 900,
	"k": 0
}


static func situation(state: ChessState, move, turn_moves: Array, ledger: RefCounted, victim_rec: Dictionary) -> Dictionary:
	var ply := state.move_stack.size()
	var a_char := str(move.piece)
	var v_char := str(move.captured_piece) if move.captured_piece != null else str(victim_rec.get("char", "p"))
	var a_lower := a_char.to_lower()
	var v_lower := v_char.to_lower()
	var a_white := not ChessState.piece_color(a_char)

	var av: int = VALUE.get(a_lower, 0)
	var vv: int = VALUE.get(v_lower, 0)

	# 1. Material and phase O(64) sweep
	var mat_w := 0
	var mat_b := 0
	var type_left := {}

	for idx in 64:
		var p = state.pieces[idx]
		if p == null:
			continue
		var ps := str(p)
		var pl := ps.to_lower()
		if pl == "k":
			continue
		var val: int = VALUE.get(pl, 0)
		if ChessState.piece_color(ps):
			mat_b += val
		else:
			mat_w += val
		type_left[ps] = type_left.get(ps, 0) + 1

	var phase := clampf(float(mat_w + mat_b) / 8000.0, 0.0, 1.0)
	var mat_diff := (mat_w - mat_b) if a_white else (mat_b - mat_w)
	var mat_diff_before := mat_diff + vv
	var lead_flip := (mat_diff_before <= 0 and mat_diff > 0)
	var victim_type_left: int = type_left.get(v_char, 0)

	# 2. Threat signals (Pin-aware derived from legal replies)
	var gives_check := state.in_check()
	var replies := turn_moves.size()
	var recapture_min := -1

	for rm in turn_moves:
		if rm.to_square == move.to_square:
			var r_val: int = VALUE.get(str(rm.piece).to_lower(), 100)
			if recapture_min < 0 or r_val < recapture_min:
				recapture_min = r_val

	var recapturable := (recapture_min >= 0)
	var exch := vv - (av if recapturable else 0)

	# Distance
	var f1: int = ChessState.square_get_file(move.from_square)
	var r1: int = ChessState.square_get_rank(move.from_square)
	var f2: int = ChessState.square_get_file(move.to_square)
	var r2: int = ChessState.square_get_rank(move.to_square)
	var dist: int = maxi(absi(f1 - f2), absi(r1 - r2))

	# 3. Special move flags
	var promotes: bool = (move.promotion != null and not str(move.promotion).is_empty())
	var underpromotion: bool = (promotes and str(move.promotion).to_lower() != "q")
	var is_cap: bool = move.is_capture()
	var cap_sq: int = int(move.captured_square) if move.get("captured_square") != null else -1
	var to_sq: int = int(move.to_square)
	var is_ep: bool = (is_cap and cap_sq >= 0 and cap_sq != to_sq) or (is_cap and move.captured_piece == null)
	var a_is_king: bool = (a_lower == "k")
	var a_is_pawn: bool = (a_lower == "p")
	var v_is_queen: bool = (v_lower == "q")

	# 4. Ledger history
	var v_born_ply: int = victim_rec.get("born_ply", 0)
	var v_age := ply - v_born_ply
	var v_moves: int = victim_rec.get("moves", 0)
	var v_kills: int = victim_rec.get("kills", 0)
	var v_victims: Array = victim_rec.get("victims", [])

	var revenge_char := ""
	var revenge_gap := 999
	for vic in v_victims:
		var vc: String = str(vic.get("char", ""))
		if not vc.is_empty():
			var vcv: int = VALUE.get(vc.to_lower(), 0)
			var cur_best: int = VALUE.get(revenge_char.to_lower(), -1)
			if vcv > cur_best:
				revenge_char = vc
				revenge_gap = ply - int(vic.get("ply", ply))

	var a_kills_before: int = maxi(0, int(victim_rec.get("kills", 0)))
	var streak: int = ledger.get_streak(a_white) if ledger != null else 0
	var first_blood: bool = (ledger.captures.size() <= 1) if ledger != null else false

	return {
		"ply": ply,
		"a_char": a_char,
		"v_char": v_char,
		"a_lower": a_lower,
		"v_lower": v_lower,
		"a_white": a_white,
		"av": av,
		"vv": vv,
		"phase": phase,
		"mat_diff": mat_diff,
		"mat_diff_before": mat_diff_before,
		"lead_flip": lead_flip,
		"victim_type_left": victim_type_left,
		"gives_check": gives_check,
		"replies": replies,
		"recapture_min": recapture_min,
		"recapturable": recapturable,
		"exch": exch,
		"dist": dist,
		"promotes": promotes,
		"underpromotion": underpromotion,
		"en_passant": is_ep,
		"a_is_king": a_is_king,
		"a_is_pawn": a_is_pawn,
		"v_is_queen": v_is_queen,
		"v_age": v_age,
		"v_moves": v_moves,
		"v_kills": v_kills,
		"revenge_char": revenge_char,
		"revenge_gap": revenge_gap,
		"a_kills_before": a_kills_before,
		"streak": streak,
		"first_blood": first_blood
	}
