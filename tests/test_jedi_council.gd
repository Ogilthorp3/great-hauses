extends SceneTree

# Headless integration test for the JEDI COUNCIL opponent (src/ai/jedi_council.gd).
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> -s res://tests/test_jedi_council.gd
# Exit code 0 = all green, 1 = failures.

const JediScript := preload("res://src/ai/jedi_council.gd")
const CS := preload("res://src/chess/ChessState.gd")

var rows := []
var failures := 0
var _server: TCPServer
var _mock_running := false
var _mock_replies: Array = []
var _mock_requests: Array = []


func _initialize() -> void:
	_main()


func _main() -> void:
	print("\n=== JediCouncilOpponent — headless test suite ===")

	var opp := JediScript.new()
	opp.name = "JediCouncilTest"
	root.add_child(opp)
	await process_frame
	await process_frame

	# 1. Semantic Legal Move Annotations
	var state := CS.new()
	var legal: Array = state.legal_moves(true)
	var annotated: String = opp._annotate_legal_moves(state, legal)
	check("annotations: not empty", true, not annotated.is_empty())
	check("annotations: contains e2e4", true, annotated.contains("e2e4"))
	check("annotations: identifies center control", true, annotated.contains("Controls Center e4"))

	# 2. Forced Move Fast Path
	var forced_state := CS.new()
	forced_state.set_fen("8/8/8/8/8/1k6/r7/K7 w - - 0 1") # Ka1 checked by Ra2 defended by Kb3 -> only Kb1
	var forced_move = await opp.choose_move(forced_state)
	check("forced move: played instantly", true, forced_move != null)
	check("forced move: is Kb1", "a1b1", String(forced_move.to_uci()).to_lower() if forced_move != null else "")
	check("forced move: source is forced", "forced", opp.last_source)

	# 3. Mock Server Setup for 3-Phase Multi-Agent Debate
	_server = TCPServer.new()
	var err := _server.listen(0, "127.0.0.1")
	check("mock: server listen", OK, err)
	var port: int = _server.get_local_port()
	opp.custom_endpoint = "http://127.0.0.1:%d/v1/chat/completions" % port
	_mock_running = true
	_run_mock_server()

	# Test Phase 1 & 2 & 3 Mock responses:
	# Yoda Proposal (Phase 1):
	# Qui-Gon Proposal (Phase 1):
	# Windu Critique (Phase 2):
	# Yoda Final Synthesis (Phase 3):
	_mock_replies = [
		# Yoda Proposal:
		"ASSESSMENT: White opens with strong spatial control.\nCANDIDATES:\n1. MOVE: e2e4 | PLAN: Claim the center\n2. MOVE: d2d4 | PLAN: Solid pawn structure\nPREFERRED: e2e4\nREASON: The center, a Jedi must control.",
		# Qui-Gon Proposal:
		"ASSESSMENT: Active development creates initiative.\nCANDIDATES:\n1. MOVE: g1f3 | PLAN: Develop knight\n2. MOVE: e2e4 | PLAN: Strike center\nPREFERRED: g1f3\nREASON: Flow with the living force.",
		# Windu Critique:
		"CRITIQUE: Both e2e4 and g1f3 are sound. e2e4 immediately claims d5/f5 with maximum territorial pressure.\nBLUNDER_WARNING: No tactical blunders detected\nRECOMMENDED: e2e4\nWISDOM: Secure the center before the dark side encroaches.",
		# Yoda Synthesis:
		"SYNTHESIS: Harmonized the council is. With e2e4, both space and initiative we seize.\nPLAN: Seize the board center\nREASON: In unity, the path is clear.\nMOVE: e2e4"
	]

	var debates: Array = []
	opp.council_debated.connect(func(speaker, topic, vote):
		debates.append({"speaker": speaker, "topic": topic, "vote": vote}))

	var debated_move = await opp.choose_move(state)
	check("debate: move chosen", true, debated_move != null)
	check("debate: chosen move is e2e4", "e2e4", String(debated_move.to_uci()).to_lower() if debated_move != null else "")
	check("debate: source is pure_llm_council_debate", "pure_llm_council_debate", opp.last_source)
	check("debate: debates signal emitted", true, debates.size() >= 3)
	check("debate: 4 mock requests received", 4, _mock_requests.size())

	# Cleanup
	_mock_running = false
	_server.stop()
	opp.queue_free()

	_print_summary()
	quit(1 if failures > 0 else 0)


func _run_mock_server() -> void:
	while _mock_running:
		if _server.is_connection_available():
			var peer := _server.take_connection()
			_handle_connection(peer)
		await create_timer(0.01).timeout


func _handle_connection(peer: StreamPeerTCP) -> void:
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() == 0:
		await create_timer(0.01).timeout
	if peer.get_available_bytes() == 0:
		peer.disconnect_from_host()
		return
	var raw := peer.get_utf8_string(peer.get_available_bytes())
	var body_idx := raw.find("\r\n\r\n")
	if body_idx >= 0:
		var json_body := raw.substr(body_idx + 4)
		var parsed = JSON.parse_string(json_body)
		if parsed is Dictionary:
			_mock_requests.append(parsed)

	var reply_content: String = "MOVE: e2e4\nPLAN: Standard move\nREASON: The Force flows."
	if not _mock_replies.is_empty():
		reply_content = _mock_replies.pop_front()

	var resp_body := JSON.stringify({
		"id": "chatcmpl-mock",
		"object": "chat.completion",
		"created": 1234567,
		"model": "council-mock",
		"choices": [{
			"index": 0,
			"message": {
				"role": "assistant",
				"content": reply_content
			},
			"finish_reason": "stop"
		}],
		"usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150}
	})

	var http_resp := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" % [resp_body.to_utf8_buffer().size(), resp_body]
	peer.put_data(http_resp.to_utf8_buffer())
	peer.disconnect_from_host()


func check(desc: String, expected, actual) -> void:
	var ok: bool = (expected == actual)
	if not ok:
		failures += 1
	rows.append({"desc": desc, "expected": str(expected), "actual": str(actual), "ok": ok})


func _print_summary() -> void:
	print("")
	printf("%-46s %-14s %-14s %-6s\n", ["test", "expected", "actual", "ok"])
	for r in rows:
		printf("%-46s %-14s %-14s %-6s\n", [
			r["desc"],
			r["expected"].left(14),
			r["actual"].left(14),
			"PASS" if r["ok"] else "FAIL"
		])
	print("")
	print("%d checks, %d failures" % [rows.size(), failures])


func printf(fmt: String, args: Array) -> void:
	print(fmt % args)
