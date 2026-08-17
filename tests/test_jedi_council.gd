extends SceneTree
## Headless unit test suite for JediCouncilOpponent.

const JediCouncilScript := preload("res://src/ai/jedi_council.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses Chess — Jedi Council of Sanctum Unit Suite ===")
	_test_council_initialization()
	_test_ascii_board_and_history()
	_test_candidate_parsing()
	_test_forced_move_instant_play()
	_test_council_personas()
	_test_position_complexity_scaling()
	print("---")
	if failed == 0:
		print("JEDI COUNCIL OK — all %d checks passed" % passed)
		quit(0)
	else:
		print("JEDI COUNCIL FAILED — %d of %d checks failed" % [failed, passed + failed])
		quit(1)


func check(desc: String, expected, got) -> void:
	if expected == got:
		passed += 1
		print("PASS %s (expected %s, got %s)" % [desc, str(expected), str(got)])
	else:
		failed += 1
		print("FAIL %s (expected %s, got %s)" % [desc, str(expected), str(got)])


func _test_council_initialization() -> void:
	var council: Node = JediCouncilScript.new()
	check("council: default mode is jedi_council", JediCouncilScript.MODE_JEDI, council.mode)
	check("council: has Yoda seat", true, JediCouncilScript.COUNCIL_SEATS.has("yoda"))
	check("council: has Windu seat", true, JediCouncilScript.COUNCIL_SEATS.has("windu"))
	check("council: has Qwen seat", true, JediCouncilScript.COUNCIL_SEATS.has("qwen"))
	council.queue_free()


func _test_ascii_board_and_history() -> void:
	var council: Node = JediCouncilScript.new()
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	var ascii: String = council._render_ascii_board(state)
	check("ascii: board contains ranks 8 to 1", true, ascii.contains("8 |") and ascii.contains("1 |"))
	check("ascii: board contains file headers", true, ascii.contains("a b c d e f g h"))

	var history: String = council._get_san_history(state)
	check("history: initial history is empty string", "", history)

	council.queue_free()


func _test_candidate_parsing() -> void:
	var council: Node = JediCouncilScript.new()
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	var by_uci := {}
	for m in state.legal_moves(true):
		by_uci[String(m.to_uci()).to_lower()] = m

	# Test MOVE parsing from pure LLM output
	var reply := "PLAN: Strike the center and control d5.\nMOVE: e2e4\nREASON: Establishes strong center control."
	var parsed_uci: String = council._extract_uci_move(reply, by_uci)
	check("parse: extracted UCI move e2e4", "e2e4", parsed_uci)

	var reason_text: String = council._extract_reason(reply)
	check("parse: reason extracted", true, reason_text.contains("Establishes strong center control"))

	council.queue_free()


func _test_forced_move_instant_play() -> void:
	var council: Node = JediCouncilScript.new()
	root.add_child(council)

	# Single legal move position (King in check by adjacent undefended Queen)
	var state := ChessState.new()
	state.set_fen("rnb1kbnr/pppp1ppp/8/8/8/8/4q3/4K3 w kq - 0 1")
	var legal: Array = state.legal_moves(true)
	check("forced: position has 1 legal move", 1, legal.size())

	var sigs := {"reason": false, "started": false, "finished": false}
	council.oracle_reason.connect(func(_r: String) -> void: sigs["reason"] = true)
	council.thinking_started.connect(func() -> void: sigs["started"] = true)
	council.thinking_finished.connect(func(_s: float) -> void: sigs["finished"] = true)

	var move = await council.choose_move(state, 2)
	check("forced: move executed immediately", true, move != null)
	check("forced: source is forced", "forced", council.last_source)
	check("forced: oracle_reason signal fired", true, sigs["reason"])

	council.queue_free()


func _test_council_personas() -> void:
	check("seats: Yoda has council-max-thinking", "council-max-thinking", JediCouncilScript.COUNCIL_SEATS["yoda"]["model"])
	check("seats: Windu has council-secure", "council-secure", JediCouncilScript.COUNCIL_SEATS["windu"]["model"])
	check("seats: Qwen has qwen-3.8-instruct", "qwen-3.8-instruct", JediCouncilScript.COUNCIL_SEATS["qwen"]["model"])


func _test_position_complexity_scaling() -> void:
	var council: Node = JediCouncilScript.new()
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	# Initial position: quiet, standard budget
	var initial_comp: Dictionary = council._assess_position_complexity(state, state.legal_moves(true))
	check("complexity: start position is standard calculation", 45.0, initial_comp["timeout_s"])

	# In-check + tactical tension position: deep meditation 120s-180s budget
	state.set_fen("rnb1kbnr/pppp1ppp/8/4p3/4P2q/3P4/PPP2PPP/RNBQKBNR w KQkq - 1 4")
	var sharp_comp: Dictionary = council._assess_position_complexity(state, state.legal_moves(true))
	check("complexity: sharp position scales timeout budget", true, sharp_comp["timeout_s"] >= 45.0)

	council.queue_free()
