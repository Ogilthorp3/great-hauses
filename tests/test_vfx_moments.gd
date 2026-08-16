class_name TestVfxMoments
extends SceneTree
## Unit test suite for the 3-Tier VFX Moments System.
## Runs headless (-s) and tests ledger, context, scoring, and governor pacing.

const CaptureLedgerScript := preload("res://src/cinematics/capture_ledger.gd")
const MomentContextScript := preload("res://src/cinematics/moment_context.gd")
const MomentScoreScript := preload("res://src/cinematics/moment_score.gd")
const MomentGovernorScript := preload("res://src/cinematics/moment_governor.gd")
const ChessStateScript := preload("res://src/chess/ChessState.gd")

func _init() -> void:
	print("🧪 Starting VFX Moments test suite...")
	var passes := 0

	# 1. Test CaptureLedger
	var ledger = CaptureLedgerScript.new()
	var state = ChessStateScript.new()
	state.reset()
	ledger.reset_from(state)
	assert(ledger.plies == 0, "Initial plies should be 0")
	passes += 1
	print("  PASS: ledger initialization")

	# 2. Test MomentContext & MomentScore on a Queen Sacrifice
	var mock_sit: Dictionary = {
		"ply": 24,
		"a_char": "Q",
		"v_char": "p",
		"a_lower": "q",
		"v_lower": "p",
		"a_white": true,
		"av": 900,
		"vv": 100,
		"phase": 0.6,
		"mat_diff": -800,
		"mat_diff_before": -700,
		"lead_flip": false,
		"victim_type_left": 4,
		"gives_check": true,
		"replies": 1,
		"recapture_min": 100,
		"recapturable": true,
		"exch": -800,
		"dist": 4,
		"promotes": false,
		"underpromotion": false,
		"en_passant": false,
		"a_is_king": false,
		"a_is_pawn": false,
		"v_is_queen": false,
		"v_age": 12,
		"v_moves": 2,
		"v_kills": 0,
		"revenge_char": "",
		"revenge_gap": 999,
		"a_kills_before": 0,
		"streak": 0,
		"first_blood": false
	}
	var scored: Dictionary = MomentScoreScript.score(mock_sit)
	assert(scored["notability"] >= 0.70, "Queen sacrifice with check and 1 reply must score high notability!")
	assert(scored["lead"] == "skill", "Queen sacrifice lead must be skill!")
	passes += 1
	print("  PASS: moment scoring (queen sacrifice notability = %.2f)" % scored["notability"])

	# 3. Test Governor Distribution Pacing
	var gov = MomentGovernorScript.new(42)
	var t0_count := 0
	var t1_count := 0
	var t2_count := 0

	for i in 60:
		var notab := 0.15
		if i % 4 == 0:
			notab = 0.50
		if i % 14 == 0:
			notab = 0.88
		var dec: Dictionary = gov.decide(notab)
		match dec["tier"]:
			0: t0_count += 1
			1: t1_count += 1
			2: t2_count += 1

	print("  Governor 60-capture distribution: Tier 0 = %d, Tier 1 = %d, Tier 2 = %d" % [t0_count, t1_count, t2_count])
	assert(t0_count > t1_count, "Tier 0 must be majority")
	assert(t1_count > 0, "Tier 1 must fire")
	assert(t2_count > 0, "Tier 2 must fire")
	passes += 1
	print("  PASS: moment governor distribution and reservoir")

	print("✅ ALL %d VFX MOMENT TESTS PASSED!" % passes)
	quit(0)
