class_name MomentScore
extends RefCounted
## Deterministic 4-axis situational scorer for Great Hauses captures.
## Evaluates Stakes, Story, Skill, and Rarity, folding into a normalized notability float [0.0, 1.0].

const WEIGHTS: Dictionary = {
	"stakes": 0.75,
	"story": 0.85,
	"skill": 1.00,
	"rarity": 0.95
}


static func score(sit: Dictionary) -> Dictionary:
	var p_stakes := score_stakes(sit)
	var p_story := score_story(sit)
	var p_skill := score_skill(sit)
	var p_rarity := score_rarity(sit)

	var parts: Dictionary = {
		"stakes": p_stakes,
		"story": p_story,
		"skill": p_skill,
		"rarity": p_rarity
	}

	var best_k := "stakes"
	var best_val := -1.0
	var weighted_vals: Dictionary = {}

	for k in parts.keys():
		var w_val: float = float(WEIGHTS[k]) * float(parts[k]["score"])
		weighted_vals[k] = w_val
		if w_val > best_val:
			best_val = w_val
			best_k = k

	var other_sum := 0.0
	for k in parts.keys():
		if k != best_k:
			other_sum += weighted_vals[k]
	var other_mean := other_sum / 3.0

	var notability := clampf(best_val + 0.30 * other_mean, 0.0, 1.0)
	var lead_tag: String = str(parts[best_k].get("tag", ""))

	return {
		"notability": notability,
		"lead": best_k,
		"tag": lead_tag,
		"parts": parts
	}


static func score_stakes(sit: Dictionary) -> Dictionary:
	var vv: float = float(sit.get("vv", 0))
	var v := vv / 900.0
	var phase: float = float(sit.get("phase", 1.0))
	var amp := 1.0 + 0.6 * (1.0 - phase)
	var s := v * amp

	var victim_left: int = int(sit.get("victim_type_left", 1))
	if victim_left == 0 and vv >= 320:
		s += 0.25
	elif victim_left == 0:
		s += 0.10

	var lead_flip: bool = bool(sit.get("lead_flip", false))
	if lead_flip:
		s += 0.30

	var tag := "pawn"
	if lead_flip:
		tag = "lead_flip"
	elif victim_left == 0 and sit.get("v_is_queen", false):
		tag = "last_queen"
	elif victim_left == 0:
		tag = "last_of_kind"
	elif phase < 0.35:
		tag = "bare_board"
	elif sit.get("v_is_queen", false):
		tag = "queen"
	elif vv >= 500:
		tag = "rook"
	elif vv >= 300:
		tag = "minor"

	return {
		"score": clampf(s, 0.0, 0.85),
		"tag": tag
	}


const PIECE_VAL: Dictionary = {
	"p": 100,
	"n": 320,
	"b": 330,
	"r": 500,
	"q": 900,
	"k": 0
}


static func score_story(sit: Dictionary) -> Dictionary:
	var matches: Array[Dictionary] = []

	var revenge_char: String = str(sit.get("revenge_char", ""))
	var a_lower: String = str(sit.get("a_lower", ""))
	if not revenge_char.is_empty() and revenge_char.to_lower() == a_lower:
		matches.append({"tag": "revenge_kin", "score": 0.80})
	elif not revenge_char.is_empty() and PIECE_VAL.get(revenge_char.to_lower(), 0) >= 320:
		matches.append({"tag": "revenge_named", "score": 0.75})
	elif not revenge_char.is_empty():
		matches.append({"tag": "revenge_any", "score": 0.52})

	var v_kills: int = int(sit.get("v_kills", 0))
	if v_kills >= 3:
		matches.append({"tag": "nemesis", "score": 0.78})

	var streak: int = int(sit.get("streak", 0))
	if streak >= 3:
		matches.append({"tag": "streak", "score": 0.70})

	var v_age: int = int(sit.get("v_age", 0))
	if v_age >= 40:
		matches.append({"tag": "veteran", "score": 0.65})

	var a_kills: int = int(sit.get("a_kills_before", 0))
	if a_kills >= 2:
		matches.append({"tag": "butcher", "score": 0.58})

	var v_moves: int = int(sit.get("v_moves", 0))
	var ply: int = int(sit.get("ply", 0))
	if v_moves == 0 and ply >= 40:
		matches.append({"tag": "statue", "score": 0.50})

	if bool(sit.get("first_blood", false)):
		matches.append({"tag": "first_blood", "score": 0.45})

	if matches.is_empty():
		return {"score": 0.0, "tag": "none"}

	var best_score := 0.0
	var best_tag := "none"
	for m in matches:
		if float(m["score"]) > best_score:
			best_score = float(m["score"])
			best_tag = str(m["tag"])

	var bonus: float = float(matches.size() - 1) * 0.15
	return {
		"score": clampf(best_score + bonus, 0.0, 1.0),
		"tag": best_tag
	}


static func score_skill(sit: Dictionary) -> Dictionary:
	var exch: int = int(sit.get("exch", 0))
	var replies: int = int(sit.get("replies", 0))
	var gives_check: bool = bool(sit.get("gives_check", false))
	var en_passant: bool = bool(sit.get("en_passant", false))

	var base := 0.0
	var tag := "even"

	if exch >= 500:
		base = 0.75
		tag = "theft"
	elif exch >= 300:
		base = 0.60
		tag = "theft"
	elif exch >= 100:
		base = 0.45
		tag = "clean"
	elif exch >= 0:
		base = 0.15
		tag = "even"
	else:
		if replies <= 3:
			base = 0.90
			tag = "sacrifice"
		elif gives_check:
			base = 0.70
			tag = "sacrifice"
		else:
			base = 0.05
			tag = "blunder"

	if gives_check:
		base += 0.15
	if replies <= 2:
		base += 0.15
		if tag != "sacrifice":
			tag = "noose"
	if en_passant:
		base += 0.05

	return {
		"score": clampf(base, 0.0, 1.0),
		"tag": tag
	}


static func score_rarity(sit: Dictionary) -> Dictionary:
	var best_score := 0.0
	var best_tag := "none"

	var check_rule := func(cond: bool, s: float, t: String) -> void:
		if cond and s > best_score:
			best_score = s
			best_tag = t

	check_rule.call(bool(sit.get("underpromotion", false)), 1.00, "underpromotion")
	check_rule.call(bool(sit.get("en_passant", false)), 0.90, "en_passant")
	check_rule.call(bool(sit.get("promotes", false)), 0.85, "promo_capture")
	check_rule.call(bool(sit.get("a_is_pawn", false)) and bool(sit.get("v_is_queen", false)), 0.80, "pawn_takes_queen")
	check_rule.call(bool(sit.get("a_is_king", false)), 0.65, "king_kills")
	check_rule.call(int(sit.get("dist", 0)) >= 6 and str(sit.get("a_lower", "")) in "qbr", 0.55, "long_shot")
	check_rule.call(bool(sit.get("v_is_queen", false)) and int(sit.get("av", 0)) <= 500, 0.50, "queen_hunt")
	check_rule.call(bool(sit.get("v_is_queen", false)), 0.35, "queen_trade")

	return {
		"score": best_score,
		"tag": best_tag
	}
