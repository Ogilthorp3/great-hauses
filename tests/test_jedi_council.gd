extends SceneTree
## Headless unit test suite for JediCouncilOpponent.

const JediCouncilScript := preload("res://src/ai/jedi_council.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("\n=== Great Hauses Chess — Jedi Council of Sanctum Unit Suite ===")
	_test_council_initialization()
	_test_opening_book()
	_test_candidate_parsing()
	_test_forced_move_instant_play()
	_test_council_personas()
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
	check("council: has default Qwen models", true, JediCouncilScript.QWEN_MODELS.size() > 0)
	check("council: has DeepSeek models", true, JediCouncilScript.DEEPSEEK_MODELS.size() > 0)
	council.queue_free()


func _test_opening_book() -> void:
	var council: Node = JediCouncilScript.new()
	var state := ChessState.new()
	state.set_fen(ChessState.INITIAL_FEN)

	var by_uci := {}
	for m in state.legal_moves(true):
		by_uci[String(m.to_uci()).to_lower()] = m

	# Test 1: Opening book produces a first move (e4, d4, c4, or Nf3)
	var book_move = council._check_opening_book(state, by_uci)
	check("opening: white opening move returned", true, book_move != null)
	check("opening: white move is legal", true, by_uci.has(book_move.to_uci().to_lower()))

	# Test 2: Black responds to 1. e4
	var e4_move = by_uci.get("e2e4")
	if e4_move != null:
		state.apply_move(e4_move)
		var black_by_uci := {}
		for m in state.legal_moves(true):
			black_by_uci[String(m.to_uci()).to_lower()] = m
		var black_book = council._check_opening_book(state, black_by_uci)
		check("opening: black response to e4 returned", true, black_book != null)

	council.queue_free()


func _test_candidate_parsing() -> void:
	var council: Node = JediCouncilScript.new()
	var mock_candidates := [
		{"uci": "e2e4", "san": "e4", "cp": 20, "summary": "center claim"},
		{"uci": "d2d4", "san": "d4", "cp": 18, "summary": "queen pawn control"},
		{"uci": "g1f3", "san": "Nf3", "cp": 15, "summary": "knight development"}
	]

	# Test numeric pick
	var reply_num := "DEBATE: Master Qwen recommends aggressive development.\nPICK: 2\nREASON: Controlling the center ensures early initiative."
	var pick_num: int = council._parse_candidate_pick(reply_num, mock_candidates)
	check("parse: numeric pick 2 -> index 1", 1, pick_num)

	# Test UCI move pick
	var reply_uci := "DEBATE: The Oracle sees tactical weakness on f3.\nPICK: g1f3\nREASON: Develops knight to pressure e5."
	var pick_uci: int = council._parse_candidate_pick(reply_uci, mock_candidates)
	check("parse: UCI pick g1f3 -> index 2", 2, pick_uci)

	# Test reason parsing
	var reason_text: String = council._parse_council_reason(reply_num, mock_candidates[1])
	check("parse: reason extracted", true, reason_text.contains("Controlling the center"))

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
	check("personas: Qwen 3.8 persona exists", true, JediCouncilScript.COUNCIL_PERSONAS.has("qwen"))
	check("personas: The Oracle persona exists", true, JediCouncilScript.COUNCIL_PERSONAS.has("oracle"))
	check("personas: Grand Maester persona exists", true, JediCouncilScript.COUNCIL_PERSONAS.has("maester"))
	check("personas: Master Leela persona exists", true, JediCouncilScript.COUNCIL_PERSONAS.has("leela"))
