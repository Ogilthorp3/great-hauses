class_name MomentGovernor
extends RefCounted
## Governor for Great Hauses capture moments (Pacing, Reservoir, and Novelty).
## Owns the 3-tier rates (~75% Tier 0, ~20% Tier 1, ~5-7% Tier 2).
## Pure RefCounted with dual deterministic RNG streams.

const PRIOR_W: float = 10.0
const PRIOR_MEAN: float = 0.35
const SCALE_LO: float = 0.65
const SCALE_HI: float = 1.45

const T1_BASE: float = 1.40
const T2_BASE: float = 4.80
const JITTER: float = 0.18

const COOL1: int = 1
const COOL2: int = 3
const SOFT1: int = 5
const HARD1: int = 8
const SOFT2: int = 12
const HARD2: int = 18

const M_FLOOR1: float = 0.25
const M_EXP1: float = 1.2
const M_FLOOR2: float = 0.08
const M_EXP2: float = 2.0

var n: int = 0
var sum_notability: float = 0.0
var res1: float = 0.0
var res2: float = 0.0
var last_fire1: int = -99
var last_fire2: int = -99

var jitter1: float = 1.0
var jitter2: float = 1.0

var _gate: RandomNumberGenerator
var _pick: RandomNumberGenerator

var _seen: Dictionary = {1: {}, 2: {}}
var _recent: Dictionary = {1: [], 2: []}


func _init(seed_val: int = 0) -> void:
	_gate = RandomNumberGenerator.new()
	_pick = RandomNumberGenerator.new()
	if seed_val == 0:
		_gate.randomize()
		_pick.randomize()
	else:
		_gate.seed = seed_val
		_pick.seed = seed_val ^ 0x9E3779B9
	reset_game()


func reset_game() -> void:
	n = 0
	sum_notability = 0.0
	res1 = 0.0
	res2 = 0.0
	last_fire1 = -99
	last_fire2 = -99
	_seen = {1: {}, 2: {}}
	_recent = {1: [], 2: []}
	_redraw_jitter()


func _redraw_jitter() -> void:
	jitter1 = _gate.randf_range(1.0 - JITTER, 1.0 + JITTER)
	jitter2 = _gate.randf_range(1.0 - JITTER, 1.0 + JITTER)


func decide(notability: float, candidates: Dictionary = {}) -> Dictionary:
	n += 1
	sum_notability += notability
	res1 += notability
	res2 += notability

	var mean: float = (PRIOR_W * PRIOR_MEAN + sum_notability) / (PRIOR_W + float(n))
	var scale: float = clampf(mean / PRIOR_MEAN, SCALE_LO, SCALE_HI)
	var t1: float = T1_BASE * scale * jitter1
	var t2: float = T2_BASE * scale * jitter2
	var rel: float = clampf(notability / (2.0 * mean), 0.0, 1.0)

	var chosen_tier := 0
	var fire_reason := "quiet"

	# 1. Evaluate Tier 2 (Showstopper)
	var d2 := n - last_fire2
	if d2 >= COOL2 and (res2 >= t2 or d2 >= SOFT2):
		var u2 := clampf(float(d2 - SOFT2) / float(maxi(1, HARD2 - SOFT2)), 0.0, 1.0)
		var merit2 := (M_FLOOR2 + (1.0 - M_FLOOR2) * pow(rel, M_EXP2)) if res2 >= t2 else 0.0
		var chance2 := merit2 + (1.0 - merit2) * u2
		if _gate.randf() < chance2:
			chosen_tier = 2
			fire_reason = "pity" if (res2 < t2 and d2 >= SOFT2) else "merit"

	# 2. Evaluate Tier 1 (Tactical Flourish) if Tier 2 did not fire
	if chosen_tier == 0:
		var d1 := n - last_fire1
		if d1 >= COOL1 and (res1 >= t1 or d1 >= SOFT1):
			var u1 := clampf(float(d1 - SOFT1) / float(maxi(1, HARD1 - SOFT1)), 0.0, 1.0)
			var merit1 := (M_FLOOR1 + (1.0 - M_FLOOR1) * pow(rel, M_EXP1)) if res1 >= t1 else 0.0
			var chance1 := merit1 + (1.0 - merit1) * u1
			if _gate.randf() < chance1:
				chosen_tier = 1
				fire_reason = "pity" if (res1 < t1 and d1 >= SOFT1) else "merit"

	if chosen_tier == 2:
		res2 = 0.0
		res1 = 0.0
		last_fire2 = n
		last_fire1 = n
		_redraw_jitter()
	elif chosen_tier == 1:
		res1 = 0.0
		last_fire1 = n
		_redraw_jitter()

	return {
		"tier": chosen_tier,
		"reason": fire_reason,
		"notability": notability,
		"relative": rel,
		"n": n
	}
