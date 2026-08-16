extends SceneTree
## Headless unit test suite for CoachEngine and CoachOverlay.

const CoachEngineScript := preload("res://src/coach/coach_engine.gd")
const CoachOverlayScript := preload("res://src/coach/coach_overlay.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses — Grandmaster Coach Unit Suite ===")
	_test_opening_book()
	_test_threat_radar()
	_test_best_move_recommendation()
	_test_coach_overlay()
	print("---")
	if failed == 0:
		print("COACH OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("COACH FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_opening_book() -> void:
	# Fresh board
	var info0 = CoachEngineScript._get_opening_info([])
	check("opening: initial tip provided", true, info0.has("tip"))

	# 1. e4
	var info1 = CoachEngineScript._get_opening_info(["e2e4"])
	check("opening: e4 King's Pawn recognized", true, str(info1.get("name", "")).contains("King's Pawn"))

	# 1. e4 e5
	var info2 = CoachEngineScript._get_opening_info(["e2e4", "e7e5"])
	check("opening: e4 e5 Open Game recognized", true, str(info2.get("name", "")).contains("Open Game"))

	# 1. d4
	var info_d4 = CoachEngineScript._get_opening_info(["d2d4"])
	check("opening: d4 recognized", true, str(info_d4.get("name", "")).begins_with("Queen's Pawn"))


func _test_threat_radar() -> void:
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	# Start position: No player pieces under attack
	var analysis := CoachEngineScript.analyze_position(state, true, [])
	check("threat: start pos has no threats", 0, analysis["threats"].size())
	check("threat: threat level is SAFE", "SAFE", analysis["threat_level"])

	# Scholar's Mate threat position (White Queen on f7 attacking Black King)
	var state_sc := ChessState.new()
	state_sc.set_fen("r1bqkbnr/pppp1Qpp/2n5/4p3/4P3/8/PPPP1PPP/RNB1KBNR b KQkq - 0 3")
	var analysis_sc := CoachEngineScript.analyze_position(state_sc, false, ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"])
	check("threat: scholar attack flagged", true, analysis_sc["threat_level"] == "DANGER" or analysis_sc["threats"].size() > 0)


func _test_best_move_recommendation() -> void:
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	var analysis := CoachEngineScript.analyze_position(state, true, [])
	check("coach: recommended move exists", true, analysis["recommended_move"] != null)
	check("coach: explanation text provided", true, not analysis["explanation"].is_empty())


func _test_coach_overlay() -> void:
	var overlay = CoachOverlayScript.new()
	root.add_child(overlay)

	check("overlay: coach starts hidden by default", false, overlay.is_coach_active)

	var active := overlay.toggle_coach()
	check("overlay: toggled on", true, active)

	var active2 := overlay.toggle_coach()
	check("overlay: toggled off", false, active2)

	# Update analysis
	overlay.update_analysis({
		"opening_name": "London System",
		"opening_tip": "Fortify d4!",
		"threats": [],
		"explanation": "Develop Bf4 early."
	})
	check("overlay: title label intact", true, overlay._title_label != null)

	overlay.queue_free()
