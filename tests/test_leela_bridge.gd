extends SceneTree
## Headless unit test suite for LeelaBridge and Dual-Engine Coach Consensus.

const LeelaBridgeScript := preload("res://src/coach/leela_bridge.gd")
const CoachEngineScript := preload("res://src/coach/coach_engine.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses — Leela Lc0 & Dual-Engine Unit Suite ===")
	_test_leela_availability()
	_test_dual_engine_analysis()
	print("---")
	if failed == 0:
		print("LEELA OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("LEELA FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_leela_availability() -> void:
	var path := LeelaBridgeScript.get_leela_path()
	check("leela: binary discovered", true, not path.is_empty())
	check("leela: is_available", true, LeelaBridgeScript.is_available())


func _test_dual_engine_analysis() -> void:
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	var analysis := CoachEngineScript.analyze_position(state, true, [])
	check("dual: analysis returned", true, analysis != null)
	check("dual: recommended move exists", true, analysis["recommended_move"] != null)
	check("dual: engine name includes both titans", true, analysis["engine_name"].contains("Stockfish") and analysis["engine_name"].contains("Leela"))
	check("dual: explanation text populated", true, not analysis["explanation"].is_empty())
